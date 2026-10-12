"""Per-user betting records stored in the app database.

Like ``UserSubscription``, this lives in the **app** database keyed by
``users.id`` so each user's betting ledger syncs across devices while keeping
collector tables cleanly isolated.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _uuid() -> str:
    return str(uuid.uuid4())


class UserBettingRecord(Base):
    """A single betting record entered by a user."""

    __tablename__ = "user_betting_records"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(
        String(32),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    lottery: Mapped[str] = mapped_column(String(16), nullable=False, default="macau", index=True)
    period: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    mode: Mapped[str] = mapped_column(String(32), nullable=False, default="号码单式")
    play_type: Mapped[str] = mapped_column(String(64), nullable=False, default="特码")
    numbers: Mapped[list | None] = mapped_column(JSON, nullable=True, default=list)
    xiaos: Mapped[list | None] = mapped_column(JSON, nullable=True, default=list)
    stake_per_note: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    multiplier: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    notes_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    total_amount: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    odds: Mapped[float] = mapped_column(Float, nullable=False, default=47.0)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    hit_numbers: Mapped[list | None] = mapped_column(JSON, nullable=True, default=list)
    hit_notes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    payout: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    net_profit: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    raw_input: Mapped[str | None] = mapped_column(Text, nullable=True, default="")
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)
    source_badge: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_utcnow, onupdate=_utcnow, nullable=False
    )
