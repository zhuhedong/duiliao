from __future__ import annotations

import json
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
from dj_util import atoms_xiao, html_to_lines, urls_for


SOURCE_ID = "gaoqian_1xiao"
SOURCE_NAME = "搞钱①肖"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
UPSTREAM_ID = "1788522357390"
URLS = urls_for(f"/api/v1/index/config/byid/{UPSTREAM_ID}")

PERIOD_RE = re.compile(r"^\s*第?\s*(\d{1,7})\s*期\s*战报")
CLAIM_RE = re.compile(r"(?:开奖?|開獎?)\s*[:：]?\s*(.*)$")


class UpstreamRemovedError(RuntimeError):
    def __init__(self, url: str):
        super().__init__(f"{SOURCE_NAME} 上游栏目 {UPSTREAM_ID} 已删除，等待新的同名栏目地址")
        self.url = url


def upstream_removed(text: str) -> bool:
    """Recognize the site's HTTP-200 wrapper for a deleted config row."""
    stripped = text.strip()
    if stripped.lower() in {"no find", "not found"}:
        return True
    try:
        payload = json.loads(stripped)
    except (json.JSONDecodeError, TypeError):
        return False
    if not isinstance(payload, dict):
        return False
    return str(payload.get("code")) in {"404", "410"} and payload.get("data") is None


def extract(raw: str) -> list[tuple[str, str, str, str, dict[str, str | None]]]:
    """Extract one zodiac from each historical ``NNN期战报`` block."""
    lines = html_to_lines(raw)
    starts = [i for i, line in enumerate(lines) if PERIOD_RE.match(line)]
    rows: list[tuple[str, str, str, str, dict[str, str | None]]] = []

    for position, start in enumerate(starts):
        end = starts[position + 1] if position + 1 < len(starts) else len(lines)
        block = lines[start:end]
        header_match = PERIOD_RE.match(block[0])
        if header_match is None:
            continue

        candidate_parts: list[str] = []
        claimed_raw = ""
        for line in block[1:]:
            claim_match = CLAIM_RE.search(line)
            if claim_match:
                candidate_parts.append(line[:claim_match.start()])
                claimed_raw = claim_match.group(1)
                break
            candidate_parts.append(line)

        candidate_text = " ".join(candidate_parts)
        candidates = atoms_xiao(candidate_text)
        if len(candidates) != 1:
            continue
        rows.append(
            (
                header_match.group(1),
                " ".join(block),
                candidate_text.strip(),
                str(candidates[0]["value"]),
                parse_claimed(claimed_raw),
            )
        )
    return rows


def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    if upstream_removed(page.text):
        raise UpstreamRemovedError(page.url)

    year = year_of(period) if period else None
    items: list[PredItem] = []
    seen: set[str] = set()
    for period_raw, raw_text, evidence, xiao, claimed in extract(page.text):
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
                preds=[PredAtom(kind="xiao", value=xiao, text=evidence)],
                claimed=Claimed(
                    status=claimed.get("status", "unknown"),
                    xiao=claimed.get("xiao"),
                    num=claimed.get("num"),
                    raw=claimed.get("raw"),
                ),
                raw_text=raw_text[:1024],
            )
        )

    if not items:
        raise ValueError(f"{SOURCE_NAME} 未找到一期恰好一个特肖的战报")
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
    except UpstreamRemovedError as exc:
        fail(
            SOURCE_ID,
            SOURCE_NAME,
            SITE_FAMILY,
            args.lottery,
            PLAY_TYPE,
            HIT_MODE,
            "upstream_removed",
            str(exc),
            exc.url,
        )
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
