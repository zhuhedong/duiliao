"""Database management service: status inspection, PG testing/configuration,
and SQLite file inspection & topological data import into SQLite/PostgreSQL.
"""
from __future__ import annotations

import base64
import json
import os
import re
import sqlite3
import tempfile
import time
from datetime import date, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import (
    BigInteger,
    Integer,
    SmallInteger,
    Table,
    create_engine,
    delete,
    func,
    insert,
    select,
    text,
)
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.pool import NullPool

from app.core.config import BACKEND_DIR, ROOT_DIR, settings
from app.db.session import Base as AppBase, engine as app_engine, init_db, reset_db


def _parse_datetime(val: Any) -> Any:
    if not isinstance(val, str) or not val.strip():
        return val
    s = val.strip()
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt)
        except Exception:
            pass
    return val


def _mask_url(url: str) -> str:
    """Mask password in database URL for safe UI presentation."""
    if not url:
        return ""
    if "@" in url and "://" in url:
        # e.g. postgresql+psycopg://user:password@host:5432/dbname
        prefix, rest = url.split("://", 1)
        if "@" in rest:
            auth, host_path = rest.split("@", 1)
            if ":" in auth:
                user, _ = auth.split(":", 1)
                return f"{prefix}://{user}:***@{host_path}"
            return f"{prefix}://***@{host_path}"
    return url


def normalize_db_url(url: str) -> str:
    """Normalize user-entered DB connection string into standard SQLAlchemy format."""
    if not url:
        return ""
    v = url.strip()
    if v.startswith("postgres://") or v.startswith("postgresql://"):
        try:
            u = make_url(v)
            if u.drivername in ("postgresql", "postgres"):
                return u.set(drivername="postgresql+psycopg").render_as_string(hide_password=False)
        except Exception:
            pass
    return v


def get_collector_engine() -> Engine | None:
    """Obtain the collector database engine."""
    try:
        from app import collector_bridge as cb

        cb.bootstrap()
        import db as collector_db  # type: ignore[import-not-found]

        return collector_db.get_engine()
    except Exception:
        return None


def get_database_status() -> dict[str, Any]:
    """Inspect current database connection statuses, dialect names, and table row counts."""
    # 1. App Database status
    from app import models  # noqa: F401

    app_status: dict[str, Any] = {
        "engine": app_engine.dialect.name,
        "url": _mask_url(str(app_engine.url)),
        "is_connected": False,
        "ping_ms": -1,
        "tables": {},
    }
    t0 = time.perf_counter()
    try:
        with app_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
            app_status["ping_ms"] = int((time.perf_counter() - t0) * 1000)
            app_status["is_connected"] = True

            # Count rows for app tables
            for table_name in ("users", "refresh_tokens", "system_settings"):
                if table_name in AppBase.metadata.tables:
                    tbl = AppBase.metadata.tables[table_name]
                    try:
                        count = conn.execute(select(func.count()).select_from(tbl)).scalar() or 0
                        app_status["tables"][table_name] = count
                    except Exception:
                        app_status["tables"][table_name] = 0
    except Exception as exc:
        app_status["error"] = str(exc)

    # 2. Collector Database status
    collector_status: dict[str, Any] = {
        "engine": "unknown",
        "url": "",
        "is_connected": False,
        "ping_ms": -1,
        "tables": {},
    }
    c_engine = get_collector_engine()
    if c_engine is not None:
        collector_status["engine"] = c_engine.dialect.name
        collector_status["url"] = _mask_url(str(c_engine.url))
        t1 = time.perf_counter()
        try:
            with c_engine.connect() as conn:
                conn.execute(text("SELECT 1"))
                collector_status["ping_ms"] = int((time.perf_counter() - t1) * 1000)
                collector_status["is_connected"] = True

                import db as collector_db  # type: ignore[import-not-found]

                for table_name in (
                    "draw",
                    "prediction",
                    "source",
                    "crawl_run",
                    "judge_result",
                    "schedule",
                    "number_info",
                    "audit_event",
                    "issue",
                ):
                    if table_name in collector_db.Base.metadata.tables:
                        tbl = collector_db.Base.metadata.tables[table_name]
                        try:
                            count = conn.execute(select(func.count()).select_from(tbl)).scalar() or 0
                            collector_status["tables"][table_name] = count
                        except Exception:
                            collector_status["tables"][table_name] = 0
        except Exception as exc:
            collector_status["error"] = str(exc)

    total_records = sum(app_status["tables"].values()) + sum(collector_status["tables"].values())
    total_tables = len(app_status["tables"]) + len(collector_status["tables"])

    is_pg = (app_status["engine"] == "postgresql") or (collector_status["engine"] == "postgresql")

    return {
        "mode": "postgresql" if is_pg else "sqlite",
        "app_db": app_status,
        "collector_db": collector_status,
        "total_records": total_records,
        "total_tables": total_tables,
    }


