"""User profile & device/session management. Every route requires auth."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
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
    device_id: str | None
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
    request: Request,
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
            device_id=r.device_id,
            device_name=r.device_name,
            platform=r.platform,
            app_version=r.app_version,
            ip_address=r.ip_address,
            created_at=r.created_at,
            last_used_at=r.last_used_at,
            current=(r.jti == getattr(request.state, "session_id", None))
            and (as_aware(r.expires_at) or now) > now,
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
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    """Change the current user's password."""
    if not user.password_hash or not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    user.password_hash = hash_password(payload.new_password)
    current_session_id = getattr(request.state, "session_id", None)
    sessions = db.scalars(
        select(RefreshToken).where(
            RefreshToken.user_id == user.id,
            RefreshToken.revoked == False,  # noqa: E712
        )
    ).all()
    # Keep the device that performed the password change signed in. Tokens
    # issued before session binding have no session_id and conservatively revoke
    # every refresh session so a forgotten device cannot remain authenticated.
    for session in sessions:
        if current_session_id is None or session.jti != current_session_id:
            session.revoked = True
            session.revoked_at = datetime.now(timezone.utc)
    db.commit()



# --------------------------------------------------------------------------- #
# Mobile subscriptions and notification preferences
# --------------------------------------------------------------------------- #
class SubscriptionPayload(BaseModel):
    """Full replacement of a user's subscription. PUT is idempotent."""

    source_ids: list[str] = []
    lotteries: list[str] = []
    play_types: list[str] = []
    notify_rules: dict[str, object] = {}


@router.get("/me/subscriptions")
def get_subscriptions(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    """Followed sources and notification rules, defaulted when never saved."""
    from app.api.v1.mobile import _load_subscription_row

    return {"ok": True, **_load_subscription_row(db, user.id)}


@router.put("/me/subscriptions")
def put_subscriptions(
    payload: SubscriptionPayload,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    """Replace the caller's subscription.

    Source ids are validated against the collector catalogue so a typo cannot
    silently disable notifications for a source that will never match. Lotteries
    and play types are validated for the same reason.
    """
    from app import collector_bridge as cb
    from app.api.v1.mobile import LOTTERIES, _load_subscription_row
    from app.models.subscription import DEFAULT_NOTIFY_RULES, UserSubscription

    requested = list(dict.fromkeys(payload.source_ids))
    if requested:
        try:
            known = {s["source_id"] for s in cb.registry_module().list_sources()}
        except Exception as exc:  # pragma: no cover - collector unavailable
            raise HTTPException(status_code=503, detail="source catalogue unavailable") from exc
        unknown = [s for s in requested if s not in known]
        if unknown:
            raise HTTPException(
                status_code=400,
                detail=f"unknown source_ids: {', '.join(sorted(unknown)[:10])}",
            )

    bad_lotteries = [x for x in payload.lotteries if x not in LOTTERIES]
    if bad_lotteries:
        raise HTTPException(status_code=400, detail=f"unknown lotteries: {', '.join(bad_lotteries)}")

    if payload.play_types:
        try:
            valid_plays = {r["play_type"] for r in cb.rules_catalog()}
        except Exception:  # pragma: no cover - fall back to accepting
            valid_plays = set(payload.play_types)
        bad_plays = [x for x in payload.play_types if x not in valid_plays]
        if bad_plays:
            raise HTTPException(status_code=400, detail=f"unknown play_types: {', '.join(bad_plays)}")

    # Only known rule keys are persisted, so a client cannot bloat the row.
    rules = {k: v for k, v in payload.notify_rules.items() if k in DEFAULT_NOTIFY_RULES}

    row = db.get(UserSubscription, user.id)
    if row is None:
        row = UserSubscription(user_id=user.id)
        db.add(row)
    row.source_ids = requested
    row.lotteries = list(dict.fromkeys(payload.lotteries))
    row.play_types = list(dict.fromkeys(payload.play_types))
    row.notify_rules = rules
    db.commit()
    return {"ok": True, **_load_subscription_row(db, user.id)}
