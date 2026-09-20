from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.period import normalize, year_of
from common.source_base import now_cn
from common.source_fetch import Page


@dataclass(frozen=True)
class ParsedRow:
    period_raw: str
    preds: list[dict[str, str]]
    claimed: dict[str, Any]
    raw_text: str
    group_key: str = ""


def build_prediction(
    *,
    page: Page,
    lottery: str,
    period: str | None,
    source_id: str,
    source_name: str,
    site_family: str,
    play_type: str,
    hit_mode: str,
    rows: Iterable[ParsedRow],
    empty_error: str,
) -> PredV1:
    """Normalize strict, source-specific rows into the shared pred.v1 contract."""
    year = year_of(period) if period else None
    items: list[PredItem] = []
    seen: set[tuple[str, str]] = set()
    for row in rows:
        try:
            normalized_period = normalize(lottery, row.period_raw, year=year)
        except ValueError:
            continue
        if period and normalized_period != period and not str(period).endswith(row.period_raw):
            continue
        key = (normalized_period, row.group_key)
        if key in seen or not row.preds:
            continue
        seen.add(key)
        items.append(
            PredItem(
                period_raw=row.period_raw,
                period=normalized_period,
                group_key=row.group_key,
                published_at=None,
                preds=[
                    PredAtom(kind=atom["kind"], value=str(atom["value"]), text=atom.get("text"))
                    for atom in row.preds
                ],
                claimed=Claimed(
                    status=row.claimed.get("status", "unknown"),
                    xiao=row.claimed.get("xiao"),
                    num=row.claimed.get("num"),
                    raw=row.claimed.get("raw"),
                ),
                raw_text=row.raw_text[:1024],
            )
        )
    if not items:
        raise ValueError(empty_error)
    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=source_id,
        source_name=source_name,
        site_family=site_family,
        lottery=lottery,
        play_type=play_type,
        hit_mode=hit_mode,
        fetched_at=now_cn(),
        final_url=page.url,
        content_hash=page.content_hash or sha256_text(page.text),
        items=items,
        error=None,
    )