def test_pg_connection(url: str) -> dict[str, Any]:
    """Test connection to a PostgreSQL database with a strict 5-second timeout."""
    norm_url = normalize_db_url(url)
    if not (norm_url.startswith("postgresql") or norm_url.startswith("postgres")):
        return {"ok": False, "error": "连接串必须是以 postgresql:// 或 postgres:// 开头的有效地址"}

    t0 = time.perf_counter()
    tmp_engine = None
    try:
        tmp_engine = create_engine(
            norm_url,
            poolclass=NullPool,
            connect_args={"connect_timeout": 5},
        )
        with tmp_engine.connect() as conn:
            row = conn.execute(text("SELECT version()")).fetchone()
            version_str = row[0] if row else "PostgreSQL"
            elapsed_ms = int((time.perf_counter() - t0) * 1000)
            return {
                "ok": True,
                "message": f"连接成功！响应耗时 {elapsed_ms}ms",
                "version": version_str,
                "elapsed_ms": elapsed_ms,
            }
    except Exception as exc:
        return {
            "ok": False,
            "error": f"连接失败: {exc}",
            "elapsed_ms": int((time.perf_counter() - t0) * 1000),
        }
    finally:
        if tmp_engine is not None:
            try:
                tmp_engine.dispose()
            except Exception:
                pass


def _update_env_file(filepath: Path, updates: dict[str, str]) -> None:
    """Idempotently update or append keys in an existing .env file."""
    if not filepath.exists():
        filepath.touch()
    content = filepath.read_text(encoding="utf-8")
    lines = content.splitlines()
    found_keys = set()
    new_lines = []

    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            k, _ = stripped.split("=", 1)
            k = k.strip()
            if k in updates:
                new_lines.append(f'{k}="{updates[k]}"')
                found_keys.add(k)
                continue
        new_lines.append(line)

    for k, v in updates.items():
        if k not in found_keys:
            new_lines.append(f'{k}="{v}"')

    filepath.write_text("\n".join(new_lines) + "\n", encoding="utf-8")


def update_database_config(db_url: str, collector_url: str | None = None) -> dict[str, Any]:
    """Persist new database connection settings to .env and reinitialize connections."""
    db_url = normalize_db_url(db_url)
    if collector_url:
        collector_url = normalize_db_url(collector_url)

    updates = {"DATABASE_URL": db_url}
    if collector_url:
        updates["COLLECTOR_DATABASE_URL"] = collector_url

    # 1. Update .env files
    env_backend = BACKEND_DIR / ".env"
    _update_env_file(env_backend, updates)

    env_root = ROOT_DIR / ".env"
    if env_root.exists():
        _update_env_file(env_root, updates)

    # 2. Update process environment and runtime settings
    os.environ["DATABASE_URL"] = db_url
    settings.DATABASE_URL = db_url

    if collector_url:
        os.environ["COLLECTOR_DATABASE_URL"] = collector_url
        settings.COLLECTOR_DATABASE_URL = collector_url
    elif db_url.startswith("postgres"):
        os.environ["COLLECTOR_DATABASE_URL"] = db_url
        settings.COLLECTOR_DATABASE_URL = db_url

    # 3. Reinitialize app DB engine and create tables
    reset_db(db_url)
    init_db()

    # 4. Reinitialize collector DB engine and create tables
    try:
        from app import collector_bridge as cb

        import db as collector_db  # type: ignore[import-not-found]
        import schema as collector_schema  # type: ignore[import-not-found]

        collector_db.reset_engine()
        cb.bootstrap()
        collector_schema.create_all()
    except Exception as exc:
        pass

    return get_database_status()


# Table category definitions and topological import ordering
APP_TABLES = {"users", "refresh_tokens", "system_settings"}

APP_IMPORT_ORDER = [
    "system_settings",
    "users",
    "refresh_tokens",
]

COLLECTOR_IMPORT_ORDER = [
    "number_info",
    "number_year_attr",
    "number_code_meta",
    "xiao_year_meta",
    "setting",
    "schedule",
    "source",
    "draw",
    "issue",
    "task",
    "task_attempt",
    "crawl_run",
    "crawl_run_source",
    "prediction",
    "judge_result",
    "audit_event",
    "admin_session",
    "login_failure",
    "app_account",
    "app_challenge",
    "app_rate_limit",
    "app_security_event",
    "app_activation",
    "app_session",
    "app_request_nonce",
]


