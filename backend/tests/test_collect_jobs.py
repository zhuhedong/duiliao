"""Collection-job tests: submission, per-source progress, phases, cancel, roles.

Runs entirely offline. ``PRED_ALLOW_FIXTURE=1`` plus the checked-in
``collector/fixtures/dingjian`` payloads mean the source subprocesses read from
disk instead of making outbound requests.
"""
from __future__ import annotations

import asyncio
import time

import pytest

from tests.crypto_client import ApiError

FIXTURE_DIR = "fixtures/dingjian"


# --------------------------------------------------------------------------- #
# The bridge-level contract that the job worker relies on
# --------------------------------------------------------------------------- #
def test_collect_reports_each_source_through_callbacks(fixture_sources):
    """on_start/on_done must fire per source, and on_done must carry stdout."""
    from app import collector_bridge as cb

    started: list[str] = []
    finished: list[dict] = []
    phases: list[str] = []

    result = cb.collect(
        lottery="macau",
        period="248",
        source_ids=fixture_sources,
        fixture_dir=FIXTURE_DIR,
        do_ingest=False,
        concurrency=2,
        on_start=started.append,
        on_done=finished.append,
        on_phase=phases.append,
    )

    assert sorted(started) == sorted(fixture_sources)
    assert sorted(r["source_id"] for r in finished) == sorted(fixture_sources)
    assert phases[0] == "collecting"
    assert result["source_total"] == 2
    assert result["source_ok"] == 2
    # The run.v1 projection drops stdout/stderr, but the progress callback needs
    # them for the single-source troubleshooting view.
    assert all("stdout" in r for r in finished)
    assert all(r["raw_path"] is not None for r in finished)


def test_collect_preserves_configured_order_regardless_of_completion_order(fixture_sources):
    from app import collector_bridge as cb

    result = cb.collect(
        lottery="macau",
        period="248",
        source_ids=fixture_sources,
        fixture_dir=FIXTURE_DIR,
        do_ingest=False,
        concurrency=2,
    )
    ids = [r["source_id"] for r in result["payload"]["results"]]
    assert ids == sorted(ids, key=fixture_sources.index)


def test_should_cancel_skips_sources_without_spawning_subprocesses(fixture_sources):
    from app import collector_bridge as cb

    result = cb.collect(
        lottery="macau",
        period="248",
        source_ids=fixture_sources,
        fixture_dir=FIXTURE_DIR,
        do_ingest=False,
        concurrency=2,
        should_cancel=lambda: True,
    )
    assert result["source_ok"] == 0
    for row in result["payload"]["results"]:
        assert row["ok"] is False
        assert row["error_code"] == "cancelled"
        # Zero elapsed proves no subprocess ran.
        assert row["elapsed_ms"] == 0


def test_a_raising_callback_does_not_break_the_run(fixture_sources):
    from app import collector_bridge as cb

    def explode(*_args):
        raise RuntimeError("callback blew up")

    result = cb.collect(
        lottery="macau",
        period="248",
        source_ids=fixture_sources,
        fixture_dir=FIXTURE_DIR,
        do_ingest=False,
        concurrency=2,
        on_start=explode,
        on_done=explode,
    )
    assert result["source_ok"] == 2


def test_unknown_source_ids_yield_an_empty_run():
    from app import collector_bridge as cb

    result = cb.collect(
        lottery="macau",
        period="248",
        source_ids=["no_such_source_at_all"],
        do_ingest=False,
        concurrency=2,
    )
    assert result["source_total"] == 0
    assert result["period"] == "2026248"


# --------------------------------------------------------------------------- #
# Job row lifecycle
# --------------------------------------------------------------------------- #
def test_create_job_prepopulates_every_source_as_queued(fixture_sources):
    from app import collector_bridge as cb

    job = cb.create_collect_job(
        lottery="macau", period="248", source_ids=fixture_sources, concurrency=2
    )
    assert job["status"] == "queued"
    assert job["phase"] == "queued"
    assert job["source_total"] == 2
    assert job["source_done"] == 0
    assert [i["state"] for i in job["items"]] == ["queued", "queued"]
    # Names come from the catalogue so the UI can render labels immediately.
    assert all(i["source_name"] for i in job["items"])


