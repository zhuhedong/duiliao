#!/usr/bin/env python3
"""Automated test script to verify PostgreSQL support, SQLite inspection, and data import."""
from __future__ import annotations

import os
import sqlite3
import sys
import tempfile
from pathlib import Path

# Add backend to sys.path
CURRENT_DIR = Path(__file__).resolve().parent
BACKEND_DIR = CURRENT_DIR.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.core.config import settings
from app.services.db_service import (
    SQL_PG_COLUMN_DEFAULT,
    SQL_PG_OWNED_SEQUENCE,
    SQL_PG_SETVAL,
    get_database_status,
    import_sqlite_data,
    inspect_sqlite_file,
    normalize_db_url,
    test_pg_connection,
)


def test_url_normalization() -> None:
    print("\n[1/5] Testing Database URL Normalization...")
    # Standard postgres -> postgresql+psycopg
    assert normalize_db_url("postgresql://user:pass@localhost:5432/mydb") == "postgresql+psycopg://user:pass@localhost:5432/mydb", "Failed postgresql:// normalization"
    assert normalize_db_url("postgres://user:pass@localhost:5432/mydb") == "postgresql+psycopg://user:pass@localhost:5432/mydb", "Failed postgres:// normalization"
    # Existing postgresql+psycopg remains intact
    assert normalize_db_url("postgresql+psycopg://user:pass@localhost:5432/mydb") == "postgresql+psycopg://user:pass@localhost:5432/mydb"
    # SQLite URLs remain intact
    assert normalize_db_url("sqlite:///./duiliao.db") == "sqlite:///./duiliao.db"
    print("  ✓ URL normalization passed for postgresql, postgres, and sqlite")


def test_sequence_sql_binds() -> None:
    """Every bind parameter in the sequence-repair SQL must reach the server.

    ``text()`` refuses to treat ``:seq`` as a bind parameter when ``::`` follows
    it, so ``setval(:seq::regclass, ...)`` compiled to SQL that still contained a
    literal ``:seq`` and PostgreSQL rejected it with a syntax error. Compiling
    each statement here catches that class of mistake without a live server.
    """
    print("\n[2/5] Testing Sequence Repair SQL Binds...")
    import re

    from sqlalchemy import text
    from sqlalchemy.dialects import postgresql

    dialect = postgresql.psycopg.dialect()
    cases = [
        (SQL_PG_OWNED_SEQUENCE, {"tbl", "col"}),
        (SQL_PG_COLUMN_DEFAULT, {"tbl", "col"}),
        (SQL_PG_SETVAL, {"seq", "val"}),
    ]
    for sql, expected in cases:
        compiled = str(text(sql).compile(dialect=dialect))
        stray = re.search(r"(?<!:):[A-Za-z_]\w*", compiled)
        assert stray is None, f"unbound parameter {stray.group(0)!r} left in: {compiled}"
        for name in expected:
            assert f"%({name})s" in compiled, f"{name} was not bound in: {compiled}"
    print(f"  ✓ {len(cases)} statement(s) compile with every parameter bound")


def test_connection_testing() -> None:
    print("\n[3/5] Testing PostgreSQL Connection Validator...")
    # Invalid URL syntax check
    res_inv = test_pg_connection("mysql://user:pass@localhost/db")
    assert not res_inv["ok"], "Expected invalid scheme to fail"
    print(f"  ✓ Non-PG URL correctly rejected: {res_inv['error']}")

    # Non-existent PG server with 5s timeout
    res_fake = test_pg_connection("postgresql://test:test@127.0.0.1:54329/nonexistent")
    assert not res_fake["ok"], "Expected connection failure for non-existent server"
    assert "连接失败" in res_fake["error"] or "Connection refused" in res_fake["error"]
    print(f"  ✓ Non-existent PG server handled cleanly with error: {res_fake['error'][:60]}...")


def test_sqlite_inspection() -> None:
    print("\n[4/5] Testing SQLite File Inspection...")
    # Use real duiliao.db if available
    db_file = BACKEND_DIR / "duiliao.db"
    if db_file.exists():
        bytes_data = db_file.read_bytes()
        res = inspect_sqlite_file(bytes_data, "duiliao.db")
        assert res["filename"] == "duiliao.db"
        assert res["total_tables"] >= 3
        tbl_names = {t["name"] for t in res["tables"]}
        assert "users" in tbl_names
        assert "refresh_tokens" in tbl_names
        assert "system_settings" in tbl_names
        print(f"  ✓ Successfully inspected duiliao.db ({res['total_tables']} tables, {res['total_rows']} rows)")


def test_sqlite_import_engine() -> None:
    print("\n[5/5] Testing SQLite Data Import Engine...")
    # Create a temporary SQLite database with mock system_settings
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tf:
        tf_path = tf.name

    try:
        conn = sqlite3.connect(tf_path)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE system_settings (
                key VARCHAR(128) PRIMARY KEY,
                value VARCHAR(4096) NOT NULL,
                description VARCHAR(255),
                updated_at DATETIME
            )
        """)
        cur.execute("INSERT INTO system_settings VALUES ('test_key_1', 'val_1', 'desc 1', '2026-09-20 12:00:00')")
        cur.execute("INSERT INTO system_settings VALUES ('test_key_2', 'val_2', 'desc 2', '2026-09-20 12:00:00')")
        conn.commit()
        conn.close()

        with open(tf_path, "rb") as f:
            content_bytes = f.read()

        # Import with skip mode
        res = import_sqlite_data(
            content_bytes=content_bytes,
            filename="mock_test.db",
            mode="skip",
            selected_tables=["system_settings"],
        )
        assert res["ok"] is True, f"Import failed: {res.get('error')}"
        assert res["total_inserted"] >= 0
        print(f"  ✓ Mock data imported successfully: inserted={res['total_inserted']}, skipped={res['total_skipped']} in {res['elapsed_ms']}ms")

        # Import again with skip mode -> should skip existing records
        res_skip = import_sqlite_data(
            content_bytes=content_bytes,
            filename="mock_test.db",
            mode="skip",
            selected_tables=["system_settings"],
        )
        assert res_skip["ok"] is True
        assert res_skip["total_skipped"] == 2, f"Expected 2 skipped, got {res_skip['total_skipped']}"
        print(f"  ✓ Second import with mode='skip' correctly skipped duplicates (skipped={res_skip['total_skipped']})")

        # Import with overwrite mode -> should overwrite
        res_overwrite = import_sqlite_data(
            content_bytes=content_bytes,
            filename="mock_test.db",
            mode="overwrite",
            selected_tables=["system_settings"],
        )
        assert res_overwrite["ok"] is True
        assert res_overwrite["total_inserted"] == 2, f"Expected 2 inserted on overwrite, got {res_overwrite['total_inserted']}"
        print(f"  ✓ Third import with mode='overwrite' correctly re-inserted records (inserted={res_overwrite['total_inserted']})")

        # Clean up test keys from db
        from app.db.session import engine as app_engine
        from sqlalchemy import text
        with app_engine.begin() as conn:
            conn.execute(text("DELETE FROM system_settings WHERE key IN ('test_key_1', 'test_key_2')"))

    finally:
        try:
            os.remove(tf_path)
        except Exception:
            pass


def main() -> None:
    print("==================================================")
    print("Running Database & SQLite Import Automated Tests")
    print("==================================================")
    test_url_normalization()
    test_sequence_sql_binds()
    test_connection_testing()
    test_sqlite_inspection()
    test_sqlite_import_engine()
    print("\n==================================================")
    print("All Automated Tests Passed Successfully! ✓")
    print("==================================================")


if __name__ == "__main__":
    main()
