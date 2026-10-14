"""Periods beyond today's (Beijing time) period must never be stored."""
from __future__ import annotations

from datetime import date, datetime, timedelta

import pytest

from tests.crypto_client import ApiError


def _period_mod():
    from app import collector_bridge as cb

    cb.prepare_modules()
    import common.period as period

    return period


def test_today_period_rule():
    p = _period_mod()
    assert p.max_allowed_period(date(2026, 10, 14)) == "2026287"
    assert not p.is_future_period("2026287", date(2026, 10, 14))
    assert p.is_future_period("2026288", date(2026, 10, 14))
    assert p.is_future_period("2026290", date(2026, 10, 14))
    assert not p.is_future_period("2025365", date(2026, 1, 1))
    assert not p.is_future_period("auto")
    with pytest.raises(p.FuturePeriodError, match="超过当天期号 2026287"):
        p.ensure_not_future("2026290", date(2026, 10, 14))


def _future() -> str:
    p = _period_mod()
    return p.period_for_date(p.beijing_now() + timedelta(days=3))


def test_backfill_preview_rejects_future_period(user_client):
    with pytest.raises(ApiError) as e:
        user_client.get("/collector/backfill-jobs/preview", params={"lottery": "macau", "period": _future()})
    assert e.value.status_code == 400
    assert "超过当天期号" in str(e.value)


def test_backfill_submit_rejects_future_period(staff_client):
    with pytest.raises(ApiError) as e:
        staff_client.post("/collector/backfill-jobs", body={"lottery": "macau", "period": _future(), "dry_run": True})
    assert e.value.status_code == 400


def test_manual_collect_rejects_future_period():
    from app import collector_bridge as cb

    with pytest.raises(ValueError, match="超过当天期号"):
        cb.collect("macau", _future(), source_ids=[])


def test_ingest_skips_future_items_and_fill_missing_ignores_them():
    from app import collector_bridge as cb

    p = _period_mod()
    cb.prepare_modules()
    from sqlalchemy import select

    from db import session_scope
    from ingest import ingest_run
    from schema import Prediction

    from schema import Source

    with session_scope() as s:
        src = s.scalars(select(Source).where(Source.lottery == "macau")).first()
        assert src is not None
        sid, play, hit = src.source_id, src.play_type, src.hit_mode
    today = p.beijing_now()
    periods = [p.period_for_date(today - timedelta(days=2)), p.period_for_date(today),
               p.period_for_date(today + timedelta(days=3))]
    now = today.isoformat()
    items = [{
        "period_raw": x[4:], "period": x, "group_key": "", "published_at": None,
        "preds": [{"kind": "num", "value": "01"}], "claimed": {"status": "unknown"}, "raw_text": x,
    } for x in periods]
    data = {"ok": True, "schema": "pred.v1", "source_id": sid, "source_name": "t",
            "site_family": "t", "lottery": "macau", "play_type": play, "hit_mode": hit,
            "fetched_at": now, "final_url": None, "content_hash": "h", "items": items}
    payload = {"schema": "run.v1", "run_id": "future-test-run", "lottery": "macau", "period": "auto", "run_at": now, "ok": True,
               "results": [{"source_id": sid, "ok": True, "exit_code": 0, "elapsed_ms": 1,
                            "item_count": 3, "data": data}]}
    res = ingest_run(payload)

    assert res["skipped_future"] == 1
    with session_scope() as s:
        stored = {r.period for r in s.scalars(select(Prediction).where(Prediction.source_id == sid, Prediction.play_type == play))}
    assert periods[2] not in stored
    assert all(not p.is_future_period(x) for x in stored)
    assert periods[0] in stored and periods[1] in stored
