"""Authentication endpoints. All bodies here are transparently encrypted by
the EncryptionMiddleware (the client must complete the crypto handshake first).
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.ratelimit import limiter
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import (
    AccessTokenResponse,
    BootstrapRequest,
    BootstrapStatus,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
)
from app.schemas.user import UserPublic
from app.services.auth import (
    AuthError,
    bootstrap_admin,
    bootstrap_reason,
    login_user,
    logout,
    refresh_access_token,
    register_user,
)

router = APIRouter(prefix="/auth", tags=["auth"])

_ACCESS_TTL = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60


def _client_ip(request: Request) -> str | None:
    # Trust the left-most X-Forwarded-For entry only behind a known proxy.
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else None


def _raise(err: AuthError) -> None:
    raise HTTPException(status_code=err.status_code, detail={"message": err.message, "code": err.code})


@router.post("/register", response_model=TokenResponse, status_code=201)
@limiter.limit(settings.RATE_LIMIT_AUTH)
def register(request: Request, payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        user = register_user(db, payload)
        from app.services.auth import _issue_tokens

        access, refresh = _issue_tokens(
            db, user, payload.device, _client_ip(request), request.headers.get("user-agent")
        )
    except AuthError as err:
        _raise(err)
    return TokenResponse(
        access_token=access,
        refresh_token=refresh,
        expires_in=_ACCESS_TTL,
        user=UserPublic.model_validate(user),
    )


def _peer_ip(request: Request) -> str | None:
    # The real socket peer — used for the loopback gate so a spoofed
    # X-Forwarded-For header can't unlock the bootstrap flow remotely.
    return request.client.host if request.client else None


@router.get("/bootstrap", response_model=BootstrapStatus)
def bootstrap_status(request: Request, db: Session = Depends(get_db)) -> BootstrapStatus:
    """Whether a first-run admin can be created from this client right now."""
    reason = bootstrap_reason(db, _peer_ip(request))
    return BootstrapStatus(available=reason is None, reason=reason)


@router.post("/bootstrap", response_model=TokenResponse, status_code=201)
@limiter.limit(settings.RATE_LIMIT_AUTH)
def bootstrap(request: Request, payload: BootstrapRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """Create the very first admin account and auto-login (first-run only)."""
    try:
        access, refresh, user = bootstrap_admin(
            db, payload, _peer_ip(request), request.headers.get("user-agent")
        )
    except AuthError as err:
        _raise(err)
    return TokenResponse(
        access_token=access,
        refresh_token=refresh,
        expires_in=_ACCESS_TTL,
        user=UserPublic.model_validate(user),
    )


@router.post("/login", response_model=TokenResponse)
@limiter.limit(settings.RATE_LIMIT_AUTH)
def login(request: Request, payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        access, refresh, user = login_user(
            db, payload, _client_ip(request), request.headers.get("user-agent")
        )
    except AuthError as err:
        _raise(err)
    return TokenResponse(
        access_token=access,
        refresh_token=refresh,
        expires_in=_ACCESS_TTL,
        user=UserPublic.model_validate(user),
    )


@router.post("/refresh", response_model=AccessTokenResponse)
@limiter.limit(settings.RATE_LIMIT_AUTH)
def refresh(request: Request, payload: RefreshRequest, db: Session = Depends(get_db)) -> AccessTokenResponse:
    try:
        access, new_refresh = refresh_access_token(
            db, payload.refresh_token, _client_ip(request), request.headers.get("user-agent")
        )
    except AuthError as err:
        _raise(err)
    return AccessTokenResponse(access_token=access, refresh_token=new_refresh, expires_in=_ACCESS_TTL)


@router.post("/logout", status_code=204)
def logout_endpoint(
    request: Request,
    payload: LogoutRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    logout(db, payload.refresh_token, payload.all_devices, user)


@router.get("/me", response_model=UserPublic)
def me(user: User = Depends(get_current_user)) -> UserPublic:
    return UserPublic.model_validate(user)
