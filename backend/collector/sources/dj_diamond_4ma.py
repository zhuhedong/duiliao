from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail, parse_common_args
from common.dingjian_columns import build_column_pred
from dj_util import urls_for

SOURCE_ID = "dj_diamond_4ma"
SOURCE_NAME = "澳彩中心钻石四码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
PATH = "/api/v1/index/config/byid/1786877946782"
KIND = "num"


def build(lottery: str, period: str | None, fixture: str | None):
    return build_column_pred(
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        urls=urls_for(PATH),
        parser="diamond_four_numbers",
        lottery=lottery,
        period=period,
        fixture=fixture,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
