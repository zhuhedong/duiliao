"""Unified catalog inspection and source-governance facade.

The three upstream families have different catalog formats, so their scanners
remain separate.  This module gives the API, CLI and UI one stable contract:
each family is scanned independently and the aggregate view never hides a
failure from one of the other families.
"""

from __future__ import annotations

import importlib
from typing import Any

FAMILY_MODULES: dict[str, str] = {
    "dingjian_dashi": "source_catalog",
    "tongtian_83191": "tongtian_catalog",
    "dingji_77452": "dingji_catalog",
}

FAMILY_LABELS: dict[str, str] = {
    "dingjian_dashi": "588080.com / 顶尖大师",
    "tongtian_83191": "83191.com / 通天论坛",
    "dingji_77452": "77452.com / 顶级论坛",
}

FAMILY_ALIASES = {
    "588080": "dingjian_dashi",
    "588080.com": "dingjian_dashi",
    "顶尖大师": "dingjian_dashi",
    "83191": "tongtian_83191",
    "83191.com": "tongtian_83191",
    "通天论坛": "tongtian_83191",
    "77452": "dingji_77452",
    "77452.com": "dingji_77452",
    "顶级论坛": "dingji_77452",
}


def _family(name: str) -> str:
    value = str(name or "").strip()
    value = FAMILY_ALIASES.get(value, value)
    if value in {"all", "*"}:
        return "all"
    if value not in FAMILY_MODULES:
        raise ValueError(f"不支持的站点族: {value or '空'}")
    return value


def _load(name: str) -> Any:
    return importlib.import_module(FAMILY_MODULES[name])


def _decorate(name: str, result: dict[str, Any]) -> dict[str, Any]:
    value = dict(result or {})
    value["site_family"] = name
    value["site_label"] = FAMILY_LABELS[name]
    value.setdefault("items", [])
    value.setdefault("pending", [])
    value.setdefault("missing", [])
    value.setdefault("ignored", [])
    value.setdefault("renamed", [])
    return value


def _aggregate(sites: dict[str, dict[str, Any]]) -> dict[str, Any]:
    pending: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    ignored: list[dict[str, Any]] = []
    renamed: list[dict[str, Any]] = []
    content_total = enabled = known = issues = 0
    ok = True
    active = True
    intervals: list[int] = []
    last_error: str | None = None
    for family, value in sites.items():
        ok = ok and bool(value.get("ok"))
        active = active and bool(value.get("enabled", True))
        if value.get("interval_minutes") is not None:
            intervals.append(int(value["interval_minutes"]))
        if value.get("last_error"):
            last_error = str(value["last_error"])
        content_total += int(value.get("content_total") or 0)
        enabled += int(value.get("enabled_components") or 0)
        known += int(value.get("known_components") or 0)
        issues += int(value.get("open_issue_count") or 0)
        for key, target in (("pending", pending), ("missing", missing), ("ignored", ignored), ("renamed", renamed)):
            for item in value.get(key) or []:
                target.append({"site_family": family, **dict(item)})
    return {
        "ok": ok,
        "enabled": active,
        "interval_minutes": min(intervals) if intervals else 15,
        "site_family": "all",
        "site_label": "三站点",
        "sites": sites,
        # ``families`` is an alias kept for clients that prefer a semantic name.
        "families": sites,
        "content_total": content_total,
        "enabled_components": enabled,
        "known_components": known,
        "pending": pending,
        "missing": missing,
        "ignored": ignored,
        "renamed": renamed,
        "open_issue_count": issues,
        "last_error": last_error,
    }


def status(site_family: str | None = None) -> dict[str, Any]:
    selected = _family(site_family or "all")
    if selected != "all":
        return _decorate(selected, _load(selected).status())
    sites: dict[str, dict[str, Any]] = {}
    for family in FAMILY_MODULES:
        try:
            sites[family] = _decorate(family, _load(family).status())
        except Exception as exc:  # status must still show the other families
            sites[family] = _decorate(
                family,
                {
                    "ok": False,
                    "enabled": False,
                    "content_total": 0,
                    "last_error": str(exc),
                    "items": [],
                    "pending": [],
                    "missing": [],
                },
            )
    return _aggregate(sites)


