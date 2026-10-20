"""Email delivery service using SMTP (specifically optimized for Resend: smtp.resend.com)."""
from __future__ import annotations

import logging
import smtplib
import time
from email.header import Header
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr
from typing import Any

import markdown2
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.setting import SystemSetting

logger = logging.getLogger("duiliao.email")

DEFAULT_SMTP_HOST = "smtp.resend.com"
DEFAULT_SMTP_PORT = 465
DEFAULT_SMTP_USER = "resend"
DEFAULT_FROM_NAME = "对撩 AI 研判中心"
DEFAULT_FROM_EMAIL = "onboarding@resend.dev"


def _clean_str(val: Any, default: str = "") -> str:
    if val is None:
        return default
    s = str(val).strip()
    return s if s else default


def get_email_config(db: Session | None = None, mask: bool = False) -> dict[str, Any]:
    """Retrieve current email settings from DB with fallback to Resend defaults."""
    close_db = False
    if db is None:
        db = SessionLocal()
        close_db = True

    try:
        from app.services.settings_service import get_setting_value, mask_api_key

        host = get_setting_value(db, "email_smtp_host", DEFAULT_SMTP_HOST)
        port_raw = get_setting_value(db, "email_smtp_port", str(DEFAULT_SMTP_PORT))
        try:
            port = int(port_raw)
        except ValueError:
            port = DEFAULT_SMTP_PORT

        user = get_setting_value(db, "email_smtp_user", DEFAULT_SMTP_USER)
        password = get_setting_value(db, "email_smtp_password", "")
        from_email = get_setting_value(db, "email_from_addr", DEFAULT_FROM_EMAIL)
        from_name = get_setting_value(db, "email_from_name", DEFAULT_FROM_NAME)
        default_recipients = get_setting_value(db, "email_default_recipients", "")

        return {
            "smtp_host": host,
            "smtp_port": port,
            "smtp_user": user,
            "smtp_password": mask_api_key(password) if mask else password,
            "from_email": from_email,
            "from_name": from_name,
            "default_recipients": default_recipients,
            "is_configured": bool(password.strip()),
        }
    finally:
        if close_db:
            db.close()


