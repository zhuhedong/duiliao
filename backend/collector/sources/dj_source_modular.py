"""Modular dynamic runner for any 77452.com (澳门顶级 / 顶级论坛) prediction column."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail
from dingji_util import (
    build_dj_pred,
    fetch_dj_text,
    parse_dj_amtz_rows,
    parse_dj_baota_rows,
    parse_dj_htm_section_rows,
    urls_for,
)

SITE_FAMILY = "dingji_77452"


def main() -> None:
    parser = argparse.ArgumentParser(description="顶级论坛通用动态采集器")
    parser.add_argument("--path", default="/htm/tz/amtz/001.html", help="相对路径，例如 /htm/tz/amtz/001.html 或 /htm/")
    parser.add_argument("--id", default="", help="source_id")
    parser.add_argument("--name", default="", help="source_name")
    parser.add_argument("--play_type", default="texiao", help="play_type (如 texiao, pingte_xiao, tema_n, tema_twoface)")
    parser.add_argument("--kind", default="xiao", choices=["xiao", "num", "twoface", "wei", "head", "bose", "all"], help="kind")
    parser.add_argument("--hit_mode", default="any", help="hit_mode")
    parser.add_argument("--lottery", default="macau", help="彩种 (默认 macau)")
    parser.add_argument("--period", default=None, help="目标期号")
    parser.add_argument("--fixture", default=None, help="测试固件路径")
    parser.add_argument("--section", default=None, help="主页特定栏目关键词（如 贺州怀中猫、茂名阳光小逗比）")
    parser.add_argument("--baota_key", default=None, choices=["1xiao", "1ma", "3xiao", "3ma", "5xiao", "5ma", "7xiao", "7ma"], help="宝塔子栏目 key")

    args = parser.parse_args()
    clean_path = args.path.strip()
    source_id = args.id or f"dj_{Path(clean_path).stem}"
    source_name = args.name or f"顶级_{Path(clean_path).stem}"

    urls = urls_for(clean_path)
    try:
        parsed_rows = None
        if args.section or args.baota_key:
            raw_text, _, _ = fetch_dj_text(urls, args.fixture)
            if args.baota_key:
                parsed_rows = parse_dj_baota_rows(raw_text, args.baota_key)
            elif args.section:
                parsed_rows = parse_dj_htm_section_rows(raw_text, args.section)

        pred = build_dj_pred(
            source_id=source_id,
            source_name=source_name,
            play_type=args.play_type,
            hit_mode=args.hit_mode,
            urls=urls,
            kind=args.kind,
            lottery=args.lottery,
            period=args.period,
            fixture=args.fixture,
            parsed_rows=parsed_rows,
        )
        emit(pred, ok=True)
    except Exception as e:
        fail(source_id, source_name, SITE_FAMILY, args.lottery, args.play_type, args.hit_mode, "fetch", str(e))


if __name__ == "__main__":
    main()
