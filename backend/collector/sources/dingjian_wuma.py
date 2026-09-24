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

SOURCE_ID = "dingjian_wuma"
SOURCE_NAME = "顶尖五码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1790161228288")
XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    index = 0
    while index < len(lines):
        match = re.search(r"第\s*(\d+)\s*期", lines[index])
        if not match:
            index += 1
            continue
        period = match.group(1)
        index += 1
        block: list[str] = []
        while index < len(lines) and not re.search(r"第\s*\d+\s*期", lines[index]):
            block.append(lines[index])
            index += 1
        number_lines = [
            line for line in block
            if re.fullmatch(r"[\d.\-－\s]+", line) and re.search(r"\d", line)
        ]
        nums = atoms_num(" ".join(number_lines))
        claim_line = next((line for line in block if line.startswith("开奖")), "")
        drawn = re.search(rf"开奖[:：]\s*([{XIAO}])(\d{{1,2}})", claim_line)
        if not nums or "發" in claim_line or "发" in claim_line:
            claimed = {"status": "pending", "xiao": None, "num": None, "raw": claim_line or "等待公布"}
            preds: list[dict] = []
        else:
            claimed = {
                "status": "hit" if drawn or "中" in claim_line else "unknown",
                "xiao": drawn.group(1) if drawn else None,
                "num": f"{int(drawn.group(2)):02d}" if drawn else None,
                "raw": claim_line,
            }
            preds = nums
        rows.append(ParsedRow(period_raw=period, preds=preds, claimed=claimed, raw_text=" ".join(block)))
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
