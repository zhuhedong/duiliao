from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail, parse_common_args
from common.source_fetch import load_page
from common.source_rows import ParsedRow, build_prediction
from dj_util import atoms_num, atoms_xiao, claimed_from, html_to_lines, urls_for

SOURCE_ID = "dingjian_baoliao"
SOURCE_NAME = "顶尖爆料·一肖二码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1789907465205")


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    for i, ln in enumerate(lines):
        m = re.match(r"^(\d+)期", ln)
        if not m:
            continue
        period = m.group(1)
        block = [ln]
        for j in range(i + 1, min(i + 7, len(lines))):
            if re.search(r"^\d+期", lines[j]) or "顶尖大师" in lines[j]:
                break
            block.append(lines[j])
        chunk = " ".join(block)

        if "等待公布" in chunk or "發88" in chunk or "？00" in chunk:
            claimed = {"status": "pending", "xiao": None, "num": None, "raw": "等待公布"}
            rows.append(ParsedRow(period_raw=period, preds=[], claimed=claimed, raw_text=chunk))
        else:
            body = " ".join(block[2:]) if len(block) > 2 else " ".join(block[1:])
            xiaos = atoms_xiao(body)
            nums = atoms_num(body)
            atoms = xiaos + nums
            claimed_line = block[1] if len(block) > 1 else ln
            claimed = claimed_from(claimed_line)
            if atoms:
                rows.append(ParsedRow(period_raw=period, preds=atoms, claimed=claimed, raw_text=chunk))
    return rows


def build(lottery: str, period: str | None, fixture: str | None):
    page = load_page(urls=URLS, fixture=fixture)
    return build_prediction(
        page=page,
        lottery=lottery,
        period=period,
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        rows=extract(page.text),
        empty_error=f"{SOURCE_NAME} 未提取到有效一肖二码预测数据",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
