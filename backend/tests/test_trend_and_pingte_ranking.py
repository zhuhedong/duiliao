"""Tests for the trend and Pingte ranking endpoints."""
from fastapi.testclient import TestClient

from app.main import app


def test_trend_endpoint_compatible():
    client = TestClient(app)
    # Open unencrypted compatible route
    res = client.get("/api/v1/trend/getTrend?lottery=macau&limit=10")
    assert res.status_code == 200
    data = res.json()
    assert data["code"] == 1
    assert data["msg"] == "操作成功"
    assert "data" in data
    assert isinstance(data["data"], list)


def test_collector_trend_endpoint(user_client, seeded_draws):
    res = user_client.get("/collector/trend?lottery=macau&limit=10")
    assert res["code"] == 1
    assert "data" in res
    assert len(res["data"]) > 0
    item = res["data"][0]
    assert "period" in item
    assert "code" in item
    assert len(item["code"]) == 7


def test_pingte_ranking_endpoint(user_client, seeded_draws):
    res = user_client.get("/collector/pingte-ranking?lottery=macau&limit=50")
    assert res["ok"] is True
    assert res["lottery"] == "macau"
    assert res["sample_periods"] > 0
    assert len(res["zodiac_ranking"]) == 12
    assert len(res["tail_ranking"]) == 10
    assert len(res["number_ranking"]) == 49
    assert len(res["bose_ranking"]) == 3
    assert len(res["wuxing_ranking"]) == 5

    # Check structure
    z0 = res["zodiac_ranking"][0]
    assert "name" in z0
    assert "count" in z0
    assert "current_omission" in z0
    assert "max_omission" in z0
    assert "max_consecutive" in z0
    assert "numbers" in z0
    assert z0["rank"] == 1

    t0 = res["tail_ranking"][0]
    assert "name" in t0
    assert "count" in t0
    assert "numbers" in t0

    n0 = res["number_ranking"][0]
    assert "number" in n0
    assert "count" in n0
    assert "ping_count" in n0
    assert "tema_count" in n0
    assert "bose" in n0
    assert "xiao" in n0
