from __future__ import annotations

import json
from unittest.mock import MagicMock, patch
import pytest

import draw_sync


def test_from_generic_with_n_keys():
    obj = {
        "periodStr": "2026263",
        "date": "2026-09-20",
        "n1": "44",
        "n2": "28",
        "n3": "03",
        "n4": "02",
        "n5": "24",
        "n6": "13",
        "n7": "09",
    }
    row = draw_sync.from_generic(obj, "macau", "test:getLastLottery")
    assert row["lottery"] == "macau"
    assert row["period"] == "2026263"
    assert row["period_raw"] == "263"
    assert str(row["draw_date"]) == "2026-09-20"
    assert [row[f"z{i}"] for i in range(1, 7)] == ["44", "28", "03", "02", "24", "13"]
    assert row["tema"] == "09"


def test_from_generic_legacy_open_code():
    obj = {
        "period": "2026248",
        "openTime": "2026-09-05",
        "openCode": "18,26,09,30,45,33,28",
    }
    row = draw_sync.from_generic(obj, "macau", "test:legacy")
    assert row["period"] == "2026248"
    assert [row[f"z{i}"] for i in range(1, 7)] == ["18", "26", "09", "30", "45", "33"]
    assert row["tema"] == "28"


def test_fetch_get_last_lottery_success():
    payload = {
        "code": 0,
        "message": "Success",
        "data": {
            "id": 20262632,
            "date": "2026-09-20",
            "period": 263,
            "periodStr": "2026263",
            "time": "21:30",
            "n1": "44",
            "n2": "28",
            "n3": "03",
            "n4": "02",
            "n5": "24",
            "n6": "13",
            "n7": "09",
            "status": True,
        },
    }
    mock_resp = MagicMock()
    mock_resp.json.return_value = payload

    with patch("common.http.get", return_value=mock_resp):
        rows = draw_sync.fetch_get_last_lottery(
            "https://kj2.kjkjkj-1.com/api/v1/index/getLastLottery",
            {"lotterytype": "2"},
            "macau",
        )
        assert len(rows) == 1
        r = rows[0]
        assert r["lottery"] == "macau"
        assert r["period"] == "2026263"
        assert r["tema"] == "09"
        assert [r[f"z{i}"] for i in range(1, 7)] == ["44", "28", "03", "02", "24", "13"]


def test_fetch_get_last_lottery_status_false():
    payload = {
        "code": 0,
        "message": "Success",
        "data": {
            "id": 20262642,
            "date": "2026-09-21",
            "period": 264,
            "periodStr": "2026264",
            "status": False,
        },
    }
    mock_resp = MagicMock()
    mock_resp.json.return_value = payload

    with patch("common.http.get", return_value=mock_resp):
        with pytest.raises(ValueError, match="尚未完成或尚未开奖"):
            draw_sync.fetch_get_last_lottery(
                "https://kj2.kjkjkj-1.com/api/v1/index/getLastLottery",
                {"lotterytype": "2"},
                "macau",
            )


def test_fetch_get_last_lottery_biz_error():
    payload = {"code": 500, "message": "Server Error", "data": None}
    mock_resp = MagicMock()
    mock_resp.json.return_value = payload

    with patch("common.http.get", return_value=mock_resp):
        with pytest.raises(ValueError, match="Server Error"):
            draw_sync.fetch_get_last_lottery("http://example.com", {}, "macau")


def test_fetch_get_trend_adaptive_last_lottery():
    # Calling fetch_get_trend with getLastLottery single-object data
    payload = {
        "code": 0,
        "data": {
            "date": "2026-09-20",
            "periodStr": "2026263",
            "n1": "44", "n2": "28", "n3": "03", "n4": "02", "n5": "24", "n6": "13", "n7": "09",
            "status": True,
        },
    }
    mock_resp = MagicMock()
    mock_resp.json.return_value = payload

    with patch("common.http.get", return_value=mock_resp):
        rows = draw_sync.fetch_get_trend("http://example.com/getLastLottery", {}, "macau")
        assert len(rows) == 1
        assert rows[0]["period"] == "2026263"
        assert rows[0]["tema"] == "09"


def test_fetch_get_last_lottery_adaptive_trend_items():
    # Calling fetch_get_last_lottery with getTrend list data
    payload = {
        "code": 0,
        "data": [
            {
                "period": "2026263",
                "date": "2026-09-20",
                "code": ["44", "28", "03", "02", "24", "13", "09"],
            }
        ],
    }
    mock_resp = MagicMock()
    mock_resp.json.return_value = payload

    with patch("common.http.get", return_value=mock_resp):
        rows = draw_sync.fetch_get_last_lottery("http://example.com/getTrend", {}, "macau")
        assert len(rows) == 1
        assert rows[0]["period"] == "2026263"
        assert rows[0]["tema"] == "09"