def test_progress_updates_advance_the_counters(fixture_sources):
    from app import collector_bridge as cb

    job = cb.create_collect_job(lottery="macau", source_ids=fixture_sources)
    job_id = job["id"]

    cb.update_collect_job_source(job_id, fixture_sources[0], "running")
    mid = cb.get_collect_job(job_id)
    assert mid["items"][0]["state"] == "running"
    assert mid["source_done"] == 0

    cb.update_collect_job_source(job_id, fixture_sources[0], "ok", item_count=5, elapsed_ms=120)
    cb.update_collect_job_source(
        job_id, fixture_sources[1], "fail", error_code="timeout", error_msg="too slow"
    )
    done = cb.get_collect_job(job_id)
    assert done["source_done"] == 2
    assert done["source_ok"] == 1
    assert done["items"][0]["item_count"] == 5
    assert done["items"][1]["error_code"] == "timeout"
    assert [f["source_id"] for f in done["failed"]] == [fixture_sources[1]]


def test_cancel_on_a_queued_job_terminates_it_immediately(fixture_sources):
    from app import collector_bridge as cb

    job = cb.create_collect_job(lottery="macau", source_ids=fixture_sources)
    cancelled = cb.request_collect_job_cancel(job["id"])
    assert cancelled["status"] == "cancelled"
    assert cancelled["cancel_requested"] is True
    assert cb.is_collect_job_cancelled(job["id"]) is True


def test_cancel_on_a_finished_job_is_a_no_op(fixture_sources):
    from app import collector_bridge as cb

    job = cb.create_collect_job(lottery="macau", source_ids=fixture_sources)
    cb.finish_collect_job(job["id"], "done", result={"ok": True})
    again = cb.request_collect_job_cancel(job["id"])
    assert again["status"] == "done"


def test_cancel_on_a_missing_job_returns_none():
    from app import collector_bridge as cb

    assert cb.request_collect_job_cancel(999_999) is None


def test_stale_running_jobs_are_reaped_as_interrupted(fixture_sources):
    from datetime import datetime, timedelta

    from app import collector_bridge as cb
    from db import session_scope
    from schema import CollectJob

    job = cb.create_collect_job(lottery="macau", source_ids=fixture_sources)
    with session_scope() as s:
        row = s.get(CollectJob, job["id"])
        row.status = "running"
        row.started_at = datetime.now() - timedelta(hours=9)

    assert cb.reap_stale_collect_jobs(max_age_minutes=180) >= 1
    after = cb.get_collect_job(job["id"])
    assert after["status"] == "interrupted"
    assert "restart" in (after["error"] or "")


def test_a_recent_running_job_is_not_reaped(fixture_sources):
    from app import collector_bridge as cb
    from db import session_scope
    from schema import CollectJob

    job = cb.create_collect_job(lottery="macau", source_ids=fixture_sources)
    with session_scope() as s:
        s.get(CollectJob, job["id"]).status = "running"
    cb.mark_collect_job_started(job["id"])

    cb.reap_stale_collect_jobs(max_age_minutes=180)
    assert cb.get_collect_job(job["id"])["status"] == "running"


def test_concurrent_progress_writes_do_not_lose_updates(fixture_sources):
    """Regression: the progress JSON column is a read-modify-write hot spot.

    Several collection threads finish at once and each merges its own entry into
    one JSON column. Without serialisation the later write discards the earlier
    one, progress under-reports, and source_done never reaches source_total.
    """
    import threading

    from app import collector_bridge as cb

    source_ids = [f"race_source_{i}" for i in range(12)]
    job = cb.create_collect_job(lottery="macau", source_ids=[])
    job_id = job["id"]

    # Seed the progress map directly: these ids are not real sources, so
    # create_collect_job would resolve them away.
    from db import session_scope
    from schema import CollectJob

    with session_scope() as s:
        row = s.get(CollectJob, job_id)
        row.progress = {sid: {"state": "queued"} for sid in source_ids}
        row.source_ids = source_ids
        row.source_total = len(source_ids)

    barrier = threading.Barrier(len(source_ids))

    def worker(source_id: str) -> None:
        barrier.wait()  # maximise contention
        cb.update_collect_job_source(job_id, source_id, "ok", item_count=1)

    threads = [threading.Thread(target=worker, args=(sid,)) for sid in source_ids]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    final = cb.get_collect_job(job_id)
    assert final["source_done"] == len(source_ids)
    assert final["source_ok"] == len(source_ids)
    assert all(item["state"] == "ok" for item in final["items"])


