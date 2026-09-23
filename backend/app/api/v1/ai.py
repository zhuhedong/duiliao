"""AI Analysis API endpoints for scraped lottery data and prompt templates."""
from __future__ import annotations

import json
import threading
from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field, field_validator

from app import collector_bridge as cb
from app.api.deps import get_current_user, require_roles
from app.models.user import User, UserRole
from app.services.ai.analyzer import (
    analyze_scraped_data,
    analyze_scraped_data_stream,
    analyze_zodiac_streaks,
    analyze_zodiac_streaks_stream,
)
from app.services.ai.prompts import list_prompt_templates

router = APIRouter(prefix="/ai", tags=["ai"])
_user = Depends(get_current_user)
_staff = Depends(require_roles(UserRole.ADMIN, UserRole.STAFF))
_AI_CONCURRENCY = threading.BoundedSemaphore(2)


class AIAnalyzeRequest(BaseModel):
    prompt_id: str = Field(
        default="macau_analyst_expert",
        description="Prompt template ID: macau_analyst_expert, consensus_synthesis, structured_extraction, risk_and_kill, summary_digest",
    )
    period: str | None = Field(
        default="262",
        description="目标期号（动态替换进提示词中，如 262）",
    )
    custom_prompt: str | None = Field(
        default=None,
        max_length=12000,
        description="Optional custom prompt. If provided, overrides the preset template.",
    )
    provider: str | None = Field(
        default=None,
        max_length=64,
        description="AI Provider: openai (default, DeepSeek/Qwen/Kimi/OpenAI), gemini, or anthropic",
    )
    model: str | None = Field(
        default=None,
        max_length=128,
        description="Optional model override (e.g. deepseek-chat, gemini-2.5-flash, claude-3-5-sonnet)",
    )
    format_mode: str = Field(
        default="modules_summary",
        description="Context formatting mode: 'modules_summary' (denoised text, recommended) or 'raw_html'",
    )
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)
    fetch_fresh: bool = Field(
        default=True,
        description="Whether to fetch fresh data from 588080.com. If false, custom_data must be supplied.",
    )
    custom_data: dict[str, Any] | None = Field(
        default=None,
        description="Optional pre-fetched data object to analyze instead of fetching fresh.",
    )

    @field_validator("custom_data")
    @classmethod
    def _limit_custom_data(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        if value is None:
            return None
        try:
            encoded = json.dumps(value, ensure_ascii=False, default=str)
        except (TypeError, ValueError) as exc:
            raise ValueError("custom_data 必须是可序列化的数据对象") from exc
        if len(encoded.encode("utf-8")) > 1_000_000:
            raise ValueError("custom_data 不能超过 1 MB")
        if len(value) > 10_000:
            raise ValueError("custom_data 顶层字段不能超过 10000 个")
        return value


@router.get("/prompts")
def get_prompts(_: User = _user) -> list[dict[str, Any]]:
    """List all available preset prompt templates for data analysis."""
    return list_prompt_templates()


@router.post("/analyze-588080")
def analyze_588080_page(
    req: AIAnalyzeRequest = Body(...),
    _: User = _staff,
) -> dict[str, Any]:
    """Execute AI analysis on 588080.com scraped data using the specified prompt and model."""
    data_source = None
    if not req.fetch_fresh:
        if not req.custom_data:
            raise HTTPException(status_code=400, detail="fetch_fresh 为 false 时必须提供 custom_data 数据对象")
        data_source = req.custom_data

    if not _AI_CONCURRENCY.acquire(timeout=5):
        raise HTTPException(status_code=429, detail="AI 分析任务较多，请稍后重试")
    try:
        result = analyze_scraped_data(
            scraped_data=data_source,
            prompt_id=req.prompt_id,
            period=req.period,
            custom_prompt=req.custom_prompt,
            provider=req.provider,
            model=req.model,
            format_mode=req.format_mode,
            temperature=req.temperature,
        )
    finally:
        _AI_CONCURRENCY.release()


    if not result.ok:
        raise HTTPException(status_code=502, detail=result.error)

    return result.to_dict()


@router.post("/analyze-stream")
def analyze_stream_page(
    req: AIAnalyzeRequest = Body(...),
    _: User = _staff,
):
    """Stream AI analysis progress and generation tokens in real time (SSE)."""
    data_source = None
    if not req.fetch_fresh:
        if not req.custom_data:
            raise HTTPException(status_code=400, detail="fetch_fresh 为 false 时必须提供 custom_data 数据对象")
        data_source = req.custom_data

    if not _AI_CONCURRENCY.acquire(timeout=5):
        raise HTTPException(status_code=429, detail="AI 分析任务较多，请稍后重试")

    def event_stream():
        try:
            for event in analyze_scraped_data_stream(
                scraped_data=data_source,
                prompt_id=req.prompt_id,
                period=req.period,
                custom_prompt=req.custom_prompt,
                provider=req.provider,
                model=req.model,
                format_mode=req.format_mode,
                temperature=req.temperature,
            ):
                yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
        finally:
            _AI_CONCURRENCY.release()

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )



