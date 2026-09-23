from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail, parse_common_args
from common.source_fetch import load_page
from common.source_rows import ParsedRow, build_prediction
from dj_util import ANY_PERIOD_RE, atoms_num, atoms_xiao, claimed_from, html_to_lines, urls_for

SOURCE_ID = "jue_mi_mashi"
SOURCE_NAME = "绝密码师"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1790067938745")


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    for i, ln in enumerate(lines):
        m = ANY_PERIOD_RE.match(ln)
        if not m:
            continue
        period = m.group(1)
        body: list[str] = []
        for j in range(i + 1, min(i + 6, len(lines))):
            if ANY_PERIOD_RE.match(lines[j]) or "顶尖大师" in lines[j]:
                break
            body.append(lines[j])
        chunk = " ".join([ln] + body)
        claim_line = next((l for l in body if "开奖" in l or "開獎" in l), "")
        claimed = claimed_from(claim_line.replace("🀄", "中"))
        
        # Check if pending period
        if "88" in claim_line or "天天爆庄" in chunk or "内幕在手" in chunk:
            claimed["status"] = "pending"
            rows.append(ParsedRow(period_raw=period, preds=[], claimed=claimed, raw_text=chunk))
            continue

        xiaos: list[dict] = []
        nums: list[dict] = []
        for bline in body:
            if "开奖" in bline or "開獎" in bline:
                continue
            x = atoms_xiao(bline)
            if x and len(bline) <= 10:
                xiaos.extend(x)
            n = atoms_num(bline)
            if n:
                nums.extend(n)

        atoms = xiaos + nums
        if atoms:
            rows.append(ParsedRow(period_raw=period, preds=atoms, claimed=claimed, raw_text=chunk))
    return rows


def build(lottery: str, period: str | None, fixture: str | None):
    page = load_page(urls=URLS, fixture=fixture)
    return build_prediction(
        page=page,
        lottery=lottery,
        period=period,
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        rows=extract(page.text),
        empty_error=f"{SOURCE_NAME} 未提取到有效预测数据",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
