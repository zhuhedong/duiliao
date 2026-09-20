from __future__ import annotations

import json
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
from dj_util import atoms_num, claimed_from, period_blocks, urls_for

SOURCE_ID = "yaoqianshu_3ma"
SOURCE_NAME = "摇钱树致富三码"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
UPSTREAM_ID = "1785835319301"
URLS = urls_for(f"/api/v1/index/config/byid/{UPSTREAM_ID}")

HEADER_RE = re.compile(r"^\s*(?P<period>\d{1,7})\s*期.*开奖记录")


class UpstreamRemovedError(RuntimeError):
    def __init__(self, url: str):
        super().__init__(f"{SOURCE_NAME} 上游栏目 {UPSTREAM_ID} 已删除，等待新的同名栏目地址")
        self.url = url


def upstream_removed(text: str) -> bool:
    stripped = text.strip()
    if stripped.lower() in {"no find", "not found"}:
        return True
    try:
        payload = json.loads(stripped)
    except (json.JSONDecodeError, TypeError):
        return False
    return (
        isinstance(payload, dict)
        and str(payload.get("code")) in {"404", "410"}
        and payload.get("data") is None
    )


def extract(raw: str) -> list[ParsedRow]:
    rows: list[ParsedRow] = []
    for match, block in period_blocks(raw, HEADER_RE):
        evidence = " ".join(block[1:])
        candidates = atoms_num(evidence)
        if len(candidates) != 3:
            continue
        rows.append(
            ParsedRow(
                period_raw=match.group("period"),
                preds=[{"kind": "num", "value": atom["value"], "text": evidence} for atom in candidates],
                claimed=claimed_from(" ".join(block)), raw_text=" ".join(block),
            )
        )
    return rows


def build(lottery: str, period: str | None, fixture: str | None):
    page = load_page(urls=URLS, fixture=fixture)
    if upstream_removed(page.text):
        raise UpstreamRemovedError(page.url)
    return build_prediction(
        page=page, lottery=lottery, period=period, source_id=SOURCE_ID,
        source_name=SOURCE_NAME, site_family=SITE_FAMILY, play_type=PLAY_TYPE,
        hit_mode=HIT_MODE, rows=extract(page.text),
        empty_error=f"{SOURCE_NAME} 未找到恰好三个有效特码",
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except UpstreamRemovedError as exc:
        fail(
            SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE,
            "upstream_removed", str(exc), exc.url,
        )
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
