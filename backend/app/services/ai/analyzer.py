"""High-level AI analyzer orchestrator for scraped prediction data."""
from __future__ import annotations

import logging
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

# Ensure collector is accessible
COLLECTOR_DIR = Path(__file__).resolve().parent.parent.parent.parent / "collector"
if str(COLLECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_DIR))

from app.services.ai.client import AIResponse, BaseAIProvider, get_ai_client
from app.services.ai.formatter import format_scraped_data_for_ai
from app.services.ai.prompts import detect_period_from_data, get_prompt_template
from collector.fetch_588080 import fetch_588080_full_page

log = logging.getLogger("duiliao.ai.analyzer")


@dataclass
class AnalysisResult:
    ok: bool
    provider: str
    model: str
    prompt_id: str
    period: str
    analysis: str
    usage: dict[str, int]
    elapsed_sec: float
    scraped_summary: dict[str, Any]
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def analyze_scraped_data(
    *,
    scraped_data: dict[str, Any] | Any | None = None,
    prompt_id: str = "macau_analyst_expert",
    period: str | None = None,
    custom_prompt: str | None = None,
    provider: str | None = None,
    model: str | None = None,
    format_mode: str = "modules_summary",
    temperature: float = 0.7,
    api_key: str | None = None,
    base_url: str | None = None,
    client: BaseAIProvider | None = None,
) -> AnalysisResult:
    """Analyze scraped 588080.com prediction data with the selected AI model and prompt."""
    t0 = time.perf_counter()

    # 1. Fetch fresh data if not supplied
    if scraped_data is None:
        log.info("未提供抓取数据，正在实时从 588080.com 抓取最新数据...")
        scraped_data = fetch_588080_full_page()
        if not scraped_data.ok:
            return AnalysisResult(
                ok=False,
                provider=provider or "unknown",
                model=model or "unknown",
                prompt_id=prompt_id,
                period=period or "262",
                analysis="",
                usage={},
                elapsed_sec=round(time.perf_counter() - t0, 2),
                scraped_summary={},
                error=f"网页数据抓取失败: {scraped_data.error}",
            )

    scraped_summary = (
        scraped_data.to_summary() if hasattr(scraped_data, "to_summary") else (scraped_data.get("summary") or {})
    )

    # 2. Determine target period
    target_period = str(period).strip() if period else detect_period_from_data(scraped_data, default="262")

    # 3. Format context data
    formatted_context = format_scraped_data_for_ai(scraped_data, mode=format_mode)

    # 4. Construct prompt messages with dynamic period
    if custom_prompt:
        rendered_custom = custom_prompt.replace("{period}", target_period)
        messages = [
            {"role": "system", "content": "你是一位专业的澳门六合彩数据对料与预测分析专家。请根据用户提供的数据与要求进行严谨分析。"},
            {
                "role": "user",
                "content": f"{rendered_custom}\n\n【抓取数据内容如下】:\n---\n{formatted_context}\n---",
            },
        ]
        active_prompt_id = "custom"
    else:
        template = get_prompt_template(prompt_id)
        messages = template.render(context_data=formatted_context, period=target_period)
        active_prompt_id = template.id

    # 5. Invoke AI model
    try:
        ai_client = client or get_ai_client(
            provider=provider,
            api_key=api_key,
            base_url=base_url,
            model=model,
        )

        resp: AIResponse = ai_client.generate(
            messages,
            model=model,
            temperature=temperature,
        )

        elapsed = time.perf_counter() - t0
        return AnalysisResult(
            ok=True,
            provider=resp.provider,
            model=resp.model,
            prompt_id=active_prompt_id,
            period=target_period,
            analysis=resp.content,
            usage=resp.usage,
            elapsed_sec=round(elapsed, 2),
            scraped_summary=scraped_summary,
            error=None,
        )

    except Exception as e:
        elapsed = time.perf_counter() - t0
        log.exception("AI analysis failed: %s", e)
        return AnalysisResult(
            ok=False,
            provider=provider or "unknown",
            model=model or "unknown",
            prompt_id=active_prompt_id,
            period=target_period,
            analysis="",
            usage={},
            elapsed_sec=round(elapsed, 2),
            scraped_summary=scraped_summary,
            error=f"AI 分析调用失败: {str(e)}",
        )


def analyze_scraped_data_stream(
    *,
    scraped_data: dict[str, Any] | Any | None = None,
    prompt_id: str = "macau_analyst_expert",
    period: str | None = None,
    custom_prompt: str | None = None,
    provider: str | None = None,
    model: str | None = None,
    format_mode: str = "modules_summary",
    temperature: float = 0.7,
    api_key: str | None = None,
    base_url: str | None = None,
    client: BaseAIProvider | None = None,
):
    """Execute streaming AI analysis, yielding progress events and real-time delta tokens."""
    t0 = time.perf_counter()

    # 1. Fetch fresh data if not supplied
    if scraped_data is None:
        yield {"stage": "status", "message": "未检测到已抓取数据，正在实时抓取最新预测模块..."}
        scraped_data = fetch_588080_full_page()
        if not scraped_data.ok:
            yield {"stage": "error", "error": f"网页数据抓取失败: {scraped_data.error}"}
            return

    scraped_summary = (
        scraped_data.to_summary() if hasattr(scraped_data, "to_summary") else (scraped_data.get("summary") or {})
    )

    # 2. Determine target period
    target_period = str(period).strip() if period else detect_period_from_data(scraped_data, default="262")

    # 3. Format context data
    yield {"stage": "status", "message": "正在清洗提炼预测卡片数据..."}
    formatted_context = format_scraped_data_for_ai(scraped_data, mode=format_mode)

    # 4. Construct prompt messages with dynamic period
    if custom_prompt:
        rendered_custom = custom_prompt.replace("{period}", target_period)
        messages = [
            {"role": "system", "content": "你是一位专业的澳门六合彩数据对料与预测分析专家。请根据用户提供的数据与要求进行严谨分析。"},
            {
                "role": "user",
                "content": f"{rendered_custom}\n\n【抓取到的第 {target_period} 期全部预测数据如下】：\n---\n{formatted_context}\n---",
            },
        ]
        active_prompt_id = "custom"
    else:
        template = get_prompt_template(prompt_id or "macau_analyst_expert")
        messages = template.render(context_data=formatted_context, period=target_period)
        active_prompt_id = template.id

    yield {
        "stage": "started",
        "message": f"已成功连接大模型，正在对第 {target_period} 期进行流式对料研判...",
        "target_period": target_period,
        "scraped_summary": scraped_summary,
    }

    # 5. Invoke streaming AI model
    try:
        ai_client = client or get_ai_client(
            provider=provider,
            api_key=api_key,
            base_url=base_url,
            model=model,
        )

        for chunk in ai_client.generate_stream(
            messages,
            model=model,
            temperature=temperature,
        ):
            yield {"stage": "delta", "delta": chunk}

        elapsed = time.perf_counter() - t0
        yield {
            "stage": "done",
            "provider": provider or "openai",
            "model": model or ai_client.default_model,
            "period": target_period,
            "prompt_id": active_prompt_id,
            "elapsed_sec": round(elapsed, 2),
            "scraped_summary": scraped_summary,
        }

    except Exception as e:
        elapsed = time.perf_counter() - t0
        log.exception("Stream AI analysis failed: %s", e)
        yield {
            "stage": "error",
            "error": f"AI 分析调用失败: {str(e)}",
            "elapsed_sec": round(elapsed, 2),
        }


# ---------------------------------------------------------------------------
# Zodiac Streak Analysis (跨期连肖分析)
# ---------------------------------------------------------------------------

def analyze_zodiac_streaks(
    *,
    lottery: str = "macau",
    num_periods: int = 30,
    min_streak: int = 3,
    prompt_id: str = "zodiac_streak_analysis",
    custom_prompt: str | None = None,
    provider: str | None = None,
    model: str | None = None,
    temperature: float = 0.7,
    api_key: str | None = None,
    base_url: str | None = None,
    client: BaseAIProvider | None = None,
) -> AnalysisResult:
    """Analyze zodiac streaks across N periods with the selected AI model."""
    from app.services.ai.zodiac_streak import (
        compute_streaks,
        format_zodiac_streak_for_ai,
        get_zodiac_by_periods,
    )

    t0 = time.perf_counter()

    # 1. Fetch draw data
    try:
        period_data = get_zodiac_by_periods(lottery=lottery, num_periods=num_periods)
    except Exception as e:
        return AnalysisResult(
            ok=False, provider=provider or "unknown", model=model or "unknown",
            prompt_id=prompt_id, period="", analysis="", usage={},
            elapsed_sec=round(time.perf_counter() - t0, 2), scraped_summary={},
            error=f"查询开奖数据失败: {str(e)}",
        )

    if not period_data:
        return AnalysisResult(
            ok=False, provider=provider or "unknown", model=model or "unknown",
            prompt_id=prompt_id, period="", analysis="", usage={},
            elapsed_sec=round(time.perf_counter() - t0, 2), scraped_summary={},
            error="数据库中没有找到开奖记录，请先同步开奖数据。",
        )

    # 2. Compute streak statistics
    streak_stats = compute_streaks(period_data, min_streak=min_streak)

    # 3. Format context for AI
    formatted_context = format_zodiac_streak_for_ai(period_data, streak_stats)

    # Determine the next target period
    latest_period = period_data[-1]["period"]
    try:
        target_period = str(int(latest_period) + 1)
    except ValueError:
        target_period = latest_period

    # 4. Construct prompt messages
    if custom_prompt:
        rendered_custom = custom_prompt.replace("{period}", target_period)
        messages = [
            {"role": "system", "content": "你是一位专业的六合彩生肖走势与连码规律分析专家。请根据用户提供的历史开奖生肖数据进行严谨分析。"},
            {"role": "user", "content": f"{rendered_custom}\n\n{formatted_context}"},
        ]
        active_prompt_id = "custom"
    else:
        template = get_prompt_template(prompt_id)
        messages = template.render(context_data=formatted_context, period=target_period)
        active_prompt_id = template.id

    # 5. Invoke AI model
    try:
        ai_client = client or get_ai_client(
            provider=provider, api_key=api_key, base_url=base_url, model=model,
        )
        resp: AIResponse = ai_client.generate(messages, model=model, temperature=temperature)

        elapsed = time.perf_counter() - t0
        return AnalysisResult(
            ok=True, provider=resp.provider, model=resp.model,
            prompt_id=active_prompt_id, period=target_period,
            analysis=resp.content, usage=resp.usage,
            elapsed_sec=round(elapsed, 2),
            scraped_summary={
                "lottery": lottery,
                "num_periods": num_periods,
                "min_streak": min_streak,
                "period_range": streak_stats.get("period_range", {}),
                "active_streaks_count": len(streak_stats.get("active_streaks", [])),
            },
        )
    except Exception as e:
        elapsed = time.perf_counter() - t0
        log.exception("Zodiac streak AI analysis failed: %s", e)
        return AnalysisResult(
            ok=False, provider=provider or "unknown", model=model or "unknown",
            prompt_id=active_prompt_id, period=target_period,
            analysis="", usage={},
            elapsed_sec=round(elapsed, 2), scraped_summary={},
            error=f"AI 分析调用失败: {str(e)}",
        )


