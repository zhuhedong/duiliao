"""Shared FastAPI dependencies (auth, roles)."""
from __future__ import annotations

import jwt
from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.security import ACCESS, decode_token
from app.db.session import get_db
from app.models.user import User, UserRole

_UNAUTH = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Not authenticated",
    headers={"WWW-Authenticate": "Bearer"},
)


def _bearer_token(request: Request) -> str:
    auth = request.headers.get("authorization", "")
    scheme, _, token = auth.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise _UNAUTH
    return token


def get_current_user(
    request: Request,
    db: Session = Depends(get_db),
) -> User:
    token = _bearer_token(request)
    try:
        payload = decode_token(token, expected_type=ACCESS)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Access token expired",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError:
        raise _UNAUTH

    user = db.get(User, payload.get("sub"))
    if user is None or not user.is_active:
        raise _UNAUTH
    # Preserve the refresh-token session identity for endpoints that need to
    # distinguish this device from the user's other active sessions.
    request.state.session_id = payload.get("session_id")
    return user


def require_roles(*roles: UserRole):
    """Dependency factory that enforces the current user has one of `roles`."""

    def _dep(user: User = Depends(get_current_user)) -> User:
        if roles and user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return user

    return _dep