def inspect_sqlite_file(content_bytes: bytes, filename: str) -> dict[str, Any]:
    """Parse an uploaded SQLite database file and return table schemas and row counts."""
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tf:
        tf.write(content_bytes)
        tf_path = tf.name

    try:
        con = sqlite3.connect(tf_path)
        cur = con.cursor()
        raw_tables = cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()

        table_info_list = []
        total_rows = 0

        for row in raw_tables:
            tbl = row[0]
            try:
                cnt = cur.execute(f'SELECT count(*) FROM "{tbl}"').fetchone()[0]
            except Exception:
                cnt = 0
            total_rows += cnt

            cols = cur.execute(f'PRAGMA table_info("{tbl}")').fetchall()
            col_names = [c[1] for c in cols]

            category = "other"
            if tbl in APP_TABLES:
                category = "app"
            elif tbl in COLLECTOR_IMPORT_ORDER:
                category = "collector"

            table_info_list.append(
                {
                    "name": tbl,
                    "rows": cnt,
                    "columns": col_names,
                    "category": category,
                }
            )

        con.close()

        return {
            "filename": filename,
            "file_size": len(content_bytes),
            "total_tables": len(table_info_list),
            "total_rows": total_rows,
            "tables": table_info_list,
        }
    finally:
        try:
            os.remove(tf_path)
        except Exception:
            pass


def _sync_pg_sequences(engine: Engine, table: Table) -> None:
    """Reset PostgreSQL serial/identity sequences to max(id) after data import."""
    if engine.dialect.name != "postgresql":
        return
    for col in table.primary_key.columns:
        if isinstance(col.type, (Integer, BigInteger, SmallInteger)):
            col_name = col.name
            tbl_name = table.name
            sql = text(
                f"SELECT setval(pg_get_serial_sequence('{tbl_name}', '{col_name}'), "
                f"COALESCE(MAX({col_name}), 1)) FROM {tbl_name}"
            )
            try:
                with engine.begin() as conn:
                    conn.execute(sql)
            except Exception:
                pass


