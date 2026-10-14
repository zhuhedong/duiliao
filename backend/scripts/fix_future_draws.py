"""List (and optionally delete) draw/开奖 rows whose period exceeds today's period.

Today's period = Beijing-time year + day of year (e.g. 2026-10-14 -> 2026287).
Read-only by default. Deleting requires BOTH --delete and --yes, and only
removes rows of the ``draw`` table with period > today.

    python scripts/fix_future_draws.py                     # report only
    python scripts/fix_future_draws.py --samples 20
    python scripts/fix_future_draws.py --today 2026287     # override cutoff
    python scripts/fix_future_draws.py --delete --yes      # delete those draw rows
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def run(today: str | None = None, samples: int = 10, delete: bool = False) -> dict:
    from app import collector_bridge as cb

    cb.prepare_modules()
    from sqlalchemy import delete as sa_delete, func, select

    from common.period import max_allowed_period
    from db import session_scope
    from schema import Draw

    today = today or max_allowed_period()
    cond = (func.length(Draw.period) == 7) & (Draw.period > today)
    out: dict = {"today": today, "by_lottery": {}, "deleted": 0}
    with session_scope() as s:
        for lottery, n in s.execute(select(Draw.lottery, func.count()).where(cond).group_by(Draw.lottery)):
            rows = s.scalars(select(Draw).where(cond, Draw.lottery == lottery).order_by(Draw.period.desc()).limit(samples))
            out["by_lottery"][lottery] = {
                "count": n,
                "samples": [(r.period, str(r.draw_date), r.source) for r in rows],
            }
        if delete:
            out["deleted"] = s.execute(sa_delete(Draw).where(cond)).rowcount or 0
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--today", help="cutoff period YYYYDDD (default: today, Beijing time)")
    ap.add_argument("--samples", type=int, default=10)
    ap.add_argument("--delete", action="store_true", help="delete the listed draw rows")
    ap.add_argument("--yes", action="store_true", help="confirm --delete")
    a = ap.parse_args()
    if a.delete and not a.yes:
        print("--delete requires --yes; nothing deleted.")
        return 2
    res = run(a.today, a.samples, delete=a.delete)
    print(f"today's max allowed period: {res['today']}")
    total = 0
    for lottery, info in res["by_lottery"].items():
        total += info["count"]
        print(f"\n[{lottery}] {info['count']} draw rows with period > {res['today']}")
        for sample in info["samples"]:
            print("   period=%s draw_date=%s source=%s" % sample)
    print(f"\nTOTAL future draw rows: {total}")
    print(f"deleted: {res['deleted']}" if a.delete else "(dry run, nothing deleted; use --delete --yes to remove)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
