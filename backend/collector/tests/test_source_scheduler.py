"""Tests for SourceScheduler, cron_util, and scheduled collection tasks."""
from __future__ import annotations

import asyncio
import os
import sys
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path

# Add backend and collector to sys.path
BASE_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = BASE_DIR / "collector"
for p in (str(BASE_DIR), str(COLLECTOR_DIR)):
    if p not in sys.path:
        sys.path.insert(0, p)

import cron_util
from app import collector_bridge as cb
from app.services.source_scheduler import source_scheduler


class TestCronUtil(unittest.TestCase):
    def test_cron_parsing(self):
        c = cron_util.CronSchedule("*/15 20-22 * * 1-5")
        self.assertIn(0, c.minutes)
        self.assertIn(15, c.minutes)
        self.assertIn(30, c.minutes)
        self.assertIn(45, c.minutes)
        self.assertNotIn(10, c.minutes)
        self.assertEqual(c.hours, {20, 21, 22})
        # 1-5 in cron is Mon-Fri, which maps to Python weekdays 0-4
        self.assertEqual(c.weekdays, {0, 1, 2, 3, 4})

    def test_pure_cron_next_occurrence(self):
        base = datetime(2026, 9, 20, 14, 11, 25, tzinfo=cron_util.TZ8)
        next_dt = cron_util.CronSchedule("*/15 * * * *").next_occurrence(base)
        self.assertEqual(next_dt, datetime(2026, 9, 20, 14, 15, 0, tzinfo=cron_util.TZ8))

    def test_future_start_at_with_cron(self):
        base = datetime(2026, 9, 20, 14, 0, 0, tzinfo=cron_util.TZ8)
        start = datetime(2026, 9, 20, 18, 30, 0, tzinfo=cron_util.TZ8)
        # Cron is every hour on the hour (0 * * * *)
        # At start_at (18:30), next occurrence should be 19:00:00
        next_dt = cron_util.compute_next_run(
            cron_expr="0 * * * *",
            start_at=start,
            base_time=base,
        )
        self.assertEqual(next_dt, datetime(2026, 9, 20, 19, 0, 0, tzinfo=cron_util.TZ8))

    def test_one_shot_task(self):
        base = datetime(2026, 9, 20, 14, 0, 0, tzinfo=cron_util.TZ8)
        start = datetime(2026, 9, 20, 15, 30, 0, tzinfo=cron_util.TZ8)
        # Future one-shot
        next_dt = cron_util.compute_next_run(
            cron_expr=None,
            start_at=start,
            base_time=base,
        )
        self.assertEqual(next_dt, start)

        # Already expired one-shot
        past_base = datetime(2026, 9, 20, 16, 0, 0, tzinfo=cron_util.TZ8)
        next_dt_past = cron_util.compute_next_run(
            cron_expr=None,
            start_at=start,
            base_time=past_base,
        )
        self.assertIsNone(next_dt_past)

    def test_end_at_expiration(self):
        base = datetime(2026, 9, 20, 14, 0, 0, tzinfo=cron_util.TZ8)
        end = datetime(2026, 9, 20, 14, 10, 0, tzinfo=cron_util.TZ8)
        # Cron next occurrence would be 14:15, but end is 14:10
        next_dt = cron_util.compute_next_run(
            cron_expr="*/15 * * * *",
            end_at=end,
            base_time=base,
        )
        self.assertIsNone(next_dt)


    def test_time_window_to_cron_same_hour(self):
        # 21:00 to 21:30 every 5 minutes
        expr = cron_util.time_window_to_cron("21:00", "21:30", 5)
        self.assertEqual(expr, "0-30/5 21 * * *")

        c = cron_util.CronSchedule(expr)
        base = datetime(2026, 9, 20, 21, 0, 0, tzinfo=cron_util.TZ8)
        self.assertEqual(c.next_occurrence(base), datetime(2026, 9, 20, 21, 5, 0, tzinfo=cron_util.TZ8))
        self.assertEqual(c.next_occurrence(datetime(2026, 9, 20, 21, 25, 0, tzinfo=cron_util.TZ8)),
                         datetime(2026, 9, 20, 21, 30, 0, tzinfo=cron_util.TZ8))

    def test_time_window_to_cron_cross_hour(self):
        # 20:45 to 21:30 every 5 minutes
        expr = cron_util.time_window_to_cron("20:45", "21:30", 5)
        self.assertEqual(expr, "45-59/5 20 * * *; 0-30/5 21 * * *")

        c = cron_util.CronSchedule(expr)
        self.assertTrue(c.is_composite)
        # At 20:55, next should be 21:00
        base = datetime(2026, 9, 20, 20, 55, 0, tzinfo=cron_util.TZ8)
        self.assertEqual(c.next_occurrence(base), datetime(2026, 9, 20, 21, 0, 0, tzinfo=cron_util.TZ8))

    def test_time_window_today_lifecycle(self):
        # When user configures: today 21:00 to 21:30 every 5 mins
        # start_at = 2026-09-20 21:00:00, end_at = 2026-09-20 21:30:00
        cron = "0-30/5 21 * * *"
        s_at = datetime(2026, 9, 20, 21, 0, 0, tzinfo=cron_util.TZ8)
        e_at = datetime(2026, 9, 20, 21, 30, 0, tzinfo=cron_util.TZ8)

        # Before start (e.g. 15:00): next run is exactly 21:00:00
        r1 = cron_util.compute_next_run(cron, start_at=s_at, end_at=e_at,
                                       base_time=datetime(2026, 9, 20, 15, 0, 0, tzinfo=cron_util.TZ8))
        self.assertEqual(r1, s_at)

        # After 21:00 run: next run is 21:05
        r2 = cron_util.compute_next_run(cron, start_at=s_at, end_at=e_at,
                                       base_time=datetime(2026, 9, 20, 21, 0, 0, tzinfo=cron_util.TZ8))
        self.assertEqual(r2, datetime(2026, 9, 20, 21, 5, 0, tzinfo=cron_util.TZ8))

        # After 21:25 run: next run is 21:30
        r3 = cron_util.compute_next_run(cron, start_at=s_at, end_at=e_at,
                                       base_time=datetime(2026, 9, 20, 21, 25, 0, tzinfo=cron_util.TZ8))
        self.assertEqual(r3, datetime(2026, 9, 20, 21, 30, 0, tzinfo=cron_util.TZ8))

        # After 21:30 run (window finished): next run is None -> task completes!
        r4 = cron_util.compute_next_run(cron, start_at=s_at, end_at=e_at,
                                       base_time=datetime(2026, 9, 20, 21, 30, 0, tzinfo=cron_util.TZ8))
        self.assertIsNone(r4)


