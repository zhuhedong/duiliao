"""Tests for schedule execution logs API endpoints and per-source results persistence."""
from __future__ import annotations

import pytest
from app import collector_bridge as cb
from tests.crypto_client import ApiError


def test_schedule_logs_api_lifecycle(staff_client):
    # 1. Create a test schedule
    sched = cb.create_schedule(
        name="API-Test-Schedule",
        lottery="macau",
        source_ids=["tt_6xiao"],
        cron="*/15 * * * *",
        enabled=True,
    )
    sched_id = sched["id"]

    try:
        # 2. Add sample schedule logs directly via cb
        sources_sample = [
            {
                "source_id": "tt_6xiao",
                "source_name": "六肖中特",
                "ok": True,
                "exit_code": 0,
                "elapsed_ms": 120,
                "item_count": 1,
                "error_code": None,
                "error_msg": None,
                "data": {
                    "ok": True,
                    "items": [
                        {
                            "period": "2026248",
                            "preds": [{"kind": "xiao", "value": "牛"}],
                        }
                    ],
                },
                "raw_path": "out/raw/test/tt_6xiao.json",
            }
        ]

        log_row = cb.add_schedule_log(
            schedule_id=sched_id,
            schedule_name="API-Test-Schedule",
            lottery="macau",
            action="定时采集",
            status="success",
            detail="[定时采集] 采集完成: 期数 2026248, 成功 1/1 源",
            period="2026248",
            run_id="run_20260922_001",
            concurrency=8,
            duration_sec=1.23,
            source_total=1,
            source_ok=1,
            source_fail=0,
            sources_result=sources_sample,
            result={"ok": True, "source_total": 1, "source_ok": 1},
        )
        log_id = log_row["id"]

        # 3. Test GET /collector/schedules/{schedule_id}/logs
        res = staff_client.get(f"/collector/schedules/{sched_id}/logs")
        assert res["ok"] is True
        assert res["total"] >= 1
        assert len(res["logs"]) >= 1
        first_log = res["logs"][0]
        assert first_log["id"] == log_id
        assert first_log["schedule_id"] == sched_id
        assert first_log["action"] == "定时采集"
        assert first_log["status"] == "success"
        assert len(first_log["sources_result"]) == 1
        source_entry = first_log["sources_result"][0]
        assert source_entry["source_id"] == "tt_6xiao"
        assert source_entry["source_name"] == "六肖中特"
        assert source_entry["data"]["items"][0]["period"] == "2026248"

        # 4. Test GET /collector/schedules/logs (global logs endpoint)
        global_res = staff_client.get(
            "/collector/schedules/logs",
            params={"lottery": "macau", "status": "success", "limit": 10},
        )
        assert global_res["ok"] is True
        assert global_res["total"] >= 1
        matching = [item for item in global_res["items"] if item["id"] == log_id]
        assert len(matching) == 1
        assert matching[0]["sources_result"][0]["source_id"] == "tt_6xiao"

        # 5. Test GET /collector/schedules/logs/{log_id}
        detail_res = staff_client.get(f"/collector/schedules/logs/{log_id}")
        assert detail_res["ok"] is True
        assert detail_res["log"]["id"] == log_id
        assert detail_res["log"]["schedule_name"] == "API-Test-Schedule"
        assert len(detail_res["log"]["sources_result"]) == 1
        assert detail_res["log"]["sources_result"][0]["data"] is not None

        # 6. Test GET /collector/schedules/logs/{log_id} with non-existent id
        with pytest.raises(ApiError) as exc:
            staff_client.get("/collector/schedules/logs/9999999")
        assert exc.value.status_code == 404

    finally:
        cb.delete_schedule(sched_id)
