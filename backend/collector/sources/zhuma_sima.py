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
from dj_util import atoms_num, claimed_from, period_blocks, urls_for

SOURCE_ID = "zhuma_sima"
SOURCE_NAME = "主买四码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1787383047657")

HEADER_RE = re.compile(r"^\s*(?P<period>\d{1,7})\s*期\s+主买四码")
CANDIDATE_RE = re.compile(r"主买\s*《(?P<candidates>[^》]+)》")


def extract(raw: str) -> list[ParsedRow]:
    rows: list[ParsedRow] = []
    for match, block in period_blocks(raw, HEADER_RE):
        if len(block) < 2:
            continue
        candidate_match = CANDIDATE_RE.search(block[1])
        if candidate_match is None:
            continue
        evidence = candidate_match.group("candidates")
        nums = atoms_num(evidence)
        if len(nums) != 4:
            continue
        claimed = claimed_from(block[0])
        if claimed.get("status") == "hit" and claimed.get("num"):
            claimed["status"] = "hit" if claimed["num"] in {atom["value"] for atom in nums} else "miss"
        rows.append(
            ParsedRow(
                period_raw=match.group("period"),
                preds=[{"kind": "num", "value": atom["value"], "text": evidence} for atom in nums],
                claimed=claimed, raw_text=" ".join(block[:2]),
            )
        )
    return rows


def build(lottery: str, period: str | None, fixture: str | None):
    page = load_page(urls=URLS, fixture=fixture)
    return build_prediction(
        page=page, lottery=lottery, period=period, source_id=SOURCE_ID,
        source_name=SOURCE_NAME, site_family=SITE_FAMILY, play_type=PLAY_TYPE,
        hit_mode=HIT_MODE, rows=extract(page.text),
        empty_error=f"{SOURCE_NAME} 未找到恰好四个主买号码",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