def import_sqlite_data(
    content_bytes: bytes,
    filename: str,
    mode: str = "skip",  # "skip" | "overwrite"
    selected_tables: list[str] | None = None,
) -> dict[str, Any]:
    """Import data from an SQLite file into current target databases (SQLite or PostgreSQL).

    Handles topological foreign key dependencies, conflict handling ('skip' or 'overwrite'),
    JSON column conversions, and PostgreSQL sequence synchronization.
    """
    t0 = time.perf_counter()

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tf:
        tf.write(content_bytes)
        tf_path = tf.name

    summary: dict[str, Any] = {}
    total_inserted = 0
    total_skipped = 0

    try:
        sqlite_con = sqlite3.connect(tf_path)
        sqlite_con.row_factory = sqlite3.Row
        cur = sqlite_con.cursor()

        # Find tables present in SQLite file
        file_tables = {
            r[0]
            for r in cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            ).fetchall()
        }

        # Determine tables to import
        tables_to_process = file_tables
        if selected_tables:
            tables_to_process = file_tables.intersection(set(selected_tables))

        # Make sure target tables exist
        init_db()
        c_engine = get_collector_engine()
        if c_engine is not None:
            try:
                import schema as collector_schema  # type: ignore[import-not-found]

                collector_schema.create_all()
            except Exception:
                pass

        # Prepare target table mappings: (table_name -> (target_engine, Table object))
        import db as collector_db  # type: ignore[import-not-found]

        # Determine topological import order
        ordered_tables: list[str] = []
        for t in APP_IMPORT_ORDER:
            if t in tables_to_process and t not in ordered_tables:
                ordered_tables.append(t)
        for t in COLLECTOR_IMPORT_ORDER:
            if t in tables_to_process and t not in ordered_tables:
                ordered_tables.append(t)
        for t in sorted(tables_to_process):
            if t not in ordered_tables:
                ordered_tables.append(t)

        for tbl_name in ordered_tables:
            # Find target table definition and engine
            target_engine: Engine | None = None
            table_obj: Table | None = None

            if tbl_name in AppBase.metadata.tables:
                target_engine = app_engine
                table_obj = AppBase.metadata.tables[tbl_name]
            elif c_engine is not None and tbl_name in collector_db.Base.metadata.tables:
                target_engine = c_engine
                table_obj = collector_db.Base.metadata.tables[tbl_name]

            if target_engine is None or table_obj is None:
                summary[tbl_name] = {
                    "status": "skipped",
                    "reason": "目标数据库中未定义此表结构",
                    "inserted": 0,
                    "skipped": 0,
                }
                continue

            # Fetch rows from SQLite
            rows = cur.execute(f'SELECT * FROM "{tbl_name}"').fetchall()
            if not rows:
                summary[tbl_name] = {"status": "empty", "inserted": 0, "skipped": 0}
                continue

            pk_cols = [col.name for col in table_obj.primary_key.columns]
            col_names = [col.name for col in table_obj.columns]

            tbl_inserted = 0
            tbl_skipped = 0
            batch_size = 200

            # Execute import in batches within a transaction
            with target_engine.begin() as conn:
                # If overwrite mode and no primary key, or user requested clear
                existing_pks: set = set()
                if pk_cols:
                    if len(pk_cols) == 1:
                        pk_col = table_obj.c[pk_cols[0]]
                        existing_pks = set(conn.execute(select(pk_col)).scalars().all())
                    else:
                        # Composite primary key
                        pk_tuple = tuple(table_obj.c[k] for k in pk_cols)
                        existing_pks = set(conn.execute(select(*pk_tuple)).fetchall())

                records_to_insert = []

                for r in rows:
                    row_dict = dict(r)
                    # Filter only columns existing in destination
                    filtered = {k: v for k, v in row_dict.items() if k in col_names}

                    # Determine PK presence
                    is_existing = False
                    if pk_cols:
                        if len(pk_cols) == 1:
                            val = filtered.get(pk_cols[0])
                            is_existing = val in existing_pks
                        else:
                            val = tuple(filtered.get(k) for k in pk_cols)
                            is_existing = val in existing_pks

                    if is_existing:
                        if mode == "skip":
                            tbl_skipped += 1
                            continue
                        elif mode == "overwrite":
                            # In overwrite mode: delete old row so we can re-insert cleanly
                            if len(pk_cols) == 1:
                                conn.execute(
                                    delete(table_obj).where(
                                        table_obj.c[pk_cols[0]] == filtered.get(pk_cols[0])
                                    )
                                )
                            else:
                                conds = [table_obj.c[k] == filtered.get(k) for k in pk_cols]
                                conn.execute(delete(table_obj).where(*conds))

                    # Type conversions: DateTime, Date, Boolean, JSON
                    for c in table_obj.columns:
                        if c.name in filtered:
                            val = filtered[c.name]
                            if val is None:
                                continue
                            ctype_str = str(c.type).upper()
                            if "DATETIME" in ctype_str or "TIMESTAMP" in ctype_str or "DATE" in ctype_str:
                                filtered[c.name] = _parse_datetime(val)
                            elif "BOOL" in ctype_str and isinstance(val, int):
                                filtered[c.name] = bool(val)
                            elif (
                                ctype_str.startswith("JSON")
                                and isinstance(val, str)
                                and (val.startswith("{") or val.startswith("["))
                            ):
                                try:
                                    filtered[c.name] = json.loads(val)
                                except Exception:
                                    pass

                    records_to_insert.append(filtered)
                    if pk_cols:
                        if len(pk_cols) == 1:
                            existing_pks.add(filtered.get(pk_cols[0]))
                        else:
                            existing_pks.add(tuple(filtered.get(k) for k in pk_cols))

                    if len(records_to_insert) >= batch_size:
                        conn.execute(insert(table_obj), records_to_insert)
                        tbl_inserted += len(records_to_insert)
                        records_to_insert.clear()

                if records_to_insert:
                    conn.execute(insert(table_obj), records_to_insert)
                    tbl_inserted += len(records_to_insert)
                    records_to_insert.clear()

                # Sync sequences if on PostgreSQL
                _sync_pg_sequences(target_engine, table_obj)

            total_inserted += tbl_inserted
            total_skipped += tbl_skipped
            summary[tbl_name] = {
                "status": "success",
                "inserted": tbl_inserted,
                "skipped": tbl_skipped,
            }

        sqlite_con.close()

        elapsed_ms = int((time.perf_counter() - t0) * 1000)
        return {
            "ok": True,
            "filename": filename,
            "total_inserted": total_inserted,
            "total_skipped": total_skipped,
            "elapsed_ms": elapsed_ms,
            "summary": summary,
        }
    except Exception as exc:
        return {
            "ok": False,
            "error": f"导入过程发生异常: {exc}",
            "elapsed_ms": int((time.perf_counter() - t0) * 1000),
            "summary": summary,
        }
    finally:
        try:
            os.remove(tf_path)
        except Exception:
            pass
