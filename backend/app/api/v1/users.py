"""User profile & device/session management. Every route requires auth."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.security import hash_password, verify_password
from app.db.session import get_db
from app.models.user import RefreshToken, User, as_aware
from app.schemas.user import PasswordChange, UserPublic, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


class SessionInfo(BaseModel):
    id: str
    device_name: str | None
    platform: str | None
    app_version: str | None
    ip_address: str | None
    created_at: datetime
    last_used_at: datetime | None
    current: bool = False


@router.get("/me", response_model=UserPublic)
def get_me(user: User = Depends(get_current_user)) -> UserPublic:
    return UserPublic.model_validate(user)


@router.patch("/me", response_model=UserPublic)
def update_me(
    payload: UserUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserPublic:
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(user, field, value)
    db.commit()
    db.refresh(user)
    return UserPublic.model_validate(user)


@router.get("/me/sessions", response_model=list[SessionInfo])
def list_sessions(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[SessionInfo]:
    now = datetime.now(timezone.utc)
    rows = db.scalars(
        select(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked == False)  # noqa: E712
        .order_by(RefreshToken.created_at.desc())
    ).all()
    return [
        SessionInfo(
            id=r.id,
            device_name=r.device_name,
            platform=r.platform,
            app_version=r.app_version,
            ip_address=r.ip_address,
            created_at=r.created_at,
            last_used_at=r.last_used_at,
            current=(as_aware(r.expires_at) or now) > now,
        )
        for r in rows
    ]


@router.delete("/me/sessions/{session_id}", status_code=204)
def revoke_session(
    session_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    row = db.get(RefreshToken, session_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Session not found")
    row.revoked = True
    row.revoked_at = datetime.now(timezone.utc)
    db.commit()


@router.post("/me/password", status_code=204)
def change_password(
    payload: PasswordChange,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    """Change the current user's password."""
    if not user.password_hash or not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    user.password_hash = hash_password(payload.new_password)
    db.commit()
