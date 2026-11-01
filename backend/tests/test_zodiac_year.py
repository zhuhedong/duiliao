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
    assert result["exclude_tema"] is False
    assert result["periods"][0]["repeated_xiaos"][0]["count"] == 4


def test_exclude_tema_filters_special_ball_from_zodiac_and_repeats(year_draws):
    year_draws("2026048", date(2026, 2, 17), balls=["01", "02", "03", "04", "05", "06", "37"])

    with_tema = zodiac_streak.get_zodiac_by_year(exclude_tema=False)
    assert with_tema["exclude_tema"] is False
    period_with = with_tema["periods"][0]
    assert len(period_with["balls"]) == 7
    assert len(period_with["xiaos"]) == 7
    assert period_with["has_repeated_xiao"] is True
    assert period_with["repeated_xiaos"] == [
        {"xiao": "马", "count": 2, "positions": ["正1", "特码"]}
    ]

    no_tema = zodiac_streak.get_zodiac_by_year(exclude_tema=True)
    assert no_tema["exclude_tema"] is True
    period_no = no_tema["periods"][0]
    assert len(period_no["balls"]) == 6
    assert len(period_no["xiaos"]) == 6
    assert period_no["balls"] == ["01", "02", "03", "04", "05", "06"]
    assert period_no["xiaos"] == ["马", "蛇", "龙", "兔", "虎", "牛"]
    assert period_no["has_repeated_xiao"] is False
    assert period_no["repeated_xiaos"] == []


def test_exclude_tema_preserves_repeats_among_positive_balls_while_dropping_special(year_draws):
    # 01 (马), 13 (马) are in positive balls. 25 (马) is in special ball (tema).
    year_draws("2026048", date(2026, 2, 17), balls=["01", "13", "02", "03", "04", "05", "25"])

    with_tema = zodiac_streak.get_zodiac_by_year(exclude_tema=False)
    p_with = with_tema["periods"][0]
    assert p_with["balls"] == ["01", "13", "02", "03", "04", "05", "25"]
    assert p_with["xiaos"] == ["马", "马", "蛇", "龙", "兔", "虎", "马"]
    assert p_with["has_repeated_xiao"] is True
    assert p_with["repeated_xiaos"] == [
        {"xiao": "马", "count": 3, "positions": ["正1", "正2", "特码"]}
    ]

    no_tema = zodiac_streak.get_zodiac_by_year(exclude_tema=True)
    p_no = no_tema["periods"][0]
    assert p_no["balls"] == ["01", "13", "02", "03", "04", "05"]
    assert p_no["xiaos"] == ["马", "马", "蛇", "龙", "兔", "虎"]
    assert p_no["has_repeated_xiao"] is True
    assert p_no["repeated_xiaos"] == [
        {"xiao": "马", "count": 2, "positions": ["正1", "正2"]}
    ]


@pytest.mark.parametrize(
    ("val", "expected"),
    [
        ("false", False),
        ("0", False),
        ("no", False),
        (False, False),
        (None, False),
        ("true", True),
        ("1", True),
        ("yes", True),
        (True, True),
    ],
)
def test_get_zodiac_by_year_normalizes_string_and_falsy_exclude_tema(year_draws, val, expected):
    year_draws("2026048", date(2026, 2, 17), balls=["01", "02", "03", "04", "05", "06", "37"])
    res = zodiac_streak.get_zodiac_by_year(exclude_tema=val)
    assert res["exclude_tema"] is expected
    assert len(res["periods"][0]["balls"]) == (6 if expected else 7)


def test_year_data_api_supports_exclude_tema(user_client, year_draws):
    year_draws("2026048", date(2026, 2, 17), balls=["01", "02", "03", "04", "05", "06", "37"])
    res_default = user_client.get("/ai/zodiac-year-data", params={"lottery": "macau"})
    assert res_default["exclude_tema"] is False
    assert len(res_default["periods"][0]["balls"]) == 7
    assert res_default["periods"][0]["has_repeated_xiao"] is True

    res_excluded = user_client.get(
        "/ai/zodiac-year-data",
        params={"lottery": "macau", "exclude_tema": "true"},
    )
    assert res_excluded["exclude_tema"] is True
    assert len(res_excluded["periods"][0]["balls"]) == 6
    assert res_excluded["periods"][0]["has_repeated_xiao"] is False


@pytest.mark.parametrize(
    "params",
    [
        {"lottery": "invalid"},
        {"year": 9999},
        {"year": "no-year"},
        {"exclude_tema": "invalid"},
    ],
)
def test_year_data_api_validates_filters(user_client, params):
    with pytest.raises(ApiError) as exc:
        user_client.get("/ai/zodiac-year-data", params=params)
    assert exc.value.status_code == 422


def test_year_data_requires_login(crypto_client):
    with pytest.raises(ApiError) as exc:
        crypto_client.get("/ai/zodiac-year-data")
    assert exc.value.status_code == 401
