"""Record and query fetch_observation rows."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import desc, select

from db import session_scope
from schema import FetchObservation

TZ8 = timezone(timedelta(hours=8))


def _now() -> datetime:
    return datetime.now(TZ8).replace(tzinfo=None)


def record_observation(
    *,
    source_id: str | None = None,
    lottery: str | None = None,
    period: str | None = None,
    url: str | None = None,
    http_status: int | None = None,
    elapsed_ms: int | None = None,
    content_hash: str | None = None,
    error: str | None = None,
    job_id: int | None = None,
    ok: bool = False,
) -> dict[str, Any]:
    with session_scope() as session:
        row = FetchObservation(
            source_id=source_id,
            lottery=lottery,
            period=period,
            url=(url or "")[:512] or None,
            http_status=http_status,
            elapsed_ms=elapsed_ms,
            content_hash=content_hash,
            error=(error or "")[:512] or None,
            job_id=job_id,
            ok=1 if ok else 0,
            created_at=_now(),
        )
        session.add(row)
        session.flush()
        return {
            "id": row.id,
            "source_id": row.source_id,
            "lottery": row.lottery,
            "period": row.period,
            "url": row.url,
            "http_status": row.http_status,
            "elapsed_ms": row.elapsed_ms,
            "content_hash": row.content_hash,
            "error": row.error,
            "job_id": row.job_id,
            "ok": bool(row.ok),
            "created_at": row.created_at.isoformat(sep=" ", timespec="seconds") if row.created_at else None,
        }


def record_from_collect_result(
    result: dict[str, Any],
    *,
    lottery: str | None = None,
    period: str | None = None,
    job_id: int | None = None,
) -> dict[str, Any] | None:
    """Map a collect() per-source result dict into an observation row."""
    source_id = result.get("source_id")
    if not source_id:
        return None
    ok = bool(result.get("ok"))
    error = result.get("error_msg") or result.get("error_code")
    # Prefer an explicit final_url / content_hash when the payload carried them.
    url = result.get("final_url") or result.get("url")
    content_hash = result.get("content_hash")
    raw = result.get("stdout")
    if isinstance(raw, str) and raw.strip().startswith("{") and content_hash is None:
        try:
            import json

            payload = json.loads(raw)
            if isinstance(payload, dict):
                content_hash = content_hash or payload.get("content_hash")
                url = url or payload.get("final_url")
        except Exception:
            pass
    return record_observation(
        source_id=str(source_id),
        lottery=lottery,
        period=str(period) if period else None,
        url=str(url) if url else None,
        http_status=result.get("http_status") or (200 if ok else None),
        elapsed_ms=result.get("elapsed_ms"),
        content_hash=str(content_hash) if content_hash else None,
        error=str(error) if error else None,
        job_id=job_id,
        ok=ok,
    )


def list_observations(
    *,
    source_id: str | None = None,
    lottery: str | None = None,
    job_id: int | None = None,
    only_failures: bool = False,
    hash_changed_from: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> dict[str, Any]:
    limit = max(1, min(int(limit), 200))
    offset = max(0, int(offset))
    with session_scope() as session:
        stmt = select(FetchObservation)
        if source_id:
            stmt = stmt.where(FetchObservation.source_id == source_id)
        if lottery:
            stmt = stmt.where(FetchObservation.lottery == lottery)
        if job_id is not None:
            stmt = stmt.where(FetchObservation.job_id == job_id)
        if only_failures:
            stmt = stmt.where(FetchObservation.ok == 0)
        if hash_changed_from:
            stmt = stmt.where(FetchObservation.content_hash.is_not(None)).where(
                FetchObservation.content_hash != hash_changed_from
            )
        total = len(session.scalars(stmt).all())
        rows = session.scalars(
            stmt.order_by(desc(FetchObservation.id)).offset(offset).limit(limit)
        ).all()
        items = [
            {
                "id": r.id,
                "source_id": r.source_id,
                "lottery": r.lottery,
                "period": r.period,
                "url": r.url,
                "http_status": r.http_status,
                "elapsed_ms": r.elapsed_ms,
                "content_hash": r.content_hash,
                "error": r.error,
                "job_id": r.job_id,
                "ok": bool(r.ok),
                "created_at": r.created_at.isoformat(sep=" ", timespec="seconds") if r.created_at else None,
            }
            for r in rows
        ]
        return {"total": total, "count": len(items), "items": items}


def previous_hash(source_id: str) -> str | None:
    with session_scope() as session:
        row = session.scalars(
            select(FetchObservation)
            .where(FetchObservation.source_id == source_id)
            .where(FetchObservation.content_hash.is_not(None))
            .order_by(desc(FetchObservation.id))
            .limit(1)
        ).first()
        return row.content_hash if row else None


def list_hash_change_events(
    since: datetime | None = None,
    *,
    lottery: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Emit an event when a source's content_hash differs from its previous observation.

    ``since`` only filters the *newer* observation so older hashes remain
    visible for comparison even when they fall before the cursor.
    """
    limit = max(1, min(int(limit), 200))
    with session_scope() as session:
        stmt = (
            select(FetchObservation)
            .where(FetchObservation.content_hash.is_not(None))
            .where(FetchObservation.ok == 1)
            .order_by(desc(FetchObservation.id))
            .limit(max(limit * 10, 100))
        )
        if lottery:
            stmt = stmt.where(FetchObservation.lottery == lottery)
        rows = list(session.scalars(stmt).all())

    by_source: dict[str, list[FetchObservation]] = {}
    for row in rows:
        if not row.source_id:
            continue
        by_source.setdefault(row.source_id, []).append(row)

    events: list[dict[str, Any]] = []
    cutoff = None
    if since is not None:
        cutoff = since.replace(tzinfo=None) if since.tzinfo else since

    for source_id, items in by_source.items():
        for idx, newer in enumerate(items[:-1]):
            if cutoff is not None and newer.created_at and newer.created_at < cutoff:
                continue
            older = items[idx + 1]
            if not newer.content_hash or not older.content_hash:
                continue
            if newer.content_hash == older.content_hash:
                continue
            events.append(
                {
                    "source_id": source_id,
                    "lottery": newer.lottery,
                    "period": newer.period,
                    "old_hash": older.content_hash,
                    "new_hash": newer.content_hash,
                    "url": newer.url,
                    "observation_id": newer.id,
                    "occurred_at": newer.created_at,
                }
            )
            break
    events.sort(key=lambda e: e["occurred_at"] or datetime.min, reverse=True)
    return events[:limit]


