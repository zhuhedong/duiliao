"""Background scheduler for automatic lottery draw fetching and judging."""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone, timedelta
from typing import Any

from app import collector_bridge as cb

logger = logging.getLogger("app.services.draw_scheduler")
TZ8 = timezone(timedelta(hours=8))


def _now_cn() -> datetime:
    return datetime.now(TZ8)


def _now_str() -> str:
    return _now_cn().strftime("%Y-%m-%d %H:%M:%S")


def _parse_time_str(val: str, default: tuple[int, int, int]) -> tuple[int, int, int]:
    try:
        parts = [int(p) for p in val.strip().split(":")]
        if len(parts) == 2:
            return (parts[0], parts[1], 0)
        elif len(parts) == 3:
            return (parts[0], parts[1], parts[2])
    except Exception:
        pass
    return default


class DrawScheduler:
    """Manages scheduled window checks for lottery draws.
    
    Default window: Beijing Time every day 21:33:30 to 21:36:00, syncing every 30 seconds.
    Supports manual trigger anytime.
    """

    def __init__(self) -> None:
        self.enabled: bool = True
        self.running: bool = False
        self.start_time: str = "21:33:30"
        self.end_time: str = "21:36:00"
        self.interval_seconds: int = 30
        self.lotteries: list[str] = ["macau", "hk"]
        self.last_run_at: str | None = None
        self.last_success_at: str | None = None
        self.last_error: str | None = None
        self.last_result: dict[str, Any] | None = None
        self.sync_count: int = 0
        self.recent_logs: list[dict[str, Any]] = []
        self._trigger_event: asyncio.Event = asyncio.Event()

    def _add_log(self, lottery: str, status: str, message: str, result: dict[str, Any] | None = None) -> None:
        entry = {
            "timestamp": _now_str(),
            "lottery": lottery,
            "status": status,
            "message": message,
            "result": result,
        }
        self.recent_logs.insert(0, entry)
        if len(self.recent_logs) > 50:
            self.recent_logs = self.recent_logs[:50]

    def _compute_window_state(self, now: datetime) -> tuple[bool, datetime]:
        sh, sm, ss = _parse_time_str(self.start_time, (21, 33, 30))
        eh, em, es = _parse_time_str(self.end_time, (21, 36, 0))

        today_start = datetime(now.year, now.month, now.day, sh, sm, ss, tzinfo=TZ8)
        today_end = datetime(now.year, now.month, now.day, eh, em, es, tzinfo=TZ8)

        if now < today_start:
            return False, today_start
        elif now <= today_end:
            return True, now
        else:
            tomorrow = now + timedelta(days=1)
            tomorrow_start = datetime(tomorrow.year, tomorrow.month, tomorrow.day, sh, sm, ss, tzinfo=TZ8)
            return False, tomorrow_start

    async def _sync_lottery(self, lottery: str) -> dict[str, Any]:
        """Run draw sync in a worker thread to avoid blocking asyncio event loop."""
        return await asyncio.to_thread(cb.sync_draws, lottery=lottery)

    async def run_single_cycle(self, manual: bool = False) -> dict[str, Any]:
        """Execute one sync pass across all monitored lotteries."""
        self.last_run_at = _now_str()
        cycle_results: dict[str, Any] = {}
        has_error = False

        for lottery in self.lotteries:
            try:
                res = await self._sync_lottery(lottery)
                cycle_results[lottery] = res
                self.sync_count += 1
                tag = "手动触发" if manual else "定时同步"
                msg = f"[{tag}] 成功: 新增 {res.get('inserted', 0)}, 更新 {res.get('updated', 0)}, 对奖 {res.get('judged', 0)} 条"
                self._add_log(lottery, "success", msg, res)
                self.last_success_at = _now_str()
            except Exception as exc:
                has_error = True
                err_msg = str(exc)
                cycle_results[lottery] = {"ok": False, "error": err_msg}
                self.last_error = f"[{lottery}] {err_msg}"
                tag = "手动触发" if manual else "定时同步"
                self._add_log(lottery, "error", f"[{tag}] 失败: {err_msg}")
                logger.warning("Draw sync failed for %s: %s", lottery, exc)

        if not has_error:
            self.last_error = None
        self.last_result = cycle_results
        return cycle_results

    async def run_loop(self) -> None:
        """Main periodic loop running during the FastAPI lifespan."""
        self.running = True
        logger.info(
            "DrawScheduler started (window: %s - %s every %ds, lotteries: %s)",
            self.start_time,
            self.end_time,
            self.interval_seconds,
            self.lotteries,
        )
        try:
            while self.running:
                # Check for manual trigger first
                if self._trigger_event.is_set():
                    self._trigger_event.clear()
                    logger.info("Manual trigger received in DrawScheduler")
                    try:
                        await self.run_single_cycle(manual=True)
                    except Exception as e:
                        logger.error("Error in manual DrawScheduler cycle: %s", e, exc_info=True)
                    continue

                if not self.enabled:
                    try:
                        await asyncio.wait_for(self._trigger_event.wait(), timeout=10.0)
                        self._trigger_event.clear()
                    except asyncio.TimeoutError:
                        pass
                    continue

                now = _now_cn()
                in_window, next_run = self._compute_window_state(now)

                if in_window:
                    logger.info("DrawScheduler within active window [%s], executing sync pass...", now.strftime("%H:%M:%S"))
                    try:
                        await self.run_single_cycle(manual=False)
                    except Exception as e:
                        logger.error("Error in DrawScheduler cycle: %s", e, exc_info=True)

                    # Sleep interval_seconds (e.g. 30s) or until trigger event
                    try:
                        await asyncio.wait_for(self._trigger_event.wait(), timeout=self.interval_seconds)
                        self._trigger_event.clear()
                    except asyncio.TimeoutError:
                        pass
                else:
                    # Outside window: wait until next window start
                    wait_seconds = max(1.0, (next_run - now).total_seconds())
                    sleep_chunk = min(wait_seconds, 10.0)
                    try:
                        await asyncio.wait_for(self._trigger_event.wait(), timeout=sleep_chunk)
                        self._trigger_event.clear()
                    except asyncio.TimeoutError:
                        pass
        except asyncio.CancelledError:
            logger.info("DrawScheduler received cancel signal")
        finally:
            self.running = False
            logger.info("DrawScheduler stopped")

    def trigger_now(self) -> None:
        """Wake up the worker immediately for an unscheduled sync."""
        self._trigger_event.set()

    def set_config(
        self,
        enabled: bool | None = None,
        start_time: str | None = None,
        end_time: str | None = None,
        interval_seconds: int | None = None,
        lotteries: list[str] | None = None,
    ) -> dict[str, Any]:
        if enabled is not None:
            self.enabled = bool(enabled)
        if start_time is not None and start_time.strip():
            self.start_time = start_time.strip()
        if end_time is not None and end_time.strip():
            self.end_time = end_time.strip()
        if interval_seconds is not None:
            self.interval_seconds = max(5, min(interval_seconds, 3600))
        if lotteries is not None:
            valid = [l for l in lotteries if l in {"hk", "macau", "taiwan", "new"}]
            if valid:
                self.lotteries = valid
        return self.get_status()

    def get_status(self) -> dict[str, Any]:
        now = _now_cn()
        in_window, next_run = self._compute_window_state(now)
        return {
            "enabled": self.enabled,
            "running": self.running,
            "start_time": self.start_time,
            "end_time": self.end_time,
            "interval_seconds": self.interval_seconds,
            "in_window": in_window,
            "current_time": now.strftime("%Y-%m-%d %H:%M:%S"),
            "next_run_at": next_run.strftime("%Y-%m-%d %H:%M:%S") if next_run else None,
            "lotteries": self.lotteries,
            "last_run_at": self.last_run_at,
            "last_success_at": self.last_success_at,
            "last_error": self.last_error,
            "last_result": self.last_result,
            "sync_count": self.sync_count,
            "recent_logs": self.recent_logs[:20],
        }


# Global singleton instance
draw_scheduler = DrawScheduler()
