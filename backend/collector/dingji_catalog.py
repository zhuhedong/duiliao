"""Discover, diff and record the 77452.com / 澳门顶级 / 顶级论坛 content catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import select

from common import ROOT
from common.http import get
from common.parse_pred import strip_html
from common.sites.dingji import (
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
SETTING_KEY = "dingji_catalog"
SITE_FAMILY = "dingji_77452"
TOTAL_AMTZ_PAGES = 69


def now_iso() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def _split_env(name: str) -> list[str]:
    return [value for value in re.split(r"[,;\s]+", os.getenv(name, "").strip()) if value]


def scan_concurrency() -> int:
    try:
        return max(1, min(int(os.getenv("PRED_DINGJI_SCAN_CONCURRENCY", "12")), 32))
    except ValueError:
        return 12


def watcher_enabled() -> bool:
    return os.getenv("PRED_DINGJI_CATALOG_ENABLED", "1").strip().lower() not in {"0", "false", "no", "off"}


def interval_minutes() -> int:
    try:
        return max(5, min(int(os.getenv("PRED_CATALOG_INTERVAL_MIN", "15")), 1440))
    except ValueError:
        return 15


def catalog_config(cfg: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = cfg or load_config()
    family = dict((cfg.get("site_families") or {}).get(SITE_FAMILY) or {})
    entries = _split_env("PRED_DINGJI_ENTRY") or family.get("entry_urls") or list(DEFAULT_ENTRIES)
    configured_hosts = _split_env("PRED_DINGJI_HOSTS") or load_cached_api_hosts() or list(STATIC_API_HOSTS)
    ignored_raw = family.get("catalog_ignore") or {}
    ignored: dict[str, str] = {}
    if isinstance(ignored_raw, dict):
        ignored = {str(k): str(v or "配置为非资料模块") for k, v in ignored_raw.items()}
    return {
        "entry_urls": [str(v).rstrip("/") + "/" for v in entries],
        "fallback_hosts": [*configured_hosts, *load_cached_api_hosts(), *STATIC_API_HOSTS],
        "expected_title": str(family.get("expected_title") or "顶级"),
        "ignored": ignored,
    }


def local_inventory(cfg: dict[str, Any]) -> dict[str, list[dict]]:
    """Map path/identifier (e.g. /htm/tz/amtz/001.html) to registered sources."""
    registered: dict[str, list[dict]] = {}
    sources_folder = ROOT / "sources"
    for row in cfg.get("sources") or []:
        if row.get("site_family") != SITE_FAMILY:
            continue
        extra = row.get("extra") or {}
        path_key = extra.get("path")
        # If not in extra, check script file for URLS
        if not path_key:
            script_path = sources_folder / Path(row.get("script_path") or f"{row['source_id']}.py").name
            if script_path.exists():
                text = script_path.read_text(encoding="utf-8")
                m = re.search(r'urls_for\(["\']([^"\']+)["\']\)', text)
                if m:
                    path_key = m.group(1)
        if path_key:
            registered.setdefault(path_key, []).append(
                {
                    "source_id": row["source_id"],
                    "source_name": row.get("source_name") or row["source_id"],
                    "enabled": bool(row.get("enabled", True)),
                }
            )
    return registered


def scan_amtz_page(host: str, page_idx: int) -> dict[str, Any]:
    path = f"/htm/tz/amtz/{page_idx:03d}.html"
    url = f"{host.rstrip('/')}{path}"
    try:
        r = get(url, timeout=5, retries=1)
        text = r.text
        # Extract title & sample
        m_td = re.search(r"<td[^>]*>(.*?)</td>", text, re.I | re.S)
        raw_td = m_td.group(1) if m_td else ""
        sample = " ".join(re.sub(r"<[^>]+>", " ", raw_td).split())
        
        # Extract column name from e.g. "264期: 九肖 【...】" or "259期:【 精选24码 】"
        col_m = re.search(r"\d{1,7}\s*期\s*[:：]?\s*【?\s*([^【】:：\d]{2,10})", sample)
        name = col_m.group(1).strip() if col_m else f"amtz_{page_idx:03d}"

        return {
            "path": path,
            "page_idx": page_idx,
            "name": name,
            "sample": sample[:120],
            "ok": True,
            "content_hash": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        }
    except Exception as exc:
        return {
            "path": path,
            "page_idx": page_idx,
            "name": f"amtz_{page_idx:03d}",
            "sample": f"Error: {exc}",
            "ok": False,
            "content_hash": None,
        }


def scan(*, record: bool = True) -> dict[str, Any]:
    started_at = now_iso()
    started = time.monotonic()
    cfg = load_config()
    settings = catalog_config(cfg)
    hosts, discovery_errors = discover_api_hosts(
        settings["entry_urls"],
        fallback_hosts=settings["fallback_hosts"],
        deadline_sec=15.0,
    )
    if not hosts:
        raise RuntimeError("未发现可用的 77452.com 线路")
    active_host = hosts[0]
    registered = local_inventory(cfg)
    ignored = settings["ignored"]

    # The 69 fixed subpages are independent.  Parallel probes keep a full
    # catalog sweep within a practical interval while each request retains its
    # own timeout and failure record.
    with ThreadPoolExecutor(max_workers=min(scan_concurrency(), TOTAL_AMTZ_PAGES)) as executor:
        infos = list(executor.map(lambda idx: scan_amtz_page(active_host, idx), range(1, TOTAL_AMTZ_PAGES + 1)))

    items: list[dict[str, Any]] = []
    for info in infos:
        path = info["path"]
        idx = int(info.get("page_idx") or 0)
        sources = registered.get(path, [])
        if path in ignored or str(idx) in ignored:
            coverage = "ignored"
        elif any(s["enabled"] for s in sources):
            coverage = "enabled"
        elif sources:
            coverage = "disabled"
        else:
            coverage = "untracked"

        items.append(
            {
                **info,
                "coverage": coverage,
                "sources": sources,
                "ignore_reason": ignored.get(path) or ignored.get(str(idx)),
            }
        )

    pending = [i for i in items if i["coverage"] == "untracked"]
    enabled_count = sum(i["coverage"] == "enabled" for i in items)
    known_count = sum(i["coverage"] != "untracked" for i in items)

    result = {
        "ok": True,
        "enabled": watcher_enabled(),
        "interval_minutes": interval_minutes(),
        "active_host": active_host,
        "hosts": hosts,
        "last_attempt_at": started_at,
        "last_success_at": now_iso(),
        "last_error": None,
        "scan_concurrency": min(scan_concurrency(), TOTAL_AMTZ_PAGES),
        "scan_duration_ms": int((time.monotonic() - started) * 1000),
        "failed_components": sum(not item.get("ok") for item in items),
        "scan_errors": [
            {"path": item["path"], "error": item.get("sample", "")}
            for item in items
            if not item.get("ok")
        ],
        "content_total": len(items),
        "enabled_components": enabled_count,
        "known_components": known_count,
        "items": items,
        "pending": pending,
        "discovery_warnings": discovery_errors[-10:],
    }

    if record:
        create_all()
        save_api_hosts(hosts)
        _record_success(result)
        _write_report(result)
    return result


def _record_success(result: dict[str, Any]) -> None:
    with session_scope(guard=False) as session:
        session.merge(Setting(key=SETTING_KEY, value=result))


def _write_report(result: dict[str, Any]) -> None:
    target = ROOT / "out" / "dingji-catalog"
    target.mkdir(parents=True, exist_ok=True)
    (target / "latest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    
    labels = {
        "enabled": "已启用",
        "disabled": "已登记停用",
        "ignored": "已忽略",
        "untracked": "待接入",
    }
    lines = [
        "# 77452.com 顶级论坛栏目自动巡检",
        "",
        f"- 巡检时间：{result['last_success_at']}",
        f"- 当前线路：`{result['active_host']}`",
        f"- 总子栏目页：{result['content_total']}；已纳管/已知：{result['known_components']}；已启用：{result['enabled_components']}；待接入：{len(result['pending'])}；失败：{result.get('failed_components', 0)}",
        f"- 并发探测：{result.get('scan_concurrency', 1)}；扫描耗时：{result.get('scan_duration_ms', 0)} ms",
        "",
        "| 序号 | 相对路径 | 栏目推断 | 状态 | 本地来源 | 样本片段 |",
        "|---|---|---|---|---|---|",
    ]
    for item in result["items"]:
        local = "、".join(s["source_id"] for s in item["sources"]) or "—"
        display_name = item["name"].replace("|", "\\|")
        sample_disp = item["sample"][:40].replace("|", "\\|")
        lines.append(
            f"| {item['page_idx']:03d} | `{item['path']}` | {display_name} | "
            f"{labels.get(item['coverage'], item['coverage'])} | {local} | {sample_disp} |"
        )
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
    value["enabled"] = watcher_enabled()
    return value


def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
    parser = argparse.ArgumentParser(description="自动巡检 77452.com 顶级论坛栏目")
    sub = parser.add_subparsers(dest="command", required=True)
    scan_parser = sub.add_parser("scan")
    scan_parser.add_argument("--record", action="store_true", help="写入状态与报告")
    sub.add_parser("status")
    args = parser.parse_args()

    if args.command == "status":
        res = status()
    else:
        res = scan(record=args.record)
    sys.stdout.write(json.dumps(res, ensure_ascii=False) + "\n")
    if not res.get("ok"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
