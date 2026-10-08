"""Full-year zodiac export with date-specific mapping and within-draw repeats."""
from contextlib import contextmanager
from datetime import date, datetime, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.services.ai import zodiac_streak
from tests.crypto_client import ApiError


@pytest.fixture
def year_draws(monkeypatch):
    import db
    from schema import Draw

    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Draw.__table__.create(engine)

    @contextmanager
    def session_scope(guard=False):
        with Session(engine) as session:
            yield session

    monkeypatch.setattr(db, "session_scope", session_scope)

    def add(period, draw_date, balls=None, lottery="macau"):
        balls = balls or ["01", "13", "25", "02", "14", "03", "37"]
        with Session(engine) as session:
            session.add(Draw(
                lottery=lottery, period=period, period_raw=period,
                draw_date=draw_date, source="year-export-test",
                **dict(zip(("z1", "z2", "z3", "z4", "z5", "z6", "tema"), balls)),
            ))
            session.commit()

    yield add
    engine.dispose()


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch):
    class FixedDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 10, 8, tzinfo=timezone.utc).astimezone(tz)

    monkeypatch.setattr(zodiac_streak, "datetime", FixedDateTime)


def test_year_filters_dates_and_lottery_and_orders_all_draws(year_draws):
    year_draws("2026003", date(2026, 10, 8))
    year_draws("2026001", date(2026, 1, 1))
    year_draws("2026002", date(2026, 2, 17))
    year_draws("2025365", date(2025, 12, 31))
    year_draws("2027001", date(2027, 1, 1))
    year_draws("2026004", date(2026, 10, 9))  # Not opened yet.
    year_draws("2026001", date(2026, 1, 1), lottery="hk")

    result = zodiac_streak.get_zodiac_by_year()
    assert result["year"] == 2026
    assert result["total_periods"] == 3
    assert [row["period"] for row in result["periods"]] == ["2026001", "2026002", "2026003"]
    assert zodiac_streak.get_zodiac_by_year(lottery="hk")["total_periods"] == 1
    assert zodiac_streak.get_zodiac_by_year(year=2025)["total_periods"] == 1


def test_zodiac_mapping_changes_at_lunar_new_year_and_includes_tema_repeats(year_draws):
    year_draws("2026047", date(2026, 2, 16))
    year_draws("2026048", date(2026, 2, 17))

    before, after = zodiac_streak.get_zodiac_by_year()["periods"]
    assert before["xiaos"] == ["蛇", "蛇", "蛇", "龙", "龙", "兔", "蛇"]
    assert after["xiaos"] == ["马", "马", "马", "蛇", "蛇", "龙", "马"]
    assert after["has_repeated_xiao"] is True
    assert after["repeated_xiaos"] == [
        {"xiao": "马", "count": 4, "positions": ["正1", "正2", "正3", "特码"]},
        {"xiao": "蛇", "count": 2, "positions": ["正4", "正5"]},
    ]
    assert len(after["balls"]) == len(after["xiaos"]) == 7


def test_no_repeats_and_empty_year_are_explicit(year_draws):
    year_draws("2026001", date(2026, 1, 1), ["01", "02", "03", "04", "05", "06", "07"])
    row = zodiac_streak.get_zodiac_by_year()["periods"][0]
    assert row["has_repeated_xiao"] is False
    assert row["repeated_xiaos"] == []
    empty = zodiac_streak.get_zodiac_by_year(year=2024)
    assert empty["periods"] == []
    assert empty["total_periods"] == 0


def test_year_export_has_no_recent_period_limit(year_draws):
    for index in range(501):
        year_draws(f"2026{index:04}", date(2026, 1, 1))
    result = zodiac_streak.get_zodiac_by_year()
    assert result["total_periods"] == 501
    assert result["periods"][0]["period"] == "20260000"
    assert result["periods"][-1]["period"] == "20260500"


def test_default_year_uses_beijing_time(year_draws, monkeypatch):
    class NewYearDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 12, 31, 16, 30, tzinfo=timezone.utc).astimezone(tz)

    monkeypatch.setattr(zodiac_streak, "datetime", NewYearDateTime)
    year_draws("2027001", date(2027, 1, 1))
    result = zodiac_streak.get_zodiac_by_year()
    assert result["year"] == 2027
    assert result["total_periods"] == 1


def test_year_data_api_is_available_to_signed_in_users(user_client, year_draws):
    year_draws("2026001", date(2026, 1, 1))
    result = user_client.get("/ai/zodiac-year-data", params={"lottery": "macau"})
    assert result["ok"] is True
    assert result["year"] == 2026
    assert result["periods"][0]["repeated_xiaos"][0]["count"] == 4


@pytest.mark.parametrize("params", [{"lottery": "invalid"}, {"year": 9999}, {"year": "no-year"}])
def test_year_data_api_validates_filters(user_client, params):
    with pytest.raises(ApiError) as exc:
        user_client.get("/ai/zodiac-year-data", params=params)
    assert exc.value.status_code == 422


def test_year_data_requires_login(crypto_client):
    with pytest.raises(ApiError) as exc:
        crypto_client.get("/ai/zodiac-year-data")
    assert exc.value.status_code == 401
