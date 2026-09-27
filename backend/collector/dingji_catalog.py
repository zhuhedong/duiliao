"""Discover, diff and record the 77452.com / 澳门顶级 / 顶级论坛 content catalog."""

from __future__ import annotations

import argparse
import hashlib
import html
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
MAX_AMTZ_PROBE = 100
PERIOD_RE = re.compile(r"(?:第\s*)?(\d{1,7})\s*期")


def now_iso() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def _split_env(name: str) -> list[str]:
    return [value for value in re.split(r"[,;\s]+", os.getenv(name, "").strip()) if value]


def scan_concurrency() -> int:
    try:
        return max(1, min(int(os.getenv("PRED_DINGJI_SCAN_CONCURRENCY", "12")), 32))
    except ValueError:
        return 12


def max_amtz_probe() -> int:
    try:
        return max(TOTAL_AMTZ_PAGES, min(int(os.getenv("PRED_DINGJI_MAX_PAGE", str(MAX_AMTZ_PROBE))), 200))
    except ValueError:
        return MAX_AMTZ_PROBE


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


def _parse_amtz_records(raw: str) -> tuple[str, list[dict[str, Any]]]:
    """Parse the live table markup, retaining evidence for governance review."""
    title_match = re.search(r"<h1[^>]*>(.*?)</h1>", raw, re.I | re.S)
    title = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", title_match.group(1))).split()) if title_match else ""
    records: list[dict[str, Any]] = []
    cells = re.findall(r"<tr\b[^>]*>\s*<td[^>]*>(.*?)</td>\s*</tr>", raw, re.I | re.S)
    for cell in cells:
        cleaned = html.unescape(re.sub(r"<[^>]+>", " ", cell))
        cleaned = " ".join(cleaned.replace("\xa0", " ").split())
        period_match = PERIOD_RE.search(cleaned)
        if not period_match:
            continue
        compact = re.sub(r"\s+", "", cleaned)
        claim_match = re.search(r"(?:开|開)\s*[:：]?\s*([^准準错錯挂掛\s]+)", cleaned)
        claim = claim_match.group(1) if claim_match else ""
        if any(mark in compact for mark in ("0000", "?00", "？00", "發00", "发00")):
            status = "pending"
        elif any(mark in compact for mark in ("错", "錯", "挂", "掛", "未中")):
            status = "miss"
        elif any(mark in compact for mark in ("准", "準", "中")):
            status = "hit"
        else:
            status = "unknown"
        records.append(
            {
                "period": int(period_match.group(1)),
                "status": status,
                "claim": claim[:40],
                "sample": cleaned[:360],
            }
        )
    return title, records


def scan_amtz_page(host: str, page_idx: int) -> dict[str, Any]:
    path = f"/htm/tz/amtz/{page_idx:03d}.html"
    url = f"{host.rstrip('/')}{path}"
    try:
        # 404 is an expected result while discovering the end of the live
        # range; do not retry it as if it were a transient source failure.
        r = get(url, timeout=5, retries=0)
        text = r.text
        title, records = _parse_amtz_records(text)
        sample = records[0]["sample"] if records else " ".join(strip_html(text).split())[:120]
        name = re.sub(r"^.*?[【\[]|[】\]].*$", "", title).strip() or title or f"amtz_{page_idx:03d}"
        periods = [row["period"] for row in records]
        table_count = len(re.findall(r"<table\b", text, re.I))

        return {
            "path": path,
            "page_idx": page_idx,
            "name": name[:80],
            "sample": sample[:120],
            "ok": True,
            "available": True,
            "status_code": r.status_code,
            "title": title[:120],
            "content_kind": "prediction_table" if records else "empty_markup",
            "parser_hint": "amtz_table_rows" if records else "no_period_rows",
            "table_count": table_count,
            "record_count": len(records),
            "latest_period": max(periods) if periods else None,
            "status_counts": {status: sum(row["status"] == status for row in records) for status in ("hit", "miss", "pending", "unknown")},
            "records": records[-12:],
            "content_hash": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        }
    except Exception as exc:
        return {
            "path": path,
            "page_idx": page_idx,
            "name": f"amtz_{page_idx:03d}",
            "sample": f"Error: {exc}",
            "ok": False,
            "available": False,
            "retired": "404" in str(exc) or "Not Found" in str(exc),
            "status_code": None,
            "content_kind": "fetch_error",
            "parser_hint": "fetch_error",
            "record_count": 0,
            "latest_period": None,
            "content_hash": None,
        }


