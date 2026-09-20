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

SOURCE_ID = "huobao_qima"
SOURCE_NAME = "火爆七码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1784807003200")

HEADER_RE = re.compile(r"^\s*✦?\s*(?P<period>\d{1,7})\s*期\s*(?P<candidates>.*?)(?:\s*★|$)")


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    for index, line in enumerate(lines):
        match = HEADER_RE.match(line)
        if match is None:
            continue
        end = next((i for i in range(index + 1, len(lines)) if HEADER_RE.match(lines[i])), len(lines))
        block = lines[index:end]
        xiao_line = next((value for value in block[1:] if "主推三肖" in value), "")
        result_line = next((value for value in block[1:] if "开奖" in value or "開獎" in value), "")
        nums = atoms_num(match.group("candidates"))
        xiaos = atoms_xiao(xiao_line)
        if len(nums) != 7 or len(xiaos) != 3:
            continue
        atoms = [{"kind": "xiao", "value": atom["value"], "text": xiao_line} for atom in xiaos]
        atoms.extend({"kind": "num", "value": atom["value"], "text": match.group("candidates")} for atom in nums)
        rows.append(
            ParsedRow(
                period_raw=match.group("period"),
                preds=atoms,
                claimed=claimed_from(result_line),
                raw_text=" ".join(value for value in [line, xiao_line, result_line] if value),
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
        empty_error=f"{SOURCE_NAME} 未找到完整的七码和主推三肖",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
