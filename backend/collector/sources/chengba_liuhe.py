from __future__ import annotations
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
from dj_util import urls_for, html_to_lines

import re

SOURCE_ID = 'chengba_liuhe'
SOURCE_NAME = '称霸六合'
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = 'texiao'
HIT_MODE = 'any'
TITLE = '称霸六合'
URLS = urls_for('/api/v1/index/config/byid/1780230329019')

XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"
PERIOD_RE = re.compile(r"第?\s*(\d{1,7})\s*期")
GROUP_RE = re.compile(
    rf"[〖【]\s*([{XIAO}])\s*[.。·．]\s*(\d{{1,2}})\s*[.。·．]\s*(\d{{1,2}})\s*[〗】]"
)


def extract(raw: str) -> list[tuple[str, str, list[dict], dict]]:
    """Read one period block and keep its four ``生肖.号码.号码`` groups together."""
    lines = html_to_lines(raw)
    starts = [
        i for i, line in enumerate(lines)
        if PERIOD_RE.search(line) and (TITLE in line or (i + 1 < len(lines) and TITLE in lines[i + 1]))
    ]
    rows = []
    for pos, start in enumerate(starts):
        end = starts[pos + 1] if pos + 1 < len(starts) else len(lines)
        block_lines = lines[start:end]
        # Advertising after the settled result belongs to neither predictions nor the next period.
        claimed_index = next((i for i, line in enumerate(block_lines) if "开奖" in line or "開獎" in line), None)
        candidate_lines = block_lines[1:claimed_index] if claimed_index is not None else block_lines[1:]
        groups = GROUP_RE.findall(" ".join(candidate_lines))
        if len(groups) != 4:
            continue
        atoms = []
        for xiao, first, second in groups:
            group_text = f"{xiao}.{first}.{second}"
            atoms.extend([
                {"kind": "xiao", "value": xiao, "text": group_text},
                {"kind": "num", "value": f"{int(first):02d}", "text": group_text},
                {"kind": "num", "value": f"{int(second):02d}", "text": group_text},
            ])
        match = PERIOD_RE.search(block_lines[0])
        if match:
            raw_text = " ".join(block_lines[:claimed_index + 1] if claimed_index is not None else block_lines)
            claimed_text = block_lines[claimed_index] if claimed_index is not None else ""
            rows.append((match.group(1), raw_text, atoms, parse_claimed(claimed_text)))
    return rows

def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    year = year_of(period) if period else None
    items: list[PredItem] = []
    for period_raw, raw, atoms_src, claimed in extract(page.text):
        try:
            per = normalize(lottery, period_raw, year=year)
        except ValueError:
            continue
        if period and per != period and not str(period).endswith(period_raw):
            continue
        atoms = [PredAtom(kind=a["kind"], value=a["value"], text=a["text"]) for a in atoms_src]
        items.append(PredItem(
            period_raw=period_raw, period=per, published_at=None, preds=atoms,
            claimed=Claimed(status=claimed.get("status", "unknown"), xiao=claimed.get("xiao"),
                            num=claimed.get("num"), raw=claimed.get("raw")),
            raw_text=raw[:1024],
        ))
    if not items:
        raise ValueError(f"{TITLE} 未找到完整的四组一肖二码资料")
    return PredV1(ok=True, schema_name="pred.v1", source_id=SOURCE_ID, source_name=SOURCE_NAME,
        site_family=SITE_FAMILY, lottery=lottery, play_type=PLAY_TYPE, hit_mode=HIT_MODE,
        fetched_at=now_cn(), final_url=page.url, content_hash=page.content_hash or sha256_text(page.text),
        items=items, error=None)

def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))

if __name__ == "__main__":
    main()
