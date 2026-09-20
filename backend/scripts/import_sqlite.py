#!/usr/bin/env python3
"""CLI utility to import data from an SQLite database file into PostgreSQL or SQLite.

Usage:
  python backend/scripts/import_sqlite.py <path_to_sqlite.db> [options]

Options:
  --target-url URL    Target database connection string (defaults to current active DB)
  --mode MODE         Import mode: 'skip' (default) or 'overwrite'
  --tables TABLES     Comma-separated list of tables to import (e.g. 'draw,prediction,source')
  --inspect-only      Only inspect and print SQLite file structure without importing
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Add backend directory to sys.path
CURRENT_DIR = Path(__file__).resolve().parent
BACKEND_DIR = CURRENT_DIR.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.db_service import (
    get_database_status,
    import_sqlite_data,
    inspect_sqlite_file,
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import data from SQLite file into PostgreSQL or local database."
    )
    parser.add_argument("sqlite_path", help="Path to source SQLite .db file")
    parser.add_argument(
        "--target-url",
        default="",
        help="Optional target database connection URL (defaults to configured DB)",
    )
    parser.add_argument(
        "--mode",
        choices=["skip", "overwrite"],
        default="skip",
        help="Import mode: 'skip' duplicates (default) or 'overwrite' conflicting keys",
    )
    parser.add_argument(
        "--tables",
        default="",
        help="Comma-separated list of tables to import (e.g. 'draw,prediction')",
    )
    parser.add_argument(
        "--inspect-only",
        action="store_true",
        help="Only inspect and print SQLite tables and row counts without importing",
    )

    args = parser.parse_args()

    file_path = Path(args.sqlite_path).resolve()
    if not file_path.exists() or not file_path.is_file():
        print(f"Error: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Reading {file_path.name} ({file_path.stat().st_size:,} bytes)...")
    content_bytes = file_path.read_bytes()

    # 1. Inspect
    inspect_res = inspect_sqlite_file(content_bytes, file_path.name)
    print(f"\n--- Inspection Report for {inspect_res['filename']} ---")
    print(f"Total Tables: {inspect_res['total_tables']}, Total Records: {inspect_res['total_rows']:,}")
    print(f"{'Table Name':<25} {'Category':<12} {'Rows':>10}")
    print("-" * 50)
    for t in inspect_res["tables"]:
        print(f"{t['name']:<25} {t['category']:<12} {t['rows']:>10,}")
    print("-" * 50)

    if args.inspect_only:
        print("\nInspection complete (--inspect-only specified). Exiting.")
        sys.exit(0)

    # 2. Status
    status = get_database_status()
    print(f"\nTarget Mode: {status['mode'].upper()}")
    print(f"App DB:       {status['app_db']['engine']} -> {status['app_db']['url']}")
    print(f"Collector DB: {status['collector_db']['engine']} -> {status['collector_db']['url']}")

    selected_tables = [t.strip() for t in args.tables.split(",") if t.strip()] or None
    if selected_tables:
        print(f"Filtering tables to import: {selected_tables}")

    confirm = input(f"\nProceed with import (mode='{args.mode}')? [y/N]: ").strip().lower()
    if confirm not in ("y", "yes"):
        print("Aborted.")
        sys.exit(0)

    print("\nStarting import, please wait...")
    import_res = import_sqlite_data(
        content_bytes=content_bytes,
        filename=file_path.name,
        mode=args.mode,
        selected_tables=selected_tables,
    )

    if not import_res.get("ok"):
        print(f"\nImport Failed: {import_res.get('error')}", file=sys.stderr)
        sys.exit(1)

    print(f"\nImport Completed Successfully in {import_res['elapsed_ms']}ms!")
    print(f"Total Inserted: {import_res['total_inserted']:,}")
    print(f"Total Skipped:  {import_res['total_skipped']:,}")
    print("\nTable Breakdown:")
    print(f"{'Table Name':<25} {'Status':<10} {'Inserted':>10} {'Skipped':>10}")
    print("-" * 60)
    for tbl, info in import_res["summary"].items():
        print(
            f"{tbl:<25} {info.get('status', 'ok'):<10} "
            f"{info.get('inserted', 0):>10,} {info.get('skipped', 0):>10,}"
        )
    print("-" * 60)


if __name__ == "__main__":
    main()
