"""System settings endpoints for managing AI configurations, keys, and connectivity testing."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_roles
from app.core.config import settings
from app.db.session import get_db
from app.models.user import User, UserRole
from app.services.settings_service import (
    get_all_ai_settings,
    save_ai_settings,
    test_ai_connection,
)

router = APIRouter(prefix="/settings", tags=["settings"])
_user = Depends(get_current_user)
_staff = Depends(require_roles(UserRole.ADMIN, UserRole.STAFF))
_admin = Depends(require_roles(UserRole.ADMIN))


class ProviderSettingPayload(BaseModel):
    base_url: str | None = None
    api_key: str | None = None
    model: str | None = None


class AISettingsUpdatePayload(BaseModel):
    default_provider: str | None = Field(default=None, description="openai, gemini, or anthropic")
    openai: ProviderSettingPayload | None = None
    gemini: ProviderSettingPayload | None = None
    anthropic: ProviderSettingPayload | None = None


class AITestPayload(BaseModel):
    provider: str = Field(..., description="Target provider: openai, gemini, or anthropic")
    base_url: str | None = None
    api_key: str | None = None
    model: str | None = None


@router.get("/ai")
def get_ai_config(
    db: Session = Depends(get_db),
    _: User = _staff,
) -> dict[str, Any]:
    """Retrieve all current AI configurations (with API keys masked)."""
    return get_all_ai_settings(db, mask=True)


@router.put("/ai")
def update_ai_config(
    payload: AISettingsUpdatePayload = Body(...),
    db: Session = Depends(get_db),
    _: User = _admin,
) -> dict[str, Any]:
    """Save updated AI configurations (Base URL, models, and unmasked API keys)."""
    data = payload.model_dump(exclude_unset=True)
    updated = save_ai_settings(db, data)
    return updated


@router.post("/ai/test")
def test_ai_conn(
    payload: AITestPayload = Body(...),
    _: User = _admin,
) -> dict[str, Any]:
    """Test connection and authentication with the specified AI provider and endpoint."""
    try:
        res = test_ai_connection(
            provider=payload.provider,
            base_url=payload.base_url,
            api_key=payload.api_key,
            model=payload.model,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return res


# ==============================================================================
# Database Management Endpoints
# ==============================================================================


class DBTestPayload(BaseModel):
    url: str = Field(..., description="PostgreSQL connection URL to test")


class DBConfigPayload(BaseModel):
    database_url: str = Field(..., description="Primary application database URL")
    collector_database_url: str | None = Field(default=None, description="Optional collector database URL")


class SchemaRepairPayload(BaseModel):
    scope: str = Field(default="all", description="'all', 'app', or 'collector'")
    seed: bool = Field(default=True, description="Reseed collector reference data after creating tables")


class SqliteInspectPayload(BaseModel):
    filename: str = Field(default="database.db")
    content_base64: str = Field(..., description="Base64-encoded SQLite file content")


class SqliteImportPayload(BaseModel):
    filename: str = Field(default="database.db")
    content_base64: str = Field(..., description="Base64-encoded SQLite file content")
    mode: str = Field(default="skip", description="'skip' to ignore existing rows, 'overwrite' to replace")
    tables: list[str] | None = Field(default=None, description="Optional list of specific tables to import")


@router.get("/database")
def get_db_status(
    _: User = _staff,
) -> dict[str, Any]:
    """Retrieve current database engines, connection statuses, and table row counts."""
    from app.services.db_service import get_database_status

    return get_database_status()


@router.get("/database/schema")
def check_db_schema(
    _: User = _staff,
) -> dict[str, Any]:
    """Report which declared tables are missing from the app and collector databases."""
    from app.services.db_service import verify_schema

    return verify_schema()


@router.post("/database/schema/repair")
def repair_db_schema(
    payload: SchemaRepairPayload = Body(default=SchemaRepairPayload()),
    user: User = _staff,
) -> dict[str, Any]:
    """Create the missing tables only, one at a time (staff/admin only).

    Never drops or alters an existing table, so it is safe to re-run.
    """
    from app.services.db_service import repair_schema

    try:
        return repair_schema(scope=payload.scope, seed=payload.seed)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/database/test")
def test_db_connection(
    payload: DBTestPayload = Body(...),
    _: User = _admin,
) -> dict[str, Any]:
    """Test connection to a specified PostgreSQL database instance."""
    from app.services.db_service import test_pg_connection

    return test_pg_connection(payload.url)


@router.post("/database/config")
def save_db_config(
    payload: DBConfigPayload = Body(...),
    user: User = _admin,
) -> dict[str, Any]:
    """Save updated database URLs, update .env, and reinitialize connections (staff/admin only)."""
    from app.services.db_service import update_database_config

    return update_database_config(
        db_url=payload.database_url,
        collector_url=payload.collector_database_url,
    )


@router.post("/database/inspect-sqlite")
def inspect_sqlite(
    payload: SqliteInspectPayload = Body(...),
    _: User = _staff,
) -> dict[str, Any]:
    """Inspect an uploaded SQLite database file without importing."""
    import base64

    try:
        content_bytes = base64.b64decode(payload.content_base64, validate=True)
        if len(content_bytes) > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
            raise HTTPException(status_code=413, detail="SQLite 文件超过允许的大小限制")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Base64 解码失败，请确认文件数据完整")

    from app.services.db_service import inspect_sqlite_file

    return inspect_sqlite_file(content_bytes=content_bytes, filename=payload.filename)


@router.post("/database/import-sqlite")
def import_sqlite(
    payload: SqliteImportPayload = Body(...),
    user: User = _staff,
) -> dict[str, Any]:
    """Import data from an uploaded SQLite database file into current database (staff/admin only)."""
    import base64

    try:
        content_bytes = base64.b64decode(payload.content_base64, validate=True)
        if len(content_bytes) > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
            raise HTTPException(status_code=413, detail="SQLite 文件超过允许的大小限制")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Base64 解码失败，请确认文件数据完整")
    if payload.mode not in {"skip", "overwrite"}:
        raise HTTPException(status_code=400, detail="mode 只能是 skip 或 overwrite")
    if payload.tables and len(payload.tables) > 100:
        raise HTTPException(status_code=400, detail="tables 数量不能超过 100")

    from app.services.db_service import import_sqlite_data

    res = import_sqlite_data(
        content_bytes=content_bytes,
        filename=payload.filename,
        mode=payload.mode,
        selected_tables=payload.tables,
    )
    return res
