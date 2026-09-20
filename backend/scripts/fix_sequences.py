#!/usr/bin/env python3
"""Re-align PostgreSQL primary key sequences with the rows actually stored.

A dataset loaded by ``import_sqlite.py`` (or restored from a dump) keeps its
original ``id`` values, which does not advance the serial sequence behind the
column. The next ordinary INSERT then asks for an id that already exists:

    duplicate key value violates unique constraint "draw_pkey"
    DETAIL:  Key (id)=(2) already exists.

Usage:
  python backend/scripts/fix_sequences.py --check       # report only, writes nothing
  python backend/scripts/fix_sequences.py               # repair both databases
  python backend/scripts/fix_sequences.py --scope app   # app | collector | all

Repairing only ever moves a sequence forward, never back, so it is safe to
re-run and safe on a healthy database.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

CURRENT_DIR = Path(__file__).resolve().parent
BACKEND_DIR = CURRENT_DIR.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.db_service import get_database_status, sync_sequences


def main() -> None:
    parser = argparse.ArgumentParser(description="Repair PostgreSQL id sequences.")
    parser.add_argument(
        "--scope", default="all", choices=["all", "app", "collector"],
        help="Which database to process (default: all)",
    )
    parser.add_argument(
        "--check", action="store_true",
        help="Only report out-of-sync sequences, do not change anything",
    )
    args = parser.parse_args()

    status = get_database_status()
    print(f"Mode: {status['mode']}")
    print(f"  app       : {status['app_db'].get('url', '')}")
    print(f"  collector : {status['collector_db'].get('url', '')}")
    if status["mode"] != "postgresql":
        print("\nNot a PostgreSQL target; sequences are a PostgreSQL-only concern. Nothing to do.")
        return

    try:
        res = sync_sequences(scope=args.scope, dry_run=args.check)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)

    verb = "behind the data" if args.check else "realigned"
    if res["synced"]:
        print(f"\n{len(res['synced'])} sequence(s) {verb}:")
        for item in res["synced"]:
            print(f"  {item}")
    else:
        print("\nAll sequences are already ahead of the stored data.")

    if res["failed"]:
        print(f"\n{len(res['failed'])} failure(s):", file=sys.stderr)
        for item in res["failed"]:
            print(f"  {item['db']}.{item['table']}: {item['error']}", file=sys.stderr)
        sys.exit(1)

    if args.check and res["synced"]:
        print("\nRe-run without --check to repair.")


if __name__ == "__main__":
    main()
