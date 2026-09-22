"""Mobile-client endpoints (``/app/*``).

Mounted on the regular ``api_router``, so these routes inherit the encryption
middleware and JWT auth exactly like every other ``/api/v1`` route — no new
exempt paths are introduced.

What lives here and why:

* ``GET /app/home`` — the home screen needs five different datasets. Fetching
  them individually would be five encrypted round-trips on a mobile link, so
  they are aggregated into one response and degraded independently: a failure in
  one block returns null for that block instead of failing the whole screen.
* ``/app/collect-jobs`` — submit/poll/cancel/list for asynchronous collection,
  replacing the blocking ``POST /collector/collect`` for mobile use.
* ``GET /app/events`` — an incremental, cursor-based feed the client polls to
  raise local notifications (no third-party push is used).
* ``GET /app/version`` — force-update check for internally distributed builds.
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app import collector_bridge as cb
from app.api.deps import get_current_user, require_roles
from app.db.session import get_db
from app.models.user import User, UserRole
from app.services.collect_jobs import collect_job_worker
from app.services.settings_service import get_setting_value

logger = logging.getLogger("app.api.mobile")

router = APIRouter(prefix="/app", tags=["mobile"])

_user = Depends(get_current_user)
_staff = Depends(require_roles(UserRole.ADMIN, UserRole.STAFF))

LOTTERIES = ("hk", "macau", "taiwan", "new")
PLATFORMS = ("android", "ios")

# Setting keys backing GET /app/version.
VERSION_KEYS = {
    "android": ("app_android_latest_version", "app_android_min_version", "app_android_download_url"),
    "ios": ("app_ios_latest_version", "app_ios_min_version", "app_ios_download_url"),
}


def _validate_lottery(lottery: str) -> str:
    if lottery not in LOTTERIES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"unknown lottery: {lottery}",
        )
    return lottery


# --------------------------------------------------------------------------- #
# Home aggregation
# --------------------------------------------------------------------------- #
async def _safe(label: str, fn, *args, **kwargs) -> Any:
    """Run a blocking bridge call off the event loop, returning None on failure.

    The home screen must render on a partially broken backend (an empty database,
    a missing draw, an analytics error) rather than returning 500 and leaving the
    client with a blank screen.
    """
    try:
        return await asyncio.to_thread(fn, *args, **kwargs)
    except Exception:
        logger.warning("home block %r failed", label, exc_info=True)
        return None


@router.get("/home")
async def home(
    lottery: str = Query("macau"),
    play_type: str = Query("pingte_xiao"),
    user: User = _user,
) -> dict[str, Any]:
    """Everything the home screen needs, in one encrypted round-trip."""
    _validate_lottery(lottery)

    draws = await _safe("draws", cb.list_draws, lottery=lottery, limit=1, offset=0)
    latest = None
    if isinstance(draws, dict) and draws.get("items"):
        latest = draws["items"][0]
    period = (latest or {}).get("period")

    consensus_task = (
        _safe("consensus", cb.consensus_compare, lottery, period, play_type) if period else _safe("noop", lambda: None)
    )
    comparison_task = (
        _safe("comparison", cb.get_period_comparison, lottery, period) if period else _safe("noop", lambda: None)
    )
    ratings_task = _safe("ratings", cb.ratings, lottery=lottery, play_type=play_type, windows=[30, 50, 100])
    jobs_task = _safe("jobs", cb.list_collect_jobs, limit=3, lottery=lottery)

    consensus, comparison, ratings, jobs = await asyncio.gather(
        consensus_task, comparison_task, ratings_task, jobs_task
    )

    # Keep the payload small: the home screen shows a leader summary and a top 5,
    # not the full boards.
    consensus_summary = None
    if isinstance(consensus, dict):
        groups = consensus.get("groups") or []
        consensus_summary = {
            "lottery": consensus.get("lottery"),
            "period": consensus.get("period"),
            "group_count": len(groups),
            "groups": [
                {
                    "play_type": g.get("play_type"),
                    "n_sources": g.get("n_sources"),
                    "n_votes": g.get("n_votes"),
                    "leader": g.get("leader"),
                    "leader_votes": g.get("leader_votes"),
                    "leader_hit": g.get("leader_hit"),
                }
                for g in groups[:5]
            ],
        }

    ratings_top = None
    if isinstance(ratings, dict):
        ratings_top = {
            "lottery": ratings.get("lottery"),
            "play_type": ratings.get("play_type"),
            "windows": ratings.get("windows"),
            "sources": (ratings.get("sources") or [])[:5],
        }

    return {
        "ok": True,
        "lottery": lottery,
        "play_type": play_type,
        "server_time": datetime.now(timezone.utc).isoformat(),
        "latest_draw": latest,
        "consensus": consensus_summary,
        "comparison_summary": (comparison or {}).get("summary") if isinstance(comparison, dict) else None,
        "ratings_top": ratings_top,
        "recent_jobs": (jobs or {}).get("items") if isinstance(jobs, dict) else None,
        "collect_worker": collect_job_worker.get_status(),
        "rule_version": await _safe("rule_version", _rule_version),
    }


def _rule_version() -> str | None:
    rows = cb.rules_catalog()
    return (rows[0].get("version") if rows else None)


# --------------------------------------------------------------------------- #
# Collection jobs
# --------------------------------------------------------------------------- #
class CollectJobCreate(BaseModel):
    lottery: str = Field("macau")
    period: str | None = Field(None, description="canonical or raw; omit to auto-detect")
    source_ids: list[str] | None = None
    concurrency: int = Field(8, ge=1, le=32)
    ingest: bool = True
    auto_judge: bool = True


@router.post("/collect-jobs", status_code=status.HTTP_202_ACCEPTED)
async def create_collect_job(
    payload: CollectJobCreate,
    user: User = _staff,
) -> dict[str, Any]:
    """Queue a collection run and return immediately with the job id.

    Returns 202 with the full resolved source list so the client can render every
    source as "queued" before the first subprocess starts.
    """
    _validate_lottery(payload.lottery)
    try:
        job = await collect_job_worker.submit(
            lottery=payload.lottery,
            period=payload.period,
            source_ids=payload.source_ids,
            concurrency=payload.concurrency,
            do_ingest=payload.ingest,
            auto_judge=payload.auto_judge,
            created_by=user.id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    if not job.get("source_ids"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="no enabled sources matched the request",
        )
    return job


@router.get("/collect-jobs")
async def list_collect_jobs(
    limit: int = Query(30, ge=1, le=200),
    offset: int = Query(0, ge=0),
    lottery: str | None = Query(None),
    job_status: str | None = Query(None, alias="status"),
    user: User = _user,
) -> dict[str, Any]:
    """Run history, newest first. Readable by any signed-in user."""
    if lottery:
        _validate_lottery(lottery)
    result = await asyncio.to_thread(
        cb.list_collect_jobs, limit=limit, offset=offset, lottery=lottery, status=job_status
    )
    result["worker"] = collect_job_worker.get_status()
    return result


@router.get("/collect-jobs/{job_id}")
async def get_collect_job(job_id: int, user: User = _user) -> dict[str, Any]:
    """Poll one job: phase, per-source state, and (once finished) the statistics."""
    job = await asyncio.to_thread(cb.get_collect_job, job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="job not found")
    return job


@router.delete("/collect-jobs/{job_id}")
async def cancel_collect_job(job_id: int, user: User = _staff) -> dict[str, Any]:
    """Request cancellation.

    Sources already running are allowed to finish rather than being killed
    mid-write; queued sources are skipped. A job that has not started yet moves
    straight to ``cancelled``.
    """
    job = await collect_job_worker.cancel(job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="job not found")
    return job


# --------------------------------------------------------------------------- #
# Event feed
# --------------------------------------------------------------------------- #
def _parse_since(since: str | None) -> tuple[datetime | None, str | None]:
    if not since:
        return None, None
    raw = since.strip()
    if not raw:
        return None, None
    if raw.startswith("v1."):
        try:
            encoded = raw[3:]
            encoded += "=" * (-len(encoded) % 4)
            payload = json.loads(base64.urlsafe_b64decode(encoded).decode("utf-8"))
            occurred_at = payload["occurred_at"]
            key = payload["key"]
            if not isinstance(occurred_at, str) or not isinstance(key, str):
                raise ValueError("invalid cursor fields")
            parsed = datetime.fromisoformat(occurred_at.replace("Z", "+00:00"))
        except (ValueError, KeyError, TypeError, json.JSONDecodeError, base64.binascii.Error) as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="since must be a valid event cursor",
            ) from exc
    else:
        key = None
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="since must be an ISO-8601 timestamp or event cursor",
            ) from exc
    # Collector timestamps are naive CN-local; normalise so comparisons work.
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone(timedelta(hours=8))).replace(tzinfo=None)
    return parsed, key


def _iso(value: Any) -> str | None:
    if isinstance(value, datetime):
        return value.isoformat()
    return value if value is None else str(value)


def _event_key(event: dict[str, Any]) -> str:
    """Return a deterministic tie-breaker for events sharing a timestamp."""
    data = event.get("data") or {}
    return "|".join(
        str(event.get(name) or "")
        for name in ("type", "lottery", "period")
    ) + "|" + "|".join(
        str(data.get(name) or "")
        for name in ("job_id", "source_id", "play_type", "leader_key")
    )


def _event_time(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone(timedelta(hours=8))).replace(tzinfo=None)
    return parsed


def _encode_event_cursor(event: dict[str, Any]) -> str:
    payload = json.dumps(
        {"occurred_at": event["occurred_at"], "key": _event_key(event)},
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")
    return "v1." + base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")


@router.get("/events")
async def events(
    since: str | None = Query(None, description="ISO-8601 cursor; exclusive"),
    lottery: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    user: User = _user,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    """Incremental event feed for notification polling.

    Events are computed from existing tables (plus ``consensus_leader``, which the
    job worker maintains) rather than stored in a queue, so the same cursor works
    for any number of devices and nothing is consumed by being read.

    ``next_cursor`` is an opaque composite cursor for the newest event returned,
    or the incoming cursor when there is nothing new. Legacy ISO timestamps are
    still accepted as input. Clients persist the value and pass it back as
    ``since``.
    """
    if lottery:
        _validate_lottery(lottery)
    cursor_time, cursor_key = _parse_since(since)
    # Existing bridge queries accept a timestamp only. Query one second before
    # a composite cursor (the database may store timestamps at second
    # precision), then apply the tie-breaker below so same-time events are never
    # lost at a page boundary.
    query_since = (
        cursor_time - timedelta(seconds=1)
        if cursor_time is not None and cursor_key is not None
        else cursor_time
    )
    source_limit = min(max(limit * 2, limit), 200)

    # Read synchronously: a SQLAlchemy Session is not thread-safe, and this is a
    # single primary-key lookup.
    sub = _load_subscription_row(db, user.id)
    followed: list[str] = list(sub.get("source_ids") or [])
    preferred_lotteries: set[str] = set(sub.get("lotteries") or [])
    preferred_play_types: set[str] = set(sub.get("play_types") or [])
    rules: dict[str, Any] = dict(sub.get("notify_rules") or {})

    def enabled(key: str, default: bool = True) -> bool:
        value = rules.get(key, default)
        return bool(value)

    out: list[dict[str, Any]] = []

    if enabled("draw_published"):
        for row in await asyncio.to_thread(
            cb.list_recent_draw_events, query_since, lottery, source_limit
        ) or []:
            out.append(
                {
                    "type": "draw_published",
                    "occurred_at": _iso(row["occurred_at"]),
                    "lottery": row["lottery"],
                    "period": row["period"],
                    "title": "新开奖",
                    "body": f"{row['lottery']} {row['period']} 特码 {row['tema']}",
                    "data": row | {"occurred_at": _iso(row["occurred_at"])},
                }
            )

    # Hit/miss events are only meaningful for sources the user follows.
    if followed and (enabled("source_hit", False) or enabled("source_miss_streak")):
        judged = await asyncio.to_thread(
            cb.list_recent_judge_events, query_since, lottery, followed, source_limit
        ) or []
        if enabled("source_hit", False):
            for row in judged:
                if row.get("official_hit") != 1:
                    continue
                out.append(
                    {
                        "type": "source_hit",
                        "occurred_at": _iso(row["occurred_at"]),
                        "lottery": row["lottery"],
                        "period": row["period"],
                        "title": "关注源命中",
                        "body": f"{row['source_name']} {row['play_type']} {row['period']} 命中",
                        "data": row | {"occurred_at": _iso(row["occurred_at"])},
                    }
                )

        if enabled("source_miss_streak") and judged:
            threshold = int(rules.get("miss_streak_threshold") or 3)
            # Only sources with a newly judged miss can have crossed the
            # threshold since the last poll, so the streak scan is limited to
            # them rather than every followed source.
            newly_missed = {
                r["source_id"]: r for r in judged if r.get("official_hit") == 0
            }
            if newly_missed:
                streaks = await asyncio.to_thread(
                    cb.source_miss_streaks,
                    lottery or "macau",
                    list(newly_missed.keys()),
                )
                for source_id, streak in streaks.items():
                    if streak < threshold:
                        continue
                    row = newly_missed[source_id]
                    out.append(
                        {
                            "type": "source_miss_streak",
                            "occurred_at": _iso(row["occurred_at"]),
                            "lottery": row["lottery"],
                            "period": row["period"],
                            "title": "关注源连挂",
                            "body": f"{row['source_name']} 已连挂 {streak} 期",
                            "data": {
                                "source_id": source_id,
                                "source_name": row["source_name"],
                                "streak": streak,
                                "threshold": threshold,
                                "period": row["period"],
                                "occurred_at": _iso(row["occurred_at"]),
                            },
                        }
                    )

    if enabled("consensus_leader_changed", False):
        for row in await asyncio.to_thread(
            cb.list_consensus_leader_changes, query_since, lottery, source_limit
        ) or []:
            out.append(
                {
                    "type": "consensus_leader_changed",
                    "occurred_at": _iso(row["changed_at"]),
                    "lottery": row["lottery"],
                    "period": row["period"],
                    "title": "共识领先变动",
                    "body": f"{row['play_type']} 领先方案已变更（{row['leader_votes']} 票）",
                    "data": row | {"changed_at": _iso(row["changed_at"])},
                }
            )

    if enabled("collect_job_finished"):
        for row in await asyncio.to_thread(
            cb.list_finished_job_events, query_since, lottery, None, source_limit
        ) or []:
            out.append(
                {
                    "type": "collect_job_finished",
                    "occurred_at": _iso(row["occurred_at"]),
                    "lottery": row["lottery"],
                    "period": row["period"],
                    "title": "采集任务完成" if row["status"] == "done" else f"采集任务{row['status']}",
                    "body": f"{row['lottery']} {row['period'] or ''} 成功 {row['source_ok']}/{row['source_total']}",
                    "data": row | {"occurred_at": _iso(row["occurred_at"])},
                }
            )

    # Subscription scopes are shared by all event types. Events without a
    # play-type (draws and job completion) are still governed by the lottery
    # preference, while source/consensus events additionally honour play types.
    if preferred_lotteries or preferred_play_types:
        out = [
            event
            for event in out
            if (
                not preferred_lotteries
                or event.get("lottery") in preferred_lotteries
            )
            and (
                not preferred_play_types
                or not event.get("data", {}).get("play_type")
                or event.get("data", {}).get("play_type") in preferred_play_types
            )
        ]

    # A single ordered, truncated stream. For old timestamp-only cursors retain
    # the original exclusive semantics; for composite cursors compare both
    # timestamp and identity so same-timestamp events are delivered exactly once.
    if cursor_time is not None:
        filtered: list[dict[str, Any]] = []
        for event in out:
            event_time = _event_time(event.get("occurred_at"))
            if event_time is None or event_time < cursor_time:
                continue
            if event_time == cursor_time and cursor_key is None:
                continue
            if event_time == cursor_time and cursor_key is not None and _event_key(event) <= cursor_key:
                continue
            filtered.append(event)
        out = filtered

    out.sort(key=lambda e: (e["occurred_at"] or "", _event_key(e)))
    truncated = len(out) > limit
    out = out[:limit]
    next_cursor = (
        _encode_event_cursor(out[-1])
        if out
        else (since if since and cursor_key is not None else _iso(cursor_time))
    )

    return {
        "ok": True,
        "count": len(out),
        "has_more": truncated,
        "next_cursor": next_cursor,
        "events": out,
    }


# --------------------------------------------------------------------------- #
# Version / force update
# --------------------------------------------------------------------------- #
@router.get("/version")
def version(
    platform: str = Query(..., description="android | ios"),
    current: str | None = Query(None, description="the running build's version"),
    db: Session = Depends(get_db),
    user: User = _user,
) -> dict[str, Any]:
    """Update check for internally distributed builds.

    Configured through ``system_settings`` so a release does not need a redeploy.
    ``update_required`` is true when the running build is below ``min_supported``.
    """
    if platform not in PLATFORMS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"unknown platform: {platform}",
        )
    latest_key, min_key, url_key = VERSION_KEYS[platform]
    latest = get_setting_value(db, latest_key, "") or None
    min_supported = get_setting_value(db, min_key, "") or None
    download_url = get_setting_value(db, url_key, "") or None
    notes = get_setting_value(db, f"app_{platform}_release_notes", "") or None

    update_required = False
    update_available = False
    if current:
        if min_supported and _version_tuple(current) < _version_tuple(min_supported):
            update_required = True
        if latest and _version_tuple(current) < _version_tuple(latest):
            update_available = True

    return {
        "ok": True,
        "platform": platform,
        "current": current,
        "latest": latest,
        "min_supported": min_supported,
        "download_url": download_url,
        "release_notes": notes,
        "update_available": update_available,
        "update_required": update_required,
    }


def _version_tuple(value: str) -> tuple[int, ...]:
    """Parse a dotted version leniently; unparsable segments sort as 0."""
    parts: list[int] = []
    for chunk in str(value).strip().split("."):
        digits = "".join(ch for ch in chunk if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts) or (0,)


# --------------------------------------------------------------------------- #
# Subscriptions (shared with the /users router)
# --------------------------------------------------------------------------- #
def _load_subscription_row(db: Session, user_id: str) -> dict[str, Any]:
    """Read a user's subscription, falling back to defaults when absent."""
    from app.models.subscription import DEFAULT_NOTIFY_RULES, UserSubscription

    row = db.get(UserSubscription, user_id)
    if row is None:
        return {
            "source_ids": [],
            "lotteries": [],
            "play_types": [],
            "notify_rules": dict(DEFAULT_NOTIFY_RULES),
            "updated_at": None,
        }
    rules = dict(DEFAULT_NOTIFY_RULES)
    rules.update(row.notify_rules or {})
    return {
        "source_ids": list(row.source_ids or []),
        "lotteries": list(row.lotteries or []),
        "play_types": list(row.play_types or []),
        "notify_rules": rules,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }
