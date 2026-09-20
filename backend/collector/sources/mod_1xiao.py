from __future__ import annotations
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.parse_pred import parse_column_text
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args
from common.source_fetch import load_page
from dj_util import urls_for, isolate_title, atoms_xiao, atoms_num, claimed_of, twoface, html_to_lines

SOURCE_ID = 'mod_1xiao'
SOURCE_NAME = '九肖模块①肖'
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = 'texiao'
HIT_MODE = 'any'
TITLE = '①肖'
KIND = 'xiao'
URLS = urls_for('/api/v1/index/config/byid/1780230448702')

def pick_atoms(text: str):
    if KIND == "xiao":
        return atoms_xiao(text)
    if KIND == "num":
        return atoms_num(text)
    if KIND == "twoface":
        return twoface(text)
    return atoms_xiao(text) + atoms_num(text)

def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    column_text = isolate_title(page.text, TITLE)
    if not column_text:
        raise ValueError(f"找不到栏目 {TITLE}")
    year = year_of(period) if period else None
    parsed = parse_column_text(column_text, title_hint=TITLE, prefer=("num" if KIND=="num" else "xiao"))
    items: list[PredItem] = []
    seen=set()
    rows = parsed or []
    if not rows:
        for line in column_text.splitlines():
            m = __import__("re").search(r"(\d+)\s*期", line)
            if not m:
                continue
            rows.append({"period_raw": m.group(1), "preds": pick_atoms(line), "claimed": claimed_of(line), "raw_text": line})
    for row in rows:
        raw = row.get("raw_text") or ""
        if TITLE not in raw:
            continue
        try:
            per = normalize(lottery, row["period_raw"], year=year)
        except ValueError:
            continue
        if period and per != period and not str(period).endswith(str(row["period_raw"])):
            continue
        atoms_src = row.get("preds") or pick_atoms(raw)
        if KIND == "xiao":
            atoms_src = [a for a in atoms_src if (a.get("kind") if isinstance(a, dict) else a.kind) == "xiao"]
        if KIND == "num":
            atoms_src = [a for a in atoms_src if (a.get("kind") if isinstance(a, dict) else getattr(a,"kind",None)) == "num"]
        if not atoms_src:
            atoms_src = pick_atoms(raw)
        atoms=[]
        for a in atoms_src:
            if isinstance(a, dict):
                atoms.append(PredAtom(kind=a["kind"], value=str(a["value"]), text=a.get("text")))
            else:
                atoms.append(a)
        if not atoms or per in seen:
            continue
        seen.add(per)
        c = row.get("claimed") or claimed_of(raw)
        if not isinstance(c, dict):
            c = {"status": getattr(c,"status","unknown"), "xiao": None, "num": None, "raw": getattr(c,"raw",None)}
        items.append(PredItem(
            period_raw=str(row["period_raw"]), period=per, published_at=None, preds=atoms,
            claimed=Claimed(status=c.get("status","unknown"), xiao=c.get("xiao"), num=c.get("num"), raw=c.get("raw")),
            raw_text=raw[:1024],
        ))
    if not items:
        raise ValueError(f"{TITLE} 切出行后解析为空")
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
