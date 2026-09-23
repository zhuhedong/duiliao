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
from dj_util import atoms_num, html_to_lines, urls_for

SOURCE_ID = "touzi_dashen"
SOURCE_NAME = "澳彩投资大神"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1790066325194")


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    for ln in lines:
        m = re.search(r"(\d+)\s*期\s*投资三码\s*【([^】]+)】", ln)
        if not m:
            continue
        period = m.group(1)
        target = m.group(2)
        nums = [p for p in atoms_num(target) if p["value"] != "88"]
        status = "pending" if "88" in target or not nums else "unknown"
        claimed = {"status": status, "xiao": None, "num": None, "raw": target}
        rows.append(ParsedRow(period_raw=period, preds=nums, claimed=claimed, raw_text=ln))
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