# --------------------------------------------------------------------------- #
# The worker, driven deterministically
# --------------------------------------------------------------------------- #
def test_worker_runs_a_job_through_every_phase_to_done(
    fixture_sources, seeded_draws, monkeypatch
):
    """End-to-end: queued -> collecting -> ingesting -> judging -> done."""
    from app import collector_bridge as cb
    from app.services.collect_jobs import collect_job_worker

    seen_phases: list[str] = []
    real_set_phase = cb.set_collect_job_phase

    def spy(job_id, phase):
        seen_phases.append(phase)
        return real_set_phase(job_id, phase)

    monkeypatch.setattr(cb, "set_collect_job_phase", spy)

    # Point collect() at the offline fixtures for this test only.
    real_collect = cb.collect

    def collect_with_fixtures(*args, **kwargs):
        kwargs["fixture_dir"] = FIXTURE_DIR
        return real_collect(*args, **kwargs)

    monkeypatch.setattr(cb, "collect", collect_with_fixtures)

    job = cb.create_collect_job(
        lottery="macau",
        period="248",
        source_ids=fixture_sources,
        concurrency=2,
        do_ingest=True,
        auto_judge=True,
    )

    # Clear any judgements a previous test left for this period, so the
    # "judged" count below is deterministic rather than order-dependent
    # (re-judging an already-judged period legitimately reports 0).
    from db import session_scope
    from schema import JudgeResult
    from sqlalchemy import delete

    with session_scope() as s:
        s.execute(
            delete(JudgeResult).where(
                JudgeResult.lottery == "macau", JudgeResult.period == "2026248"
            )
        )

    asyncio.run(collect_job_worker._run_job(job["id"]))

    final = cb.get_collect_job(job["id"])
    assert final["status"] == "done"
    assert final["phase"] == "done"
    assert final["source_done"] == 2
    assert final["source_ok"] == 2
    assert final["period"] == "2026248"
    assert final["run_id"]
    assert final["result"]["ingest"] is not None
    assert final["result"]["judge"] is not None
    assert final["result"]["judge"]["ok"] is True
    assert final["result"]["judge"]["judged"] >= 1
    assert final["started_at"] and final["finished_at"]
    assert [i["state"] for i in final["items"]] == ["ok", "ok"]
    assert "collecting" in seen_phases
    assert "ingesting" in seen_phases
    assert "judging" in seen_phases


def test_worker_marks_a_cancelled_job_cancelled(fixture_sources, monkeypatch):
    from app import collector_bridge as cb
    from app.services.collect_jobs import collect_job_worker

    real_collect = cb.collect

    def collect_with_fixtures(*args, **kwargs):
        kwargs["fixture_dir"] = FIXTURE_DIR
        return real_collect(*args, **kwargs)

    monkeypatch.setattr(cb, "collect", collect_with_fixtures)

    job = cb.create_collect_job(
        lottery="macau", period="248", source_ids=fixture_sources, do_ingest=False
    )
    job_id = job["id"]
    # Requesting cancellation on a queued job finalises it as cancelled, so the
    # worker must decline to run it at all.
    asyncio.run(collect_job_worker.cancel(job_id))
    asyncio.run(collect_job_worker._run_job(job_id))

    final = cb.get_collect_job(job_id)
    assert final["status"] == "cancelled"
    assert final["source_ok"] == 0


def test_worker_records_failure_without_losing_the_job(fixture_sources, monkeypatch):
    from app import collector_bridge as cb
    from app.services.collect_jobs import collect_job_worker

    def boom(*_args, **_kwargs):
        raise RuntimeError("collector exploded")

    monkeypatch.setattr(cb, "collect", boom)

    job = cb.create_collect_job(lottery="macau", period="248", source_ids=fixture_sources)
    asyncio.run(collect_job_worker._run_job(job["id"]))

    final = cb.get_collect_job(job["id"])
    assert final["status"] == "failed"
    assert "exploded" in final["error"]