def send_smtp_email(
    *,
    to_emails: list[str] | str,
    subject: str,
    html_content: str,
    text_content: str | None = None,
    config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Send an email via SMTP.

    If config is omitted, loads it from database.
    """
    t0 = time.perf_counter()
    cfg = config or get_email_config(mask=False)

    host = _clean_str(cfg.get("smtp_host"), DEFAULT_SMTP_HOST)
    port = int(cfg.get("smtp_port") or DEFAULT_SMTP_PORT)
    user = _clean_str(cfg.get("smtp_user"), DEFAULT_SMTP_USER)
    password = _clean_str(cfg.get("smtp_password"))
    from_email = _clean_str(cfg.get("from_email"), DEFAULT_FROM_EMAIL)
    from_name = _clean_str(cfg.get("from_name"), DEFAULT_FROM_NAME)

    if not password:
        raise ValueError("SMTP 密码/API Key 未配置，请先在系统设置中配置 Resend API Key")

    # Normalize recipients
    if isinstance(to_emails, str):
        recipients = [e.strip() for e in to_emails.replace(";", ",").split(",") if e.strip()]
    else:
        recipients = [str(e).strip() for e in to_emails if str(e).strip()]

    if not recipients:
        raise ValueError("收件人列表为空，请至少提供一个有效的接收邮箱地址")

    # Build MIME message
    msg = MIMEMultipart("alternative")
    msg["Subject"] = Header(subject, "utf-8")
    msg["From"] = formataddr((str(Header(from_name, "utf-8")), from_email))
    msg["To"] = ", ".join(recipients)

    if text_content:
        msg.attach(MIMEText(text_content, "plain", "utf-8"))
    msg.attach(MIMEText(html_content, "html", "utf-8"))

    logger.info("Connecting to SMTP %s:%d (user=%s) for %d recipients...", host, port, user, len(recipients))

    try:
        if port == 465:
            server = smtplib.SMTP_SSL(host, port, timeout=25.0)
            server.ehlo()
        else:
            server = smtplib.SMTP(host, port, timeout=25.0)
            server.ehlo()
            server.starttls()
            server.ehlo()

        server.login(user, password)
        server.sendmail(from_email, recipients, msg.as_string())
        server.quit()
    except Exception as exc:
        logger.exception("Failed to send email via SMTP %s:%d: %s", host, port, exc)
        raise RuntimeError(f"邮件发送失败: {exc}") from exc

    elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
    logger.info("Email sent successfully in %s ms to %s", elapsed_ms, recipients)
    return {
        "ok": True,
        "recipients": recipients,
        "elapsed_ms": elapsed_ms,
        "from": from_email,
        "subject": subject,
    }


def render_ai_report_email(
    *,
    task_name: str = "帖文 AI 智能研判",
    period: str = "",
    markdown_content: str,
    model_name: str = "",
    elapsed_sec: float = 0.0,
    generated_time: str = "",
) -> str:
    """Transform markdown AI judgment report into a clean, modern responsive HTML email."""
    if not generated_time:
        generated_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

    # Convert markdown to html with extended features
    rendered_body = markdown2.markdown(
        markdown_content,
        extras=[
            "tables",
            "fenced-code-blocks",
            "strike",
            "cuddled-lists",
            "break-on-newline",
        ],
    )

    # Wrap inside responsive HTML template with inline styles
    html = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{task_name}</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #1e293b;
      background-color: #f8fafc;
      margin: 0;
      padding: 24px 12px;
    }}
    .email-container {{
      max-width: 680px;
      margin: 0 auto;
      background: #ffffff;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 4px 20px -2px rgba(0, 0, 0, 0.06);
      border: 1px solid #e2e8f0;
    }}
    .header {{
      background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%);
      padding: 32px 28px;
      color: #ffffff;
    }}
    .badge {{
      display: inline-block;
      padding: 4px 12px;
      background: rgba(255, 255, 255, 0.2);
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
    }}
    .title {{
      font-size: 22px;
      font-weight: 800;
      margin: 0 0 8px 0;
      line-height: 1.3;
    }}
    .meta-bar {{
      font-size: 13px;
      opacity: 0.9;
    }}
    .meta-bar span {{
      margin-right: 16px;
    }}
    .content {{
      padding: 32px 28px;
      font-size: 15px;
      line-height: 1.7;
      color: #334155;
    }}
    .content h1, .content h2, .content h3 {{
      color: #0f172a;
      font-weight: 700;
      margin-top: 24px;
      margin-bottom: 12px;
    }}
    .content h1 {{ font-size: 20px; border-bottom: 2px solid #e2e8f0; padding-bottom: 8px; }}
    .content h2 {{ font-size: 18px; color: #4338ca; }}
    .content h3 {{ font-size: 16px; }}
    .content p {{ margin: 0 0 16px 0; }}
    .content ul, .content ol {{
      margin: 0 0 16px 0;
      padding-left: 24px;
    }}
    .content li {{ margin-bottom: 6px; }}
    .content table {{
      width: 100%;
      border-collapse: collapse;
      margin: 20px 0;
      font-size: 14px;
    }}
    .content th, .content td {{
      padding: 10px 14px;
      border: 1px solid #e2e8f0;
      text-align: left;
    }}
    .content th {{
      background-color: #f1f5f9;
      font-weight: 600;
      color: #1e293b;
    }}
    .content tr:nth-child(even) {{
      background-color: #f8fafc;
    }}
    .content blockquote {{
      border-left: 4px solid #6366f1;
      padding: 8px 16px;
      margin: 16px 0;
      background-color: #eef2ff;
      border-radius: 0 8px 8px 0;
      color: #3730a3;
    }}
    .content strong {{
      color: #0f172a;
    }}
    .footer {{
      background: #f1f5f9;
      padding: 20px 28px;
      font-size: 12px;
      color: #64748b;
      border-top: 1px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }}
    .footer-left {{ float: left; }}
    .footer-right {{ float: right; }}
    .clear {{ clear: both; }}
  </style>
</head>
<body>
  <div class="email-container">
    <div class="header">
      <div class="badge">🎯 AI 研判深度精算报告</div>
      <h1 class="title">{task_name}{f' · 第 {period} 期' if period else ''}</h1>
      <div class="meta-bar">
        <span>⏱️ 研判时间：{generated_time}</span>
        {f'<span>🧠 模型：{model_name}</span>' if model_name else ''}
        {f'<span>⚡ 耗时：{elapsed_sec:.1f}s</span>' if elapsed_sec else ''}
      </div>
    </div>
    
    <div class="content">
      {rendered_body}
    </div>

    <div class="footer">
      <div class="footer-left">
        本研判报告由 <strong>对撩 AI 智能引擎</strong> 自动采集并精算生成。<br>
        通过 <strong>Resend</strong> 高可用邮件传输网络安全投递。
      </div>
      <div class="footer-right">
        {generated_time}
      </div>
      <div class="clear"></div>
    </div>
  </div>
</body>
</html>"""
    return html
