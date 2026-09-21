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
    inspect as sa_inspect,
    select,
    text,
)
from sqlalchemy.engine import Connection, Engine, make_url
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
            for table_name in ("users", "refresh_tokens", "system_settings", "user_subscriptions"):
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
                    "collect_job",
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


# ==============================================================================
# Schema verification & repair
# ==============================================================================


def _app_target() -> tuple[Engine, Any]:
    """Return the app (engine, metadata) with every model registered."""
    from app import models  # noqa: F401  (registers models on AppBase.metadata)

    return app_engine, AppBase.metadata


def _collector_target() -> tuple[Engine, Any]:
    """Return the collector (engine, metadata) without running any DDL.

    Deliberately avoids ``collector_bridge.bootstrap()``: bootstrap creates and
    migrates the schema, so it is unusable for diagnosing a database whose
    schema is the thing that is broken.
    """
    from app import collector_bridge as cb

    cb.prepare_modules()
    import db as collector_db  # type: ignore[import-not-found]

    return collector_db.get_engine(), collector_db.Base.metadata


def _empty_report() -> dict[str, Any]:
    return {
        "engine": "unknown",
        "url": "",
        "is_connected": False,
        "declared": [],
        "existing": [],
        "missing": [],
        "unmanaged": [],
    }


def _schema_report(engine: Engine, metadata: Any, counterpart: set[str]) -> dict[str, Any]:
    """Diff one database against its declared metadata.

    ``counterpart`` holds the table names owned by the *other* metadata
    registry; they are excluded from ``unmanaged`` so that a shared database
    does not report the app's tables as strays of the collector (or vice versa).
    """
    declared = [t.name for t in metadata.sorted_tables]
    report = _empty_report()
    report.update({
        "engine": engine.dialect.name,
        "url": _mask_url(str(engine.url)),
        "declared": declared,
    })
    try:
        with engine.connect() as conn:
            present = set(sa_inspect(conn).get_table_names())
    except Exception as exc:
        report["error"] = str(exc)
        return report
    report["is_connected"] = True
    report["existing"] = [name for name in declared if name in present]
    report["missing"] = [name for name in declared if name not in present]
    report["unmanaged"] = sorted(present - set(declared) - counterpart)
    return report


def verify_schema() -> dict[str, Any]:
    """Check that every table declared in the ORM metadata exists in its database.

    ``missing`` comes back in dependency (foreign-key safe) order, which is the
    same order :func:`repair_schema` creates them in.
    """
    app_eng, app_meta = _app_target()
    app_declared = {t.name for t in app_meta.sorted_tables}

    c_engine: Engine | None = None
    try:
        c_engine, c_meta = _collector_target()
        collector = _schema_report(c_engine, c_meta, app_declared)
        c_declared = {t.name for t in c_meta.sorted_tables}
    except Exception as exc:
        collector = _empty_report()
        collector["error"] = str(exc)
        c_declared = set()

    app = _schema_report(app_eng, app_meta, c_declared)

    missing_total = len(app["missing"]) + len(collector["missing"])
    return {
        "ok": missing_total == 0 and app["is_connected"] and collector["is_connected"],
        "missing_total": missing_total,
        "shared_database": c_engine is not None and str(c_engine.url) == str(app_eng.url),
        "app_db": app,
        "collector_db": collector,
    }


def _create_missing(
    engine: Engine, metadata: Any, missing: list[str]
) -> tuple[list[str], list[dict[str, str]]]:
    """Create the named tables one transaction at a time, in foreign-key order.

    One transaction per table is the whole point: a single failing table must
    not roll back the tables already created alongside it, which is exactly how
    a leftover reference to a dropped table once wiped out an entire
    ``create_all()`` and left the database empty.
    """
    wanted = set(missing)
    created: list[str] = []
    failed: list[dict[str, str]] = []
    for table in metadata.sorted_tables:
        if table.name not in wanted:
            continue
        try:
            with engine.begin() as conn:
                table.create(conn, checkfirst=True)
            created.append(table.name)
        except Exception as exc:
            failed.append({"table": table.name, "error": str(exc)})
    return created, failed