class TestSourceSchedulerIntegration(unittest.TestCase):
    def setUp(self):
        self.created_ids: list[int] = []

    def tearDown(self):
        for sid in self.created_ids:
            try:
                cb.delete_schedule(sid)
            except Exception:
                pass

    def test_crud_and_trigger(self):
        now_cn = cron_util.now_cn()
        item = cb.create_schedule(
            name="UT-Macau-Periodic",
            lottery="macau",
            source_ids=["tt_6xiao"],
            cron="*/20 * * * *",
            start_at=now_cn,
            enabled=True,
            do_ingest=True,
            auto_judge=True,
        )
        self.created_ids.append(item["id"])
        self.assertEqual(item["name"], "UT-Macau-Periodic")
        self.assertIsNotNone(item["next_run_at"])

        # Update
        updated = cb.update_schedule(item["id"], name="UT-Macau-Updated", cron="*/30 * * * *")
        self.assertEqual(updated["name"], "UT-Macau-Updated")
        self.assertEqual(updated["cron"], "*/30 * * * *")

        # Trigger execution
        res = asyncio.run(source_scheduler.trigger_now(item["id"]))
        self.assertTrue(res.get("ok"))

        # Verify DB record updated
        persisted = cb.get_schedule(item["id"])
        self.assertEqual(persisted["last_status"], "success")
        self.assertIsNotNone(persisted["last_run_at"])

    def test_time_window_concurrency_execution(self):
        # Create a task with concurrency=8 and multiple sources
        sources = ["haige_pingte", "heizhuang_pingte", "wu_buzhong", "chengba_liuhe"]
        item = cb.create_schedule(
            name="UT-TimeWindow-Concurrent",
            lottery="macau",
            source_ids=sources,
            cron="0-30/5 21 * * *",
            enabled=True,
            do_ingest=True,
            auto_judge=True,
            spec={
                "concurrency": 8,
                "time_window_start": "21:00",
                "time_window_end": "21:30",
                "interval_minutes": 5,
                "window_date": "today",
            },
        )
        self.created_ids.append(item["id"])
        self.assertEqual(item["spec"]["concurrency"], 8)
        self.assertEqual(item["spec"]["time_window_start"], "21:00")

        # Trigger execution with thread pool concurrency
        res = asyncio.run(source_scheduler.trigger_now(item["id"]))
        self.assertTrue(res.get("ok"))
        # Should collect all 4 sources concurrently
        self.assertEqual(res.get("source_total"), 4)
        self.assertEqual(res.get("source_ok"), 4)


if __name__ == "__main__":
    unittest.main()
