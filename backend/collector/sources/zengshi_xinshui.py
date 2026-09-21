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

SOURCE_ID = "zengshi_xinshui"
SOURCE_NAME = "曾氏心水二肖中特"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1789905813382")


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    for i, ln in enumerate(lines):
        m = re.match(r"^第?(\d+)期", ln)
        if not m:
            continue
        period = m.group(1)
        block = [ln]
        for j in range(i + 1, min(i + 6, len(lines))):
            if re.search(r"^第?\d+期", lines[j]) or "顶尖大师" in lines[j]:
                break
            block.append(lines[j])
        chunk = " ".join(block)

        if "信赖" in chunk or "富翁" in chunk or "？00" in chunk:
            claimed = {"status": "pending", "xiao": None, "num": None, "raw": "等待公布"}
            rows.append(ParsedRow(period_raw=period, preds=[], claimed=claimed, raw_text=chunk))
        else:
            xiaos = atoms_xiao(block[1] if len(block) > 1 else "")
            nums = atoms_num(block[2] if len(block) > 2 else "")
            atoms = xiaos + nums
            claimed_line = next((l for l in block if "开奖" in l), "")
            claimed = claimed_from(claimed_line)
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
        empty_error=f"{SOURCE_NAME} 未提取到有效二肖预测数据",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
