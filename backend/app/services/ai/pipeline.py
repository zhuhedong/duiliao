"""Pipeline orchestrator for: Scraped Data -> Custom Prompt -> AI Judgment -> Resend Email Dispatch."""
from __future__ import annotations

import logging
import time
from typing import Any

from app.services.ai.analyzer import AnalysisResult, analyze_scraped_data
from app.services.ai.scraped_data import load_latest_scraped_data
from app.services.email_service import (
    get_email_config,
    render_ai_report_email,
    send_smtp_email,
)
from collector.fetch_588080 import FetchResult, fetch_588080_full_page

logger = logging.getLogger("duiliao.ai.pipeline")


def run_ai_judgment_pipeline(
    *,
    prompt_id: str = "macau_analyst_expert",
    custom_prompt: str | None = None,
    period: str | None = None,
    provider: str | None = None,
    model: str | None = None,
    format_mode: str = "modules_summary",
    temperature: float = 0.7,
    fetch_fresh: bool = True,
    recipients: list[str] | str | None = None,
    subject: str | None = None,
    task_name: str = "澳门六合彩帖文 AI 智能研判",
    send_email: bool = True,
) -> dict[str, Any]:
    """Execute the end-to-end intelligence pipeline:

    1. Fetch / load scraped 588080.com post & prediction data.
    2. Format denoised context & render custom prompt template.
    3. Run AI judgment via selected LLM provider.
    4. Render rich HTML email template.
    5. Deliver via Resend SMTP (smtp.resend.com) to target recipient(s).
    """
    t0 = time.perf_counter()
    data_source: Any = None

    # Step 1: Scrape web data (reusing AI 研判 data pipeline)
    if fetch_fresh:
        logger.info("Pipeline Step 1: Fetching fresh scraped data from 588080.com...")
        try:
            fetch_res = fetch_588080_full_page(include_raw_html=False)
            if fetch_res.ok:
                data_source = fetch_res
                try:
                    from app.services.ai.scraped_data import save_scraped_data

                    save_scraped_data(fetch_res)
                except Exception as save_err:
                    logger.warning("Failed to save scraped cache: %s", save_err)
            else:
                logger.warning("Fresh scrape returned not ok: %s, falling back to cached dump", fetch_res.error)
                data_source = load_latest_scraped_data(max_age_sec=3600 * 24)
        except Exception as exc:
            logger.warning("Fresh scrape failed with exception: %s, falling back to cached dump", exc)
            data_source = load_latest_scraped_data(max_age_sec=3600 * 24)

    if data_source is None:
        data_source = load_latest_scraped_data(max_age_sec=3600 * 24)

    # If still None (e.g. fetch_fresh was false or cache empty), force live scrape
    if data_source is None:
        logger.info("No cache available, performing live scrape from 588080.com...")
        try:
            fetch_res = fetch_588080_full_page(include_raw_html=False)
            if fetch_res.ok:
                data_source = fetch_res
                try:
                    from app.services.ai.scraped_data import save_scraped_data

                    save_scraped_data(fetch_res)
                except Exception:
                    pass
            else:
                raise ValueError(f"在线抓取网页数据失败: {fetch_res.error or '连接超时或页面异常'}")
        except Exception as exc:
            raise ValueError(f"自动抓取网页发生异常: {exc}") from exc

    # Step 2 & 3: Run AI Analysis
    logger.info("Pipeline Step 2 & 3: Running AI analysis with prompt_id=%s, model=%s, format_mode=%s...", prompt_id, model or "default", format_mode)
    analysis_result: AnalysisResult = analyze_scraped_data(
        scraped_data=data_source,
        prompt_id=prompt_id,
        period=period,
        custom_prompt=custom_prompt,
        provider=provider,
        model=model,
        format_mode=format_mode,
        temperature=temperature,
    )

    if not analysis_result.ok:
        raise RuntimeError(f"AI 研判失败: {analysis_result.error or '未知模型错误'}")

    target_period = analysis_result.period or period or "最新"

    # Step 4 & 5: Render HTML report and send via Resend SMTP
    email_delivery: dict[str, Any] = {"sent": False}
    if send_email:
        logger.info("Pipeline Step 4 & 5: Preparing email delivery via Resend...")
        email_cfg = get_email_config(mask=False)

        # Resolve recipient list
        actual_recipients: list[str] = []
        if recipients:
            if isinstance(recipients, str):
                actual_recipients = [r.strip() for r in recipients.replace(";", ",").split(",") if r.strip()]
            else:
                actual_recipients = [str(r).strip() for r in recipients if str(r).strip()]
        elif email_cfg.get("default_recipients"):
            raw_rec = email_cfg["default_recipients"]
            actual_recipients = [r.strip() for r in raw_rec.replace(";", ",").split(",") if r.strip()]

        if not actual_recipients:
            logger.warning("No email recipients specified or configured in system settings. Email skipped.")
            email_delivery = {
                "sent": False,
                "reason": "no_recipients",
                "message": "未配置收件人邮箱，已跳过发信（研判结果已生成）",
            }
        elif not email_cfg.get("smtp_password"):
            logger.warning("Resend SMTP password / API Key not configured. Email skipped.")
            email_delivery = {
                "sent": False,
                "reason": "no_api_key",
                "message": "系统设置中未配置 Resend API Key，已跳过发信（研判结果已生成）",
            }
        else:
            email_subject = subject or f"【对撩】第 {target_period} 期 帖文 AI 研判报告"
            html_content = render_ai_report_email(
                task_name=task_name,
                period=target_period,
                markdown_content=analysis_result.analysis,
                model_name=f"{analysis_result.provider}/{analysis_result.model}",
                elapsed_sec=analysis_result.elapsed_sec,
            )

            try:
                send_res = send_smtp_email(
                    to_emails=actual_recipients,
                    subject=email_subject,
                    html_content=html_content,
                    text_content=analysis_result.analysis,
                    config=email_cfg,
                )
                email_delivery = {
                    "sent": True,
                    "recipients": send_res.get("recipients", []),
                    "elapsed_ms": send_res.get("elapsed_ms", 0),
                    "subject": email_subject,
                }
            except Exception as exc:
                logger.exception("Failed to deliver pipeline report email: %s", exc)
                email_delivery = {
                    "sent": False,
                    "reason": "send_failed",
                    "error": str(exc),
                }

    total_elapsed = round(time.perf_counter() - t0, 2)
    logger.info("Intelligence pipeline completed in %ss (email sent: %s)", total_elapsed, email_delivery.get("sent"))

    return {
        "ok": True,
        "period": target_period,
        "analysis": analysis_result.analysis,
        "provider": analysis_result.provider,
        "model": analysis_result.model,
        "prompt_id": analysis_result.prompt_id,
        "elapsed_sec": analysis_result.elapsed_sec,
        "total_elapsed_sec": total_elapsed,
        "usage": analysis_result.usage,
        "scraped_summary": analysis_result.scraped_summary,
        "email_delivery": email_delivery,
    }