def list_consecutive_failure_events(
    since: datetime | None = None,
    *,
    lottery: str | None = None,
    threshold: int = 3,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Emit when a source's newest failure streak *exactly* equals ``threshold``.

    Exact match avoids re-notifying on every subsequent failure; the next alert
    waits until the streak recovers and then crosses the threshold again.
    """
    threshold = max(2, min(int(threshold), 20))
    limit = max(1, min(int(limit), 200))
    with session_scope() as session:
        stmt = select(FetchObservation).order_by(desc(FetchObservation.id)).limit(400)
        if lottery:
            stmt = stmt.where(FetchObservation.lottery == lottery)
        rows = list(session.scalars(stmt).all())

    by_source: dict[str, list[FetchObservation]] = {}
    for row in rows:
        if not row.source_id:
            continue
        by_source.setdefault(row.source_id, []).append(row)

    events: list[dict[str, Any]] = []
    for source_id, items in by_source.items():
        streak = 0
        newest_fail: FetchObservation | None = None
        for row in items:
            if row.ok:
                break
            streak += 1
            if newest_fail is None:
                newest_fail = row
        if streak != threshold or newest_fail is None:
            continue
        if since is not None and newest_fail.created_at:
            cutoff = since.replace(tzinfo=None) if since.tzinfo else since
            if newest_fail.created_at < cutoff:
                continue
        events.append(
            {
                "source_id": source_id,
                "lottery": newest_fail.lottery,
                "period": newest_fail.period,
                "streak": streak,
                "threshold": threshold,
                "error": newest_fail.error,
                "observation_id": newest_fail.id,
                "occurred_at": newest_fail.created_at,
            }
        )
    events.sort(key=lambda e: e["occurred_at"] or datetime.min, reverse=True)
    return events[:limit]
