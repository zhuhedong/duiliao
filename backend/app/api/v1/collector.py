"""Collector API — collection, ingest, draw sync, judging, consensus/analytics
and source management, ported from pred-collector.

Read endpoints require a logged-in user; mutating / operational endpoints
(source CRUD, collection runs, draw sync, catalog scans) require staff/admin.
The API process never makes outbound requests to prediction sites itself — the
``/collect`` endpoint launches the per-source scripts as isolated subprocesses.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app import collector_bridge as cb
from app.api.deps import get_current_user, require_roles
from app.models.user import User, UserRole

router = APIRouter(prefix="/collector", tags=["collector"])

# Reusable auth dependencies.
_user = Depends(get_current_user)
_staff = Depends(require_roles(UserRole.ADMIN, UserRole.STAFF))

Lottery = str  # "hk" | "macau" | "taiwan" | "new"


def _bad_request(exc: Exception) -> HTTPException:
    return HTTPException(status_code=400, detail=str(exc))


# --------------------------------------------------------------------------- #
# Request models
# --------------------------------------------------------------------------- #
class CollectRequest(BaseModel):
    lottery: Lottery
    period: str | None = None
    source_ids: list[str] | None = None
    fixture_dir: str | None = Field(
        default=None,
        description="Optional dir of <source_id>.json fixtures for offline runs.",
    )
    ingest: bool = True
    concurrency: int = Field(8, description="并发线程池大小，默认 8")


class DrawSyncRequest(BaseModel):
    lottery: Lottery
    period: str | None = None
    draws: list[dict[str, Any]] | None = Field(
        default=None,
        description="Generic draw objects to import; omit to fetch via configured adapter.",
    )


class JudgeRequest(BaseModel):
    lottery: Lottery
    period: str


class ConfirmMissingRequest(BaseModel):
    source_id: str
    periods: list[str]


class SourceCreate(BaseModel):
    source_id: str
    source_name: str | None = None
    site_family: str | None = None
    lottery: Lottery = "macau"
    play_type: str = "pingte_xiao"
    hit_mode: str = "any"
    script_path: str | None = None
    timeout_sec: int | None = None
    enabled: bool | None = None
    remark: str | None = None
    extra: dict[str, Any] | None = None
    script: str | None = None
    create_script: bool = True


class SourceUpdate(BaseModel):
    source_name: str | None = None
    site_family: str | None = None
    lottery: str | None = None
    play_type: str | None = None
    hit_mode: str | None = None
    script_path: str | None = None
    timeout_sec: int | None = None
    enabled: bool | None = None
    remark: str | None = None
    extra: dict[str, Any] | None = None
    script: str | None = None


class ScriptWrite(BaseModel):
    content: str


class DrawConfigUpdate(BaseModel):
    adapter: str | None = None
    url: str | None = None
    headers: dict[str, Any] | None = None
    lotterytype: str | None = None


class SourceTestRequest(BaseModel):
    lottery: Lottery = "macau"
    period: str | None = None
    fixture_dir: str | None = None
    ingest: bool = False


class ScriptRunRequest(BaseModel):
    lottery: Lottery = "macau"
    period: str | None = None
    fixture: str | None = None


class DrawSchedulerConfig(BaseModel):
    enabled: bool | None = None
    start_time: str | None = None
    end_time: str | None = None
    interval_seconds: int | None = None
    lotteries: list[str] | None = None


class ScheduleCreate(BaseModel):
    name: str = Field(..., description="任务名称，如：澳门晚间全量采集")
    lottery: Lottery = "macau"
    period: str | None = Field(None, description="指定采集期数；若为空则自动检测最新期")
    source_ids: list[str] | None = Field(None, description="指定采集的数据源ID列表；若为空则采集所有有效数据源")
    cron: str | None = Field(None, description="标准5段Cron表达式或分号隔开的多段表达式，如：0-30/5 21 * * *")
    start_at: str | None = Field(None, description="指定开始时间，格式：YYYY-MM-DD HH:MM:SS")
    end_at: str | None = Field(None, description="指定结束时间，过期后停止执行")
    enabled: bool = True
    do_ingest: bool = True
    auto_judge: bool = True
    # 特定时间段模式支持（如：当天 21:00-21:30 每 5 分钟一次）
    time_window_start: str | None = Field(None, description="时间段开始，如 21:00")
    time_window_end: str | None = Field(None, description="时间段结束，如 21:30")
    interval_minutes: int | None = Field(None, description="时间段内间隔分钟数，如 5")
    window_date: str | None = Field(None, description="执行日期: 'today'（仅今天执行）或 'daily'（每日重复）或具体日期")
    concurrency: int = Field(8, description="并发线程池大小，默认 8")
    spec: dict[str, Any] | None = None


class ScheduleUpdate(BaseModel):
    name: str | None = None
    lottery: str | None = None
    period: str | None = None
    source_ids: list[str] | None = None
    cron: str | None = None
    start_at: str | None = None
    end_at: str | None = None
    enabled: bool | None = None
    do_ingest: bool | None = None
    auto_judge: bool | None = None
    time_window_start: str | None = None
    time_window_end: str | None = None
    interval_minutes: int | None = None
    window_date: str | None = None
    concurrency: int | None = None
    spec: dict[str, Any] | None = None



# --------------------------------------------------------------------------- #
# Pipeline
# --------------------------------------------------------------------------- #
@router.post("/collect")
def collect(req: CollectRequest, _: User = _staff) -> dict[str, Any]:
    """Run enabled source scripts for a lottery+period and (by default) ingest."""
    try:
        return cb.collect(
            req.lottery,
            req.period,
            source_ids=req.source_ids,
            fixture_dir=req.fixture_dir,
            do_ingest=req.ingest,
            concurrency=req.concurrency,
        )
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


@router.post("/ingest")
def ingest(payload: dict[str, Any] = Body(...), _: User = _staff) -> dict[str, Any]:
    """Ingest a run.v1 payload directly (dedupe + upsert + auto-judge)."""
    try:
        return cb.ingest_payload(payload)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


@router.post("/draws/sync")
def draws_sync(req: DrawSyncRequest, _: User = _staff) -> dict[str, Any]:
    """Import official draws (validated) and re-judge affected predictions."""
    try:
        return cb.sync_draws(req.lottery, req.period, req.draws)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


@router.post("/judge")
def judge(req: JudgeRequest, _: User = _staff) -> dict[str, Any]:
    """Recompute JudgeResults for a lottery+period."""
    try:
        return cb.judge(req.lottery, req.period)
    except (ValueError, KeyError, SystemExit) as exc:
        raise _bad_request(exc)


# --------------------------------------------------------------------------- #
# Consensus / analytics (read)
# --------------------------------------------------------------------------- #
@router.get("/consensus")
def consensus(
    lottery: Lottery,
    period: str,
    play_type: str | None = None,
    _: User = _user,
) -> dict[str, Any]:
    try:
        return cb.consensus_compare(lottery, period, play_type)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


@router.get("/ratings")
def ratings(
    lottery: Lottery,
    play_type: str,
    windows: str = Query("30,50,100", description="Comma-separated rolling windows."),
    period_from: str | None = None,
    period_to: str | None = None,
    _: User = _user,
) -> dict[str, Any]:
    try:
        parsed = tuple(int(w) for w in windows.split(",") if w.strip())
        return cb.ratings(lottery, play_type, parsed or (30, 50, 100), period_from, period_to)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


@router.get("/monitor")
def monitor(lottery: Lottery | None = None, _: User = _user) -> dict[str, Any]:
    return cb.monitor(lottery)


@router.get("/draws")
def list_draws(
    lottery: Lottery | None = None,
    limit: int = 50,
    offset: int = 0,
    period_from: str | None = None,
    period_to: str | None = None,
    _: User = _user,
) -> dict[str, Any]:
    """List stored official draws (most recent first)."""
    return cb.list_draws(lottery, limit, offset, period_from, period_to)


@router.get("/predictions")
def list_predictions(
    lottery: Lottery | None = None,
    period: str | None = None,
    source_id: str | None = None,
    status: str | None = None,
    limit: int = 100,
    offset: int = 0,
    _: User = _user,
) -> dict[str, Any]:
    """List stored predictions (most recent period first)."""
    return cb.list_predictions(lottery, period, source_id, status=status, limit=limit, offset=offset)


@router.get("/sources/{source_id}/history")
def get_source_history(
    source_id: str,
    lottery: Lottery | None = None,
    status: str | None = None,
    period_from: str | None = None,
    period_to: str | None = None,
    limit: int = 50,
    offset: int = 0,
    _: User = _user,
) -> dict[str, Any]:
    """Retrieve full prediction history, judge verification, and draw results for a source."""
    try:
        return cb.get_source_history(
            source_id,
            lottery=lottery,
            status=status,
            period_from=period_from,
            period_to=period_to,
            limit=limit,
            offset=offset,
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise _bad_request(exc)


@router.post("/missing/confirm")
def confirm_missing(req: ConfirmMissingRequest, _: User = _staff) -> dict[str, Any]:
    try:
        return cb.confirm_missing(req.source_id, req.periods)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


@router.get("/rules")
def rules(_: User = _user) -> list[dict[str, Any]]:
    return cb.rules_catalog()


@router.get("/numbers")
def numbers(date: str | None = None, _: User = _user) -> dict[str, Any]:
    """01–49 with zodiac / 家野 / 波色 / 大小 / 单双 / 头 / 尾 / 合数 for a date."""
    try:
        return cb.list_numbers(date)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


# --------------------------------------------------------------------------- #
# Source management (registry)
# --------------------------------------------------------------------------- #
@router.get("/sources")
def list_sources(_: User = _user) -> list[dict[str, Any]]:
    return cb.registry_module().list_sources()


@router.get("/sources/{source_id}")
def get_source(source_id: str, _: User = _user) -> dict[str, Any]:
    reg = cb.registry_module()
    try:
        return reg.get_source(source_id)
    except reg.RegistryError as exc:
        raise HTTPException(status_code=404, detail=exc.message)


@router.post("/sources", status_code=201)
def create_source(body: SourceCreate, _: User = _staff) -> dict[str, Any]:
    reg = cb.registry_module()
    try:
        return reg.create_source(body.model_dump(exclude_none=True))
    except reg.RegistryError as exc:
        raise HTTPException(status_code=400, detail=exc.message)


@router.patch("/sources/{source_id}")
def update_source(source_id: str, body: SourceUpdate, _: User = _staff) -> dict[str, Any]:
    reg = cb.registry_module()
    try:
        return reg.update_source(source_id, body.model_dump(exclude_unset=True))
    except reg.RegistryError as exc:
        code = 404 if exc.code == "not_found" else 400
        raise HTTPException(status_code=code, detail=exc.message)


@router.delete("/sources/{source_id}")
def delete_source(source_id: str, delete_file: bool = False, _: User = _staff) -> dict[str, Any]:
    reg = cb.registry_module()
    try:
        return reg.delete_source(source_id, delete_file=delete_file)
    except reg.RegistryError as exc:
        code = 404 if exc.code == "not_found" else 400
        raise HTTPException(status_code=code, detail=exc.message)


@router.get("/families")
def list_families(_: User = _user) -> dict[str, Any]:
    return cb.registry_module().list_families()


@router.get("/scripts")
def list_scripts(_: User = _user) -> list[dict[str, Any]]:
    return cb.registry_module().list_scripts()


@router.get("/scripts/{name}")
def read_script(name: str, _: User = _staff) -> dict[str, Any]:
    reg = cb.registry_module()
    try:
        return reg.read_script(name)
    except reg.RegistryError as exc:
        code = 404 if exc.code == "not_found" else 400
        raise HTTPException(status_code=code, detail=exc.message)


@router.put("/scripts/{name}")
def write_script(name: str, body: ScriptWrite, _: User = _staff) -> dict[str, Any]:
    reg = cb.registry_module()
    try:
        return reg.write_script(name, body.content)
    except reg.RegistryError as exc:
        raise HTTPException(status_code=400, detail=exc.message)


@router.get("/draw-config")
def get_draw_config(lottery: str | None = None, _: User = _user) -> dict[str, Any]:
    return cb.registry_module().get_draw_config(lottery)


@router.put("/draw-config/{lottery}")
def update_draw_config(lottery: str, body: DrawConfigUpdate, _: User = _staff) -> dict[str, Any]:
    reg = cb.registry_module()
    try:
        return reg.update_draw_config(lottery, body.model_dump(exclude_none=True))
    except reg.RegistryError as exc:
        raise HTTPException(status_code=400, detail=exc.message)


# --------------------------------------------------------------------------- #
# Source catalog (588080 / 顶尖大师 auto-discovery)
# --------------------------------------------------------------------------- #
@router.get("/catalog/status")
def catalog_status(_: User = _user) -> dict[str, Any]:
    return cb.catalog_status()


@router.post("/catalog/scan")
def catalog_scan(record: bool = True, _: User = _staff) -> dict[str, Any]:
    try:
        return cb.catalog_scan(record=record)
    except (ValueError, RuntimeError) as exc:
        raise _bad_request(exc)


# --------------------------------------------------------------------------- #
# Script execution & testing
# --------------------------------------------------------------------------- #
@router.post("/sources/{source_id}/test")
def test_source(
    source_id: str,
    req: SourceTestRequest = Body(default_factory=SourceTestRequest),
    _: User = _staff,
) -> dict[str, Any]:
    """Execute a single source script directly with detailed output & optional ingest."""
    try:
        return cb.test_source_script(
            source_id,
            lottery=req.lottery,
            period=req.period,
            fixture_dir=req.fixture_dir,
            do_ingest=req.ingest,
        )
    except Exception as exc:
        raise _bad_request(exc)


@router.post("/scripts/{name}/run")
def run_script(
    name: str,
    req: ScriptRunRequest = Body(default_factory=ScriptRunRequest),
    _: User = _staff,
) -> dict[str, Any]:
    """Execute any script in sources/ directly by filename."""
    try:
        return cb.run_script_by_name(
            name,
            lottery=req.lottery,
            period=req.period,
            fixture=req.fixture,
        )
    except Exception as exc:
        raise _bad_request(exc)


@router.get("/scripts/templates")
def script_templates(_: User = _user) -> list[dict[str, Any]]:
    """List available script templates."""
    return cb.registry_module().get_script_templates()


# --------------------------------------------------------------------------- #
# Data Ingestion & Comparison View (开奖与预测明细比对)
# --------------------------------------------------------------------------- #
@router.get("/comparison")
def get_comparison(lottery: Lottery, period: str, _: User = _user) -> dict[str, Any]:
    """Return aggregated official draw, source predictions, and JudgeResults for a period."""
    try:
        return cb.get_period_comparison(lottery, period)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


@router.post("/comparison/judge")
def judge_and_compare(req: JudgeRequest, _: User = _staff) -> dict[str, Any]:
    """Re-judge predictions for a period and immediately return updated comparison."""
    try:
        cb.judge(req.lottery, req.period)
        return cb.get_period_comparison(req.lottery, req.period)
    except (ValueError, KeyError) as exc:
        raise _bad_request(exc)


# --------------------------------------------------------------------------- #
# Automatic Draw Scheduler (开奖自动更新后台调度)
# --------------------------------------------------------------------------- #
@router.get("/draw-scheduler")
def get_draw_scheduler(_: User = _user) -> dict[str, Any]:
    """Get current auto-sync status, config, and recent logs."""
    from app.services.draw_scheduler import draw_scheduler

    return draw_scheduler.get_status()


@router.post("/draw-scheduler")
def update_draw_scheduler(
    body: DrawSchedulerConfig = Body(default_factory=DrawSchedulerConfig),
    trigger: bool = Query(False, description="Trigger immediate sync now"),
    _: User = _staff,
) -> dict[str, Any]:
    """Update auto-sync configuration or trigger an immediate sync."""
    from app.services.draw_scheduler import draw_scheduler

    if trigger:
        draw_scheduler.trigger_now()
    return draw_scheduler.set_config(
        enabled=body.enabled,
        start_time=body.start_time,
        end_time=body.end_time,
        interval_seconds=body.interval_seconds,
        lotteries=body.lotteries,
    )


# --------------------------------------------------------------------------- #
# Page Data Scraper (网页数据完整获取)
# --------------------------------------------------------------------------- #
class SiteDumpRequest(BaseModel):
    host: str | None = None
    timeout: float = 12.0
    include_html: bool = True
    include_modules: bool = False


@router.post("/site-dump/588080")
def dump_588080(
    req: SiteDumpRequest = Body(default_factory=SiteDumpRequest),
    _: User = _user,
) -> dict[str, Any]:
    """Fetch complete data and assembled HTML for 588080.com."""
    import sys
    from pathlib import Path

    collector_dir = Path(__file__).resolve().parent.parent.parent.parent / "collector"
    if str(collector_dir) not in sys.path:
        sys.path.insert(0, str(collector_dir))
    from collector.fetch_588080 import fetch_588080_full_page

    result = fetch_588080_full_page(
        host=req.host,
        timeout=req.timeout,
    )
    if not result.ok:
        raise HTTPException(status_code=502, detail=f"抓取 588080 失败: {result.error}")

    data: dict[str, Any] = result.to_summary()
    if req.include_html:
        data["html"] = result.html
        data["raw_html"] = result.raw_html
        data["raw_html_error"] = result.raw_html_error
    if req.include_modules:
        data["modules"] = result.modules
    return data


# --------------------------------------------------------------------------- #
# Source Collection Scheduled Tasks (数据源采集定时任务)
# --------------------------------------------------------------------------- #
@router.get("/schedules")
def list_collection_schedules(
    lottery: Lottery | None = None,
    _: User = _user,
) -> dict[str, Any]:
    """List all scheduled source collection tasks and scheduler status."""
    from app.services.source_scheduler import source_scheduler

    schedules = cb.list_schedules(lottery=lottery)
    return {
        "ok": True,
        "scheduler": source_scheduler.get_status(),
        "schedules": schedules,
    }


@router.post("/schedules")
def create_collection_schedule(
    req: ScheduleCreate,
    _: User = _staff,
) -> dict[str, Any]:
    """Create a new scheduled collection task (supports cron, time window, and start_at)."""
    from app.services.source_scheduler import source_scheduler
    import cron_util

    try:
        cron_expr = req.cron
        start_at = req.start_at
        end_at = req.end_at
        spec = dict(req.spec or {})
        if req.concurrency:
            spec["concurrency"] = req.concurrency

        # Time window shortcut support (e.g. 21:00 to 21:30 every N minutes)
        if req.time_window_start and req.time_window_end and req.interval_minutes:
            tw_start = req.time_window_start.strip()
            tw_end = req.time_window_end.strip()
            interval = int(req.interval_minutes)
            spec["time_window_start"] = tw_start
            spec["time_window_end"] = tw_end
            spec["interval_minutes"] = interval
            window_date = (req.window_date or "today").strip()
            spec["window_date"] = window_date

            if not cron_expr:
                cron_expr = cron_util.time_window_to_cron(tw_start, tw_end, interval)

            if window_date == "today" or (window_date != "daily" and len(window_date) == 10):
                target_date = cron_util.now_cn().strftime("%Y-%m-%d") if window_date == "today" else window_date
                if not start_at:
                    start_at = f"{target_date} {tw_start}:00"
                if not end_at:
                    end_at = f"{target_date} {tw_end}:00"

        item = cb.create_schedule(
            name=req.name,
            lottery=req.lottery,
            period=req.period,
            source_ids=req.source_ids,
            cron=cron_expr,
            start_at=start_at,
            end_at=end_at,
            enabled=req.enabled,
            do_ingest=req.do_ingest,
            auto_judge=req.auto_judge,
            spec=spec,
        )
        source_scheduler.wake()
        return {"ok": True, "schedule": item}
    except Exception as exc:
        raise _bad_request(exc)


@router.get("/schedules/logs")
def list_collection_schedule_logs(
    schedule_id: int | None = None,
    lottery: str | None = None,
    status: str | None = None,
    limit: int = 50,
    offset: int = 0,
    _: User = _user,
) -> dict[str, Any]:
    """List execution logs across all schedules with optional filters and pagination."""
    res = cb.list_schedule_logs(
        schedule_id=schedule_id,
        lottery=lottery,
        status=status,
        limit=limit,
        offset=offset,
    )
    return {
        "ok": True,
        "total": res["total"],
        "items": res["items"],
    }


@router.get("/schedules/logs/{log_id}")
def get_collection_schedule_log_detail(
    log_id: int,
    _: User = _user,
) -> dict[str, Any]:
    """Get detail of a single schedule execution log including full source return results."""
    row = cb.get_schedule_log(log_id)
    if not row:
        raise HTTPException(status_code=404, detail="Schedule log not found")
    return {"ok": True, "log": row}


@router.get("/schedules/{schedule_id}")
def get_collection_schedule(
    schedule_id: int,
    _: User = _user,
) -> dict[str, Any]:
    """Get details of a specific collection schedule."""
    item = cb.get_schedule(schedule_id)
    if not item:
        raise HTTPException(status_code=404, detail="Schedule not found")
    return {"ok": True, "schedule": item}


@router.put("/schedules/{schedule_id}")
def update_collection_schedule(
    schedule_id: int,
    req: ScheduleUpdate,
    _: User = _staff,
) -> dict[str, Any]:
    """Update a scheduled collection task."""
    from app.services.source_scheduler import source_scheduler
    import cron_util

    fields = req.model_dump(exclude_unset=True)

    tw_start = fields.pop("time_window_start", None)
    tw_end = fields.pop("time_window_end", None)
    tw_interval = fields.pop("interval_minutes", None)
    win_date = fields.pop("window_date", None)
    concurrency = fields.pop("concurrency", None)

    existing = cb.get_schedule(schedule_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Schedule not found")

    spec = dict(fields.get("spec") or existing.get("spec") or {})
    spec_changed = False

    if concurrency is not None:
        spec["concurrency"] = concurrency
        spec_changed = True

    if tw_start and tw_end and tw_interval:
        tw_start = tw_start.strip()
        tw_end = tw_end.strip()
        tw_interval = int(tw_interval)
        spec["time_window_start"] = tw_start
        spec["time_window_end"] = tw_end
        spec["interval_minutes"] = tw_interval
        window_date = (win_date or spec.get("window_date") or "today").strip()
        spec["window_date"] = window_date
        spec_changed = True

        if "cron" not in fields or not fields["cron"]:
            fields["cron"] = cron_util.time_window_to_cron(tw_start, tw_end, tw_interval)

        if window_date == "today" or (window_date != "daily" and len(window_date) == 10):
            target_date = cron_util.now_cn().strftime("%Y-%m-%d") if window_date == "today" else window_date
            if "start_at" not in fields or not fields["start_at"]:
                fields["start_at"] = f"{target_date} {tw_start}:00"
            if "end_at" not in fields or not fields["end_at"]:
                fields["end_at"] = f"{target_date} {tw_end}:00"

    if spec_changed or "spec" in fields:
        fields["spec"] = spec

    try:
        updated = cb.update_schedule(schedule_id, **fields)
        if not updated:
            raise HTTPException(status_code=404, detail="Schedule not found")
        source_scheduler.wake()
        return {"ok": True, "schedule": updated}
    except HTTPException:
        raise
    except Exception as exc:
        raise _bad_request(exc)


@router.delete("/schedules/{schedule_id}")
def delete_collection_schedule(
    schedule_id: int,
    _: User = _staff,
) -> dict[str, Any]:
    """Delete a scheduled collection task."""
    ok = cb.delete_schedule(schedule_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Schedule not found")
    return {"ok": True, "message": f"Schedule #{schedule_id} deleted"}


@router.post("/schedules/{schedule_id}/trigger")
async def trigger_collection_schedule(
    schedule_id: int,
    _: User = _staff,
) -> dict[str, Any]:
    """Immediately trigger execution of a collection schedule in background."""
    from app.services.source_scheduler import source_scheduler

    try:
        res = await source_scheduler.trigger_now(schedule_id)
        return {"ok": True, "result": res}
    except Exception as exc:
        raise _bad_request(exc)


@router.get("/schedules/{schedule_id}/logs")
def get_collection_schedule_logs(
    schedule_id: int,
    limit: int = 50,
    offset: int = 0,
    _: User = _user,
) -> dict[str, Any]:
    """Get recent execution logs for a specific schedule from database with per-source return results."""
    res = cb.list_schedule_logs(schedule_id=schedule_id, limit=limit, offset=offset)
    item = cb.get_schedule(schedule_id)
    return {
        "ok": True,
        "schedule": item,
        "total": res["total"],
        "logs": res["items"],
    }


