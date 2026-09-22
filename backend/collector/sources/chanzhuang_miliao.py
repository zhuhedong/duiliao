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

SOURCE_ID = "chanzhuang_miliao"
SOURCE_NAME = "铲庄秘料一肖二码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "texiao"
HIT_MODE = "any"
URLS = urls_for("/api/v1/index/config/byid/1789990039716")


def extract(raw: str) -> list[ParsedRow]:
    lines = html_to_lines(raw)
    rows: list[ParsedRow] = []
    last_valid_period = None
    for i, ln in enumerate(lines):
        m = re.match(r"^第?(\d+)期$", ln.replace(" ", ""))
        if not m:
            continue
        raw_p = m.group(1)
        block = [ln]
        for j in range(i + 1, min(i + 8, len(lines))):
            if re.search(r"^第?\d+期", lines[j].replace(" ", "")):
                break
            block.append(lines[j])
        chunk = " ".join(block)

        period = raw_p
        if last_valid_period and int(period) < int(last_valid_period):
            # Upstream typo recovery (e.g. 264 -> 25 instead of 265)
            period = str(int(last_valid_period) + 1)
        else:
            last_valid_period = period

        if "暴富" in chunk or "上车" in chunk or "發88" in chunk:
            claimed = {"status": "pending", "xiao": None, "num": None, "raw": "等待公布"}
            rows.append(ParsedRow(period_raw=period, preds=[], claimed=claimed, raw_text=chunk))
            continue

        xiaos = []
        nums = []
        claimed_line = ""
        for b_line in block[1:]:
            if "开奖" in b_line:
                claimed_line = b_line
            elif ".com" in b_line or "顶尖大师" in b_line:
                continue
            else:
                xiaos.extend(atoms_xiao(b_line))
                nums.extend(atoms_num(b_line))

        atoms = xiaos + nums
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
