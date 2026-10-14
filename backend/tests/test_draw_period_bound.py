"""Draw (开奖) records must never be stored with a period beyond today's period."""
from __future__ import annotations

from datetime import timedelta

import pytest

from tests.crypto_client import ApiError

BALLS = ["01", "02", "03", "04", "05", "06", "07"]


def _mods():
    from app import collector_bridge as cb

    cb.prepare_modules()
    import common.period as period
    import draw_sync

    return period, draw_sync


def _row(period: str, draw_date, lottery: str = "macau") -> dict:
    z = dict(zip(["z1", "z2", "z3", "z4", "z5", "z6", "tema"], BALLS))
    return {"lottery": lottery, "period": period, "period_raw": period[4:], "draw_date": draw_date,
            "source": "test", **z}


def test_validate_draw_rejects_future_period():
    p, ds = _mods()
    today = p.beijing_now().date()
    with pytest.raises(p.FuturePeriodError):
        ds.validate_draw(_row(p.period_for_date(today + timedelta(days=3)), today))


def test_validate_draw_rejects_period_ahead_of_draw_date():
    p, ds = _mods()
    d = p.beijing_now().date() - timedelta(days=5)
    with pytest.raises(p.FuturePeriodError, match="下一期占位"):
        ds.validate_draw(_row(p.period_for_date(d + timedelta(days=2)), d))
    ds.validate_draw(_row(p.period_for_date(d), d))  # consistent row ok


def test_fetched_future_draws_are_skipped(monkeypatch):
    p, ds = _mods()
    from app import collector_bridge as cb

    today = p.beijing_now().date()
    old = today.replace(month=1, day=2)  # early period: doesn't become the "latest draw" for other tests
    good = ds.from_generic({"period": p.period_for_date(old), "openCode": BALLS,
                            "draw_date": str(old)}, "macau", "test")
    bad = dict(good, period=p.period_for_date(today + timedelta(days=3)))
    monkeypatch.setattr(ds, "fetch_get_last_lottery", lambda *a, **k: [bad, good])
    monkeypatch.setattr(ds, "fetch_get_trend", lambda *a, **k: [])
    res = cb.sync_draws("macau")
    assert res["skipped_future"] == 1
    assert res["count"] == 1


def test_draw_sync_api_rejects_future_period(staff_client):
    p, _ = _mods()
    future = p.period_for_date(p.beijing_now() + timedelta(days=3))
    with pytest.raises(ApiError) as e:
        staff_client.post("/collector/draws/sync", body={"lottery": "macau", "period": future})
    assert e.value.status_code == 400 and "超过当天期号" in str(e.value)
    today = p.beijing_now().date()
    draws = [{"period": future, "openCode": BALLS, "draw_date": str(today), "source": "api"}]
    with pytest.raises(ApiError) as e:
        staff_client.post("/collector/draws/sync", body={"lottery": "macau", "draws": draws})
    assert e.value.status_code == 400


def test_fix_future_draws_script_dry_run_and_delete():
    p, _ = _mods()
    from db import session_scope
    from schema import Draw
    from scripts.fix_future_draws import run

    future = p.period_for_date(p.beijing_now() + timedelta(days=3))
    with session_scope() as s:
        s.add(Draw(lottery="taiwan", period=future, period_raw=future[4:], draw_date=p.beijing_now().date(),
                   z1="01", z2="02", z3="03", z4="04", z5="05", z6="06", tema="07", source="test", tag={}))
    res = run()
    assert res["by_lottery"]["taiwan"]["count"] == 1 and res["deleted"] == 0
    assert run()["by_lottery"]["taiwan"]["count"] == 1  # dry run kept it
    assert run(delete=True)["deleted"] == 1
    assert "taiwan" not in run()["by_lottery"]


def test_source_page_future_rows_never_become_draw_or_current_period():
    """Realistic 资料 rows: an upcoming placeholder row must not be a draw nor the current period."""
    p, ds = _mods()
    from app import collector_bridge as cb
    from common.parse_pred import parse_column_text
    from db import session_scope
    from schema import Prediction
    from sqlalchemy import delete

    today = p.max_allowed_period()
    future = p.period_for_date(p.beijing_now() + timedelta(days=3))
    text = f"{future[4:]}期:平特【鼠牛虎】开:？00准\n{today[4:]}期:平特【猴鸡狗】开:猴29准"
    items = parse_column_text(text)
    assert {it["period_raw"] for it in items} == {future[4:], today[4:]}
    # A page row (placeholder claim "？00") can never pass as a draw.
    with pytest.raises(ValueError):
        ds.validate_draw(_row(p.normalize("macau", items[0]["period_raw"]), p.beijing_now().date()) | {"tema": "00"})
    with pytest.raises(ValueError):
        ds.validate_draw(_row(future, p.beijing_now().date()))
    now = p.beijing_now().replace(tzinfo=None)
    with session_scope() as s:
        s.add(Prediction(source_id="dj_4xiao", lottery="macau", play_type="pingte_xiao", hit_mode="any",
                         period=future, period_raw=future[4:], preds_json=[], claimed_status="pending",
                         raw_text=items[0]["raw_text"], content_hash="t", fetched_at=now,
                         first_seen_at=now, last_seen_at=now, last_run_id="t"))
    try:
        info = cb.consensus_latest_period("macau")
        assert info["current_period"] == today
        assert info["latest_prediction_period"] != future
    finally:
        with session_scope() as s:
            s.execute(delete(Prediction).where(Prediction.period == future))
