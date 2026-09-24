from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail, parse_common_args
from tt_util import (
    build_tt_pred,
    expand_period_ranges,
    fetch_tt_text,
    parse_tt_rows,
    reconstruct_js_html,
    urls_for,
)

SOURCE_ID = "tt_5tt"
SOURCE_NAME = "通天头数五期必中"
SITE_FAMILY = "tongtian_83191"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
URLS = urls_for("/chajie/5tt.js")


def build(lottery: str, period: str | None, fixture: str | None):
    raw, final_url, content_hash = fetch_tt_text(URLS, fixture)
    rows = expand_period_ranges(parse_tt_rows(reconstruct_js_html(raw)))
    return build_tt_pred(
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        urls=URLS,
        kind="num",
        lottery=lottery,
        period=period,
        parsed_rows=rows,
        final_url=final_url,
        content_hash=content_hash,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
