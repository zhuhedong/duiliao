from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.parse_pred import parse_claimed
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args
from common.source_fetch import load_page
from dj_util import html_to_lines, urls_for


SOURCE_ID = "daxiao_zhongte"
SOURCE_NAME = "大小中特"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "tema_twoface"
HIT_MODE = "any"
TITLE = "大小中特"
URLS = urls_for("/api/v1/index/config/byid/1690557551507")

PERIOD_RE = re.compile(r"第?\s*(\d{1,7})\s*期")
PRED_RE = re.compile(rf"{re.escape(TITLE)}\s*[】\]]?\s*[〖【\[]\s*([大小])\s*数\s*[〗】\]]")
CLAIM_RE = re.compile(r"(?:开奖?|開獎?)\s*[:：]?\s*(.+)$")


def extract(raw: str) -> list[tuple[str, str, str, dict[str, str | None]]]:
    """Keep only the explicit 大数 or 小数 value in the prediction bracket."""
    rows: list[tuple[str, str, str, dict[str, str | None]]] = []
    for line in html_to_lines(raw):
        if TITLE not in line:
            continue
        period_match = PERIOD_RE.search(line)
        pred_match = PRED_RE.search(line)
        if period_match is None or pred_match is None:
            # Future placeholders such as “？数” are not predictions.
            continue
        claim_match = CLAIM_RE.search(line)
        claimed = parse_claimed(claim_match.group(1) if claim_match else "")
        rows.append((period_match.group(1), line, pred_match.group(1), claimed))
    return rows


def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    year = year_of(period) if period else None
    items: list[PredItem] = []
    seen: set[str] = set()

    for period_raw, raw, size_value, claimed in extract(page.text):
        try:
            normalized_period = normalize(lottery, period_raw, year=year)
        except ValueError:
            continue
        if period and normalized_period != period and not str(period).endswith(period_raw):
            continue
        if normalized_period in seen:
            continue
        seen.add(normalized_period)
        items.append(
            PredItem(
                period_raw=period_raw,
                period=normalized_period,
                published_at=None,
                preds=[PredAtom(kind="size", value=size_value, text=f"{size_value}数")],
                claimed=Claimed(
                    status=claimed.get("status", "unknown"),
                    xiao=claimed.get("xiao"),
                    num=claimed.get("num"),
                    raw=claimed.get("raw"),
                ),
                raw_text=raw[:1024],
            )
        )

    if not items:
        raise ValueError(f"{TITLE} 未找到明确的大数或小数预测")
    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        lottery=lottery,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        fetched_at=now_cn(),
        final_url=page.url,
        content_hash=page.content_hash or sha256_text(page.text),
        items=items,
        error=None,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
