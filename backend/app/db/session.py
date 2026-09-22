"""Database engine / session setup (SQLAlchemy 2.x)."""
from __future__ import annotations

from collections.abc import Generator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import settings

def create_app_engine(url: str | None = None):
    u = url or settings.DATABASE_URL
    kw: dict = {"pool_pre_ping": True, "echo": False}
    is_sqlite = u.startswith("sqlite")
    if is_sqlite:
        kw["connect_args"] = {"check_same_thread": False}
    else:
        kw.update(
            pool_size=20,
            max_overflow=30,
            pool_recycle=1800,
            pool_timeout=30,
        )
    eng = create_engine(u, **kw)
    if is_sqlite:
        @event.listens_for(eng, "connect")
        def _sqlite_connect(dbapi_conn, _rec):
            cur = dbapi_conn.cursor()
            cur.execute("PRAGMA foreign_keys=ON")
            cur.execute("PRAGMA journal_mode=WAL")
            cur.execute("PRAGMA synchronous=NORMAL")
            cur.execute("PRAGMA busy_timeout=30000")
            cur.execute("PRAGMA cache_size=-64000")
            cur.execute("PRAGMA temp_store=MEMORY")
            cur.close()
    return eng


engine = create_app_engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def reset_db(new_url: str | None = None) -> None:
    """Dispose current engine and re-create SessionLocal with new_url or current settings."""
    global engine, SessionLocal
    if engine is not None:
        try:
            engine.dispose()
        except Exception:
            pass
    if new_url:
        settings.DATABASE_URL = settings.normalize_database_url(new_url)
    engine = create_app_engine(new_url)
    SessionLocal.configure(bind=engine)


class Base(DeclarativeBase):
    """Declarative base for all ORM models."""


def get_db() -> Generator:
    """FastAPI dependency that yields a scoped DB session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Create tables. For real migrations use Alembic; this is fine for dev."""
    # Import models so they are registered on Base.metadata before create_all.
    from app import models  # noqa: F401

    Base.metadata.create_all(bind=engine)
