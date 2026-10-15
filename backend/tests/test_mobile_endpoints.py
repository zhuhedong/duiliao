"""Tests for the /app/* mobile endpoints and the subscription routes."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from tests.crypto_client import ApiError


# --------------------------------------------------------------------------- #
# Home aggregation
# --------------------------------------------------------------------------- #
def test_home_returns_a_complete_structure_even_with_no_data(user_client):
    """A sparse database must degrade to nulls, not a 500."""
    body = user_client.get("/app/home", params={"lottery": "taiwan"})
    assert body["ok"] is True
    assert body["lottery"] == "taiwan"
    for key in (
        "latest_draw",
        "consensus",
        "comparison_summary",
        "ratings_top",
        "recent_jobs",
        "collect_worker",
        "server_time",
        "rule_version",
    ):
        assert key in body, f"missing home block: {key}"


def test_home_includes_the_latest_draw_once_seeded(user_client, seeded_draws):
    body = user_client.get("/app/home", params={"lottery": "macau"})
    assert body["latest_draw"] is not None
    assert body["latest_draw"]["period"] == "2026248"
    # Ball attributes are needed to render the home card without a second call.
    assert body["latest_draw"]["tema"]
    assert body["rule_version"] == "2026-09-06.2"


def test_home_rejects_an_unknown_lottery(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.get("/app/home", params={"lottery": "atlantis"})
    assert exc.value.status_code == 400


def test_home_survives_a_failing_block(user_client, monkeypatch, seeded_draws):
    """One broken dataset must not blank the whole screen."""
    from app import collector_bridge as cb

    def boom(*_a, **_k):
        raise RuntimeError("ratings engine down")

    monkeypatch.setattr(cb, "ratings", boom)
    body = user_client.get("/app/home", params={"lottery": "macau"})
    assert body["ok"] is True
    assert body["ratings_top"] is None
    # Unrelated blocks still populated.
    assert body["latest_draw"] is not None


def test_home_requires_authentication(crypto_client):
    with pytest.raises(ApiError) as exc:
        crypto_client.get("/app/home")
    assert exc.value.status_code == 401


def test_app_routes_require_an_encryption_session(raw_client):
    """Both protection layers apply to the new routes, not just JWT."""
    res = raw_client.get("/api/v1/app/home")
    assert res.status_code == 401
    assert res.json()["code"] == "no_session"


# --------------------------------------------------------------------------- #
# Version / force update
# --------------------------------------------------------------------------- #
def test_version_rejects_an_unknown_platform(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.get("/app/version", params={"platform": "blackberry"})
    assert exc.value.status_code == 400


def test_version_is_quiet_when_nothing_is_configured(user_client):
    body = user_client.get("/app/version", params={"platform": "android", "current": "1.0.0"})
    assert body["ok"] is True
    assert body["update_required"] is False
    assert body["update_available"] is False


def test_version_flags_required_and_available_updates(user_client, db_session):
    from app.services.settings_service import set_setting_value

    set_setting_value(db_session, "app_android_latest_version", "2.4.0")
    set_setting_value(db_session, "app_android_min_version", "2.0.0")
    set_setting_value(db_session, "app_android_download_url", "https://example.test/app.apk")
    db_session.commit()

    old = user_client.get("/app/version", params={"platform": "android", "current": "1.9.9"})
    assert old["update_required"] is True
    assert old["update_available"] is True
    assert old["download_url"] == "https://example.test/app.apk"

    mid = user_client.get("/app/version", params={"platform": "android", "current": "2.1.0"})
    assert mid["update_required"] is False
    assert mid["update_available"] is True

    current = user_client.get("/app/version", params={"platform": "android", "current": "2.4.0"})
    assert current["update_required"] is False
    assert current["update_available"] is False


def test_version_comparison_is_numeric_not_lexicographic(user_client, db_session):
    """'2.10.0' must be newer than '2.9.0', which string compare gets wrong."""
    from app.services.settings_service import set_setting_value

    set_setting_value(db_session, "app_ios_latest_version", "2.10.0")
    set_setting_value(db_session, "app_ios_min_version", "2.10.0")
    db_session.commit()

    body = user_client.get("/app/version", params={"platform": "ios", "current": "2.9.0"})
    assert body["update_required"] is True


def test_version_tolerates_a_build_suffix(user_client, db_session):
    from app.services.settings_service import set_setting_value

    set_setting_value(db_session, "app_android_min_version", "2.0.0")
    db_session.commit()
    body = user_client.get(
        "/app/version", params={"platform": "android", "current": "2.1.0+42"}
    )
    assert body["update_required"] is False


# --------------------------------------------------------------------------- #
# Subscriptions
# --------------------------------------------------------------------------- #
def test_subscriptions_default_when_never_saved(user_client):
    body = user_client.get("/users/me/subscriptions")
    assert body["ok"] is True
    assert body["source_ids"] == []
    # Defaults must be present so the settings screen has switches to render.
    assert body["notify_rules"]["draw_published"] is True
    assert body["notify_rules"]["miss_streak_threshold"] == 3


def test_subscription_put_is_idempotent(user_client, fixture_sources):
    payload = {
        "source_ids": fixture_sources,
        "lotteries": ["macau"],
        "play_types": ["pingte_xiao"],
        "notify_rules": {"draw_published": False, "collect_job_finished": True},
    }
    first = user_client.put("/users/me/subscriptions", payload)
    second = user_client.put("/users/me/subscriptions", payload)
    for key in ("source_ids", "lotteries", "play_types"):
        assert first[key] == second[key] == payload[key]
    assert second["notify_rules"]["draw_published"] is False
    assert second["notify_rules"]["collect_job_finished"] is True

    fetched = user_client.get("/users/me/subscriptions")
    assert fetched["source_ids"] == fixture_sources


def test_subscription_rejects_unknown_source_ids(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.put("/users/me/subscriptions", {"source_ids": ["not_a_real_source"]})
    assert exc.value.status_code == 400
    assert "not_a_real_source" in exc.value.message


def test_subscription_rejects_unknown_lottery_and_play_type(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.put("/users/me/subscriptions", {"lotteries": ["atlantis"]})
    assert exc.value.status_code == 400

    with pytest.raises(ApiError) as exc:
        user_client.put("/users/me/subscriptions", {"play_types": ["not_a_play"]})
    assert exc.value.status_code == 400


def test_subscription_drops_unknown_rule_keys(user_client):
    body = user_client.put(
        "/users/me/subscriptions",
        {"notify_rules": {"draw_published": True, "bogus_rule": True}},
    )
    assert "bogus_rule" not in body["notify_rules"]


def test_subscription_deduplicates_source_ids(user_client, fixture_sources):
    dupes = fixture_sources + fixture_sources
    body = user_client.put("/users/me/subscriptions", {"source_ids": dupes})
    assert body["source_ids"] == fixture_sources


def test_subscriptions_are_per_user(user_client, staff_client, fixture_sources):
    user_client.put("/users/me/subscriptions", {"source_ids": [fixture_sources[0]]})
    staff_client.put("/users/me/subscriptions", {"source_ids": [fixture_sources[1]]})
    assert user_client.get("/users/me/subscriptions")["source_ids"] == [fixture_sources[0]]
    assert staff_client.get("/users/me/subscriptions")["source_ids"] == [fixture_sources[1]]


# --------------------------------------------------------------------------- #
# Event feed
# --------------------------------------------------------------------------- #
def test_events_rejects_a_malformed_cursor(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.get("/app/events", params={"since": "not-a-timestamp"})
    assert exc.value.status_code == 400


def test_a_future_cursor_returns_nothing(user_client, seeded_draws):
    future = (datetime.now(timezone.utc) + timedelta(days=3650)).isoformat()
    body = user_client.get("/app/events", params={"since": future})
    assert body["count"] == 0
    assert body["events"] == []
    # With nothing new the cursor must not move backwards.
    assert body["next_cursor"] is not None


def test_draw_events_are_emitted_and_the_cursor_advances(user_client, seeded_draws):
    body = user_client.get("/app/events", params={"lottery": "macau", "limit": 50})
    draw_events = [e for e in body["events"] if e["type"] == "draw_published"]
    assert draw_events, "expected draw_published events for the seeded draws"
    assert all(e["occurred_at"] for e in draw_events)
    assert body["next_cursor"].startswith("v1."), "new cursors include a timestamp tie-breaker"

    # Replaying with the returned cursor must not re-deliver the same events.
    again = user_client.get(
        "/app/events", params={"lottery": "macau", "since": body["next_cursor"], "limit": 50}
    )
    assert not [e for e in again["events"] if e["type"] == "draw_published"]


def test_events_are_ordered_oldest_first(user_client, seeded_draws):
    body = user_client.get("/app/events", params={"limit": 50})
    stamps = [e["occurred_at"] for e in body["events"]]
    assert stamps == sorted(stamps)


def test_disabled_rules_suppress_their_events(user_client, seeded_draws):
    user_client.put("/users/me/subscriptions", {"notify_rules": {"draw_published": False}})
    body = user_client.get("/app/events", params={"lottery": "macau", "limit": 50})
    assert not [e for e in body["events"] if e["type"] == "draw_published"]

    user_client.put("/users/me/subscriptions", {"notify_rules": {"draw_published": True}})
    body = user_client.get("/app/events", params={"lottery": "macau", "limit": 50})
    assert [e for e in body["events"] if e["type"] == "draw_published"]


def test_finished_jobs_produce_events(user_client, staff_client, fixture_sources):
    from app import collector_bridge as cb

    job = cb.create_collect_job(lottery="macau", period="248", source_ids=fixture_sources)
    cb.finish_collect_job(
        job["id"], "done", result={"ok": True}, run_id="test-run", period="2026248"
    )

    body = user_client.get("/app/events", params={"lottery": "macau", "limit": 100})
    job_events = [e for e in body["events"] if e["type"] == "collect_job_finished"]
    assert job_events
    assert any(e["data"]["job_id"] == job["id"] for e in job_events)


def test_unfollowed_sources_produce_no_hit_events(user_client, seeded_draws, fixture_sources):
    """source_hit is only meaningful for followed sources."""
    user_client.put(
        "/users/me/subscriptions",
        {"source_ids": [], "notify_rules": {"source_hit": True}},
    )
    body = user_client.get("/app/events", params={"lottery": "macau", "limit": 100})
    assert not [e for e in body["events"] if e["type"] == "source_hit"]


def test_limit_is_respected_and_reports_truncation(user_client, seeded_draws):
    body = user_client.get("/app/events", params={"limit": 1})
    assert len(body["events"]) <= 1
    assert isinstance(body["has_more"], bool)


def test_events_requires_authentication(crypto_client):
    with pytest.raises(ApiError) as exc:
        crypto_client.get("/app/events")
    assert exc.value.status_code == 401


# --------------------------------------------------------------------------- #
# Consensus leader tracking
# --------------------------------------------------------------------------- #
def test_first_leader_observation_is_not_reported_as_a_change():
    """There is no prior leader to move away from, so nothing should fire."""
    from app import collector_bridge as cb
    from db import session_scope
    from schema import ConsensusLeader

    with session_scope() as s:
        s.add(
            ConsensusLeader(
                lottery="macau",
                period="2026900",
                play_type="pingte_xiao",
                leader_key="xiao:猪",
                leader_votes=3,
                previous_key=None,
            )
        )

    changes = cb.list_consensus_leader_changes()
    assert not [c for c in changes if c["period"] == "2026900"]


def test_a_leader_change_is_reported_with_its_previous_value():
    from app import collector_bridge as cb
    from db import session_scope
    from schema import ConsensusLeader

    with session_scope() as s:
        s.add(
            ConsensusLeader(
                lottery="macau",
                period="2026901",
                play_type="pingte_xiao",
                leader_key="xiao:兔",
                leader_votes=5,
                previous_key="xiao:猪",
            )
        )

    changes = cb.list_consensus_leader_changes()
    row = next(c for c in changes if c["period"] == "2026901")
    assert row["leader_key"] == "xiao:兔"
    assert row["previous_key"] == "xiao:猪"


def test_leader_key_is_order_insensitive():
    from app.collector_bridge import _leader_key

    a = _leader_key([{"kind": "xiao", "value": "兔"}, {"kind": "xiao", "value": "猪"}])
    b = _leader_key([{"kind": "xiao", "value": "猪"}, {"kind": "xiao", "value": "兔"}])
    assert a == b
    assert _leader_key([]) == ""
    assert _leader_key(None) == ""


# --------------------------------------------------------------------------- #
# Betting records: server storage, 龙兔各数5 expansion & auto draw settlement
# --------------------------------------------------------------------------- #
def test_betting_record_long_tu_geshu_5_expansion_and_storage(user_client):
    created = user_client.post(
        "/app/records",
        {
            "lottery": "macau",
            "period": "2026999",
            "mode": "号码单式",
            "play_type": "正码",
            "raw_input": "龙兔各数5",
        },
    )
    assert created["ok"] is True
    rec = created["record"]
    assert rec["numbers"] == ["03", "15", "27", "39", "04", "16", "28", "40"]
    assert rec["stake_per_note"] == 5
    assert rec["notes_count"] == 8
    assert rec["total_amount"] == 40
    assert rec["status"] == "pending"

    listed = user_client.get("/app/records", params={"lottery": "macau"})
    assert listed["ok"] is True
    matched = [r for r in listed["items"] if r["id"] == rec["id"]]
    assert len(matched) == 1
    assert matched[0]["numbers"] == ["03", "15", "27", "39", "04", "16", "28", "40"]
    assert matched[0]["total_amount"] == 40


def test_betting_record_auto_settlement_when_draw_published(user_client):
    from app import collector_bridge as cb

    created = user_client.post(
        "/app/records",
        {
            "lottery": "macau",
            "period": "2026201",
            "mode": "号码单式",
            "play_type": "正码",
            "raw_input": "龙兔各数5",
        },
    )
    rec_id = created["record"]["id"]
    assert created["record"]["status"] == "pending"
    assert created["record"]["total_amount"] == 40

    # Simulate official draw arriving for 2026201 via cb.sync_draws:
    # 03 (龙), 15 (龙), and 28 (兔) are drawn -> 3 hits × ¥5 × 7 odds = ¥105 payout, +¥65 net profit
    sync_res = cb.sync_draws(
        "macau",
        draws=[
            {
                "lottery": "macau",
                "period": "2026201",
                "period_raw": "201",
                "draw_date": "2026-07-20",
                "openCode": "03,15,19,22,31,45,28",
                "source": "fixture:official",
            }
        ],
    )
    assert sync_res.get("betting_records_settled", 0) >= 1

    listed = user_client.get("/app/records", params={"lottery": "macau"})
    settled_rec = next(r for r in listed["items"] if r["id"] == rec_id)
    assert settled_rec["status"] == "won"
    assert settled_rec["hit_numbers"] == ["03", "15", "28"]
    assert settled_rec["payout"] == 105
    assert settled_rec["net_profit"] == 65
    assert settled_rec["win_pill_label"] == "中 3 码 +¥65"

    deleted = user_client.delete(f"/app/records/{rec_id}")
    assert deleted["ok"] is True
    assert deleted["deleted"] is True


def test_betting_record_multi_link_fushi_3_4_and_settlement(user_client):
    from app import collector_bridge as cb

    # "鼠虎马猴鸡 给我打复试3，4连一组5块" -> 5肖复试 3,4连: C(5,3)=10 + C(5,4)=5 = 15组 × ¥5 = ¥75
    created = user_client.post(
        "/app/records",
        {
            "lottery": "macau",
            "period": "2026202",
            "raw_input": "鼠虎马猴鸡 给我打复试3，4连一组5块",
        },
    )
    assert created["ok"] is True
    rec = created["record"]
    assert rec["mode"] == "连肖复试"
    assert rec["xiaos"] == ["鼠", "虎", "马", "猴", "鸡"]
    assert rec["numbers"] == []
    assert rec["fushi_links"] == [3, 4]
    assert rec["stake_per_note"] == 5
    assert rec["notes_count"] == 15
    assert rec["total_amount"] == 75
    assert rec["status"] == "pending"

    # Simulate draw where 鼠(07), 虎(05), 马(01), 猴(11) all appear (4 of the 5 zodiacs hit):
    # - 3连 hits C(4,3) = 4 groups
    # - 4连 hits C(4,4) = 1 group
    # Total hit_notes = 5
    sync_res = cb.sync_draws(
        "macau",
        draws=[
            {
                "lottery": "macau",
                "period": "2026202",
                "period_raw": "202",
                "draw_date": "2026-07-21",
                "openCode": "07,05,01,11,03,04,16",
                "source": "fixture:official",
            }
        ],
    )
    assert sync_res.get("betting_records_settled", 0) >= 1

    listed = user_client.get("/app/records", params={"lottery": "macau"})
    settled_rec = next(r for r in listed["items"] if r["id"] == rec["id"])
    assert settled_rec["status"] == "won"
    assert settled_rec["hit_numbers"] == ["鼠", "虎", "马", "猴"]
    assert settled_rec["payout"] == 325  # (鼠虎马 45 + 鼠虎猴 50 + 鼠马猴 45 + 虎马猴 45) + (鼠虎马猴 140) = 325
    assert settled_rec["net_profit"] == 250
    assert settled_rec["win_pill_label"] == "中 5 注 +¥250"


    cleared = user_client.delete("/app/records", params={"lottery": "macau"})
    assert cleared["ok"] is True
    assert cleared["deleted_count"] >= 1
    after_clear = user_client.get("/app/records", params={"lottery": "macau"})
    assert after_clear["items"] == []


def test_lianxiao_odds_with_and_without_ma():
    from app.services.betting_records_service import default_odds_for, lianxiao_odds

    # 1. Verification of user-configured table
    # 不带马: 2=4.0, 3=10.0, 4=30.0, 5=100.0
    assert lianxiao_odds(2, has_ma=False) == 4.0
    assert lianxiao_odds(3, has_ma=False) == 10.0
    assert lianxiao_odds(4, has_ma=False) == 30.0
    assert lianxiao_odds(5, has_ma=False) == 100.0

    # 带马: 2=3.8, 3=9.0, 4=28.0, 5=80.0
    assert lianxiao_odds(2, has_ma=True) == 3.8
    assert lianxiao_odds(3, has_ma=True) == 9.0
    assert lianxiao_odds(4, has_ma=True) == 28.0
    assert lianxiao_odds(5, has_ma=True) == 80.0

    # 2. default_odds_for inferring from xiaos
    assert default_odds_for("3连肖", xiaos=["鼠", "虎", "猴"]) == 10.0
    assert default_odds_for("3连肖", xiaos=["鼠", "虎", "马"]) == 9.0
    assert default_odds_for("2连肖", xiaos=["鼠", "虎"]) == 4.0
    assert default_odds_for("2连肖", xiaos=["鼠", "马"]) == 3.8
    assert default_odds_for("4连肖", xiaos=["鼠", "虎", "兔", "龙"]) == 30.0
    assert default_odds_for("4连肖", xiaos=["鼠", "虎", "兔", "马"]) == 28.0
    assert default_odds_for("5连肖", xiaos=["鼠", "虎", "兔", "龙", "蛇"]) == 100.0
    assert default_odds_for("5连肖", xiaos=["鼠", "虎", "兔", "龙", "马"]) == 80.0


def test_betting_records_copy_single_and_batch_to_target_period(user_client):
    # 1. Create two records in period 2026203
    r1 = user_client.post(
        "/app/records",
        {
            "lottery": "macau",
            "period": "2026203",
            "raw_input": "龙兔各数5",
        },
    )
    assert r1["ok"] is True
    id1 = r1["record"]["id"]

    r2 = user_client.post(
        "/app/records",
        {
            "lottery": "macau",
            "period": "2026203",
            "raw_input": "03,15,28 特码各10",
        },
    )
    assert r2["ok"] is True
    id2 = r2["record"]["id"]

    # 2. Test copy_single_record: copy r1 into target period 2026287 (3-digit '287' test)
    copy_single_res = user_client.post(
        f"/app/records/{id1}/copy",
        {"target_period": "287"},
    )
    assert copy_single_res["ok"] is True
    copied_single = copy_single_res["record"]
    assert copied_single["id"] != id1
    assert copied_single["period"] == "2026287"
    assert copied_single["status"] == "pending"
    assert copied_single["total_amount"] == r1["record"]["total_amount"]
    assert "复制自2026203期" in (copied_single["source_badge"] or "")

    # 3. Test copy_records (batch/whole period): copy all records from 2026203 to 2026288
    copy_batch_res = user_client.post(
        "/app/records/copy",
        {
            "lottery": "macau",
            "source_period": "2026203",
            "target_period": "2026288",
        },
    )
    assert copy_batch_res["ok"] is True
    assert copy_batch_res["copied_count"] == 2
    batch_items = copy_batch_res["items"]
    assert len(batch_items) == 2
    for b in batch_items:
        assert b["period"] == "2026288"
        assert b["status"] == "pending"

    # Cleanup
    user_client.delete("/app/records")


def test_lianxiao_settlement_with_ma_5_yuan_yields_45_not_56():
    """Verify that a ¥5 bet on 3-lian containing '马' evaluates to ¥45 payout (not 56),

    even if an existing record in DB previously had legacy odds 11.2 and payout 56.
    """
    from app.services.betting_records_service import (
        UserBettingRecord,
        evaluate_record_against_draw,
        _sync_record_odds,
    )

    # 1. Stored legacy record with odds=11.2, payout=56
    legacy_rec = UserBettingRecord(
        user_id="test_user",
        lottery="macau",
        period="2026203",
        mode="连肖复试",
        play_type="3连肖",
        xiaos=["马", "羊", "猴"],
        numbers=[],
        stake_per_note=5,
        multiplier=1,
        notes_count=1,
        total_amount=5,
        odds=11.2,
        status="won",
        hit_numbers=["马", "羊", "猴"],
        hit_notes=1,
        payout=56,
        net_profit=51,
        raw_input="三连 马 羊 猴 各5块",
    )

    draw = {
        "lottery": "macau",
        "period": "2026203",
        "balls": ["01", "12", "11", "03", "04", "05"],  # 01=马, 12=羊, 11=猴
        "tema": "45",
    }

    # Evaluate against draw must auto-correct odds to 9.0 and payout to 45 (5 * 9.0 = 45)
    changed = evaluate_record_against_draw(legacy_rec, draw)
    assert changed is True
    assert legacy_rec.status == "won"
    assert legacy_rec.odds == 9.0
    assert legacy_rec.payout == 45
    assert legacy_rec.net_profit == 40  # 45 - 5 = 40

    # Running evaluate again must be stable and return False
    assert evaluate_record_against_draw(legacy_rec, draw) is False

    # 2. 3连 不带马 test: 5块 should yield 50 payout (5 * 10.0 = 50, net profit +45)
    rec_no_ma = UserBettingRecord(
        user_id="test_user",
        lottery="macau",
        period="2026203",
        mode="连肖复试",
        play_type="3连肖",
        xiaos=["牛", "羊", "猴"],
        numbers=[],
        stake_per_note=5,
        multiplier=1,
        notes_count=1,
        total_amount=5,
        odds=11.2,
        status="pending",
        hit_numbers=[],
        hit_notes=0,
        payout=0,
        net_profit=0,
        raw_input="三连 牛 羊 猴 各5块",
    )
    draw_no_ma = {
        "lottery": "macau",
        "period": "2026203",
        "balls": ["06", "12", "11", "03", "04", "05"],  # 06=牛, 12=羊, 11=猴
        "tema": "45",
    }
    changed_no_ma = evaluate_record_against_draw(rec_no_ma, draw_no_ma)
    assert changed_no_ma is True
    assert rec_no_ma.status == "won"
    assert rec_no_ma.odds == 10.0
    assert rec_no_ma.payout == 50
    assert rec_no_ma.net_profit == 45

    # 3. Test _sync_record_odds on pending record before draw
    pending_rec = UserBettingRecord(
        user_id="test_user",
        lottery="macau",
        period="2026204",
        mode="连肖复试",
        play_type="3连肖",
        xiaos=["马", "鸡", "狗"],
        numbers=[],
        stake_per_note=5,
        multiplier=1,
        notes_count=1,
        total_amount=5,
        odds=11.2,
        status="pending",
        hit_numbers=[],
        hit_notes=0,
        payout=0,
        net_profit=0,
        raw_input="三连 马 鸡 狗 各5块",
    )
    synced = _sync_record_odds(pending_rec)
    assert synced is True
    assert pending_rec.odds == 9.0


def test_lianxiao_2_with_ma_odds_is_3_8():
    """带马 2连赔率应为 3.8（不是旧的 3.5）；不带马 2连仍为 4.0。"""
    from app.services.betting_records_service import (
        UserBettingRecord,
        evaluate_record_against_draw,
        _sync_record_odds,
        lianxiao_odds,
    )

    assert lianxiao_odds(2, has_ma=True) == 3.8
    assert lianxiao_odds(2, has_ma=False) == 4.0

    # Pending record with legacy wrong odds 3.5 must sync to 3.8
    pending = UserBettingRecord(
        user_id="test_user",
        lottery="macau",
        period="2026205",
        mode="连肖复试",
        play_type="2连肖",
        xiaos=["马", "猴"],
        numbers=[],
        stake_per_note=5,
        multiplier=1,
        notes_count=1,
        total_amount=5,
        odds=3.5,
        status="pending",
        hit_numbers=[],
        hit_notes=0,
        payout=0,
        net_profit=0,
        raw_input="二连 马 猴 各5块",
    )
    assert _sync_record_odds(pending) is True
    assert pending.odds == 3.8

    # Settlement: ¥5 × 3.8 = ¥19 payout
    draw = {
        "lottery": "macau",
        "period": "2026205",
        "balls": ["01", "11", "03", "04", "05", "06"],  # 01=马, 11=猴
        "tema": "45",
    }
    rec = UserBettingRecord(
        user_id="test_user",
        lottery="macau",
        period="2026205",
        mode="连肖复试",
        play_type="2连肖",
        xiaos=["马", "猴"],
        numbers=[],
        stake_per_note=5,
        multiplier=1,
        notes_count=1,
        total_amount=5,
        odds=3.5,
        status="pending",
        hit_numbers=[],
        hit_notes=0,
        payout=0,
        net_profit=0,
        raw_input="二连 马 猴 各5块",
    )
    assert evaluate_record_against_draw(rec, draw) is True
    assert rec.status == "won"
    assert rec.odds == 3.8
    assert rec.payout == 19
    assert rec.net_profit == 14

    # 不带马 2连: ¥5 × 4.0 = ¥20
    rec2 = UserBettingRecord(
        user_id="test_user",
        lottery="macau",
        period="2026205",
        mode="连肖复试",
        play_type="2连肖",
        xiaos=["牛", "猴"],
        numbers=[],
        stake_per_note=5,
        multiplier=1,
        notes_count=1,
        total_amount=5,
        odds=3.5,
        status="pending",
        hit_numbers=[],
        hit_notes=0,
        payout=0,
        net_profit=0,
        raw_input="二连 牛 猴 各5块",
    )
    draw2 = {
        "lottery": "macau",
        "period": "2026205",
        "balls": ["06", "11", "03", "04", "05", "07"],  # 06=牛, 11=猴
        "tema": "45",
    }
    assert evaluate_record_against_draw(rec2, draw2) is True
    assert rec2.odds == 4.0
    assert rec2.payout == 20
    assert rec2.net_profit == 15