def analyze_zodiac_streaks_stream(
    *,
    lottery: str = "macau",
    num_periods: int = 30,
    min_streak: int = 3,
    prompt_id: str = "zodiac_streak_analysis",
    custom_prompt: str | None = None,
    provider: str | None = None,
    model: str | None = None,
    temperature: float = 0.7,
    api_key: str | None = None,
    base_url: str | None = None,
    client: BaseAIProvider | None = None,
):
    """Stream zodiac streak AI analysis, yielding progress events and real-time tokens."""
    from app.services.ai.zodiac_streak import (
        compute_streaks,
        format_zodiac_streak_for_ai,
        get_zodiac_by_periods,
    )

    t0 = time.perf_counter()

    # 1. Fetch draw data
    yield {"stage": "status", "message": f"正在查询最近 {num_periods} 期开奖数据..."}
    try:
        period_data = get_zodiac_by_periods(lottery=lottery, num_periods=num_periods)
    except Exception as e:
        yield {"stage": "error", "error": f"查询开奖数据失败: {str(e)}"}
        return

    if not period_data:
        yield {"stage": "error", "error": "数据库中没有找到开奖记录，请先同步开奖数据。"}
        return

    # 2. Compute streak statistics
    yield {"stage": "status", "message": f"已获取 {len(period_data)} 期数据，正在计算连肖走势统计..."}
    streak_stats = compute_streaks(period_data, min_streak=min_streak)

    # 3. Format context for AI
    formatted_context = format_zodiac_streak_for_ai(period_data, streak_stats)

    # Determine the next target period
    latest_period = period_data[-1]["period"]
    try:
        target_period = str(int(latest_period) + 1)
    except ValueError:
        target_period = latest_period

    # 4. Construct prompt messages
    if custom_prompt:
        rendered_custom = custom_prompt.replace("{period}", target_period)
        messages = [
            {"role": "system", "content": "你是一位专业的六合彩生肖走势与连码规律分析专家。请根据用户提供的历史开奖生肖数据进行严谨分析。"},
            {"role": "user", "content": f"{rendered_custom}\n\n{formatted_context}"},
        ]
        active_prompt_id = "custom"
    else:
        template = get_prompt_template(prompt_id or "zodiac_streak_analysis")
        messages = template.render(context_data=formatted_context, period=target_period)
        active_prompt_id = template.id

    active_count = len(streak_stats.get("active_streaks", []))
    yield {
        "stage": "started",
        "message": f"已连接大模型，正在分析 {len(period_data)} 期生肖连码走势（发现 {active_count} 个活跃连码）...",
        "target_period": target_period,
        "streak_summary": {
            "lottery": lottery,
            "num_periods": len(period_data),
            "min_streak": min_streak,
            "period_range": streak_stats.get("period_range", {}),
            "active_streaks_count": active_count,
        },
    }

    # 5. Invoke streaming AI model
    try:
        ai_client = client or get_ai_client(
            provider=provider, api_key=api_key, base_url=base_url, model=model,
        )
        for chunk in ai_client.generate_stream(messages, model=model, temperature=temperature):
            yield {"stage": "delta", "delta": chunk}

        elapsed = time.perf_counter() - t0
        yield {
            "stage": "done",
            "provider": provider or "openai",
            "model": model or ai_client.default_model,
            "period": target_period,
            "prompt_id": active_prompt_id,
            "elapsed_sec": round(elapsed, 2),
        }
    except Exception as e:
        elapsed = time.perf_counter() - t0
        log.exception("Zodiac streak stream AI analysis failed: %s", e)
        yield {
            "stage": "error",
            "error": f"AI 分析调用失败: {str(e)}",
            "elapsed_sec": round(elapsed, 2),
        }

