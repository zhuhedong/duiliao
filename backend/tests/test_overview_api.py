"""Tests for the workbench overview endpoint (GET /collector/overview).

Runs offline against the throwaway session databases; collection uses the
checked-in fixtures so no outbound HTTP happens.
"""
from __future__ import annotations

from app import collector_bridge as cb

FIXTURE_DIR = "fixtures/dingjian"


def test_overview_requires_auth(crypto_client):
    import pytest
    from tests.crypto_client import ApiError

    with pytest.raises(ApiError) as exc:
        crypto_client.get("/collector/overview")
    assert exc.value.status_code == 401


def test_overview_shape_and_zero_state(user_client):
    res = user_client.get("/collector/overview")
    assert res["ok"] is True
    assert "generated_at" in res

    totals = res["totals"]
    for key in (
        "sources",
        "sources_enabled",
        "predictions",
        "draws",
        "judge_results",
        "schedules",
        "schedules_enabled",
        "crawl_runs",
    ):
        assert key in totals
        assert isinstance(totals[key], int)
        assert totals[key] >= 0

    judge = res["judge"]
    for key in ("judged", "hits", "misses", "hit_rate", "today_judged", "today_hits", "today_hit_rate", "pending_judge"):
        assert key in judge
    assert judge["judged"] == judge["hits"] + judge["misses"]

    today = res["today"]
    for key in ("date", "crawl_runs", "source_ok", "source_total", "new_predictions"):
        assert key in today

    trend = res["trend_7d"]
    assert len(trend) == 7
    for point in trend:
        assert set(point) == {"date", "judged", "hits", "hit_rate"}

    assert isinstance(res["latest_draws"], list)
    assert isinstance(res["leaderboard"], list)
    assert isinstance(res["play_type_dist"], list)
    assert isinstance(res["upcoming_schedules"], list)
    assert isinstance(res["recent_logs"], list)

    alerts = res["alerts"]
    for key in ("lagging_sources", "never_collected", "confirmed_missing_total", "items"):
        assert key in alerts

    scheduler = res["scheduler"]
    assert "draw" in scheduler and "source" in scheduler
    for key in ("enabled", "in_window", "next_run_at", "last_run_at", "last_error", "sync_count"):
        assert key in scheduler["draw"]
    for key in ("running", "active_tasks_count", "running_task_ids"):
        assert key in scheduler["source"]


def test_overview_reflects_seeded_data(user_client, seeded_draws, fixture_sources):
    """After collecting fixtures + judging, counters must move off zero."""
    result = cb.collect(
        lottery="macau",
        period="248",
        source_ids=fixture_sources,
        fixture_dir=FIXTURE_DIR,
        do_ingest=True,
        concurrency=2,
    )
    assert result["source_ok"] == 2

    res = user_client.get("/collector/overview")

    totals = res["totals"]
    assert totals["predictions"] >= 2
    assert totals["draws"] >= 2
    assert totals["judge_results"] >= 2
    assert totals["crawl_runs"] >= 1

    judge = res["judge"]
    assert judge["judged"] >= 2
    assert 0 <= judge["hits"] <= judge["judged"]
    if judge["judged"]:
        assert judge["hit_rate"] is not None
        assert 0.0 <= judge["hit_rate"] <= 1.0

    # Latest draw for macau must be enriched with balls + tema detail.
    macau = next((d for d in res["latest_draws"] if d["lottery"] == "macau"), None)
    assert macau is not None
    assert macau["period"] == "2026248"
    assert len(macau["balls"]) == 6
    assert macau["tema"]
    assert macau["tema_detail"]["num"] == macau["tema"]
    assert macau["summary"]["sum7"] > 0

    # Play-type distribution mentions the fixture play type.
    pts = {p["play_type"] for p in res["play_type_dist"]}
    assert "pingte_xiao" in pts
