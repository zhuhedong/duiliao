from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args
from tt_util import (
    atoms_num,
    claimed_of,
    clean_html,
    fetch_tt_text,
    reconstruct_js_html,
    urls_for,
)

SOURCE_ID = "tt_4wbm"
SOURCE_NAME = "通天四尾八码"
SITE_FAMILY = "tongtian_83191"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
URLS = urls_for("/chajie/4wbm.js")


def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    raw_js, final_url, chash = fetch_tt_text(URLS, fixture)
    reconstructed = reconstruct_js_html(raw_js)

    tables = re.findall(r"<table[^>]*>(.*?)</table>", reconstructed, re.DOTALL | re.I)
    items: list[PredItem] = []
    seen = set()
    year = year_of(period) if period else None

    for t in tables:
        cleaned = clean_html(t)
        p_m = re.search(r"(\d{1,7})\s*期", cleaned)
        if not p_m:
            continue
        period_raw = p_m.group(1)
        try:
            per = normalize(lottery, period_raw, year=year)
        except ValueError:
            continue

        if period and per != period and not str(period).endswith(str(period_raw)):
            continue
        if per in seen:
            continue

        # Extract prediction numbers from lines containing "尾" and brackets "【"
        wei_lines = [l for l in cleaned.splitlines() if "尾" in l and "【" in l]
        pred_text = " ".join(wei_lines)
        atom_dicts = atoms_num(pred_text)

        c_m = re.search(r"开[:：]?\s*([^\s<]+)", cleaned)
        claim_raw = c_m.group(1) if c_m else ""
        c_info = claimed_of(claim_raw, cleaned, preds=atom_dicts)

        if not atom_dicts and c_info["status"] != "pending":
            continue

        seen.add(per)
        preds = [PredAtom(kind=a["kind"], value=str(a["value"]), text=a.get("text")) for a in atom_dicts]

        items.append(
            PredItem(
                period_raw=period_raw,
                period=per,
                published_at=None,
                preds=preds,
                claimed=Claimed(
                    status=c_info["status"],
                    xiao=c_info["xiao"],
                    num=c_info["num"],
                    raw=c_info["raw"],
                ),
                raw_text=cleaned[:1024],
            )
        )

    if not items:
        raise ValueError(f"{SOURCE_NAME} 解析条目为空")

    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        lottery=lottery,  # type: ignore[arg-type]
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,  # type: ignore[arg-type]
        fetched_at=now_cn(),
        final_url=final_url,
        content_hash=chash,
        items=items,
        error=None,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))


if __name__ == "__main__":
    main()
