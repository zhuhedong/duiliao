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
from dj_util import atoms_xiao, claimed_from, period_blocks, urls_for

SOURCE_ID = "tuku_liuxiao"
SOURCE_NAME = "图库六肖"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1690557551507")

HEADER_RE = re.compile(r"^\s*(?P<period>\d{1,7})\s*期\s*六肖\s*【(?P<candidates>[^】]+)】")


def extract(raw: str) -> list[ParsedRow]:
    rows: list[ParsedRow] = []
    for match, block in period_blocks(raw, HEADER_RE):
        evidence = match.group("candidates")
        candidates = atoms_xiao(evidence)
        if len(candidates) != 6:
            continue
        rows.append(
            ParsedRow(
                period_raw=match.group("period"),
                preds=[{"kind": "xiao", "value": atom["value"], "text": evidence} for atom in candidates],
                claimed=claimed_from(block[0]), raw_text=block[0],
            )
        )
    return rows


def build(lottery: str, period: str | None, fixture: str | None):
    page = load_page(urls=URLS, fixture=fixture)
    return build_prediction(
        page=page, lottery=lottery, period=period, source_id=SOURCE_ID,
        source_name=SOURCE_NAME, site_family=SITE_FAMILY, play_type=PLAY_TYPE,
        hit_mode=HIT_MODE, rows=extract(page.text),
        empty_error=f"{SOURCE_NAME} 未找到恰好六个有效特肖",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
