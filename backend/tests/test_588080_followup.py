"""Follow-up: host-pool probe worker, catalog batch-enable, fetch notify hooks."""
from __future__ import annotations

from unittest.mock import patch

import pytest

from tests.crypto_client import ApiError


def test_host_pool_probe_reorders_healthy(tmp_root):
    from app import collector_bridge as cb

    cb.prepare_modules()
    import host_pool

    fake = {
        "schema": host_pool.SCHEMA,
        "updated_at": host_pool._now_iso(),
        "entry_urls": ["https://588080.com/"],
        "hosts": ["https://dead.example", "https://live.example"],
        "primary": "https://dead.example",
        "errors": [],
        "health": {},
    }
    with patch.object(host_pool, "save_api_hosts"):
        host_pool.save_pool(fake)

    def fake_health(host, **kwargs):
        ok = "live" in host
        return {
            "host": host,
            "ok": ok,
            "elapsed_ms": 1,
            "error": None if ok else "down",
            "checked_at": host_pool._now_iso(),
        }

    with patch.object(host_pool, "health_check", side_effect=fake_health), patch.object(
        host_pool, "save_api_hosts"
    ), patch.object(host_pool, "refresh") as refresh_mock:
        result = host_pool.probe()
        refresh_mock.assert_not_called()

    assert result["action"] == "probe"
    assert result["primary"] == "https://live.example"
    assert result["hosts"][0] == "https://live.example"
    assert result["health"]["https://dead.example"]["consecutive_failures"] == 1
    assert result["health"]["https://live.example"]["consecutive_failures"] == 0


def test_host_pool_probe_refreshes_when_all_fail(tmp_root):
    from app import collector_bridge as cb

    cb.prepare_modules()
    import host_pool

    with patch.object(host_pool, "save_api_hosts"):
        host_pool.save_pool(
            {
                "schema": host_pool.SCHEMA,
                "updated_at": host_pool._now_iso(),
                "entry_urls": ["https://588080.com/"],
                "hosts": ["https://dead.example"],
                "primary": "https://dead.example",
                "errors": [],
                "health": {},
            }
        )

    with patch.object(
        host_pool,
        "health_check",
        return_value={
            "host": "https://dead.example",
            "ok": False,
            "elapsed_ms": 1,
            "error": "down",
            "checked_at": host_pool._now_iso(),
        },
    ), patch.object(
        host_pool,
        "refresh",
        return_value={
            "schema": host_pool.SCHEMA,
            "hosts": ["https://new.example"],
            "primary": "https://new.example",
            "health": {"https://new.example": {"ok": True}},
            "errors": [],
            "entry_urls": ["https://588080.com/"],
            "updated_at": host_pool._now_iso(),
        },
    ) as refresh_mock, patch.object(host_pool, "save_api_hosts"):
        result = host_pool.probe()
        refresh_mock.assert_called_once()
    assert "refresh" in result.get("action", "")


def test_host_pool_scheduler_status_endpoint(user_client):
    body = user_client.get("/collector/host-pool/scheduler")
    assert body.get("ok") is True
    assert "interval_seconds" in body
    assert body["interval_seconds"] >= 300


def test_catalog_batch_enable_requires_confirm(staff_client):
    with pytest.raises(ApiError) as exc:
        staff_client.post(
            "/collector/catalog/batch-enable",
            {
                "confirm": False,
                "dry_run": False,
                "items": [
                    {
                        "action": "create_source",
                        "source_id": "dj_followup_demo",
                        "upstream_id": "999001",
                        "parser": "six_number_lines",
                    }
                ],
            },
        )
    assert exc.value.status_code in {400, 403}


def test_catalog_batch_enable_dry_run(staff_client):
    body = staff_client.post(
        "/collector/catalog/batch-enable",
        {
            "confirm": False,
            "dry_run": True,
            "items": [
                {
                    "action": "create_source",
                    "source_id": "dj_followup_demo",
                    "upstream_id": "999001",
                    "parser": "six_number_lines",
                    "source_name": "Followup Demo",
                },
                {
                    "action": "create_source",
                    "source_id": "dj_followup_bad",
                    "upstream_id": "999002",
                    "parser": "totally_unknown",
                },
            ],
        },
    )
    assert body["dry_run"] is True
    assert body["counts"]["create"] == 1
    assert body["counts"]["rejected"] >= 1
    assert any(item.get("will_create") for item in body["items"])
    assert any(not item.get("ok") for item in body["items"])


def test_fetch_hash_change_and_fail_streak_events():
    from app import collector_bridge as cb

    cb.prepare_modules()
    import fetch_observation as fo

    sid = "followup_hash_src"
    fo.record_observation(
        source_id=sid,
        lottery="macau",
        period="2026001",
        content_hash="aaa",
        ok=True,
    )
    fo.record_observation(
        source_id=sid,
        lottery="macau",
        period="2026002",
        content_hash="bbb",
        ok=True,
    )
    changes = fo.list_hash_change_events(None, lottery="macau", limit=20)
    assert any(
        e["source_id"] == sid and e["old_hash"] == "aaa" and e["new_hash"] == "bbb"
        for e in changes
    )

    fail_sid = "followup_fail_src"
    for i in range(3):
        fo.record_observation(
            source_id=fail_sid,
            lottery="macau",
            period=f"202610{i}",
            ok=False,
            error="timeout",
        )
    fails = fo.list_consecutive_failure_events(None, lottery="macau", threshold=3, limit=20)
    assert any(e["source_id"] == fail_sid and e["streak"] == 3 for e in fails)


def test_events_include_fetch_hash_changed(user_client):
    from app import collector_bridge as cb

    cb.prepare_modules()
    import fetch_observation as fo

    sid = "followup_event_src"
    fo.record_observation(source_id=sid, lottery="macau", content_hash="h1", ok=True)
    fo.record_observation(source_id=sid, lottery="macau", content_hash="h2", ok=True)

    user_client.put(
        "/users/me/subscriptions",
        {
            "source_ids": [],
            "lotteries": ["macau"],
            "play_types": [],
            "notify_rules": {
                "draw_published": False,
                "source_hit": False,
                "source_miss_streak": False,
                "consensus_leader_changed": False,
                "collect_job_finished": False,
                "fetch_hash_changed": True,
                "fetch_fail_streak": False,
            },
        },
    )
    page = user_client.get("/app/events", params={"lottery": "macau", "limit": 50})
    assert page.get("ok") is True
    types = {e.get("type") for e in page.get("events") or []}
    assert "fetch_hash_changed" in types
