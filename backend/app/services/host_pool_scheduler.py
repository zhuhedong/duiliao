"""Background health probe for the 588080 / 顶尖大师 API host pool.

Runs inside the FastAPI lifespan alongside draw/source schedulers. Default
interval is 15 minutes — frequent enough to rotate away from a dead mirror,
slow enough not to hammer upstream. Full rediscovery (entry → am.js) only
runs when the pool is empty or every probe fails.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from app import collector_bridge as cb
from app.core.config import settings

logger = logging.getLogger("app.services.host_pool_scheduler")
TZ8 = timezone(timedelta(hours=8))


def _now_str() -> str:
    return datetime.now(TZ8).strftime("%Y-%m-%d %H:%M:%S")


class HostPoolScheduler:
    """Periodic host-pool probe with optional manual wake."""

    def __init__(self) -> None:
        self.running: bool = False
        self._trigger_event: asyncio.Event = asyncio.Event()
        self.last_run_at: str | None = None
        self.last_success_at: str | None = None
        self.last_error: str | None = None
        self.last_result: dict[str, Any] | None = None
        self.run_count: int = 0
        self.recent_logs: list[dict[str, Any]] = []

    @property
    def enabled(self) -> bool:
        return bool(getattr(settings, "HOST_POOL_PROBE_ENABLED", True))

    @property
    def interval_seconds(self) -> int:
        raw = int(getattr(settings, "HOST_POOL_PROBE_INTERVAL_SEC", 900) or 900)
        # Floor at 5 minutes so a misconfigured env cannot flood upstream.
        return max(300, raw)

    def wake(self) -> None:
        self._trigger_event.set()

    def _add_log(self, status: str, message: str, result: dict[str, Any] | None = None) -> None:
        entry = {
            "timestamp": _now_str(),
            "status": status,
            "message": message,
            "result": result,
        }
        self.recent_logs.insert(0, entry)
        if len(self.recent_logs) > 40:
            self.recent_logs = self.recent_logs[:40]

    async def run_once(self, *, manual: bool = False, force_refresh: bool = False) -> dict[str, Any]:
        self.last_run_at = _now_str()
        tag = "手动" if manual else "定时"
        try:
            if force_refresh:
                result = await asyncio.to_thread(cb.host_pool_refresh)
                action = "refresh"
            else:
                result = await asyncio.to_thread(cb.host_pool_probe)
                action = result.get("action") or "probe"
            self.run_count += 1
            self.last_success_at = _now_str()
            self.last_error = None
            self.last_result = {"action": action, **(result if isinstance(result, dict) else {})}
            hosts = (result or {}).get("hosts") or []
            msg = f"[{tag}] {action} ok, hosts={len(hosts)}, primary={(result or {}).get('primary')}"
            self._add_log("success", msg, self.last_result)
            logger.info("HostPoolScheduler %s", msg)
            return self.last_result
        except Exception as exc:
            self.last_error = str(exc)
            self.last_result = {"ok": False, "error": str(exc)}
            self._add_log("error", f"[{tag}] 失败: {exc}")
            logger.warning("HostPoolScheduler failed: %s", exc)
            return self.last_result

    def status(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "running": self.running,
            "interval_seconds": self.interval_seconds,
            "last_run_at": self.last_run_at,
            "last_success_at": self.last_success_at,
            "last_error": self.last_error,
            "run_count": self.run_count,
            "last_result": self.last_result,
            "recent_logs": list(self.recent_logs[:20]),
        }

    async def run_loop(self) -> None:
        self.running = True
        logger.info(
            "HostPoolScheduler started (enabled=%s, interval=%ds)",
            self.enabled,
            self.interval_seconds,
        )
        try:
            # Soft startup probe after a short delay so schema init finishes first.
            try:
                await asyncio.wait_for(self._trigger_event.wait(), timeout=15.0)
                self._trigger_event.clear()
                await self.run_once(manual=True)
            except asyncio.TimeoutError:
                if self.enabled:
                    await self.run_once(manual=False)

            while self.running:
                if self._trigger_event.is_set():
                    self._trigger_event.clear()
                    await self.run_once(manual=True)
                    continue

                if not self.enabled:
                    try:
                        await asyncio.wait_for(self._trigger_event.wait(), timeout=30.0)
                        self._trigger_event.clear()
                    except asyncio.TimeoutError:
                        pass
                    continue

                try:
                    await asyncio.wait_for(
                        self._trigger_event.wait(),
                        timeout=float(self.interval_seconds),
                    )
                    self._trigger_event.clear()
                    await self.run_once(manual=True)
                except asyncio.TimeoutError:
                    await self.run_once(manual=False)
        except asyncio.CancelledError:
            logger.info("HostPoolScheduler received cancel signal")
        finally:
            self.running = False
            logger.info("HostPoolScheduler stopped")


host_pool_scheduler = HostPoolScheduler()
