"""Authentication use-cases: registration, login, token refresh, logout."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.security import (
    REFRESH,
    create_access_token,
    create_refresh_token,
    hash_password,
    password_needs_rehash,
    verify_password,
)
from app.models.user import RefreshToken, RegistrationSource, User, UserRole, UserStatus
from app.schemas.auth import BootstrapRequest, DeviceInfo, LoginRequest, RegisterRequest

MAX_FAILED_LOGINS = 5
LOCKOUT_MINUTES = 15


class AuthError(Exception):
    """Raised for any auth failure; carries an HTTP-friendly message + code."""

    def __init__(self, message: str, code: str = "auth_error", status_code: int = 401):
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _find_user_by_identifier(db: Session, identifier: str) -> User | None:
    identifier = identifier.strip()
    stmt = select(User).where(
        or_(
            User.email == identifier.lower(),
            User.phone == identifier,
            User.username == identifier,
        )
    )
    return db.scalars(stmt).first()


def register_user(db: Session, data: RegisterRequest) -> User:
    email = data.email.lower() if data.email else None

    # Uniqueness checks (avoid leaking which field collided in the message).
    clauses = []
    if email:
        clauses.append(User.email == email)
    if data.phone:
        clauses.append(User.phone == data.phone)
    if data.username:
        clauses.append(User.username == data.username)
    if clauses and db.scalars(select(User).where(or_(*clauses))).first():
        raise AuthError("An account with those details already exists", "already_exists", 409)

    user = User(
        email=email,
        phone=data.phone,
        username=data.username,
        display_name=data.display_name,
        password_hash=hash_password(data.password),
        registration_source=data.source or RegistrationSource.WEB,
        status=UserStatus.ACTIVE,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise AuthError("An account with those details already exists", "already_exists", 409)
    db.refresh(user)
    return user


def admin_exists(db: Session) -> bool:
    """True if any non-deleted admin/staff account already exists."""
    stmt = select(User.id).where(
        User.role.in_([UserRole.ADMIN.value, UserRole.STAFF.value]),
        User.deleted_at.is_(None),
    )
    return db.scalars(stmt).first() is not None


def _is_loopback(ip: str | None) -> bool:
    return ip in {"127.0.0.1", "::1", "localhost"}


def bootstrap_reason(db: Session, ip: str | None) -> str | None:
    """Return None if first-run admin bootstrap is allowed, else a reason code."""
    if not settings.ALLOW_LOCAL_BOOTSTRAP:
        return "disabled"
    if settings.is_production:
        return "production"
    if not _is_loopback(ip):
        return "not_local"
    if admin_exists(db):
        return "already_initialized"
    return None


def bootstrap_admin(
    db: Session,
    data: BootstrapRequest,
    ip: str | None,
    user_agent: str | None,
) -> tuple[str, str, User]:
    """Create the first admin account and issue tokens (auto-login).

    Guarded: only succeeds when bootstrap is allowed and no admin exists yet.
    """
    reason = bootstrap_reason(db, ip)
    if reason is not None:
        code = 409 if reason == "already_initialized" else 403
        raise AuthError("Admin bootstrap is not available", reason, code)

    email = data.email.lower() if data.email else None
    # Guard against a colliding identity so we return a clean error.
    clauses = []
    if email:
        clauses.append(User.email == email)
    if data.phone:
        clauses.append(User.phone == data.phone)
    if data.username:
        clauses.append(User.username == data.username)
    if clauses and db.scalars(select(User).where(or_(*clauses))).first():
        raise AuthError("An account with those details already exists", "already_exists", 409)

    user = User(
        email=email,
        phone=data.phone,
        username=data.username,
        display_name=data.display_name or data.username or "Administrator",
        password_hash=hash_password(data.password),
        role=UserRole.ADMIN,
        status=UserStatus.ACTIVE,
        email_verified=bool(email),
        registration_source=RegistrationSource.WEB,
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise AuthError("An account with those details already exists", "already_exists", 409)

    # Re-check under the same transaction to avoid a race creating two admins.
    other = db.scalars(
        select(User.id).where(
            User.role.in_([UserRole.ADMIN.value, UserRole.STAFF.value]),
            User.deleted_at.is_(None),
            User.id != user.id,
        )
    ).first()
    if other is not None:
        db.rollback()
        raise AuthError("Admin bootstrap is not available", "already_initialized", 409)

    access, refresh = _issue_tokens(db, user, data.device, ip, user_agent)
    return access, refresh, user


def _issue_tokens(
    db: Session,
    user: User,
    device: DeviceInfo | None,
    ip: str | None,
    user_agent: str | None,
) -> tuple[str, str]:
    role_value = getattr(user.role, "value", user.role)
    access = create_access_token(user.id, role=role_value)
    refresh, jti = create_refresh_token(user.id)

    session = RefreshToken(
        jti=jti,
        user_id=user.id,
        device_id=device.deviceId if device else None,
        device_name=device.deviceName if device else None,
        platform=device.platform if device else None,
        app_version=device.appVersion if device else None,
        user_agent=(user_agent or "")[:512] or None,
        ip_address=ip,
        expires_at=_utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        last_used_at=_utcnow(),
    )
    db.add(session)

    user.last_login_at = _utcnow()
    user.last_login_ip = ip
    user.failed_login_count = 0
    user.locked_until = None
    db.commit()
    return access, refresh


def login_user(
    db: Session,
    data: LoginRequest,
    ip: str | None = None,
    user_agent: str | None = None,
) -> tuple[str, str, User]:
    user = _find_user_by_identifier(db, data.identifier)
    # Generic error to avoid user enumeration.
    invalid = AuthError("Invalid credentials", "invalid_credentials", 401)

    if user is None or user.password_hash is None:
        raise invalid
    if user.is_locked:
        raise AuthError("Account temporarily locked. Try again later.", "locked", 423)
    if user.status != UserStatus.ACTIVE or user.deleted_at is not None:
        raise AuthError("Account is not active", "inactive", 403)

    if not verify_password(data.password, user.password_hash):
        user.failed_login_count += 1
        if user.failed_login_count >= MAX_FAILED_LOGINS:
            user.locked_until = _utcnow() + timedelta(minutes=LOCKOUT_MINUTES)
        db.commit()
        raise invalid

    # Opportunistically upgrade the password hash if parameters changed.
    if password_needs_rehash(user.password_hash):
        user.password_hash = hash_password(data.password)

    access, refresh = _issue_tokens(db, user, data.device, ip, user_agent)
    return access, refresh, user


def refresh_access_token(
    db: Session,
    refresh_token: str,
    ip: str | None = None,
    user_agent: str | None = None,
) -> tuple[str, str]:
    """Refresh access token with token rotation.

    Returns (new_access_token, new_refresh_token). The old refresh token's
    session is revoked so it can only be used once.
    """
    import jwt

    from app.core.security import decode_token

    try:
        payload = decode_token(refresh_token, expected_type=REFRESH)
    except jwt.InvalidTokenError:
        raise AuthError("Invalid refresh token", "invalid_refresh", 401)

    jti = payload.get("jti")
    session = db.scalars(select(RefreshToken).where(RefreshToken.jti == jti)).first()
    if session is None or not session.is_valid:
        raise AuthError("Refresh token revoked or expired", "revoked", 401)

    user = db.get(User, payload.get("sub"))
    if user is None or not user.is_active:
        raise AuthError("Account is not active", "inactive", 403)

    # Revoke the old refresh token (rotation).
    session.revoked = True
    session.revoked_at = _utcnow()

    # Issue new tokens, carrying forward the device info from the old session.
    device = DeviceInfo(
        deviceId=session.device_id,
        deviceName=session.device_name,
        platform=session.platform,
        appVersion=session.app_version,
    ) if session.device_id or session.device_name else None
    access, new_refresh = _issue_tokens(db, user, device, ip or session.ip_address, user_agent)
    return access, new_refresh


def logout(db: Session, refresh_token: str | None, all_devices: bool, user: User) -> None:
    if all_devices:
        for s in db.scalars(
            select(RefreshToken).where(
                RefreshToken.user_id == user.id, RefreshToken.revoked == False  # noqa: E712
            )
        ):
            s.revoked = True
            s.revoked_at = _utcnow()
        db.commit()
        return

    if refresh_token:
        import jwt

        from app.core.security import decode_token

        try:
            payload = decode_token(refresh_token, expected_type=REFRESH)
            session = db.scalars(
                select(RefreshToken).where(RefreshToken.jti == payload.get("jti"))
            ).first()
            if session and session.user_id == user.id:
                session.revoked = True
                session.revoked_at = _utcnow()
                db.commit()
        except jwt.InvalidTokenError:
            pass
