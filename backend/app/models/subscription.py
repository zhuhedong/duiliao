"""Per-user mobile subscription and notification preferences.

This lives in the **app** database rather than the collector database because it
is user-domain data keyed by ``users.id``; the two databases are deliberately
kept separate (collector tables never mix with auth tables). Storing it server
side rather than on the device is what lets preferences follow a user across
devices.
"""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# Notification rule keys understood by the client poller. Stored as a JSON object
# of key -> bool (plus `miss_streak_threshold`, an int) so new rules can be added
# without a migration.
DEFAULT_NOTIFY_RULES: dict[str, object] = {
    "draw_published": True,
    "source_hit": False,
    "source_miss_streak": True,
    "miss_streak_threshold": 3,
    "consensus_leader_changed": False,
    "collect_job_finished": True,
}


class UserSubscription(Base):
    """One row per user holding followed sources and notification rules."""

    __tablename__ = "user_subscriptions"

    user_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    # Followed collector source ids. Not a ForeignKey: sources live in the other
    # database, so referential integrity is enforced at the API boundary instead.
    source_ids: Mapped[list | None] = mapped_column(JSON, nullable=True, default=list)
    lotteries: Mapped[list | None] = mapped_column(JSON, nullable=True, default=list)
    play_types: Mapped[list | None] = mapped_column(JSON, nullable=True, default=list)
    notify_rules: Mapped[dict | None] = mapped_column(JSON, nullable=True, default=dict)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_utcnow, onupdate=_utcnow, nullable=False
    )
