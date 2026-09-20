"""Background scheduler for periodic/delayed data source collection tasks."""
from __future__ import annotations

import asyncio
import logging
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any

from app import collector_bridge as cb

logger = logging.getLogger("app.services.source_scheduler")
TZ8 = timezone(timedelta(hours=8))

# Ensure collector directory is on sys.path for cron_util
COLLECTOR_DIR = Path(__file__).resolve().parent.parent.parent / "collector"
if str(COLLECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_DIR))
import cron_util


def _now_str() -> str:
    return cron_util.now_cn().strftime("%Y-%m-%d %H:%M:%S")


class SourceScheduler:
    """Manages scheduled data collection jobs for prediction sources.

    Supports:
    - Standard 5-field cron expressions (e.g. '*/15 * * * *', '30 20 * * *').
    - Specific start time (delayed start / one-off execution).
    - Combined start time + cron recurrence + optional end time.
    - Manual immediate trigger anytime.
    - Persistent state and execution logs in database (pred.db).
    """

    def __init__(self) -> None:
        self.running: bool = False
        self.check_interval_seconds: int = 5
        self.recent_logs: list[dict[str, Any]] = []
        self._trigger_event: asyncio.Event = asyncio.Event()
        self._running_tasks: set[int] = set()

    def _add_log(
        self,
        schedule_id: int,
        schedule_name: str,
        lottery: str,
        status: str,
        message: str,
        result: dict[str, Any] | None = None,
    ) -> None:
        entry = {
            "timestamp": _now_str(),
            "schedule_id": schedule_id,
            "schedule_name": schedule_name,
            "lottery": lottery,
            "status": status,
            "message": message,
            "result": result,
        }
        self.recent_logs.insert(0, entry)
        if len(self.recent_logs) > 100:
            self.recent_logs = self.recent_logs[:100]

    def wake(self) -> None:
        """Wake up the worker immediately when tasks are added or modified."""
        self._trigger_event.set()

    async def _execute_single_schedule(self, item: dict[str, Any], manual: bool = False) -> dict[str, Any]:
        """Run one collection task in a background thread."""
        sid = item["id"]
        sname = item.get("name") or f"Task-{sid}"
        lottery = item.get("lottery") or "macau"
        period = item.get("period")
        source_ids = item.get("source_ids")
        do_ingest = item.get("do_ingest", True)
        auto_judge = item.get("auto_judge", True)

        concurrency = 8
        spec = item.get("spec")
        if isinstance(spec, dict) and "concurrency" in spec:
            try:
                concurrency = max(1, min(int(spec["concurrency"]), 32))
            except Exception:
                concurrency = 8

        now_cn = cron_util.now_cn()
        tag = "手动触发" if manual else "定时采集"
        logger.info(
            "[%s] 开始执行采集任务: #%d (%s), 彩种=%s, 期数=%s, 线程池并发=%d",
            tag,
            sid,
            sname,
            lottery,
            period or "auto",
            concurrency,
        )

        try:
            # 1. Run collection via thread pool (subprocesses run in ThreadPoolExecutor)
            res = await asyncio.to_thread(
                cb.collect,
                lottery=lottery,
                period=period,
                source_ids=source_ids,
                do_ingest=do_ingest,
                concurrency=concurrency,
            )

            # 2. If auto_judge is enabled and a period is known or detected, judge
            judged_info = None
            detected_period = res.get("period")
            judge_period = period or (detected_period if detected_period != "auto" else None)
            if auto_judge and judge_period and do_ingest:
                try:
                    judged_info = await asyncio.to_thread(cb.judge, lottery=lottery, period=judge_period)
                except Exception as je:
                    logger.warning("[%s] 自动对奖异常: %s", tag, je)

            # 3. Compute next scheduled run
            next_run = cron_util.compute_next_run(
                cron_expr=item.get("cron"),
                start_at=item.get("start_at"),
                end_at=item.get("end_at"),
                base_time=now_cn,
            )

            # If no next run (one-shot completed or end_at exceeded), disable the task
            next_enabled = None
            if not manual and next_run is None:
                next_enabled = 0

            summary = {
                "ok": res.get("ok", True),
                "run_id": res.get("run_id"),
                "period": res.get("period"),
                "source_total": res.get("source_total", 0),
                "source_ok": res.get("source_ok", 0),
                "ingest": res.get("ingest"),
                "judge": judged_info,
            }

            # 4. Save results to DB
            await asyncio.to_thread(
                cb.update_schedule_run_result,
                schedule_id=sid,
                last_run_at=now_cn,
                next_run_at=next_run,
                last_status="success",
                last_result=summary,
                enabled=next_enabled,
            )

            msg = (
                f"[{tag}] 采集完成: 期数 {res.get('period')}, "
                f"成功 {res.get('source_ok', 0)}/{res.get('source_total', 0)} 源"
            )
            self._add_log(sid, sname, lottery, "success", msg, summary)
            logger.info("[%s] 任务 #%d 执行成功: %s", tag, sid, msg)
            return summary

        except Exception as exc:
            err_msg = str(exc)
            logger.error("[%s] 任务 #%d 执行失败: %s", tag, sid, exc, exc_info=True)

            # Compute next run even on failure so recurring tasks keep running
            next_run = cron_util.compute_next_run(
                cron_expr=item.get("cron"),
                start_at=item.get("start_at"),
                end_at=item.get("end_at"),
                base_time=now_cn,
            )
            next_enabled = None
            if not manual and next_run is None:
                next_enabled = 0

            await asyncio.to_thread(
                cb.update_schedule_run_result,
                schedule_id=sid,
                last_run_at=now_cn,
                next_run_at=next_run,
                last_status="error",
                last_result={"ok": False, "error": err_msg},
                enabled=next_enabled,
            )

            self._add_log(sid, sname, lottery, "error", f"[{tag}] 采集失败: {err_msg}", {"error": err_msg})
            return {"ok": False, "error": err_msg}

    async def _safe_execute(self, item: dict[str, Any], manual: bool = False) -> dict[str, Any]:
        sid = item["id"]
        if sid in self._running_tasks:
            logger.warning("Schedule #%d is already executing, skipping duplicate launch", sid)
            return {"ok": False, "error": "Already running"}

        self._running_tasks.add(sid)
        try:
            return await self._execute_single_schedule(item, manual=manual)
        finally:
            self._running_tasks.discard(sid)

    async def trigger_now(self, schedule_id: int) -> dict[str, Any]:
        """Manually trigger immediate execution of a schedule."""
        item = await asyncio.to_thread(cb.get_schedule, schedule_id)
        if not item:
            raise ValueError(f"Schedule #{schedule_id} not found")
        return await self._safe_execute(item, manual=True)

    async def run_loop(self) -> None:
        """Main periodic loop running during the FastAPI lifespan."""
        self.running = True
        logger.info("SourceScheduler started (polling interval: %ds)", self.check_interval_seconds)
        try:
            while self.running:
                # Wait for trigger event or check interval
                try:
                    await asyncio.wait_for(self._trigger_event.wait(), timeout=self.check_interval_seconds)
                    self._trigger_event.clear()
                except asyncio.TimeoutError:
                    pass

                now = cron_util.now_cn()
                try:
                    due_items = await asyncio.to_thread(cb.get_due_schedules, now)
                except Exception as e:
                    logger.error("Failed to query due schedules: %s", e)
                    continue

                for item in due_items:
                    sid = item["id"]
                    if sid not in self._running_tasks:
                        asyncio.create_task(self._safe_execute(item, manual=False))

        except asyncio.CancelledError:
            logger.info("SourceScheduler received cancel signal")
        finally:
            self.running = False
            logger.info("SourceScheduler stopped")

    def get_status(self) -> dict[str, Any]:
        return {
            "running": self.running,
            "check_interval_seconds": self.check_interval_seconds,
            "active_tasks_count": len(self._running_tasks),
            "running_task_ids": list(self._running_tasks),
            "recent_logs": self.recent_logs[:30],
        }


# Global singleton instance
source_scheduler = SourceScheduler()
