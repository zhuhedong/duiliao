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


SOURCE_ID = "chuangxin_6xiao18"
SOURCE_NAME = "原创六肖18码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
TITLE = "原创六肖18码"
URLS = urls_for("/api/v1/index/config/byid/1690557551507")

XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"
PERIOD_RE = re.compile(r"第?\s*(\d{1,7})\s*期")
PERIOD_START_RE = re.compile(r"^\s*第?\s*\d{1,7}\s*期")
CLAIM_RE = re.compile(r"(?:开奖?|開獎?)\s*[:：]\s*(.+)")
GROUP_RE = re.compile(
    rf"[〖【]\s*([{XIAO}])\s*[♠♤.。·．:：]\s*"
    rf"(\d{{1,2}})\s*[.。·．]\s*(\d{{1,2}})\s*[.。·．]\s*(\d{{1,2}})\s*[〗】]"
)


def extract(raw: str) -> list[tuple[str, str, list[dict[str, str]], dict[str, str | None]]]:
    """Extract each complete set of six ``生肖 + 三码`` groups."""
    lines = html_to_lines(raw)
    starts = [i for i, line in enumerate(lines) if TITLE in line and PERIOD_RE.search(line)]
    rows: list[tuple[str, str, list[dict[str, str]], dict[str, str | None]]] = []

    for start in starts:
        end = next(
            (i for i in range(start + 1, len(lines)) if PERIOD_START_RE.search(lines[i])),
            len(lines),
        )
        block_lines = lines[start:end]
        groups = GROUP_RE.findall(" ".join(block_lines))
        if len(groups) != 6:
            continue

        atoms: list[dict[str, str]] = []
        for xiao, first, second, third in groups:
            group_text = f"{xiao}.{first}.{second}.{third}"
            atoms.append({"kind": "xiao", "value": xiao, "text": group_text})
            atoms.extend(
                {"kind": "num", "value": f"{int(value):02d}", "text": group_text}
                for value in (first, second, third)
            )

        period_match = PERIOD_RE.search(lines[start])
        if period_match is None:
            continue
        claim_match = CLAIM_RE.search(lines[start])
        claimed = parse_claimed(claim_match.group(1) if claim_match else "")
        raw_text = " ".join(block_lines).replace("♠", ".").replace("♤", ".")
        rows.append((period_match.group(1), raw_text, atoms, claimed))

    return rows


def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    year = year_of(period) if period else None
    items: list[PredItem] = []

    for period_raw, raw, atoms_src, claimed in extract(page.text):
        try:
            normalized_period = normalize(lottery, period_raw, year=year)
        except ValueError:
            continue
        if period and normalized_period != period and not str(period).endswith(period_raw):
            continue

        atoms = [PredAtom(kind=a["kind"], value=a["value"], text=a["text"]) for a in atoms_src]
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
        raise ValueError(f"{TITLE} 未找到完整的六组一肖三码资料")
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
