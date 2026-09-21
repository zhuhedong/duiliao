"""AI Analysis API endpoints for scraped lottery data and prompt templates."""
from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app import collector_bridge as cb
from app.api.deps import get_current_user, require_roles
from app.models.user import User, UserRole
from app.services.ai.analyzer import analyze_scraped_data, analyze_scraped_data_stream
from app.services.ai.prompts import list_prompt_templates

router = APIRouter(prefix="/ai", tags=["ai"])
_user = Depends(get_current_user)


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
        description="Optional custom prompt. If provided, overrides the preset template.",
    )
    provider: str | None = Field(
        default=None,
        description="AI Provider: openai (default, DeepSeek/Qwen/Kimi/OpenAI), gemini, or anthropic",
    )
    model: str | None = Field(
        default=None,
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


@router.get("/prompts")
def get_prompts(_: User = _user) -> list[dict[str, Any]]:
    """List all available preset prompt templates for data analysis."""
    return list_prompt_templates()


@router.post("/analyze-588080")
def analyze_588080_page(
    req: AIAnalyzeRequest = Body(...),
    _: User = _user,
) -> dict[str, Any]:
    """Execute AI analysis on 588080.com scraped data using the specified prompt and model."""
    data_source = None
    if not req.fetch_fresh:
        if not req.custom_data:
            raise HTTPException(status_code=400, detail="fetch_fresh 为 false 时必须提供 custom_data 数据对象")
        data_source = req.custom_data

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


    if not result.ok:
        raise HTTPException(status_code=502, detail=result.error)

    return result.to_dict()


@router.post("/analyze-stream")
def analyze_stream_page(
    req: AIAnalyzeRequest = Body(...),
    _: User = _user,
):
    """Stream AI analysis progress and generation tokens in real time (SSE)."""
    data_source = None
    if not req.fetch_fresh:
        if not req.custom_data:
            raise HTTPException(status_code=400, detail="fetch_fresh 为 false 时必须提供 custom_data 数据对象")
        data_source = req.custom_data

    def event_stream():
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
_staff = Depends(require_roles(UserRole.ADMIN, UserRole.STAFF))


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
