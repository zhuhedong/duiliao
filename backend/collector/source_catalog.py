"""Discover, diff and record the current 588080 / 顶尖大师 content catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable

from sqlalchemy import select

from common import ROOT
from common.http import get_json
from common.parse_pred import strip_html
from common.sites.dingjian import (
    CATALOG_PATH,
    DEFAULT_ENTRIES,
    STATIC_API_HOSTS,
    discover_api_hosts,
    load_cached_api_hosts,
    origin,
    save_api_hosts,
)
from db import session_scope
from registry import load_config, sources_dir
from schema import Issue, Setting, create_all

TZ8 = timezone(timedelta(hours=8))
SETTING_KEY = "source_catalog"
SITE_FAMILY = "dingjian_dashi"
UPSTREAM_RE = re.compile(r"config/byid/(\d+)")
ASSET_RE = re.compile(r"(?:src|href)\s*=\s*['\"]([^'\"]+)['\"]", re.I)


def now_iso() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def _split_env(name: str) -> list[str]:
    return [value for value in re.split(r"[,;\s]+", os.getenv(name, "").strip()) if value]


def watcher_enabled() -> bool:
    return os.getenv("PRED_CATALOG_ENABLED", "1").strip().lower() not in {"0", "false", "no", "off"}


def interval_minutes() -> int:
    try:
        return max(5, min(int(os.getenv("PRED_CATALOG_INTERVAL_MIN", "15")), 1440))
    except ValueError:
        return 15


def catalog_config(cfg: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = cfg or load_config()
    family = dict((cfg.get("site_families") or {}).get(SITE_FAMILY) or {})
    entries = _split_env("PRED_DINGJIAN_ENTRY") or family.get("entry_urls") or list(DEFAULT_ENTRIES)
    configured_hosts = _split_env("PRED_DINGJIAN_HOSTS") or family.get("fallback_hosts") or []
    ignored_raw = family.get("catalog_ignore") or {}
    ignored: dict[str, str] = {}
    if isinstance(ignored_raw, dict):
        ignored = {str(key): str(value or "配置为非资料模块") for key, value in ignored_raw.items()}
    elif isinstance(ignored_raw, list):
        for value in ignored_raw:
            if isinstance(value, dict) and value.get("id") is not None:
                ignored[str(value["id"])] = str(value.get("reason") or "配置为非资料模块")
            elif value is not None:
                ignored[str(value)] = "配置为非资料模块"
    return {
        "entry_urls": [str(value).rstrip("/") + "/" for value in entries],
        "fallback_hosts": [*configured_hosts, *load_cached_api_hosts(), *STATIC_API_HOSTS],
        "lottery_type": str(family.get("lottery_type") or "2"),
        "expected_title": str(family.get("expected_title") or "顶尖大师"),
        "ignored": ignored,
    }


def _script_ids(path: Path) -> set[str]:
    try:
        return set(UPSTREAM_RE.findall(path.read_text(encoding="utf-8")))
    except OSError:
        return set()


def local_inventory(cfg: dict[str, Any], script_root: Path | None = None) -> tuple[dict[str, list[dict]], dict[str, list[str]]]:
    root = script_root or sources_dir()
    registered: dict[str, list[dict]] = {}
    for row in cfg.get("sources") or []:
        extra = row.get("extra") or {}
        ids = {str(extra["upstream_id"])} if extra.get("upstream_id") not in {None, ""} else set()
        ids.update(_script_ids(root / Path(row.get("script_path") or f"{row['source_id']}.py").name))
        for upstream_id in ids:
            registered.setdefault(upstream_id, []).append(
                {
                    "source_id": row["source_id"],
                    "source_name": row.get("source_name") or row["source_id"],
                    "enabled": bool(row.get("enabled", True)),
                }
            )
    scripts: dict[str, list[str]] = {}
    if root.exists():
        for path in root.glob("*.py"):
            if path.name in {"__init__.py", "dj_util.py"}:
                continue
            for upstream_id in _script_ids(path):
                scripts.setdefault(upstream_id, []).append(path.stem)
    return registered, scripts


def classify_content(content: str | None) -> dict[str, Any]:
    raw = content or ""
    text = strip_html(raw)
    assets = list(dict.fromkeys(ASSET_RE.findall(raw)))[:12]
    has_periods = bool(re.search(r"(?:第\s*)?\d{1,7}\s*期", text))
    links = [value for value in assets if not re.search(r"\.(?:gif|jpe?g|png|webp|svg)(?:[?#]|$)", value, re.I)]
    images = [value for value in assets if value not in links]
    if has_periods:
        kind = "structured_text"
    elif links:
        kind = "external"
    elif images:
        kind = "image"
    elif text:
        kind = "unknown_text"
    else:
        kind = "empty"
    return {
        "content_kind": kind,
        "assets": assets,
        "sample": text[:1200],
        "content_hash": hashlib.sha256(raw.encode("utf-8")).hexdigest() if raw else None,
    }


def _normalize_catalog(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in rows:
        if raw.get("id") is None or raw.get("type") != "content" or bool(raw.get("hidden")):
            continue
        upstream_id = str(raw["id"])
        if upstream_id in seen:
            continue
        seen.add(upstream_id)
        result.append(
            {
                "upstream_id": upstream_id,
                "name": str(raw.get("name") or upstream_id).strip(),
                "sort": int(raw.get("sort") or 0),
                "type": "content",
                "scoped": bool(raw.get("scoped")),
                "content": raw.get("content"),
            }
        )
    return sorted(result, key=lambda row: (row["sort"], row["upstream_id"]))


def compare_inventory(
    rows: list[dict[str, Any]],
    cfg: dict[str, Any],
    *,
    previous_items: list[dict[str, Any]] | None = None,
    detail_loader: Callable[[str], dict[str, Any] | None] | None = None,
    script_root: Path | None = None,
) -> dict[str, Any]:
    registered, scripts = local_inventory(cfg, script_root)
    settings = catalog_config(cfg)
    ignored = settings["ignored"]
    previous = {str(row.get("upstream_id")): row for row in previous_items or []}
    items: list[dict[str, Any]] = []
    renamed: list[dict[str, str]] = []

    for row in _normalize_catalog(rows):
        upstream_id = row["upstream_id"]
        sources = registered.get(upstream_id, [])
        source_ids = {source["source_id"] for source in sources}
        script_only = sorted(set(scripts.get(upstream_id, [])) - source_ids)
        if upstream_id in ignored:
            coverage = "ignored"
        elif any(source["enabled"] for source in sources):
            coverage = "enabled"
        elif sources:
            coverage = "disabled"
        elif script_only:
            coverage = "script_only"
        else:
            coverage = "untracked"

        content = row.pop("content")
        if (content is None or not str(content).strip()) and coverage in {"ignored", "untracked"} and detail_loader:
            detail = detail_loader(upstream_id) or {}
            content = detail.get("content")
        item = {
            **row,
            **classify_content(content),
            "coverage": coverage,
            "sources": sources,
            "script_only": script_only,
            "ignore_reason": ignored.get(upstream_id),
        }
        old = previous.get(upstream_id)
        if old and str(old.get("name") or "") != item["name"]:
            renamed.append({"upstream_id": upstream_id, "old_name": str(old.get("name") or ""), "new_name": item["name"]})
        items.append(item)

    current_ids = {item["upstream_id"] for item in items}
    missing: list[dict[str, Any]] = []
    for upstream_id, sources in registered.items():
        enabled_sources = [source for source in sources if source["enabled"]]
        if enabled_sources and upstream_id not in current_ids:
            missing.append({"upstream_id": upstream_id, "sources": enabled_sources})

    return {
        "items": items,
        "pending": [item for item in items if item["coverage"] == "untracked"],
        "ignored": [item for item in items if item["coverage"] == "ignored"],
        "script_only": [item for item in items if item["coverage"] == "script_only"],
        "missing": missing,
        "renamed": renamed,
        "content_total": len(items),
        "enabled_components": sum(item["coverage"] == "enabled" for item in items),
        "known_components": sum(item["coverage"] != "untracked" for item in items),
    }


def _catalog_rows(hosts: list[str], lottery_type: str) -> tuple[str, list[dict[str, Any]]]:
    errors: list[str] = []
    for host in hosts:
        try:
            payload = get_json(host + CATALOG_PATH, headers={"lotteryType": lottery_type}, timeout=12, retries=1)
            if payload.get("code") != 0 or not isinstance(payload.get("data"), list):
                raise ValueError("栏目接口响应格式不正确")
            return host, payload["data"]
        except Exception as exc:
            errors.append(f"{host}: {exc}")
    raise RuntimeError("所有已验证线路的栏目接口均失败；" + "；".join(errors[-5:]))


def _detail_loader(hosts: list[str], lottery_type: str) -> Callable[[str], dict[str, Any] | None]:
    def load(upstream_id: str) -> dict[str, Any] | None:
        for host in hosts:
            try:
                payload = get_json(
                    f"{host}/api/v1/index/config/byid/{upstream_id}",
                    headers={"lotteryType": lottery_type},
                    timeout=12,
                    retries=1,
                )
                if payload.get("code") == 0 and isinstance(payload.get("data"), dict):
                    return payload["data"]
            except Exception:
                continue
        return None

    return load


def _issue_key(identity: str) -> str:
    return hashlib.sha256(f"catalog:{identity}".encode()).hexdigest()


def _ensure_issue(session, identity: str, reason: str, payload: dict[str, Any]) -> None:
    from issues import report

    key = _issue_key(identity)
    existing = session.scalar(select(Issue).where(Issue.key == key))
    signature = payload.get("signature")
    if existing is None or (existing.status == "resolved") or (existing.payload or {}).get("signature") != signature:
        report(session, "catalog", identity, reason, payload)


def _resolve_issue(session, identity: str, note: str) -> None:
    from issues import log_change

    row = session.scalar(select(Issue).where(Issue.key == _issue_key(identity)))
    if row is not None and row.status == "open":
        row.status = "resolved"
        row.note = note
        row.updated_at = datetime.now(TZ8).replace(tzinfo=None)
        log_change(session, row, "resolved")


def _record_success(result: dict[str, Any]) -> None:
    with session_scope(guard=False) as session:
        old = session.get(Setting, SETTING_KEY)
        previous = dict(old.value or {}) if old else {}
        pending_ids = {item["upstream_id"] for item in result["pending"]}
        missing_ids = {item["upstream_id"] for item in result["missing"]}

        for item in result["pending"]:
            kind = item["content_kind"]
            suffix = {
                "structured_text": "已隔离，等待解析契约验收",
                "image": "已隔离；图片栏目需要 OCR 与人工抽样验收",
                "external": "疑似外链展示模块，请确认是否忽略",
            }.get(kind, "已隔离，等待人工分类")
            signature = f"new:{item['upstream_id']}:{item['name']}:{kind}"
            _ensure_issue(
                session,
                f"new:{item['upstream_id']}",
                f"发现未接入上游栏目「{item['name']}」（{item['upstream_id']}），{suffix}",
                {"kind": "new_component", "signature": signature, **item},
            )
        for item in result["missing"]:
            names = "、".join(source["source_name"] for source in item["sources"])
            signature = f"missing:{item['upstream_id']}:{','.join(source['source_id'] for source in item['sources'])}"
            _ensure_issue(
                session,
                f"missing:{item['upstream_id']}",
                f"已启用来源对应的上游栏目 {item['upstream_id']} 已消失：{names}",
                {"kind": "missing_component", "signature": signature, **item},
            )
        for item in result["renamed"]:
            signature = f"renamed:{item['upstream_id']}:{item['old_name']}:{item['new_name']}"
            _ensure_issue(
                session,
                f"renamed:{item['upstream_id']}",
                f"上游栏目已改名：{item['old_name']} → {item['new_name']}（{item['upstream_id']}）",
                {"kind": "renamed_component", "signature": signature, **item},
            )

        for item in previous.get("items") or []:
            upstream_id = str(item.get("upstream_id") or "")
            if upstream_id and upstream_id not in pending_ids:
                _resolve_issue(session, f"new:{upstream_id}", "栏目已接入、已配置忽略或已从上游移除")
        for item in previous.get("missing") or []:
            upstream_id = str(item.get("upstream_id") or "")
            if upstream_id and upstream_id not in missing_ids:
                _resolve_issue(session, f"missing:{upstream_id}", "上游栏目已恢复或本地来源已停用")
        _resolve_issue(session, "scan", "栏目巡检恢复成功")
        session.merge(Setting(key=SETTING_KEY, value=result))


def _record_failure(message: str, started_at: str) -> dict[str, Any]:
    create_all()
    with session_scope(guard=False) as session:
        row = session.get(Setting, SETTING_KEY)
        value = dict(row.value or {}) if row else {}
        value.update(
            {
                "ok": False,
                "enabled": watcher_enabled(),
                "interval_minutes": interval_minutes(),
                "last_attempt_at": started_at,
                "last_error": message,
            }
        )
        session.merge(Setting(key=SETTING_KEY, value=value))
        _ensure_issue(
            session,
            "scan",
            f"栏目自动巡检失败：{message}",
            {"kind": "scan_failure", "signature": "scan_failure", "last_attempt_at": started_at},
        )
    return value


def _write_report(result: dict[str, Any]) -> None:
    configured = os.getenv("PRED_CATALOG_REPORT_DIR", "").strip()
    target = Path(configured) if configured else ROOT / "out" / "source-catalog"
    target.mkdir(parents=True, exist_ok=True)
    json_text = json.dumps(result, ensure_ascii=False, indent=2)
    temporary = target / "latest.json.tmp"
    temporary.write_text(json_text, encoding="utf-8")
    temporary.replace(target / "latest.json")
    labels = {
        "enabled": "已启用",
        "disabled": "已登记停用",
        "script_only": "仅有脚本",
        "ignored": "已忽略",
        "untracked": "待接入",
    }
    lines = [
        "# 588080 栏目自动巡检",
        "",
        f"- 巡检时间：{result['last_success_at']}",
        f"- 当前线路：`{result['active_host']}`",
        f"- 可见内容栏目：{result['content_total']}；已知：{result['known_components']}；待接入：{len(result['pending'])}",
        "",
        "| 上游 ID | 栏目 | 状态 | 内容类型 | 本地来源 |",
        "|---|---|---|---|---|",
    ]
    for item in result["items"]:
        local = "、".join(source["source_id"] for source in item["sources"]) or "、".join(item["script_only"]) or "—"
        display_name = item["name"].replace("|", "\\|")
        lines.append(
            f"| {item['upstream_id']} | {display_name} | "
            f"{labels.get(item['coverage'], item['coverage'])} | {item['content_kind']} | {local} |"
        )
    markdown = "\n".join(lines) + "\n"
    temporary_md = target / "latest.md.tmp"
    temporary_md.write_text(markdown, encoding="utf-8")
    temporary_md.replace(target / "latest.md")


def scan(*, record: bool = True) -> dict[str, Any]:
    started_at = now_iso()
    cfg = load_config()
    settings = catalog_config(cfg)
    try:
        hosts, discovery_errors = discover_api_hosts(
            settings["entry_urls"],
            fallback_hosts=settings["fallback_hosts"],
            expected_title=settings["expected_title"],
            max_valid=5,
        )
        active_host, rows = _catalog_rows(hosts, settings["lottery_type"])
        previous = (status().get("items") or []) if record else []
        compared = compare_inventory(
            rows,
            cfg,
            previous_items=previous,
            detail_loader=_detail_loader([active_host, *hosts], settings["lottery_type"]),
        )
        result = {
            "ok": True,
            "enabled": watcher_enabled(),
            "interval_minutes": interval_minutes(),
            "entry_urls": settings["entry_urls"],
            "active_host": active_host,
            "hosts": hosts,
            "last_attempt_at": started_at,
            "last_success_at": now_iso(),
            "last_error": None,
            "discovery_warnings": discovery_errors[-20:],
            **compared,
        }
        if record:
            create_all()
            save_api_hosts(hosts, entry_urls=settings["entry_urls"])
            _record_success(result)
            # Return the same shape as GET /source-catalog, including the
            # current issue count after this scan has opened/resolved issues.
            result = status()
            _write_report(result)
        return result
    except Exception as exc:
        if record:
            return _record_failure(str(exc), started_at)
        raise


def status() -> dict[str, Any]:
    create_all()
    with session_scope(guard=False) as session:
        row = session.get(Setting, SETTING_KEY)
        value = dict(row.value or {}) if row else {}
        open_issues = list(session.scalars(select(Issue).where(Issue.stage == "catalog", Issue.status == "open")))
    value.setdefault("ok", False)
    value.setdefault("items", [])
    value.setdefault("pending", [])
    value.setdefault("missing", [])
    value.setdefault("renamed", [])
    value.setdefault("content_total", 0)
    value["enabled"] = watcher_enabled()
    value["interval_minutes"] = interval_minutes()
    value["open_issue_count"] = len(open_issues)
    return value


def main() -> None:
    # Windows PowerShell may expose a legacy GBK stdout even though the JSON
    # contract contains symbols copied from upstream content.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
    parser = argparse.ArgumentParser(description="自动发现并核对 588080 栏目目录")
    sub = parser.add_subparsers(dest="command", required=True)
    scan_parser = sub.add_parser("scan")
    scan_parser.add_argument("--record", action="store_true", help="写入状态、线路缓存和异常中心")
    scan_parser.add_argument("--fail-on-drift", action="store_true", help="存在待接入或失效栏目时返回退出码 2")
    sub.add_parser("status")
    args = parser.parse_args()
    if args.command == "status":
        result = status()
    else:
        result = scan(record=args.record)
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    if not result.get("ok"):
        raise SystemExit(1)
    if args.command == "scan" and args.fail_on_drift and (result.get("pending") or result.get("missing")):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
