from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail, parse_common_args
from shensuan_util import build_shensuan_pred, urls_for

SOURCE_ID = "ss_3xiao"
SOURCE_NAME = "神算三肖"
SITE_FAMILY = "shensuan_70246"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
PATH = "/api/index/content_list/2"
KIND = "xiao"


def build(lottery: str, period: str | None, fixture: str | None):
    return build_shensuan_pred(
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        urls=urls_for(PATH),
        sub_label="推荐三肖", kind=KIND, article_id=24464,
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
