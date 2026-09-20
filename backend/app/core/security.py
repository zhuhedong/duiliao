"""Authentication & request-integrity primitives.

- Password hashing        : Argon2id
- Tokens                  : JWT access + opaque-ish refresh (JWT with jti)
- Request signing         : HMAC-SHA256 over canonical string
- Replay protection       : timestamp window + one-time nonce cache
"""
from __future__ import annotations

import hashlib
import hmac
import time
import uuid
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Any, Optional

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from app.core.config import settings

# --- Password hashing --------------------------------------------------------

_ph = PasswordHasher()  # Argon2id defaults are sensible and memory-hard


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError, ValueError):
        return False


def password_needs_rehash(password_hash: str) -> bool:
    try:
        return _ph.check_needs_rehash(password_hash)
    except Exception:
        return False


# --- JWT ---------------------------------------------------------------------

ACCESS = "access"
REFRESH = "refresh"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _create_token(subject: str, token_type: str, expires: timedelta, **extra: Any) -> tuple[str, str]:
    jti = uuid.uuid4().hex
    payload: dict[str, Any] = {
        "sub": subject,
        "type": token_type,
        "jti": jti,
        "iat": int(_now().timestamp()),
        "exp": int((_now() + expires).timestamp()),
        **extra,
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    return token, jti


def create_access_token(subject: str, **extra: Any) -> str:
    token, _ = _create_token(
        subject, ACCESS, timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES), **extra
    )
    return token


def create_refresh_token(subject: str, **extra: Any) -> tuple[str, str]:
    """Returns (token, jti). Persist the jti to allow server-side revocation."""
    return _create_token(
        subject, REFRESH, timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS), **extra
    )


def decode_token(token: str, expected_type: Optional[str] = None) -> dict[str, Any]:
    payload = jwt.decode(
        token,
        settings.JWT_SECRET,
        algorithms=[settings.JWT_ALGORITHM],
        options={"require": ["exp", "iat", "sub", "type"]},
    )
    if expected_type and payload.get("type") != expected_type:
        raise jwt.InvalidTokenError(f"expected {expected_type} token")
    return payload


# --- Request signing (HMAC) --------------------------------------------------

def canonical_string(session_id: str, timestamp: str, nonce: str, body_bytes: bytes) -> str:
    body_hash = hashlib.sha256(body_bytes or b"").hexdigest()
    return "\n".join([session_id, timestamp, nonce, body_hash])


def sign_request(session_id: str, timestamp: str, nonce: str, body_bytes: bytes) -> str:
    msg = canonical_string(session_id, timestamp, nonce, body_bytes).encode("utf-8")
    return hmac.new(
        settings.APP_SIGNING_SECRET.encode("utf-8"), msg, hashlib.sha256
    ).hexdigest()


def verify_signature(
    signature: str, session_id: str, timestamp: str, nonce: str, body_bytes: bytes
) -> bool:
    expected = sign_request(session_id, timestamp, nonce, body_bytes)
    return hmac.compare_digest(expected, signature or "")


def timestamp_within_window(timestamp: str) -> bool:
    try:
        ts = int(timestamp)
    except (TypeError, ValueError):
        return False
    return abs(int(time.time()) - ts) <= settings.REQUEST_TIMESTAMP_TOLERANCE_SECONDS


class NonceCache:
    """Remembers recently-seen nonces to reject replays. TTL-bounded."""

    def __init__(self, ttl_seconds: int) -> None:
        self._ttl = ttl_seconds
        self._seen: dict[str, float] = {}
        self._lock = Lock()

    def check_and_store(self, nonce: str) -> bool:
        """Return True if nonce is fresh (and record it); False if replayed."""
        if not nonce:
            return False
        now = time.time()
        with self._lock:
            # opportunistic purge
            if len(self._seen) > 10000:
                for k in [k for k, exp in self._seen.items() if exp < now]:
                    self._seen.pop(k, None)
            if nonce in self._seen and self._seen[nonce] > now:
                return False
            self._seen[nonce] = now + self._ttl
            return True


nonce_cache = NonceCache(settings.REQUEST_TIMESTAMP_TOLERANCE_SECONDS * 2)
