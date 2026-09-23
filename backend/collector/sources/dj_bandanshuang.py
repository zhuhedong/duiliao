from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail, parse_common_args
from dingji_util import build_dj_pred, urls_for

SOURCE_ID = "dj_bandanshuang"
SOURCE_NAME = "顶级论坛半单双"
SITE_FAMILY = "dingji_77452"
PLAY_TYPE = "tema_twoface"
HIT_MODE = "any"
URLS = urls_for("/htm/tz/amtz/007.html")


def build(lottery: str, period: str | None, fixture: str | None):
    return build_dj_pred(
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        urls=URLS,
        kind="twoface",
        lottery=lottery,
        period=period,
        fixture=fixture,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))


if __name__ == "__main__":
    main()
