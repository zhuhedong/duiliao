"""Discover, diff and record the 70246.com / 神算集团 content catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from common import ROOT
from common.http import get
from common.parse_pred import strip_html
from common.sites.shensuan import (
    DEFAULT_ENTRIES,
    STATIC_API_HOSTS,
    discover_api_hosts,
    fetch_decrypted_articles,
    load_cached_api_hosts,
    origin,
    save_api_hosts,
)
from db import session_scope
from registry import load_config, sources_dir
from schema import Setting, create_all

TZ8 = timezone(timedelta(hours=8))
SETTING_KEY = "shensuan_catalog"
SITE_FAMILY = "shensuan_70246"

log = logging.getLogger("pred.shensuan_catalog")


def now_iso() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def _split_env(name: str) -> list[str]:
    return [value for value in re.split(r"[,;\s]+", os.getenv(name, "").strip()) if value]


def watcher_enabled() -> bool:
    return os.getenv("PRED_SHENSUAN_CATALOG_ENABLED", "1").strip().lower() not in {"0", "false", "no", "off"}


def interval_minutes() -> int:
    try:
        return max(5, min(int(os.getenv("PRED_CATALOG_INTERVAL_MIN", "15")), 1440))
    except ValueError:
        return 15


def catalog_config(cfg: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = cfg or load_config()
    family = dict((cfg.get("site_families") or {}).get(SITE_FAMILY) or {})
    entries = _split_env("PRED_SHENSUAN_ENTRY") or family.get("entry_urls") or list(DEFAULT_ENTRIES)
    configured_hosts = _split_env("PRED_SHENSUAN_HOSTS") or family.get("fallback_hosts") or []
    ignored_raw = family.get("catalog_ignore") or {}
    ignored: dict[str, str] = {}
    if isinstance(ignored_raw, dict):
        ignored = {str(k): str(v or "配置为非资料模块") for k, v in ignored_raw.items()}
    return {
        "entry_urls": [str(v).rstrip("/") + "/" for v in entries],
        "fallback_hosts": [*configured_hosts, *load_cached_api_hosts(), *STATIC_API_HOSTS],
        "expected_title": str(family.get("expected_title") or "神算"),
        "ignored": ignored,
    }


def local_inventory(cfg: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    """Map upstream_id (e.g. '24464') or path to registered sources."""
    registered: dict[str, list[dict[str, Any]]] = {}
    for row in cfg.get("sources") or []:
        if row.get("site_family") != SITE_FAMILY:
            continue
        extra = row.get("extra") or {}
        entry = {
            "source_id": row["source_id"],
            "source_name": row.get("source_name") or row["source_id"],
            "enabled": bool(row.get("enabled", True)),
        }
        upstream_id = str(extra.get("upstream_id") or "").strip()
        path = str(extra.get("path") or "").strip()

        keys = set()
        if upstream_id:
            keys.add(upstream_id)
            if path:
                keys.add(f"{path}#{upstream_id}")
        elif path:
            keys.add(path)
        else:
            keys.add(str(row["source_id"]))

        for k in keys:
            registered.setdefault(k, []).append(entry)

    return registered


def scan(*, record: bool = True) -> dict[str, Any]:
    started = time.monotonic()
    started_at = now_iso()
    cfg = load_config()
    cat_cfg = catalog_config(cfg)
    registered = local_inventory(cfg)
    ignored = cat_cfg["ignored"]

    hosts, discovery_errors = discover_api_hosts(
        cat_cfg["entry_urls"],
        fallback_hosts=cat_cfg["fallback_hosts"],
        deadline_sec=25.0,
    )
    active_host = hosts[0] if hosts else "none"

    items: list[dict[str, Any]] = []
    seen_ids: set[str] = set()

    for lt, lt_name in ((2, "澳门六合彩"), (1, "香港六合彩")):
        path = f"/api/index/content_list/{lt}"
        try:
            articles, final_url = fetch_decrypted_articles(path)
        except Exception as exc:
            log.warning("拉取神算文章列表失败 (%s): %s", path, exc)
            continue

        for art in articles:
            aid = str(art.get("id") or "")
            if not aid or aid in seen_ids:
                continue
            seen_ids.add(aid)

            title = str(art.get("title") or f"文章-{aid}")
            full_path = f"{path}#{aid}"
            reason = ignored.get(aid) or ignored.get(full_path)
            sources = registered.get(aid) or registered.get(full_path) or []

            content = art.get("content", "")
            preview = strip_html(content)[:120].strip()

            periods_found = re.findall(r"data-period=[\"'](\d+)[\"']", content)
            unique_periods = sorted({int(p) for p in periods_found if p.isdigit()}, reverse=True)

            if reason:
                coverage = "ignored"
            elif any(s["enabled"] for s in sources):
                coverage = "enabled"
            elif sources:
                coverage = "disabled"
            else:
                coverage = "untracked"

            items.append(
                {
                    "upstream_id": aid,
                    "path": full_path,
                    "name": title,
                    "lottery_type": lt,
                    "lottery_name": lt_name,
                    "coverage": coverage,
                    "sources": sources,
                    "ignore_reason": reason,
                    "sample": preview,
                    "record_count": len(unique_periods),
                    "latest_period": unique_periods[0] if unique_periods else None,
                    "analysis": {
                        "ok": True,
                        "article_id": aid,
                        "lottery_type": lt,
                        "record_count": len(unique_periods),
                        "latest_period": unique_periods[0] if unique_periods else None,
                        "parser_hint": "shensuan_tab_panel" if periods_found else "external_nav",
                    },
                }
            )

    pending = [i for i in items if i["coverage"] == "untracked"]
    enabled_count = sum(i["coverage"] == "enabled" for i in items)
    known_count = sum(i["coverage"] != "untracked" for i in items)
    all_periods = [int(i["latest_period"]) for i in items if i.get("latest_period") is not None]

    # Calculate missing registered sources
    current_ids = {i["upstream_id"] for i in items}
    missing: list[dict[str, Any]] = []
    for uid, src_list in registered.items():
        enabled_srcs = [s for s in src_list if s["enabled"]]
        if enabled_srcs and uid not in current_ids and not uid.startswith("/"):
            missing.append({"upstream_id": uid, "sources": enabled_srcs})

    result = {
        "ok": True,
        "enabled": watcher_enabled(),
        "interval_minutes": interval_minutes(),
        "active_host": active_host,
        "hosts": hosts,
        "gateway_analysis": {
            "identity": "神算集团 | 安全入口 (ss49/49841)",
            "network_gateways": cat_cfg["entry_urls"],
            "discovery_method": "hubs.dat -> pools.dat -> *.yyrxzj.com -> XOR decrypt",
        },
        "last_attempt_at": started_at,
        "last_success_at": now_iso(),
        "last_error": None,
        "probed_pages": len(items),
        "observed_pages": len(items),
        "scan_duration_ms": int((time.monotonic() - started) * 1000),
        "content_total": len(items),
        "enabled_components": enabled_count,
        "known_components": known_count,
        "items": items,
        "pending": pending,
        "missing": missing,
        "deep_analysis": {
            "articles_count": len(items),
            "latest_period": max(all_periods, default=None),
            "record_count": sum(int(item.get("record_count") or 0) for item in items),
        },
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
    target = ROOT / "out" / "shensuan-catalog"
    target.mkdir(parents=True, exist_ok=True)
    (target / "latest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

    labels = {
        "enabled": "已启用",
        "disabled": "已登记停用",
        "ignored": "已忽略",
        "untracked": "待接入",
    }
    lines = [
        "# 70246.com 神算集团栏目自动巡检",
        "",
        f"- 巡检时间：{result['last_success_at']}",
        f"- 当前线路：`{result['active_host']}`",
        f"- 实际栏目：{result['content_total']}；已纳管/已知：{result['known_components']}；已启用：{result['enabled_components']}；待接入：{len(result['pending'])}",
        "",
        "| 文章ID | 栏目名称 | 彩种 | 状态 | 解析契约 | 期数 | 最新期 | 本地来源 | 摘要 |",
        "|---|---|---|---|---|---:|---:|---|---|",
    ]
    for item in result["items"]:
        local = "、".join(s["source_id"] for s in item["sources"]) or "—"
        display_name = item["name"].replace("|", "\\|")
        sample_disp = item["sample"][:40].replace("|", "\\|")
        lines.append(
            f"| `{item['upstream_id']}` | {display_name} | {item['lottery_name']} | "
            f"{labels.get(item['coverage'], item['coverage'])} | {item.get('analysis', {}).get('parser_hint', '—')} | "
            f"{item.get('record_count', 0)} | {item.get('latest_period') or '—'} | {local} | {sample_disp} |"
        )
    (target / "latest.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def status() -> dict[str, Any]:
    create_all()
    with session_scope(guard=False) as session:
        row = session.get(Setting, SETTING_KEY)
        value = dict(row.value or {}) if row else {}
    value.setdefault("ok", False)
    value.setdefault("enabled", watcher_enabled())
    value.setdefault("interval_minutes", interval_minutes())
    value.setdefault("content_total", 0)
    value.setdefault("enabled_components", 0)
    value.setdefault("known_components", 0)
    value.setdefault("items", [])
    value.setdefault("pending", [])
    value.setdefault("missing", [])
    value.setdefault("ignored", [])
    value.setdefault("renamed", [])
    value.setdefault("open_issue_count", 0)
    value.setdefault("last_error", None)
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description="70246.com 神算集团栏目巡检")
    parser.add_argument("--scan", action="store_true", help="执行全量扫描并持久化")
    parser.add_argument("--status", action="store_true", help="输出当前数据库状态")
    args = parser.parse_args()

    if args.scan:
        res = scan(record=True)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif args.status:
        print(json.dumps(status(), ensure_ascii=False, indent=2))
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
