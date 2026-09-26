"""Discover, diff and record the 83191.com / 通天论坛 homepage script catalog."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse

from common import ROOT
from common.http import get
from common.parse_pred import strip_html
from common.sites.tongtian import (
    DEFAULT_ENTRIES,
    STATIC_API_HOSTS,
    discover_api_hosts,
    load_cached_api_hosts,
    save_api_hosts,
)
from db import session_scope
from registry import load_config
from schema import Setting, create_all

TZ8 = timezone(timedelta(hours=8))
SETTING_KEY = "tongtian_catalog"
SITE_FAMILY = "tongtian_83191"
SCRIPT_RE = re.compile(r"/chajie/[A-Za-z0-9_]+\.js")
IFRAME_RE = re.compile(r"<iframe[^>]+(?:src|data-src)\s*=\s*['\"]([^'\"]+)['\"]", re.I)
EMBED_RE = re.compile(r"(?:src|data-src)\s*=\s*['\"]([^'\"]+)['\"]", re.I)
URL_RE = re.compile(r"""urls_for\(\s*['"]([^'"]+)['"]\s*\)""")


def now_iso() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def _split_env(name: str) -> list[str]:
    return [value for value in re.split(r"[,;\s]+", os.getenv(name, "").strip()) if value]


def watcher_enabled() -> bool:
    return os.getenv("PRED_TONGTIAN_CATALOG_ENABLED", "1").strip().lower() not in {"0", "false", "no", "off"}


def interval_minutes() -> int:
    try:
        return max(5, min(int(os.getenv("PRED_CATALOG_INTERVAL_MIN", "15")), 1440))
    except ValueError:
        return 15


def catalog_config(cfg: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = cfg or load_config()
    family = dict((cfg.get("site_families") or {}).get(SITE_FAMILY) or {})
    entries = _split_env("PRED_TONGTIAN_ENTRY") or family.get("entry_urls") or list(DEFAULT_ENTRIES)
    configured = _split_env("PRED_TONGTIAN_HOSTS") or family.get("fallback_hosts") or []
    ignored_raw = family.get("catalog_ignore") or {}
    ignored = {str(key): str(value or "配置为非资料模块") for key, value in ignored_raw.items()} if isinstance(ignored_raw, dict) else {}
    return {
        "entry_urls": [str(value) for value in entries],
        "fallback_hosts": [*configured, *load_cached_api_hosts(), *STATIC_API_HOSTS],
        "expected_title": str(family.get("expected_title") or "通天"),
        "ignored": ignored,
    }


def extract_script_paths(html: str) -> list[str]:
    """Keep homepage/script order, normalize query strings, and drop duplicates."""
    paths: list[str] = []
    for value in SCRIPT_RE.findall(html or ""):
        path = "/" + value.lstrip("/")
        if path not in paths:
            paths.append(path)
    return paths


def extract_iframe_paths(html: str) -> list[str]:
    """Return local iframe paths in source order."""
    result: list[str] = []
    normalized = (html or "").replace("\\'", "'").replace('\\"', '"')
    for value in IFRAME_RE.findall(normalized):
        value = value.strip()
        if not value or value.startswith(("#", "javascript:", "data:")):
            continue
        path = urlparse(value).path or "/"
        if path not in result:
            result.append(path)
    return result


def discover_homepage_scripts(
    host: str,
    *,
    max_pages: int = 4,
    timeout: float = 12.0,
) -> tuple[list[str], list[str], list[str]]:
    """Walk the landing page and local iframes to find live column scripts."""
    root = host.rstrip("/") + "/"
    base_origin = urlparse(root).netloc
    queue: list[str] = [root]
    visited: set[str] = set()
    paths: list[str] = []
    pages: list[str] = []
    errors: list[str] = []
    while queue and len(pages) < max(1, max_pages):
        page_url = queue.pop(0)
        if page_url in visited:
            continue
        visited.add(page_url)
        try:
            response = get(page_url, timeout=timeout, retries=1)
        except Exception as exc:
            errors.append(f"{page_url}: {exc}")
            continue
        html = response.text or ""
        pages.append(str(response.url))
        for path in extract_script_paths(html):
            if path not in paths:
                paths.append(path)
        if len(pages) >= max_pages:
            continue
        # The public landing page currently loads ``yjjy/wenzhang.js``;
        # that document writes the actual 83191.html iframe.  Follow only
        # local wrapper documents, never the dozens of prediction scripts.
        html_links = html.replace("\\'", "'").replace('\\"', '"')
        for path in extract_iframe_paths(html_links):
            child = urljoin(page_url, path)
            if urlparse(child).netloc == base_origin and child not in visited:
                queue.append(child)
        for value in EMBED_RE.findall(html_links):
            path = urlparse(value).path or ""
            if not path or "/chajie/" in path or "/tp/" in path:
                continue
            if not path.endswith((".html", ".htm", ".js")):
                continue
            child = urljoin(page_url, value)
            if urlparse(child).netloc == base_origin and child not in visited:
                queue.append(child)
    return paths, pages, errors


def local_inventory(cfg: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    registered: dict[str, list[dict[str, Any]]] = {}
    sources_folder = ROOT / "sources"
    for row in cfg.get("sources") or []:
        if row.get("site_family") != SITE_FAMILY:
            continue
        extra = row.get("extra") or {}
        path_key = extra.get("path")
        if not path_key:
            script_path = sources_folder / Path(row.get("script_path") or f"{row['source_id']}.py").name
            if script_path.exists():
                match = URL_RE.search(script_path.read_text(encoding="utf-8"))
                if match:
                    path_key = match.group(1)
        if not path_key:
            continue
        if not str(path_key).startswith("/"):
            path_key = "/chajie/" + str(path_key).lstrip("/")
        registered.setdefault(str(path_key), []).append(
            {
                "source_id": row["source_id"],
                "source_name": row.get("source_name") or row["source_id"],
                "enabled": bool(row.get("enabled", True)),
            }
        )
    return registered


def _ignore_reason(path: str, ignored: dict[str, str]) -> str | None:
    name = Path(path).name
    return ignored.get(path) or ignored.get(name)


def compare_inventory(
    paths: list[str],
    cfg: dict[str, Any],
    *,
    ignored: dict[str, str] | None = None,
) -> dict[str, Any]:
    registered = local_inventory(cfg)
    ignored = ignored if ignored is not None else catalog_config(cfg)["ignored"]
    items: list[dict[str, Any]] = []
    seen: set[str] = set()
    for path in paths:
        if path in seen:
            continue
        seen.add(path)
        sources = registered.get(path, [])
        reason = _ignore_reason(path, ignored)
        if reason:
            coverage = "ignored"
        elif any(source["enabled"] for source in sources):
            coverage = "enabled"
        elif sources:
            coverage = "disabled"
        else:
            coverage = "untracked"
        items.append(
            {
                "path": path,
                "name": Path(path).stem,
                "coverage": coverage,
                "sources": sources,
                "ignore_reason": reason,
            }
        )

    current = {item["path"] for item in items}
    missing = []
    for path, sources in registered.items():
        enabled = [source for source in sources if source["enabled"]]
        if enabled and path not in current:
            missing.append({"path": path, "sources": enabled})

    return {
        "items": items,
        "pending": [item for item in items if item["coverage"] == "untracked"],
        "missing": missing,
        "content_total": len(items),
        "enabled_components": sum(item["coverage"] == "enabled" for item in items),
        "known_components": sum(item["coverage"] != "untracked" for item in items),
    }


def _sample(host: str, path: str) -> str:
    try:
        response = get(f"{host.rstrip('/')}{path}", timeout=8, retries=0)
    except Exception as exc:
        return f"Error: {exc}"
    text = strip_html(response.text or "")
    return " ".join(text.split())[:80]


def scan(*, record: bool = True) -> dict[str, Any]:
    started_at = now_iso()
    started = time.monotonic()
    cfg = load_config()
    settings = catalog_config(cfg)
    hosts, discovery_errors = discover_api_hosts(
        settings["entry_urls"],
        fallback_hosts=settings["fallback_hosts"],
        deadline_sec=20.0,
    )
    if not hosts:
        raise RuntimeError("未发现可用的 83191.com 线路")
    active_host = hosts[0]
    paths, pages_scanned, page_errors = discover_homepage_scripts(active_host)
    compared = compare_inventory(paths, cfg, ignored=settings["ignored"])
    for item in compared["pending"]:
        item["sample"] = _sample(active_host, item["path"])
    result = {
        "ok": True,
        "enabled": watcher_enabled(),
        "interval_minutes": interval_minutes(),
        "active_host": active_host,
        "hosts": hosts,
        "last_attempt_at": started_at,
        "last_success_at": now_iso(),
        "last_error": None,
        "homepage_pages": pages_scanned,
        "pages_scanned": pages_scanned,
        "script_paths": paths,
        "homepage_errors": page_errors[-10:],
        "scan_duration_ms": int((time.monotonic() - started) * 1000),
        "discovery_warnings": discovery_errors[-10:],
        **compared,
    }
    if record:
        create_all()
        save_api_hosts(hosts)
        _record(result)
        _write_report(result)
    return result


def _record(result: dict[str, Any]) -> None:
    with session_scope(guard=False) as session:
        session.merge(Setting(key=SETTING_KEY, value=result))


def _write_report(result: dict[str, Any]) -> None:
    target = ROOT / "out" / "tongtian-catalog"
    target.mkdir(parents=True, exist_ok=True)
    (target / "latest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    labels = {"enabled": "已启用", "disabled": "已登记停用", "ignored": "已忽略", "untracked": "待接入"}
    lines = [
        "# 83191.com 通天论坛栏目自动巡检",
        "",
        f"- 巡检时间：{result['last_success_at']}",
        f"- 当前线路：`{result['active_host']}`",
        f"- 深度页面：{len(result.get('homepage_pages') or [])}；扫描耗时：{result.get('scan_duration_ms', 0)} ms",
        f"- 首页脚本：{result['content_total']}；已纳管/已知：{result['known_components']}；已启用：{result['enabled_components']}；待接入：{len(result['pending'])}；首页已下架：{len(result['missing'])}",
        "",
        "| 脚本 | 状态 | 本地来源 | 说明 |",
        "|---|---|---|---|",
    ]
    for item in result["items"]:
        local = "、".join(source["source_id"] for source in item["sources"]) or "—"
        note = item.get("ignore_reason") or item.get("sample") or ""
        lines.append(
            f"| `{item['path']}` | {labels.get(item['coverage'], item['coverage'])} | {local} | {note.replace('|', '/')} |"
        )
    if result["missing"]:
        lines += ["", "## 首页已下架但仍启用", ""]
        for item in result["missing"]:
            names = "、".join(source["source_id"] for source in item["sources"])
            lines.append(f"- `{item['path']}`：{names}")
    (target / "latest.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def status() -> dict[str, Any]:
    create_all()
    with session_scope(guard=False) as session:
        row = session.get(Setting, SETTING_KEY)
        value = dict(row.value or {}) if row else {}
    value.setdefault("ok", False)
    value["enabled"] = watcher_enabled()
    value["interval_minutes"] = interval_minutes()
    value.setdefault("open_issue_count", 0)
    value.setdefault("items", [])
    value.setdefault("pending", [])
    value.setdefault("missing", [])
    return value


def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
    parser = argparse.ArgumentParser(description="自动巡检 83191.com 通天论坛首页脚本")
    sub = parser.add_subparsers(dest="command", required=True)
    scan_parser = sub.add_parser("scan")
    scan_parser.add_argument("--record", action="store_true")
    sub.add_parser("status")
    args = parser.parse_args()
    result = status() if args.command == "status" else scan(record=args.record)
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    if not result.get("ok"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
