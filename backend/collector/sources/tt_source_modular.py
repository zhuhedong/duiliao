"""Modular dynamic runner for any 83191.com (通天) prediction column."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail
from tt_util import build_tt_pred, urls_for


def main() -> None:
    parser = argparse.ArgumentParser(description="通天通用动态采集器")
    parser.add_argument("--path", required=True, help="相对路径，例如 /chajie/dfpt.js")
    parser.add_argument("--id", default="", help="source_id")
    parser.add_argument("--name", default="", help="source_name")
    parser.add_argument("--play_type", default="texiao", help="play_type (如 texiao, pingte_xiao, tema_n, tema_twoface)")
    parser.add_argument("--kind", default="xiao", choices=["xiao", "num", "twoface", "all"], help="kind (xiao, num, twoface)")
    parser.add_argument("--hit_mode", default="any", help="hit_mode")
    parser.add_argument("--lottery", default="macau", help="彩种 (默认 macau)")
    parser.add_argument("--period", default=None, help="目标期号")
    parser.add_argument("--fixture", default=None, help="测试固件路径")

    args = parser.parse_args()
    clean_path = args.path.strip()
    source_id = args.id or f"tt_{Path(clean_path).stem}"
    source_name = args.name or f"通天_{Path(clean_path).stem}"

    urls = urls_for(clean_path)
    try:
        pred = build_tt_pred(
            source_id=source_id,
            source_name=source_name,
            play_type=args.play_type,
            hit_mode=args.hit_mode,
            urls=urls,
            kind=args.kind,
            lottery=args.lottery,
            period=args.period,
            fixture=args.fixture,
        )
        emit(pred, ok=True)
    except Exception as e:
        fail(source_id, source_name, "tongtian_83191", args.lottery, args.play_type, args.hit_mode, "fetch", str(e))


if __name__ == "__main__":
    main()
