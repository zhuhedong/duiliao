"""Asynchronous execution of collection jobs for the mobile client.

``POST /collector/collect`` runs the whole crawl inside the request, which for
40 sources at a 30s timeout and concurrency 8 is roughly 150s worst case — well
past any mobile HTTP timeout. This service turns collection into a job:

1. The request handler calls :func:`submit`, which inserts a ``queued``
   ``collect_job`` row and returns the id immediately.
2. This worker picks the row up, drives it through
   ``collecting`` -> ``ingesting`` -> ``judging`` -> ``done``, and writes
   per-source progress as each source finishes.
3. The client polls ``GET /app/collect-jobs/{id}``.

A polling worker loop is used rather than ``BackgroundTasks`` for two reasons:
queued jobs survive a process restart and get picked up, and the number of
simultaneous collections can be capped (each one spawns up to ``concurrency``
subprocesses, so unbounded parallelism would swamp the host). Submission calls
:meth:`CollectJobWorker.wake`, so a queued job still starts immediately instead
of waiting for the next tick.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any

from app import collector_bridge as cb

logger = logging.getLogger("app.services.collect_jobs")

# Each running job spawns up to `concurrency` subprocesses, so this bounds total
# subprocess fan-out at MAX_CONCURRENT_JOBS * 32 in the worst case.
MAX_CONCURRENT_JOBS = 2


class CollectJobWorker:
    """Drains queued ``collect_job`` rows, at most ``MAX_CONCURRENT_JOBS`` at a time."""

    def __init__(self) -> None:
        self.running: bool = False
        self.check_interval_seconds: int = 3
        self._trigger_event: asyncio.Event = asyncio.Event()
        self._running_jobs: set[int] = set()
        # Cancellation is checked once per source on a worker thread. Reading it
        # from memory avoids a DB round-trip per source; the DB column remains
        # the durable record and is what the poll response reports.
        self._cancelled: set[int] = set()

    # ------------------------------------------------------------------ #
    # Submission
    # ------------------------------------------------------------------ #
    async def submit(
        self,
        lottery: str,
        period: str | None = None,
        source_ids: list[str] | None = None,
        concurrency: int = 8,
        do_ingest: bool = True,
        auto_judge: bool = True,
        created_by: str | None = None,
    ) -> dict[str, Any]:
        """Create a queued job and wake the worker. Returns the job immediately."""
        job = await asyncio.to_thread(
            cb.create_collect_job,
            lottery=lottery,
            period=period,
            source_ids=source_ids,
            concurrency=concurrency,
            do_ingest=do_ingest,
            auto_judge=auto_judge,
            created_by=created_by,
        )
        self.wake()
        return job

    def wake(self) -> None:
        """Start draining now instead of waiting for the next tick."""
        self._trigger_event.set()

    async def cancel(self, job_id: int) -> dict[str, Any] | None:
        """Request cancellation. In-flight sources finish; queued ones are skipped."""
        job = await asyncio.to_thread(cb.request_collect_job_cancel, job_id)
        if job is not None:
            self._cancelled.add(job_id)
        return job

    def _is_cancelled(self, job_id: int) -> bool:
        if job_id in self._cancelled:
            return True
        # Fall back to the DB so a cancel issued before this process adopted the
        # job (or lost from memory) is still honoured.
        try:
            if cb.is_collect_job_cancelled(job_id):
                self._cancelled.add(job_id)
                return True
        except Exception:  # pragma: no cover - defensive
            logger.exception("cancel check failed for job %s", job_id)
        return False

    # ------------------------------------------------------------------ #
    # Execution
    # ------------------------------------------------------------------ #
    async def _run_job(self, job_id: int) -> None:
        """Execute one job end to end, recording progress and the final result."""
        self._running_jobs.add(job_id)
        try:
            job = await asyncio.to_thread(cb.get_collect_job, job_id)
            if job is None:
                return
            if job["status"] != "queued":
                return
            if self._is_cancelled(job_id):
                await asyncio.to_thread(
                    cb.finish_collect_job, job_id, "cancelled", {"ok": False, "cancelled": True}
                )
                return

            await asyncio.to_thread(cb.mark_collect_job_started, job_id)

            lottery = job["lottery"]
            period = job["period"]
            source_ids = job["source_ids"] or None

            def on_start(source_id: str) -> None:
                cb.update_collect_job_source(job_id, source_id, "running")

            def on_done(result: dict[str, Any]) -> None:
                source_id = result.get("source_id")
                if not source_id:
                    return
                cb.update_collect_job_source(
                    job_id,
                    source_id,
                    "ok" if result.get("ok") else "fail",
                    item_count=result.get("item_count"),
                    elapsed_ms=result.get("elapsed_ms"),
                    exit_code=result.get("exit_code"),
                    error_code=result.get("error_code"),
                    error_msg=result.get("error_msg"),
                )

            def on_phase(phase: str) -> None:
                cb.set_collect_job_phase(job_id, phase)

            res = await asyncio.to_thread(
                cb.collect,
                lottery=lottery,
                period=period,
                source_ids=source_ids,
                do_ingest=job["do_ingest"],
                concurrency=job["concurrency"],
                on_start=on_start,
                on_done=on_done,
                on_phase=on_phase,
                should_cancel=lambda: self._is_cancelled(job_id),
            )

            resolved_period = res.get("period")
            summary: dict[str, Any] = {
                "ok": bool(res.get("ok")),
                "run_id": res.get("run_id"),
                "lottery": lottery,
                "period": resolved_period,
                "source_total": res.get("source_total"),
                "source_ok": res.get("source_ok"),
                "sources": res.get("sources"),
                "ingest": res.get("ingest"),
            }

            # Judging needs a concrete period and ingested rows to judge against.
            # "auto" means no source reported a period, so there is nothing to do.
            if (
                job["auto_judge"]
                and job["do_ingest"]
                and resolved_period
                and resolved_period != "auto"
                and not self._is_cancelled(job_id)
            ):
                await asyncio.to_thread(cb.set_collect_job_phase, job_id, "judging")
                try:
                    summary["judge"] = await asyncio.to_thread(cb.judge, lottery, resolved_period)
                except Exception as exc:
                    # A judge failure must not discard a successful collection.
                    logger.exception("judge failed for job %s", job_id)
                    summary["judge"] = {"ok": False, "error": str(exc)}

            status = "cancelled" if self._is_cancelled(job_id) else "done"
            await asyncio.to_thread(
                cb.finish_collect_job,
                job_id,
                status,
                result=summary,
                run_id=res.get("run_id"),
                period=resolved_period,
            )

            # Snapshot consensus leaders now that new predictions are in. This is
            # the only moment consensus can move, so it is also the only place a
            # consensus_leader_changed event can be detected. Best effort: a
            # snapshot failure must not mark a successful collection as failed.
            if job["do_ingest"] and resolved_period and resolved_period != "auto":
                try:
                    changes = await asyncio.to_thread(
                        cb.record_consensus_leaders, lottery, resolved_period
                    )
                    if changes:
                        logger.info(
                            "job %s: %s consensus leader change(s) in %s %s",
                            job_id,
                            len(changes),
                            lottery,
                            resolved_period,
                        )
                except Exception:
                    logger.exception("consensus leader snapshot failed for job %s", job_id)
        except asyncio.CancelledError:
            # Server is shutting down; leave the row for the startup reaper.
            raise
        except Exception as exc:
            logger.exception("collect job %s failed", job_id)
            try:
                await asyncio.to_thread(
                    cb.finish_collect_job,
                    job_id,
                    "failed",
                    result={"ok": False, "error": str(exc)},
                    error=str(exc),
                )
            except Exception:  # pragma: no cover - defensive
                logger.exception("could not record failure for job %s", job_id)
        finally:
            self._running_jobs.discard(job_id)
            self._cancelled.discard(job_id)

    # ------------------------------------------------------------------ #
    # Loop
    # ------------------------------------------------------------------ #
    async def run_loop(self) -> None:
        self.running = True
        logger.info("collect job worker started")
        # Jobs run in-process, so anything left running was orphaned by a restart.
        try:
            reaped = await asyncio.to_thread(cb.reap_stale_collect_jobs)
            if reaped:
                logger.warning("marked %s interrupted collect job(s)", reaped)
        except Exception:
            logger.exception("could not reap stale collect jobs")

        try:
            while True:
                try:
                    await asyncio.wait_for(
                        self._trigger_event.wait(), timeout=self.check_interval_seconds
                    )
                except asyncio.TimeoutError:
                    pass
                self._trigger_event.clear()

                try:
                    free = MAX_CONCURRENT_JOBS - len(self._running_jobs)
                    if free <= 0:
                        continue
                    pending_ids = await asyncio.to_thread(
                        cb.get_queued_job_ids, limit=free
                    )
                    for job_id in pending_ids:
                        if len(self._running_jobs) >= MAX_CONCURRENT_JOBS:
                            break
                        if job_id in self._running_jobs:
                            continue
                        asyncio.create_task(self._run_job(job_id))
                except Exception:
                    logger.exception("collect job poll failed")
        except asyncio.CancelledError:
            logger.info("collect job worker stopped")
            raise
        finally:
            self.running = False

    def get_status(self) -> dict[str, Any]:
        return {
            "running": self.running,
            "check_interval_seconds": self.check_interval_seconds,
            "max_concurrent_jobs": MAX_CONCURRENT_JOBS,
            "active_jobs_count": len(self._running_jobs),
            "running_job_ids": sorted(self._running_jobs),
        }


collect_job_worker = CollectJobWorker()
