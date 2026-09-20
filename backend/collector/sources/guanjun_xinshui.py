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
from dj_util import atoms_num, atoms_xiao, claimed_from, period_blocks, urls_for

SOURCE_ID = "guanjun_xinshui"
SOURCE_NAME = "冠军心水一肖四码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1788694610180")

HEADER_RE = re.compile(r"^\s*(?P<period>\d{1,7})\s*期\s*.*冠军心水.*?(?:开奖?|開獎?)")
XIAO_RE = re.compile(r"一肖\s*[【\[](?P<value>[^】\]]+)[】\]]")


def extract(raw: str) -> list[ParsedRow]:
    rows: list[ParsedRow] = []
    for match, block in period_blocks(raw, HEADER_RE):
        xiao_line = next((line for line in block[1:] if "一肖" in line), "")
        number_line = next((line for line in block[1:] if "协防" in line), "")
        xiao_match = XIAO_RE.search(xiao_line)
        if not xiao_match or not number_line:
            continue
        xiaos = atoms_xiao(xiao_match.group("value"))
        number_evidence = re.split(r"各|每", number_line, maxsplit=1)[0]
        number_evidence = re.split(r"[:：]", number_evidence, maxsplit=1)[-1]
        nums = atoms_num(number_evidence)
        if len(xiaos) != 1 or len(nums) != 4:
            continue
        atoms = [{"kind": "xiao", "value": xiaos[0]["value"], "text": xiao_line}]
        atoms.extend({"kind": "num", "value": atom["value"], "text": number_evidence} for atom in nums)
        rows.append(
            ParsedRow(
                period_raw=match.group("period"),
                preds=atoms,
                claimed=claimed_from(block[0]),
                raw_text=" ".join([block[0], xiao_line, number_line]),
            )
        )
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
        empty_error=f"{SOURCE_NAME} 未找到完整的一肖和四个协防号码",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
