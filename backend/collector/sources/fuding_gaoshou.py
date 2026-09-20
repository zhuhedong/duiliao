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


SOURCE_ID = "fuding_gaoshou"
SOURCE_NAME = "福鼎高手"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
TITLE = "福鼎高手"
URLS = urls_for("/api/v1/index/config/byid/1780230349917")

XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"
PERIOD_RE = re.compile(r"第?\s*(\d{1,7})\s*期")
PERIOD_START_RE = re.compile(r"^\s*第?\s*\d{1,7}\s*期")
CLAIM_RE = re.compile(r"(?:开奖?|開獎?)\s*[:：]?\s*(.+)$")
GROUP_RE = re.compile(
    rf"([{XIAO}])\s*[-—–.。]\s*(\d{{1,2}})\s*[-—–.。]\s*(\d{{1,2}})"
)


def extract(raw: str) -> list[tuple[str, str, list[dict[str, str]], dict[str, str | None]]]:
    """Read all three ``生肖-号码-号码`` groups following a period heading."""
    lines = html_to_lines(raw)
    starts = [i for i, line in enumerate(lines) if TITLE in line and PERIOD_RE.search(line)]
    rows: list[tuple[str, str, list[dict[str, str]], dict[str, str | None]]] = []

    for start in starts:
        end = next(
            (i for i in range(start + 1, len(lines)) if PERIOD_START_RE.search(lines[i])),
            len(lines),
        )
        header = lines[start]
        candidate_lines = lines[start + 1:end]
        groups = GROUP_RE.findall(" ".join(candidate_lines))
        if len(groups) != 3:
            continue

        atoms: list[dict[str, str]] = []
        for xiao, first, second in groups:
            group_text = f"{xiao}-{int(first):02d}-{int(second):02d}"
            atoms.extend(
                [
                    {"kind": "xiao", "value": xiao, "text": group_text},
                    {"kind": "num", "value": f"{int(first):02d}", "text": group_text},
                    {"kind": "num", "value": f"{int(second):02d}", "text": group_text},
                ]
            )

        period_match = PERIOD_RE.search(header)
        if period_match is None:
            continue
        claim_match = CLAIM_RE.search(header)
        claimed = parse_claimed(claim_match.group(1) if claim_match else "")
        evidence_lines = [line for line in candidate_lines if GROUP_RE.search(line)]
        raw_text = " ".join([header, *evidence_lines]).replace("♠", ".").replace("♤", ".")
        rows.append((period_match.group(1), raw_text, atoms, claimed))
    return rows


def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    year = year_of(period) if period else None
    items: list[PredItem] = []
    seen: set[str] = set()

    for period_raw, raw, atoms_src, claimed in extract(page.text):
        try:
            normalized_period = normalize(lottery, period_raw, year=year)
        except ValueError:
            continue
        if period and normalized_period != period and not str(period).endswith(period_raw):
            continue
        if normalized_period in seen:
            continue
        seen.add(normalized_period)
        atoms = [PredAtom(kind=atom["kind"], value=atom["value"], text=atom["text"]) for atom in atoms_src]
        items.append(
            PredItem(
                period_raw=period_raw,
                period=normalized_period,
                published_at=None,
                preds=atoms,
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
        raise ValueError(f"{SOURCE_NAME} 未找到完整的三组一肖二码资料")
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