def test_judge_failure_does_not_discard_a_good_collection(fixture_sources, monkeypatch):
    from app import collector_bridge as cb
    from app.services.collect_jobs import collect_job_worker

    real_collect = cb.collect

    def collect_with_fixtures(*args, **kwargs):
        kwargs["fixture_dir"] = FIXTURE_DIR
        return real_collect(*args, **kwargs)

    monkeypatch.setattr(cb, "collect", collect_with_fixtures)
    monkeypatch.setattr(cb, "judge", lambda *_a, **_k: (_ for _ in ()).throw(RuntimeError("judge down")))

    job = cb.create_collect_job(
        lottery="macau", period="248", source_ids=fixture_sources, auto_judge=True
    )
    asyncio.run(collect_job_worker._run_job(job["id"]))

    final = cb.get_collect_job(job["id"])
    assert final["status"] == "done"
    assert final["result"]["judge"]["ok"] is False
    assert final["source_ok"] == 2


# --------------------------------------------------------------------------- #
# HTTP surface
# --------------------------------------------------------------------------- #
def test_submit_returns_immediately_with_the_full_source_list(staff_client, fixture_sources):
    started = time.perf_counter()
    job = staff_client.post(
        "/app/collect-jobs",
        {
            "lottery": "macau",
            "period": "248",
            "source_ids": fixture_sources,
            "concurrency": 2,
            "ingest": False,
            "auto_judge": False,
        },
    )
    elapsed = time.perf_counter() - started

    assert job["status"] == "queued"
    assert sorted(job["source_ids"]) == sorted(fixture_sources)
    assert len(job["items"]) == 2
    # The whole point of the job API: submission must not wait for the crawl.
    assert elapsed < 2.0, f"submit took {elapsed:.2f}s"


def test_plain_user_cannot_submit_a_job(user_client, fixture_sources):
    with pytest.raises(ApiError) as exc:
        user_client.post(
            "/app/collect-jobs",
            {"lottery": "macau", "source_ids": fixture_sources},
        )
    assert exc.value.status_code == 403


def test_plain_user_cannot_cancel_a_job(user_client, staff_client, fixture_sources):
    job = staff_client.post(
        "/app/collect-jobs",
        {"lottery": "macau", "source_ids": fixture_sources, "ingest": False},
    )
    with pytest.raises(ApiError) as exc:
        user_client.delete(f"/app/collect-jobs/{job['id']}")
    assert exc.value.status_code == 403


def test_plain_user_can_read_jobs(user_client, staff_client, fixture_sources):
    job = staff_client.post(
        "/app/collect-jobs",
        {"lottery": "macau", "source_ids": fixture_sources, "ingest": False},
    )
    fetched = user_client.get(f"/app/collect-jobs/{job['id']}")
    assert fetched["id"] == job["id"]
    listing = user_client.get("/app/collect-jobs", params={"limit": 5})
    assert listing["ok"] is True
    assert listing["count"] >= 1
    assert "worker" in listing


def test_submitting_with_no_matching_sources_is_a_400(staff_client):
    with pytest.raises(ApiError) as exc:
        staff_client.post(
            "/app/collect-jobs",
            {"lottery": "macau", "source_ids": ["definitely_not_a_source"]},
        )
    assert exc.value.status_code == 400


def test_unknown_lottery_is_rejected(staff_client, fixture_sources):
    with pytest.raises(ApiError) as exc:
        staff_client.post(
            "/app/collect-jobs",
            {"lottery": "atlantis", "source_ids": fixture_sources},
        )
    assert exc.value.status_code == 400


def test_concurrency_outside_the_allowed_range_is_rejected(staff_client, fixture_sources):
    with pytest.raises(ApiError) as exc:
        staff_client.post(
            "/app/collect-jobs",
            {"lottery": "macau", "source_ids": fixture_sources, "concurrency": 99},
        )
    assert exc.value.status_code == 422


def test_polling_a_missing_job_is_a_404(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.get("/app/collect-jobs/987654")
    assert exc.value.status_code == 404


def test_history_can_be_filtered_by_status_and_lottery(staff_client, fixture_sources):
    staff_client.post(
        "/app/collect-jobs",
        {"lottery": "macau", "source_ids": fixture_sources, "ingest": False},
    )
    listing = staff_client.get(
        "/app/collect-jobs", params={"status": "queued", "lottery": "macau", "limit": 50}
    )
    assert all(item["status"] == "queued" for item in listing["items"])
    assert all(item["lottery"] == "macau" for item in listing["items"])
    # The list view omits the heavy result blob.
    assert all("result" not in item for item in listing["items"])
