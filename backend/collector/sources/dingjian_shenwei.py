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
from dj_util import atoms_xiao, html_to_lines, urls_for

SOURCE_ID = "dingjian_shenwei"
SOURCE_NAME = "神威二肖"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1785153298599")


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
        chunk = " ".join(block)
        xiaos = atoms_xiao(chunk)
        if not xiaos or "發" in chunk or "财" in chunk:
            claimed = {"status": "pending", "xiao": None, "num": None, "raw": "等待公布"}
            preds: list[dict] = []
        else:
            winner = None
            for pos, line in enumerate(block):
                if line == "中" and pos + 1 < len(block):
                    nxt = atoms_xiao(block[pos + 1])
                    if nxt:
                        winner = nxt[0]["value"]
            claimed = {
                "status": "hit" if "中" in block else "unknown",
                "xiao": winner,
                "num": None,
                "raw": chunk[:64],
            }
            preds = xiaos
        rows.append(ParsedRow(period_raw=period, preds=preds, claimed=claimed, raw_text=chunk))
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
