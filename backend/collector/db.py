from __future__ import annotations

import json
import os
from contextlib import contextmanager
from typing import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from common.config import database_url, is_postgres


class Base(DeclarativeBase):
    pass


_ENGINE: Engine | None = None
_SESSION: sessionmaker[Session] | None = None


def reset_engine() -> None:
    global _ENGINE, _SESSION
    if _ENGINE is not None:
        _ENGINE.dispose()
    _ENGINE = None
    _SESSION = None


def _pool_setting(name: str, default: int, minimum: int, maximum: int) -> int:
    raw = os.getenv(name, str(default)).strip()
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} 必须是整数") from exc
    if not minimum <= value <= maximum:
        raise RuntimeError(f"{name} 必须在 {minimum}–{maximum} 之间")
    return value


def get_engine(url: str | None = None) -> Engine:
    global _ENGINE, _SESSION
    u = url or database_url()
    requested = make_url(u)
    if _ENGINE is not None:
        current = _ENGINE.url
        if current == requested:
            return _ENGINE
        reset_engine()
    kw: dict = {
        "json_serializer": lambda o: json.dumps(o, ensure_ascii=False, allow_nan=False),
        "future": True,
    }
    if requested.get_backend_name() == "sqlite":
        kw["connect_args"] = {"check_same_thread": False}
    else:
        kw.update(
            pool_pre_ping=True,
            pool_recycle=_pool_setting("PRED_DB_POOL_RECYCLE_SEC", 1800, 60, 86400),
            pool_size=_pool_setting("PRED_DB_POOL_SIZE", 5, 1, 100),
            max_overflow=_pool_setting("PRED_DB_MAX_OVERFLOW", 10, 0, 200),
            pool_timeout=_pool_setting("PRED_DB_POOL_TIMEOUT_SEC", 30, 1, 600),
        )
    _ENGINE = create_engine(u, **kw)
    if requested.get_backend_name() == "sqlite":
        @event.listens_for(_ENGINE, "connect")
        def _fk(dbapi_conn, _rec):  # type: ignore[no-untyped-def]
            cur = dbapi_conn.cursor()
            cur.execute("PRAGMA foreign_keys=ON")
            cur.execute("PRAGMA journal_mode=WAL")
            cur.close()
    _SESSION = sessionmaker(_ENGINE, expire_on_commit=False)
    return _ENGINE


def dialect_name(engine: Engine | None = None) -> str:
    e = engine or get_engine()
    return e.dialect.name


def using_postgres() -> bool:
    return is_postgres()


def session_factory() -> sessionmaker[Session]:
    if _SESSION is None:
        get_engine()
    if _SESSION is None:
        raise RuntimeError("database session factory was not initialized")
    return _SESSION


@contextmanager
def session_scope(guard: bool = True) -> Iterator[Session]:
    # `guard` is kept for call-site compatibility with the original project's
    # task scheduler. The scheduler is out of scope for this port, so the guard
    # is a no-op here.
    s = session_factory()()
    try:
        yield s
        s.commit()
    except Exception:
        s.rollback()
        raise
    finally:
        s.close()