# --------------------------------------------------------------------------- #
# Cached reports
# --------------------------------------------------------------------------- #
# `analyze-588080` defaults to fetch_fresh=True, so every call makes this process
# scrape 588080 and bill an LLM request. With a mobile client that is one outbound
# scrape and one LLM invoice per user per view. These endpoints separate reading a
# report (any signed-in user, free) from producing one (staff/admin, paid).
class AIReportGenerateRequest(AIAnalyzeRequest):
    lottery: str = Field(default="macau", description="Lottery the report belongs to")


@router.get("/report")
def get_ai_report(
    lottery: str = "macau",
    period: str = "",
    prompt_id: str = "macau_analyst_expert",
    _: User = _user,
) -> dict[str, Any]:
    """Return the cached report for (lottery, period, prompt_id), or 404.

    Never triggers generation — a read must not be able to run up an LLM bill.
    """
    if not period.strip():
        raise HTTPException(status_code=400, detail="period is required")
    report = cb.get_ai_report(lottery, period.strip(), prompt_id)
    if report is None:
        raise HTTPException(status_code=404, detail="no cached report for this period")
    return report


@router.get("/reports")
def list_ai_reports(
    lottery: str | None = None,
    limit: int = 20,
    _: User = _user,
) -> dict[str, Any]:
    """Metadata for recently generated reports (no content), for a picker."""
    return {"ok": True, "items": cb.list_ai_reports(lottery=lottery, limit=limit)}


@router.post("/report/generate")
def generate_ai_report(
    req: AIReportGenerateRequest = Body(...),
    user: User = _staff,
) -> dict[str, Any]:
    """Generate a report and upsert it into the cache. Staff/admin only."""
    if not req.period or not req.period.strip():
        raise HTTPException(status_code=400, detail="period is required")

    data_source = None
    if not req.fetch_fresh:
        if not req.custom_data:
            raise HTTPException(
                status_code=400, detail="fetch_fresh 为 false 时必须提供 custom_data 数据对象"
            )
        data_source = req.custom_data

    result = analyze_scraped_data(
        scraped_data=data_source,
        prompt_id=req.prompt_id,
        custom_prompt=req.custom_prompt,
        provider=req.provider,
        model=req.model,
        format_mode=req.format_mode,
        temperature=req.temperature,
        period=req.period,
    )
    if not result.ok:
        raise HTTPException(status_code=502, detail=result.error)

    payload = result.to_dict()
    saved = cb.save_ai_report(
        lottery=req.lottery,
        period=req.period.strip(),
        # A custom prompt is cached under "custom" so it cannot overwrite the
        # cached report for a named preset.
        prompt_id="custom" if req.custom_prompt else req.prompt_id,
        content=payload.get("analysis") or "",
        provider=payload.get("provider"),
        model=payload.get("model"),
        elapsed_sec=payload.get("elapsed_sec"),
        scraped_summary=payload.get("scraped_summary"),
        generated_by=user.id,
    )
    return saved


