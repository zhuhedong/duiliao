"""User + auth session models.

The schema is intentionally app-ready: it supports web and native clients,
email- or phone-based identity, multi-device sessions, MFA, soft deletion,
and brute-force lockout.
"""
from __future__ import annotations

import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


def _uuid() -> str:
    return uuid.uuid4().hex


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_aware(dt: datetime | None) -> datetime | None:
    """SQLite drops tzinfo; treat stored naive datetimes as UTC for comparison."""
    if dt is None:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


class UserStatus(str, enum.Enum):
    PENDING = "pending"      # registered, not yet verified
    ACTIVE = "active"
    SUSPENDED = "suspended"  # temporarily blocked
    BANNED = "banned"        # permanently blocked
    DELETED = "deleted"      # soft-deleted


class UserRole(str, enum.Enum):
    USER = "user"
    STAFF = "staff"
    ADMIN = "admin"


class RegistrationSource(str, enum.Enum):
    WEB = "web"
    IOS = "ios"
    ANDROID = "android"
    API = "api"


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)

    # --- Identity (either email or phone may be the primary handle) ---
    username: Mapped[str | None] = mapped_column(String(64), unique=True, index=True, nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, index=True, nullable=True)
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    phone: Mapped[str | None] = mapped_column(String(20), unique=True, index=True, nullable=True)  # E.164
    phone_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # --- Credentials ---
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # --- Profile ---
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    locale: Mapped[str] = mapped_column(String(16), default="en", nullable=False)
    timezone: Mapped[str] = mapped_column(String(48), default="UTC", nullable=False)

    # --- State / authorization ---
    status: Mapped[UserStatus] = mapped_column(String(16), default=UserStatus.ACTIVE, nullable=False)
    role: Mapped[UserRole] = mapped_column(String(16), default=UserRole.USER, nullable=False)
    registration_source: Mapped[RegistrationSource] = mapped_column(
        String(16), default=RegistrationSource.WEB, nullable=False
    )

    # --- MFA (ready for later; TOTP secret stored encrypted at rest in prod) ---
    mfa_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    mfa_secret: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # --- Security / brute-force protection ---
    failed_login_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_login_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)

    # --- Timestamps (soft delete via deleted_at) ---
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=_utcnow, nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    sessions: Mapped[list["RefreshToken"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )

    @property
    def is_active(self) -> bool:
        return self.status == UserStatus.ACTIVE and self.deleted_at is None

    @property
    def is_locked(self) -> bool:
        locked = as_aware(self.locked_until)
        return locked is not None and locked > _utcnow()


class RefreshToken(Base):
    """One row per issued refresh token = one device session.

    Enables server-side revocation, "log out everywhere", and a device list in
    the app UI. The raw refresh JWT is never stored; only its `jti`.
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    jti: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    user_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )

    # --- Device / client metadata (populated from the client on login) ---
    device_id: Mapped[str | None] = mapped_column(String(128), index=True, nullable=True)
    device_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    platform: Mapped[str | None] = mapped_column(String(16), nullable=True)  # web/ios/android
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(String(512), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)

    # --- Lifecycle ---
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship(back_populates="sessions")

    @property
    def is_valid(self) -> bool:
        expires = as_aware(self.expires_at)
        return not self.revoked and expires is not None and expires > _utcnow()