def repair_schema(scope: str = "all", seed: bool = True) -> dict[str, Any]:
    """Create only the tables that are missing, then report what changed.

    ``scope`` is ``all``, ``app`` or ``collector``. Existing tables are never
    touched: this only issues ``CREATE TABLE`` for absent ones, so it cannot
    drop or alter data. It also re-aligns the primary key sequences, which is
    how an imported dataset's stale sequences get repaired.
    """
    if scope not in ("all", "app", "collector"):
        raise ValueError("scope 必须是 all / app / collector 之一")

    before = verify_schema()
    created: dict[str, list[str]] = {"app": [], "collector": []}
    failed: list[dict[str, str]] = []
    notes: list[str] = []

    if scope in ("all", "app") and before["app_db"]["missing"]:
        engine, metadata = _app_target()
        ok, bad = _create_missing(engine, metadata, before["app_db"]["missing"])
        created["app"] = ok
        failed.extend({"db": "app", **item} for item in bad)

    if scope in ("all", "collector") and before["collector_db"]["missing"]:
        try:
            engine, metadata = _collector_target()
        except Exception as exc:
            failed.append({"db": "collector", "table": "-", "error": str(exc)})
        else:
            ok, bad = _create_missing(engine, metadata, before["collector_db"]["missing"])
            created["collector"] = ok
            failed.extend({"db": "collector", **item} for item in bad)

    # Finish what the normal startup path would have done for the new tables:
    # column/index migrations, then reference data. Both are idempotent.
    if created["collector"]:
        from app import collector_bridge as cb

        try:
            cb.prepare_modules().create_all()
        except Exception as exc:
            notes.append(f"迁移步骤未完成: {exc}")
        if seed:
            try:
                cb.seed_reference_data()
                notes.append("参考数据已重新写入 (number_info / source 等)")
            except Exception as exc:
                notes.append(f"参考数据写入失败: {exc}")

    # Key sequences left behind by an imported/restored dataset hand out ids that
    # already exist. Forward-only, so this is safe on an untouched database.
    sequences = sync_sequences(scope)
    if sequences["synced"]:
        notes.append(f"已校准 {len(sequences['synced'])} 个自增主键序列")
    for item in sequences["failed"]:
        notes.append(f"序列校准失败 {item['db']}.{item['table']}: {item['error']}")

    after = verify_schema()
    return {
        "ok": not failed and after["missing_total"] == 0,
        "scope": scope,
        "created": created,
        "sequences": sequences,
        "created_total": len(created["app"]) + len(created["collector"]),
        "failed": failed,
        "notes": notes,
        "before_missing": {
            "total": before["missing_total"],
            "app": before["app_db"]["missing"],
            "collector": before["collector_db"]["missing"],
        },
        "after": after,
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
APP_TABLES = {"users", "refresh_tokens", "system_settings", "user_subscriptions"}

APP_IMPORT_ORDER = [
    "system_settings",
    "users",
    "refresh_tokens",
    "user_subscriptions",
]

COLLECTOR_IMPORT_ORDER = [
    "number_info",
    "number_year_attr",
    "number_code_meta",
    "xiao_year_meta",
    "setting",
    "schedule",
    "collect_job",
    "ai_report",
    "consensus_leader",
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


# SQL for the sequence repair below, kept as constants so the statements can be
# compiled and checked without a live PostgreSQL server (see
# ``scripts/test_db_features.py``).
#
# Casts are written as CAST(:p AS type), never ``:p::type``: SQLAlchemy's text()
# will not recognise a bind parameter immediately followed by ``::``, so the
# ``:p`` would reach the server verbatim and fail with a syntax error.
SQL_PG_OWNED_SEQUENCE = "SELECT pg_get_serial_sequence(:tbl, :col)"
SQL_PG_COLUMN_DEFAULT = (
    "SELECT pg_get_expr(d.adbin, d.adrelid) "
    "FROM pg_attrdef d "
    "JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum "
    "WHERE d.adrelid = CAST(:tbl AS regclass) AND a.attname = :col"
)
SQL_PG_SEQUENCE_STATE = "SELECT last_value, is_called FROM {seq}"
SQL_PG_SETVAL = "SELECT setval(CAST(:seq AS regclass), :val, false)"


def _pg_column_sequence(conn: Connection, qualified_table: str, column: str) -> str | None:
    """Return the sequence feeding ``column``, or None if it has no sequence.

    ``pg_get_serial_sequence`` only reports sequences *owned* by the column, the
    link ``BIGSERIAL`` sets up. A table restored from a SQL dump can end up with
    ``DEFAULT nextval('draw_id_seq')`` and no ownership record, and then the
    catalog lookup returns NULL for a column that very much does draw from a
    sequence — which is how a stale sequence stays invisible and unrepaired. So
    fall back to reading the column default.
    """
    seq = conn.execute(
        text(SQL_PG_OWNED_SEQUENCE),
        {"tbl": qualified_table, "col": column},
    ).scalar()
    if seq:
        return str(seq)

    default = conn.execute(
        text(SQL_PG_COLUMN_DEFAULT),
        {"tbl": qualified_table, "col": column},
    ).scalar()
    match = re.search(r"nextval\('([^']+)'", str(default or ""))
    return match.group(1) if match else None


def _sync_pg_sequences(conn: Connection, table: Table, dry_run: bool = False) -> list[str]:
    """Advance this table's PostgreSQL sequences past the largest key it holds.

    Runs on the **caller's** connection on purpose. Imports insert explicit ``id``
    values, which leaves the serial/identity sequence sitting at its start; a
    second connection opened here would compute ``MAX(id)`` from a snapshot that
    cannot see the still-uncommitted rows, set the sequence to 1, and make the
    next natural insert collide with an imported row (``duplicate key value
    violates unique constraint "draw_pkey"``).

    A sequence is only ever moved forward, never back, so running this against a
    healthy database is a no-op. Returns the sequences that needed moving (and,
    unless ``dry_run``, were moved) as ``table.column=next_value``.
    """
    if conn.dialect.name != "postgresql":
        return []

    qualified = conn.dialect.identifier_preparer.format_table(table)
    moved: list[str] = []

    for col in table.primary_key.columns:
        if not isinstance(col.type, (Integer, BigInteger, SmallInteger)):
            continue
        seq = _pg_column_sequence(conn, qualified, col.name)
        if not seq:
            # Plain integer key whose values the application supplies itself.
            continue

        highest = int(conn.execute(select(func.max(col))).scalar() or 0)
        # ``seq`` is the identifier Postgres itself handed back, already quoted.
        last_value, is_called = conn.execute(
            text(SQL_PG_SEQUENCE_STATE.format(seq=seq))  # noqa: S608
        ).one()
        next_value = int(last_value) + 1 if is_called else int(last_value)
        target = max(highest + 1, next_value)
        if target == next_value:
            continue  # already ahead of the data, leave it alone
        if not dry_run:
            # is_called=false => the next nextval() returns exactly ``target``.
            conn.execute(text(SQL_PG_SETVAL), {"seq": seq, "val": target})
        moved.append(f"{table.name}.{col.name}={target} (was {next_value})")
    return moved


def _sequence_targets() -> tuple[dict[str, tuple[Engine, Any]], list[dict[str, str]]]:
    """Resolve the (engine, metadata) pair of each database, plus what failed.

    A database that cannot be resolved is *reported*, never silently dropped:
    ``draw`` lives in the collector database, so swallowing that failure would
    hide the very table this repair exists for.
    """
    targets: dict[str, tuple[Engine, Any]] = {}
    failed: list[dict[str, str]] = []
    for name, resolve in (("app", _app_target), ("collector", _collector_target)):
        try:
            targets[name] = resolve()
        except Exception as exc:
            failed.append({"db": name, "table": "-", "error": str(exc)})
    return targets, failed


def sync_sequences(scope: str = "all", dry_run: bool = False) -> dict[str, Any]:
    """Re-align every PostgreSQL key sequence with the data actually stored.

    Idempotent and forward-only, so it is safe to call on every startup and
    after every import. This is the repair for databases seeded by an SQLite
    import (or a plain dump restore), where the rows carry their original ids
    but the sequences were never advanced.

    With ``dry_run`` nothing is written: the report then lists the sequences that
    are currently handing out keys that already exist.
    """
    if scope not in ("all", "app", "collector"):
        raise ValueError("scope 必须是 all / app / collector 之一")

    synced: list[str] = []
    targets, failed = _sequence_targets()
    failed = [item for item in failed if scope in ("all", item["db"])]
    # Tables actually examined per database. Without this an empty ``synced``
    # cannot be told apart from a run that inspected nothing at all.
    inspected: dict[str, int] = {}

    for name, (engine, metadata) in targets.items():
        if scope not in ("all", name) or engine is None:
            continue
        if engine.dialect.name != "postgresql":
            inspected[name] = 0
            continue
        present: set[str] = set()
        try:
            with engine.connect() as conn:
                present = set(sa_inspect(conn).get_table_names())
        except Exception as exc:
            failed.append({"db": name, "table": "-", "error": str(exc)})
            continue
        count = 0
        for table in metadata.sorted_tables:
            if table.name not in present or not table.primary_key.columns:
                continue
            count += 1
            try:
                with engine.begin() as conn:
                    synced.extend(_sync_pg_sequences(conn, table, dry_run=dry_run))
            except Exception as exc:
                failed.append({"db": name, "table": table.name, "error": str(exc)})
        inspected[name] = count

    return {
        "ok": not failed,
        "scope": scope,
        "dry_run": dry_run,
        "inspected": inspected,
        "synced": synced,
        "failed": failed,
    }


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

                # Still inside the insert transaction, so MAX(id) sees this batch.
                _sync_pg_sequences(conn, table_obj)

            total_inserted += tbl_inserted
            total_skipped += tbl_skipped
            summary[tbl_name] = {
                "status": "success",
                "inserted": tbl_inserted,
                "skipped": tbl_skipped,
            }

        sqlite_con.close()

        # Sweep every table, not just the ones touched above: tables that were
        # empty or fully skipped may still carry stale sequences from an earlier
        # import, and they would break on the next application insert.
        sequences = sync_sequences()

        elapsed_ms = int((time.perf_counter() - t0) * 1000)
        return {
            "ok": True,
            "filename": filename,
            "total_inserted": total_inserted,
            "total_skipped": total_skipped,
            "elapsed_ms": elapsed_ms,
            "summary": summary,
            "sequences": sequences,
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
