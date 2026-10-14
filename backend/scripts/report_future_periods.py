"""List rows whose period exceeds today's period (Beijing time).

Dry-run / read-only by default: only prints counts and samples. Nothing is
deleted. Usage (from backend/):

    python scripts/report_future_periods.py            # report only
    python scripts/report_future_periods.py --today 2026287 --samples 20
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--today", help="override today's period (YYYYDDD)")
    ap.add_argument("--samples", type=int, default=10)
    args = ap.parse_args()

    from app import collector_bridge as cb

    cb.prepare_modules()
    from sqlalchemy import func, select

    from common.period import max_allowed_period
    from db import session_scope
    from schema import Base

    today = args.today or max_allowed_period()
    print(f"today's max allowed period: {today}  (read-only, nothing deleted)")
    total = 0
    with session_scope(guard=False) as s:
        for table in Base.metadata.sorted_tables:
            if "period" not in table.c:
                continue
            col = table.c.period
            cond = (func.length(col) == 7) & (col > today)
            n = s.scalar(select(func.count()).select_from(table).where(cond)) or 0
            if not n:
                continue
            total += n
            print(f"\n[{table.name}] {n} rows with period > {today}")
            group_cols = [c for c in ("lottery", "source_id") if c in table.c]
            q = select(*[table.c[c] for c in group_cols], col, func.count()).where(cond)
            q = q.group_by(*[table.c[c] for c in group_cols], col).order_by(col.desc()).limit(args.samples)
            for row in s.execute(q):
                print("   ", tuple(row))
    print(f"\nTOTAL future rows: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
