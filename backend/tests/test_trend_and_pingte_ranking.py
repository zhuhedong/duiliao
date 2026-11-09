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
    assert "ping_count" in z0
    assert "tema_count" in z0
    assert "miss_periods_count" in z0
    assert "current_omission" in z0
    assert "max_omission" in z0
    assert "max_consecutive" in z0
    assert "current_consecutive" in z0
    assert "current_range" in z0
    assert "max_consecutive_range" in z0
    assert "max_omission_range" in z0
    assert "recent_segments" in z0
    assert "streak_distribution" in z0
    assert "omission_distribution" in z0
    assert "numbers" in z0
    assert z0["rank"] == 1

    t0 = res["tail_ranking"][0]
    assert "name" in t0
    assert "count" in t0
    assert "current_consecutive" in t0
    assert "numbers" in t0

    n0 = res["number_ranking"][0]
    assert "number" in n0
    assert "count" in n0
    assert "ping_count" in n0
    assert "tema_count" in n0
    assert "current_consecutive" in n0
    assert "bose" in n0
    assert "xiao" in n0

    b0 = res["bose_ranking"][0]
    assert "current_consecutive" in b0

    w0 = res["wuxing_ranking"][0]
    assert "current_consecutive" in w0

    # Test sorting by current_consecutive_desc
    res_cons = user_client.get("/collector/pingte-ranking?lottery=macau&limit=50&order_by=current_consecutive_desc")
    assert res_cons["ok"] is True
    z_cons = res_cons["zodiac_ranking"]
    for i in range(len(z_cons) - 1):
        assert z_cons[i]["current_consecutive"] >= z_cons[i + 1]["current_consecutive"]


def test_pingte_zodiac_history_endpoint(user_client, seeded_draws):
    res = user_client.get("/collector/pingte-zodiac-history?lottery=macau&xiao=马&limit=50")
    assert res["ok"] is True
    assert res["lottery"] == "macau"
    assert res["selected_xiao"] == "马"
    assert res["sample_periods"] > 0
    assert len(res["zodiacs"]) == 12

    zh = res["zodiac_history"]
    assert zh is not None
    assert zh["name"] == "马"
    assert zh["periods_count"] + zh["miss_periods_count"] == res["sample_periods"]
    assert zh["ping_count"] + zh["tema_count"] == zh["count"]
    assert isinstance(zh["segments"], list)
    assert len(zh["segments"]) > 0
    assert sum(seg["length"] for seg in zh["segments"]) == res["sample_periods"]
    for seg in zh["segments"]:
        assert seg["type"] in ("hit", "miss")
        assert seg["start_period"] <= seg["end_period"]
        assert seg["length"] >= 1
        assert ("连开" in seg["text"]) or ("没出" in seg["text"])
    assert len(zh["period_history"]) == res["sample_periods"]

    # Custom period range (including reversed bounds & short period numbers)
    res_range = user_client.get(
        "/collector/pingte-zodiac-history?lottery=macau&xiao=马&limit=1&period_from=2026248&period_to=2026247"
    )
    assert res_range["ok"] is True
    assert res_range["sample_scope"] == "range"
    assert res_range["sample_periods"] >= 2
    assert res_range["earliest_period"] == "2026247"
    assert res_range["latest_period"] == "2026248"


def test_pingte_ranking_year_scope_default(user_client, seeded_draws):
    """limit=0 / 缺省应统计当年全部期数（sample_scope=year）。"""
    from datetime import datetime, timezone, timedelta

    year = (datetime.now(timezone.utc) + timedelta(hours=8)).year
    res = user_client.get("/collector/pingte-ranking?lottery=macau&limit=0")
    assert res["ok"] is True
    assert res.get("sample_scope") == "year"
    assert res.get("sample_year") == year
    assert res["sample_periods"] > 0
    # 区间应落在当年 period 前缀内
    assert str(res["earliest_period"]).startswith(str(year))
    assert str(res["latest_period"]).startswith(str(year))

    # 显式最近 N 期仍可用
    res50 = user_client.get("/collector/pingte-ranking?lottery=macau&limit=50")
    assert res50["ok"] is True
    assert res50.get("sample_scope") == "limit"
    assert "prev_tema_pingte" in res50
    assert res50["prev_tema_pingte"]["evaluated_periods"] == max(0, res50["sample_periods"] - 1)


def test_pingte_prev_tema_endpoint(user_client, seeded_draws):
    """测试上期特码生肖落当期平特统计接口（当年概率、连续出现区间、连续缺失区间、逐期比对明细）。"""
    res = user_client.get("/collector/pingte-prev-tema?lottery=macau&limit=0")
    assert res["ok"] is True
    assert res["lottery"] == "macau"
    assert res["sample_scope"] == "year"
    assert res["total_draws"] >= 2
    assert res["evaluated_periods"] == res["total_draws"] - 1
    assert res["sample_periods"] == res["evaluated_periods"]
    assert res["periods_count"] + res["miss_periods_count"] == res["evaluated_periods"]
    assert 0.0 <= res["probability"] <= 100.0
    assert res["latest_tema_ref"] is not None
    assert "tema" in res["latest_tema_ref"]
    assert "tema_xiao" in res["latest_tema_ref"]

    pt = res["prev_tema_pingte"]
    assert pt["evaluated_periods"] == res["evaluated_periods"]
    assert sum(seg["length"] for seg in pt["segments"]) == res["evaluated_periods"]
    for seg in pt["segments"]:
        assert seg["type"] in ("hit", "miss")
        assert ("连续出现" in seg["text"]) or ("连续缺失" in seg["text"])
    assert len(pt["period_history"]) == res["evaluated_periods"]
    p0 = pt["period_history"][0]
    assert "prev_period" in p0
    assert "prev_tema" in p0
    assert "prev_tema_xiao" in p0
    assert len(p0["all_balls"]) == 7

    # 别名路由与自定义期号区间
    res_range = user_client.get(
        "/collector/pingte-prev-tema-history?lottery=macau&limit=1&period_from=2026248&period_to=2026247"
    )
    assert res_range["ok"] is True
    assert res_range["sample_scope"] == "range"
    assert res_range["earliest_draw_period"] == "2026247"
    assert res_range["latest_period"] == "2026248"
    assert res_range["evaluated_periods"] == res_range["total_draws"] - 1