# --------------------------------------------------------------------------- #
# Zodiac streak analysis (跨期连肖分析)
# --------------------------------------------------------------------------- #
class ZodiacStreakRequest(BaseModel):
    lottery: str = Field(default="macau", description="彩种: macau, hk")
    num_periods: int = Field(default=30, ge=5, le=500, description="查询最近 N 期（默认 30）")
    min_streak: int = Field(default=3, ge=2, le=20, description="最小连码长度（默认 3，即三连起）")
    prompt_id: str = Field(
        default="zodiac_streak_analysis",
        description="Prompt template ID for streak analysis",
    )
    custom_prompt: str | None = Field(
        default=None,
        max_length=12000,
        description="Optional custom prompt overriding the preset template",
    )
    provider: str | None = Field(default=None, max_length=64)
    model: str | None = Field(default=None, max_length=128)
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)


@router.get("/zodiac-streak-data")
def get_zodiac_streak_data(
    lottery: str = "macau",
    num_periods: int = 30,
    min_streak: int = 3,
    _: User = _user,
) -> dict[str, Any]:
    """Return pre-computed zodiac streak statistics without invoking AI.

    Useful for previewing the data before running an AI analysis.
    """
    from app.services.ai.zodiac_streak import compute_streaks, get_zodiac_by_periods

    num_periods = max(5, min(num_periods, 500))
    min_streak = max(2, min(min_streak, 20))

    period_data = get_zodiac_by_periods(lottery=lottery, num_periods=num_periods)
    if not period_data:
        raise HTTPException(status_code=404, detail="没有找到开奖记录，请先同步开奖数据")

    streak_stats = compute_streaks(period_data, min_streak=min_streak)

    # Remove the large presence matrix from the response to save bandwidth
    # (the frontend can reconstruct it from period_data if needed)
    response_stats = {k: v for k, v in streak_stats.items() if k != "xiao_presence"}

    return {
        "ok": True,
        "lottery": lottery,
        "num_periods": len(period_data),
        "min_streak": min_streak,
        "periods": period_data,
        "streaks": response_stats,
    }


@router.post("/zodiac-streak-analyze")
def zodiac_streak_analyze(
    req: ZodiacStreakRequest = Body(...),
    _: User = _staff,
) -> dict[str, Any]:
    """Synchronous AI analysis of zodiac streaks across N periods."""
    if not _AI_CONCURRENCY.acquire(timeout=5):
        raise HTTPException(status_code=429, detail="AI 分析任务较多，请稍后重试")
    try:
        result = analyze_zodiac_streaks(
            lottery=req.lottery,
            num_periods=req.num_periods,
            min_streak=req.min_streak,
            prompt_id=req.prompt_id,
            custom_prompt=req.custom_prompt,
            provider=req.provider,
            model=req.model,
            temperature=req.temperature,
        )
    finally:
        _AI_CONCURRENCY.release()

    if not result.ok:
        raise HTTPException(status_code=502, detail=result.error)
    return result.to_dict()


@router.post("/zodiac-streak-stream")
def zodiac_streak_stream(
    req: ZodiacStreakRequest = Body(...),
    _: User = _staff,
):
    """Stream zodiac streak AI analysis progress and tokens in real time (SSE)."""
    if not _AI_CONCURRENCY.acquire(timeout=5):
        raise HTTPException(status_code=429, detail="AI 分析任务较多，请稍后重试")

    def event_stream():
        try:
            for event in analyze_zodiac_streaks_stream(
                lottery=req.lottery,
                num_periods=req.num_periods,
                min_streak=req.min_streak,
                prompt_id=req.prompt_id,
                custom_prompt=req.custom_prompt,
                provider=req.provider,
                model=req.model,
                temperature=req.temperature,
            ):
                yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
        finally:
            _AI_CONCURRENCY.release()

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