def analyze_gateway(entries: list[str], active_host: str, expected_title: str) -> dict[str, Any]:
    """Record the entry/gateway identity separately from the prediction path."""
    probes: list[dict[str, Any]] = []
    for entry in [*entries, active_host.rstrip("/") + "/"]:
        try:
            response = get(entry, timeout=8, retries=1)
            raw = response.text or ""
            title_match = re.search(r"<title[^>]*>(.*?)</title>", raw, re.I | re.S)
            title = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", title_match.group(1))).split()) if title_match else ""
            probes.append(
                {
                    "entry": entry,
                    "final_url": str(response.url),
                    "status_code": response.status_code,
                    "title": title[:160],
                    "prediction_markers": len(re.findall(r"amtz|九肖|特码|期", raw, re.I)),
                    "identity_match": expected_title in title or "顶级论坛" in raw,
                    "content_hash": hashlib.sha256(raw.encode("utf-8")).hexdigest() if raw else None,
                }
            )
        except Exception as exc:
            probes.append({"entry": entry, "ok": False, "error": str(exc)})
    return {
        "probes": probes,
        "identity": "matched" if any(item.get("identity_match") for item in probes) else "route_only_or_mismatch",
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
    gateway_analysis = analyze_gateway(settings["entry_urls"], active_host, settings["expected_title"])
    registered = local_inventory(cfg)
    ignored = settings["ignored"]

    # Probe beyond the currently observed range.  The live site has no
    # reliable index for these pages, so the page set itself is discovered
    # from responses instead of being treated as a hard-coded catalog.
    probe_total = max_amtz_probe()
    with ThreadPoolExecutor(max_workers=min(scan_concurrency(), probe_total)) as executor:
        probes = list(executor.map(lambda idx: scan_amtz_page(active_host, idx), range(1, probe_total + 1)))
    infos = [item for item in probes if item.get("available")]

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
    retired = [item for item in probes if not item.get("available") and item.get("retired")]
    failed = [item for item in probes if not item.get("available") and not item.get("retired")]
    all_periods = [int(item["latest_period"]) for item in items if item.get("latest_period") is not None]

    result = {
        "ok": True,
        "enabled": watcher_enabled(),
        "interval_minutes": interval_minutes(),
        "active_host": active_host,
        "hosts": hosts,
        "gateway_analysis": gateway_analysis,
        "last_attempt_at": started_at,
        "last_success_at": now_iso(),
        "last_error": None,
        "scan_concurrency": min(scan_concurrency(), probe_total),
        "probed_pages": probe_total,
        "observed_pages": len(items),
        "retired_pages": len(retired),
        "scan_duration_ms": int((time.monotonic() - started) * 1000),
        "failed_components": len(failed),
        "scan_errors": [
            {"path": item["path"], "error": item.get("sample", "")}
            for item in failed
        ],
        "content_total": len(items),
        "enabled_components": enabled_count,
        "known_components": known_count,
        "items": items,
        "pending": pending,
        "deep_analysis": {
            "pages_probed": probe_total,
            "pages_observed": len(items),
            "retired_pages": len(retired),
            "latest_period": max(all_periods, default=None),
            "record_count": sum(int(item.get("record_count") or 0) for item in items),
            "parser_hints": {
                hint: sum(item.get("parser_hint") == hint for item in items)
                for hint in sorted({str(item.get("parser_hint") or "unknown") for item in items})
            },
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
        f"- 入口身份：{(result.get('gateway_analysis') or {}).get('identity', 'unknown')}；探测页：{result.get('probed_pages', 0)}；实际栏目页：{result['content_total']}；已纳管/已知：{result['known_components']}；已启用：{result['enabled_components']}；待接入：{len(result['pending'])}",
        f"- 已下线页：{result.get('retired_pages', 0)}；失败：{result.get('failed_components', 0)}；并发探测：{result.get('scan_concurrency', 1)}；扫描耗时：{result.get('scan_duration_ms', 0)} ms",
        f"- 深解析期数：{(result.get('deep_analysis') or {}).get('record_count', 0)}；最新期：{(result.get('deep_analysis') or {}).get('latest_period') or '—'}",
        "",
        "| 序号 | 相对路径 | 栏目推断 | 状态 | 解析契约 | 期数 | 最新期 | 本地来源 | 样本片段 |",
        "|---|---|---|---|---|---:|---:|---|---|",
    ]
    for item in result["items"]:
        local = "、".join(s["source_id"] for s in item["sources"]) or "—"
        display_name = item["name"].replace("|", "\\|")
        sample_disp = item["sample"][:40].replace("|", "\\|")
        lines.append(
            f"| {item['page_idx']:03d} | `{item['path']}` | {display_name} | "
            f"{labels.get(item['coverage'], item['coverage'])} | {item.get('parser_hint', '—')} | "
            f"{item.get('record_count', 0)} | {item.get('latest_period') or '—'} | {local} | {sample_disp} |"
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
    value.setdefault("deep_analysis", {})
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
