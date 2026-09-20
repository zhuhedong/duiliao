"""Shared rate limiter (slowapi / limits)."""
from __future__ import annotations

from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[settings.RATE_LIMIT_DEFAULT],
    # headers_enabled would require every limited route to accept a
    # `response: Response` param; we keep routes clean and still enforce limits.
    headers_enabled=False,
)
