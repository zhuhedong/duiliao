from __future__ import annotations
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args
from common.source_fetch import load_page

import re
from dj_util import urls_for, html_to_lines, atoms_num, claimed_of
URLS = urls_for("/api/v1/index/config/byid/1788436830729")
def extract(raw):
    lines=html_to_lines(raw)
    rows=[]
    i=0
    while i < len(lines):
        m=re.match(r"第?(\d+)期$", lines[i].replace(" ",""))
        if m:
            period=m.group(1)
            chunk=" ".join(lines[i:i+5])
            nums=atoms_num(lines[i+1] if i+1<len(lines) else "")
            rows.append((period, chunk, nums, claimed_of(chunk)))
            i+=1
            continue
        i+=1
    return rows

SOURCE_ID = 'yingjia_sima'
SOURCE_NAME = '赢家策略主攻四码'
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = 'tema_n'
HIT_MODE = 'any'

def build(lottery, period, fixture):
    page = load_page(urls=URLS, fixture=fixture)
    year = year_of(period) if period else None
    items=[]; seen=set()
    for period_raw, raw, atoms_src, c in extract(page.text):
        try:
            per = normalize(lottery, period_raw, year=year)
        except ValueError:
            continue
        if period and per != period and not str(period).endswith(str(period_raw)):
            continue
        atoms=[]
        for a in atoms_src:
            if isinstance(a, dict):
                atoms.append(PredAtom(kind=a["kind"], value=str(a["value"]), text=a.get("text")))
        if not atoms or per in seen:
            continue
        seen.add(per)
        items.append(PredItem(period_raw=str(period_raw), period=per, published_at=None, preds=atoms,
            claimed=Claimed(status=c.get("status","unknown"), xiao=c.get("xiao"), num=c.get("num"), raw=c.get("raw")),
            raw_text=raw[:1024]))
    if not items:
        raise ValueError(SOURCE_NAME + " 解析为空")
    return PredV1(ok=True, schema_name="pred.v1", source_id=SOURCE_ID, source_name=SOURCE_NAME,
        site_family=SITE_FAMILY, lottery=lottery, play_type=PLAY_TYPE, hit_mode=HIT_MODE,
        fetched_at=now_cn(), final_url=page.url, content_hash=page.content_hash or sha256_text(page.text),
        items=items, error=None)

def main():
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))
if __name__ == "__main__":
    main()
