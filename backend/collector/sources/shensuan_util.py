"""Utility helpers for parsing 70246.com (神算集团 / ss49) predictions."""

from __future__ import annotations

import html
import re
from pathlib import Path
from typing import Any

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.period import normalize, year_of
from common.parse_pred import strip_html
from common.sites.shensuan import (
    api_hosts as ss_api_hosts,
    fetch_decrypted_articles,
    urls_for as ss_urls_for,
)
from common.source_base import emit, fail, now_cn, parse_common_args
from dingji_util import atoms_bose, atoms_num, atoms_twoface, atoms_wei, atoms_xiao

XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"
XIAO_SET = set(XIAO)


def api_hosts() -> list[str]:
    return ss_api_hosts()


def urls_for(path: str) -> list[str]:
    return ss_urls_for(path)


def parse_shensuan_article_periods(content_html: str) -> list[dict[str, Any]]:
    """Parse tab panels from Shensuan group articles (e.g. ID 24464 内幕来料-一肖一码)."""
    chunks = re.split(r"<div[^>]*class=[\"'][^\"']*tab-panel[^\"']*[\"']", content_html)
    if len(chunks) <= 1:
        return []

    row_pattern = re.compile(
        r"<span[^>]*class=[\"']row-label[\"']>([^<]+)</span>\s*<span[^>]*class=[\"']row-value[\"']>(.*?)</span>\s*<span[^>]*class=[\"']row-hint[\"']",
        re.DOTALL,
    )

    periods_data: list[dict[str, Any]] = []

    for chunk in chunks[1:]:
        per_m = re.search(r"data-period=[\"'](\d+)[\"']", chunk)
        if not per_m:
            continue
        period_raw = per_m.group(1)

        # Claimed extraction
        res_m = re.search(r"开奖结果:\s*([^\s<]+)", chunk)
        claimed_text = res_m.group(1) if res_m else ""
        num_m = re.search(r"class=[\"']result-number[\"']>(\d+)</span>", chunk)
        claimed_num = num_m.group(1) if num_m else ""

        xiao_val: str | None = None
        num_val: str | None = None
        status = "unknown"

        if "?" in claimed_text or claimed_num == "00" or not claimed_text:
            status = "pending"
        else:
            for ch in claimed_text:
                if ch in XIAO_SET:
                    xiao_val = ch
                    break
            digits = re.search(r"(?<!\d)(\d{1,2})(?!\d)", f"{claimed_text} {claimed_num}")
            if digits:
                num_val = f"{int(digits.group(1)):02d}"

        # Extract prediction rows
        rows: dict[str, str] = {}
        for lbl, val in row_pattern.findall(chunk):
            key = lbl.strip().rstrip(":：")
            cleaned_val = strip_html(val).strip()
            rows[key] = cleaned_val

        periods_data.append(
            {
                "period_raw": period_raw,
                "status": status,
                "xiao": xiao_val,
                "num": num_val,
                "claimed_raw": f"{claimed_text} {claimed_num}".strip(),
                "rows": rows,
                "full_text": strip_html(chunk)[:1024],
            }
        )

    return periods_data


def build_shensuan_pred(
    *,
    source_id: str,
    source_name: str,
    play_type: str,
    hit_mode: str,
    sub_label: str,
    kind: str,
    urls: list[str] | None = None,
    article_id: int = 24464,
    lottery: str = "macau",
    period: str | None = None,
    fixture: str | None = None,
) -> PredV1:
    """Generic builder for Shensuan (70246.com) multi-play prediction sources."""
    articles, final_url = fetch_decrypted_articles(fixture=fixture)
    target_article = next((a for a in articles if a.get("id") == article_id), None)
    if not target_article:
        raise ValueError(f"未找到神算文章 ID {article_id}")

    parsed_periods = parse_shensuan_article_periods(target_article.get("content", ""))
    if not parsed_periods:
        raise ValueError(f"{source_name} 未能解析出任何期数数据")

    chash = sha256_text(str(target_article.get("content", "")))
    year = year_of(period) if period else None
    items: list[PredItem] = []
    seen = set()

    clean_sub_label = sub_label.strip().rstrip(":：")

    for pdata in parsed_periods:
        try:
            per = normalize(lottery, pdata["period_raw"], year=year)
        except ValueError:
            continue

        if period and per != period and not str(period).endswith(str(pdata["period_raw"])):
            continue

        if per in seen:
            continue

        val_text = pdata["rows"].get(clean_sub_label, "")
        if not val_text:
            # If the current period does not contain this specific play row, skip unless it's pending
            if pdata["status"] != "pending":
                continue

        if kind == "xiao":
            atom_dicts = atoms_xiao(val_text)
        elif kind == "num":
            atom_dicts = atoms_num(val_text)
        elif kind == "twoface":
            atom_dicts = atoms_twoface(val_text)
        elif kind == "wei":
            atom_dicts = atoms_wei(val_text)
        elif kind == "bose":
            atom_dicts = atoms_bose(val_text)
        else:
            atom_dicts = atoms_xiao(val_text) + atoms_num(val_text)

        status = pdata["status"]
        xiao_val = pdata["xiao"]
        num_val = pdata["num"]

        if status != "pending":
            if kind == "xiao" and xiao_val:
                status = "hit" if any(a["value"] == xiao_val for a in atom_dicts) else "miss"
            elif kind == "num" and num_val:
                status = "hit" if any(a["value"] == num_val for a in atom_dicts) else "miss"
            elif kind == "twoface" and num_val:
                n = int(num_val)
                is_even = (n % 2 == 0)
                is_big = (n >= 25)
                hit = False
                for a in atom_dicts:
                    if a["kind"] == "odd":
                        hit = hit or (a["value"] == "双" if is_even else a["value"] == "单")
                    elif a["kind"] == "size":
                        hit = hit or (a["value"] == "大" if is_big else a["value"] == "小")
                status = "hit" if hit else "miss"

        preds = [
            PredAtom(kind=a["kind"], value=str(a["value"]), text=a.get("text"))
            for a in atom_dicts
        ]

        if not preds and status != "pending":
            continue

        seen.add(per)
        items.append(
            PredItem(
                period_raw=str(pdata["period_raw"]),
                period=per,
                published_at=None,
                preds=preds,
                claimed=Claimed(
                    status=status,
                    xiao=xiao_val,
                    num=num_val,
                    raw=pdata["claimed_raw"],
                ),
                raw_text=f"{clean_sub_label}: {val_text}".strip()[:1024],
            )
        )

    if not items:
        raise ValueError(f"{source_name} 解析条目为空")

    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=source_id,
        source_name=source_name,
        site_family="shensuan_70246",
        lottery=lottery,
        play_type=play_type,
        hit_mode=hit_mode,
        fetched_at=now_cn(),
        final_url=final_url,
        content_hash=chash,
        items=items,
        error=None,
    )
