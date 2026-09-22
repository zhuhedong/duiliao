"""Tests for the source history endpoint and enhanced predictions list."""
from __future__ import annotations

import pytest
from tests.crypto_client import ApiError


def test_get_source_history_not_found(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.get("/collector/sources/non_existent_source_9999/history")
    assert exc.value.status_code == 404


def test_get_source_history_success(user_client):
    # Retrieve sources list first
    sources = user_client.get("/collector/sources")
    assert isinstance(sources, list)
    if not sources:
        pytest.skip("no sources available in test environment")

    # Pick a source, e.g. the first one
    source_id = sources[0]["source_id"]
    res = user_client.get(f"/collector/sources/{source_id}/history")
    assert res["ok"] is True
    assert "source" in res
    assert res["source"]["source_id"] == source_id
    assert "stats" in res
    stats = res["stats"]
    for k in (
        "total",
        "judged",
        "hits",
        "misses",
        "pending",
        "conflicts",
        "missing",
        "hit_rate",
        "longest_hit",
        "longest_miss",
        "current_streak",
    ):
        assert k in stats
    assert isinstance(res["items"], list)
    assert res["total"] >= 0


def test_get_source_history_pagination(user_client):
    sources = user_client.get("/collector/sources")
    if not sources:
        pytest.skip("no sources")
    source_id = sources[0]["source_id"]

    res_p1 = user_client.get(f"/collector/sources/{source_id}/history", params={"limit": 2, "offset": 0})
    assert res_p1["ok"] is True
    assert res_p1["limit"] == 2
    assert res_p1["offset"] == 0
    assert len(res_p1["items"]) <= 2


def test_list_predictions_includes_verification(user_client):
    res = user_client.get("/collector/predictions", params={"limit": 5, "offset": 0})
    assert res["ok"] is True
    assert "items" in res
    assert "total" in res
    assert "offset" in res
    for item in res["items"]:
        assert "status" in item
        assert "official_hit" in item
        assert "source_name" in item