def scan(*, site_family: str | None = None, record: bool = True) -> dict[str, Any]:
    selected = _family(site_family or "all")
    if selected != "all":
        return _decorate(selected, _load(selected).scan(record=record))
    sites: dict[str, dict[str, Any]] = {}
    for family in FAMILY_MODULES:
        module = _load(family)
        try:
            sites[family] = _decorate(family, module.scan(record=record))
        except Exception as exc:
            # A single unavailable upstream must not prevent governance of the
            # other two sites.  The family-level scanner records its own
            # failure where supported; this also makes the aggregate explicit.
            try:
                current = module.status() if record else {}
            except Exception:
                current = {}
            current.update({"ok": False, "last_error": str(exc)})
            sites[family] = _decorate(family, current)
    return _aggregate(sites)


def reconcile_missing(
    *, site_family: str | None = None, disable_missing: bool = False
) -> dict[str, Any]:
    """Preview or apply disabling of sources whose upstream column vanished.

    Discovery never changes source configuration by itself.  Operators can
    call this explicit governance action after reviewing the missing list; a
    dry run is returned by default.
    """
    current = status(site_family)
    missing = current.get("missing") or []
    if current.get("site_family") == "all":
        # Aggregate entries already carry their family identity.
        entries = missing
    else:
        entries = [{"site_family": current.get("site_family"), **dict(item)} for item in missing]
    targets: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in entries:
        for source in item.get("sources") or []:
            sid = str(source.get("source_id") or "")
            if sid and sid not in seen:
                seen.add(sid)
                targets.append(
                    {
                        "source_id": sid,
                        "source_name": source.get("source_name") or sid,
                        "site_family": item.get("site_family"),
                        "upstream_id": item.get("upstream_id") or item.get("path"),
                    }
                )
    if not disable_missing:
        return {"ok": True, "dry_run": True, "site_family": current.get("site_family"), "items": targets}

    registry = _load_registry()
    changed: list[dict[str, Any]] = []
    for target in targets:
        try:
            row = registry.get_source(target["source_id"])
            old_remark = str(row.get("remark") or "").strip()
            note = f"上游栏目 {target['upstream_id']} 已消失，巡检治理自动停用"
            remark = old_remark if note in old_remark else (f"{old_remark}；{note}" if old_remark else note)
            registry.update_source(target["source_id"], {"enabled": False, "remark": remark})
            changed.append({**target, "enabled": False, "remark": remark})
        except Exception as exc:
            changed.append({**target, "enabled": None, "error": str(exc)})
    return {
        "ok": all(item.get("enabled") is False for item in changed) if targets else True,
        "dry_run": False,
        "site_family": current.get("site_family"),
        "items": changed,
    }


def _load_registry() -> Any:
    return importlib.import_module("registry")


def main() -> None:
    import argparse
    import json

    parser = argparse.ArgumentParser(description="三站点栏目动态巡检")
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("scan", "status", "reconcile"):
        item = sub.add_parser(command)
        item.add_argument("--site-family", default="all", choices=["all", *FAMILY_MODULES])
        if command == "scan":
            item.add_argument("--record", action="store_true")
        if command == "reconcile":
            item.add_argument("--apply", action="store_true", help="应用停用变更；默认仅预览")
    args = parser.parse_args()
    if args.command == "status":
        result = status(args.site_family)
    elif args.command == "scan":
        result = scan(site_family=args.site_family, record=args.record)
    else:
        result = reconcile_missing(site_family=args.site_family, disable_missing=args.apply)
    print(json.dumps(result, ensure_ascii=False))
    if not result.get("ok"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
