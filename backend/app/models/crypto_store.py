"""Shared crypto anti-replay / session rows for multi-worker deployments.

AES session keys and request nonces used to live only in process memory, so
horizontally scaled API workers could not share handshakes or reject cross-
worker replays. These tables are the durable store; the in-process caches in
``app.core.security`` / ``app.core.crypto`` remain an L1 layer.
"""
from __future__ import annotations

from sqlalchemy import Float, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class RequestNonce(Base):
    __tablename__ = "request_nonces"

    nonce: Mapped[str] = mapped_column(String(128), primary_key=True)
    expires_at: Mapped[float] = mapped_column(Float, nullable=False, index=True)


class CryptoSession(Base):
    __tablename__ = "crypto_sessions"

    session_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    key_b64: Mapped[str] = mapped_column(Text, nullable=False)
    expires_at: Mapped[float] = mapped_column(Float, nullable=False, index=True)
