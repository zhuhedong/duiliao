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
from dj_util import atoms_num, html_to_lines, urls_for

SOURCE_ID = "wu_buzhong"
SOURCE_NAME = "五不中"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "buzhong_num"
HIT_MODE = "none"
URLS = urls_for("/api/v1/index/config/byid/1690557551507")

ROW_RE = re.compile(
    r"^\s*第?\s*(?P<period>\d{1,7})\s*期\s*[:：]?\s*五不中\s*"
    r"[【\[]\s*(?P<candidates>[^】\]]+)\s*[】\]]"
)
NO_CLAIM = {"status": "unknown", "xiao": None, "num": None, "raw": None}


def extract(raw: str) -> list[ParsedRow]:
    rows: list[ParsedRow] = []
    for line in html_to_lines(raw):
        match = ROW_RE.search(line)
        if match is None:
            continue
        period_raw = match.group("period")
        numbers = atoms_num(match.group("candidates"))
        if len(numbers) != 5:
            raise ValueError(f"{period_raw}期五不中必须恰好5个不同号码，实际{len(numbers)}个")
        rows.append(
            ParsedRow(
                period_raw=period_raw,
                preds=numbers,
                # 页面行尾的“准”是固定栏目文字，不是作者自报命中。
                claimed=NO_CLAIM.copy(),
                raw_text=line,
            )
        )
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
        empty_error="五不中没有解析到符合格式的预测行",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
