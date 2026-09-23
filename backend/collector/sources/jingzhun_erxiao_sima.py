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
from dj_util import atoms_num, atoms_xiao, claimed_from, html_to_lines, urls_for

SOURCE_ID = "jingzhun_erxiao_sima"
SOURCE_NAME = "精准二肖四码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1790067436523")


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    for i, ln in enumerate(lines):
        m = re.search(r"(\d+)\s*期\s*二肖四码\s*(?:开[：:])?\s*([^\n]+)?", ln)
        if not m:
            continue
        period = m.group(1)
        claim_raw = (m.group(2) or "").replace("🀄", "中")
        claimed = claimed_from(f"开:{claim_raw}") if claim_raw else {"status": "unknown", "xiao": None, "num": None, "raw": None}
        body: list[str] = []
        for j in range(i + 1, min(i + 6, len(lines))):
            if re.search(r"^\d+期", lines[j]) or "顶尖大师" in lines[j]:
                break
            body.append(lines[j])
        chunk = " ".join([ln] + body)

        xiao_line = next((l for l in body if "重点二肖" in l), "")
        num_line = next((l for l in body if "旺码" in l), "")

        # Check pending
        if "88" in claim_raw or "发 / 财" in xiao_line or "88、88" in num_line:
            claimed["status"] = "pending"
            rows.append(ParsedRow(period_raw=period, preds=[], claimed=claimed, raw_text=chunk))
            continue

        xiaos = [p for p in atoms_xiao(xiao_line) if p["value"] not in {"发", "财"}]
        nums = [p for p in atoms_num(num_line) if p["value"] != "88"]
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
