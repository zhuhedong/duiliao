"""Scan missing prediction periods and submit asynchronous collect jobs to fill them."""
from __future__ import annotations

import logging
from typing import Any

from app import collector_bridge as cb
from app.services.collect_jobs import collect_job_worker

logger = logging.getLogger("app.services.backfill_jobs")


def preview_missing(
    *,
    lottery: str,
    period: str | None = None,
    source_ids: list[str] | None = None,
    limit_sources: int = 50,
) -> dict[str, Any]:
    """Return sources that lack a prediction for the given period (or latest draw)."""
    from sqlalchemy import select

    cb.prepare_modules()
    from db import session_scope
    from schema import Draw, Prediction, Source

    lottery = (lottery or "macau").strip()
    with session_scope(guard=False) as session:
        if period:
            target_period = str(period).strip()
        else:
            draw = session.scalars(
                select(Draw).where(Draw.lottery == lottery).order_by(Draw.period.desc()).limit(1)
            ).first()
            if draw is None:
                return {
                    "ok": True,
                    "lottery": lottery,
                    "period": None,
                    "missing_sources": [],
                    "missing_count": 0,
                    "note": "no_draws",
                }
            target_period = draw.period

        q = select(Source).where(Source.lottery == lottery).where(Source.enabled == 1)
        if source_ids:
            q = q.where(Source.source_id.in_(list(source_ids)))
        sources = session.scalars(q).all()
        missing: list[dict[str, Any]] = []
        for src in sources:
            exists = session.scalars(
                select(Prediction.id)
                .where(Prediction.source_id == src.source_id)
                .where(Prediction.lottery == lottery)
                .where(Prediction.period == target_period)
                .where(Prediction.claimed_status != "missing")
                .limit(1)
            ).first()
            if exists is None:
                missing.append(
                    {
                        "source_id": src.source_id,
                        "source_name": src.source_name or src.source_id,
                        "play_type": src.play_type,
                        "site_family": src.site_family,
                    }
                )
            if len(missing) >= limit_sources:
                break
        return {
            "ok": True,
            "lottery": lottery,
            "period": target_period,
            "missing_count": len(missing),
            "missing_sources": missing,
        }


async def submit_backfill(
    *,
    lottery: str,
    period: str | None = None,
    source_ids: list[str] | None = None,
    concurrency: int = 8,
    created_by: str | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    preview = preview_missing(lottery=lottery, period=period, source_ids=source_ids)
    missing_ids = [row["source_id"] for row in preview.get("missing_sources") or []]
    if dry_run or not missing_ids:
        return {
            **preview,
            "dry_run": True,
            "job": None,
            "submitted": False,
        }
    job = await collect_job_worker.submit(
        lottery=lottery,
        period=preview.get("period"),
        source_ids=missing_ids,
        concurrency=concurrency,
        do_ingest=True,
        auto_judge=True,
        created_by=created_by,
    )
    return {
        **preview,
        "dry_run": False,
        "submitted": True,
        "job": job,
    }
