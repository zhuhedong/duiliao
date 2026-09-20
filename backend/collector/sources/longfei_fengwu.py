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
from dj_util import XIAO, claimed_from, period_blocks, urls_for

SOURCE_ID = "longfei_fengwu"
SOURCE_NAME = "龙飞凤舞"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1780230338584")

HEADER_RE = re.compile(r"^\s*第?\s*(?P<period>\d{1,7})\s*期.*龙飞凤舞")
GROUP_RE = re.compile(rf"([{XIAO}])\s*[.。-]\s*(\d{{1,2}})\s*[.。-]\s*(\d{{1,2}})")


def extract(raw: str) -> list[ParsedRow]:
    rows: list[ParsedRow] = []
    for match, block in period_blocks(raw, HEADER_RE):
        groups = GROUP_RE.findall(" ".join(block[1:]))
        if len(groups) != 3 or any(not 1 <= int(num) <= 49 for group in groups for num in group[1:]):
            continue
        atoms: list[dict[str, str]] = []
        for xiao, first, second in groups:
            evidence = f"{xiao}.{int(first):02d}.{int(second):02d}"
            atoms.extend([
                {"kind": "xiao", "value": xiao, "text": evidence},
                {"kind": "num", "value": f"{int(first):02d}", "text": evidence},
                {"kind": "num", "value": f"{int(second):02d}", "text": evidence},
            ])
        rows.append(
            ParsedRow(
                period_raw=match.group("period"), preds=atoms,
                claimed=claimed_from(" ".join(block)), raw_text=" ".join(block),
            )
        )
    return rows


def build(lottery: str, period: str | None, fixture: str | None):
    page = load_page(urls=URLS, fixture=fixture)
    return build_prediction(
        page=page, lottery=lottery, period=period, source_id=SOURCE_ID,
        source_name=SOURCE_NAME, site_family=SITE_FAMILY, play_type=PLAY_TYPE,
        hit_mode=HIT_MODE, rows=extract(page.text),
        empty_error=f"{SOURCE_NAME} 未找到完整的三组一肖二码",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
