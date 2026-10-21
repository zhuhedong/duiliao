"""Tests for Resend Email Service, Settings, HTML Rendering and AI Judgment Pipeline."""
import pytest
from app.services.email_service import (
    DEFAULT_SMTP_HOST,
    DEFAULT_SMTP_PORT,
    DEFAULT_SMTP_USER,
    get_email_config,
    render_ai_report_email,
)
from app.services.settings_service import save_email_settings
from app.db.session import SessionLocal


def test_email_config_defaults():
    db = SessionLocal()
    try:
        cfg = get_email_config(db=db, mask=True)
        assert cfg["smtp_host"] == DEFAULT_SMTP_HOST
        assert cfg["smtp_port"] == DEFAULT_SMTP_PORT
        assert cfg["smtp_user"] == DEFAULT_SMTP_USER
    finally:
        db.close()


def test_save_and_retrieve_email_settings():
    db = SessionLocal()
    try:
        saved = save_email_settings(
            db,
            {
                "smtp_host": "smtp.resend.com",
                "smtp_port": 465,
                "smtp_user": "resend",
                "smtp_password": "re_test_mock_key_123456",
                "from_email": "test@example.com",
                "from_name": "AI 研判测试",
                "default_recipients": "rec1@example.com, rec2@example.com",
            },
        )
        assert saved["smtp_host"] == "smtp.resend.com"
        assert saved["from_email"] == "test@example.com"
        assert "••••" in saved["smtp_password"]  # Masked
        assert saved["is_configured"] is True

        # Unmasked retrieval
        unmasked = get_email_config(db=db, mask=False)
        assert unmasked["smtp_password"] == "re_test_mock_key_123456"
    finally:
        db.close()


def test_render_ai_report_email():
    md = """### 🎯 【澳门六合彩 第 263 期】实码与生肖研判精选

#### 一、 过滤与清洗说明
* 已清洗剔除假生肖与乱码干扰；
* 统计到 35 个专家栏目预测。

#### 二、 热度最高生肖 (Top 5)
1. **[马]** - 出现频次 28 次
2. **[虎]** - 出现频次 24 次

| 生肖 | 推荐实码 | 频次 |
| :--- | :--- | :--- |
| 马 | 11, 23, 35, 47 | 28 |
| 虎 | 03, 15, 27, 39 | 24 |
"""
    html = render_ai_report_email(
        task_name="澳门六合彩帖文 AI 智能研判",
        period="263",
        markdown_content=md,
        model_name="deepseek/deepseek-chat",
        elapsed_sec=3.2,
    )

    assert "<!DOCTYPE html>" in html
    assert "澳门六合彩帖文 AI 智能研判" in html
    assert "第 263 期" in html
    assert "deepseek/deepseek-chat" in html
    assert "<table>" in html
    assert "<strong>[马]</strong>" in html or "<strong>" in html
    assert "Resend" in html


def test_email_settings_api(admin_client):
    # GET settings (CryptoClient transparently returns decrypted dict)
    data = admin_client.get("/settings/email")
    assert "smtp_host" in data
    assert "from_email" in data

    # PUT settings
    update_payload = {
        "smtp_host": "smtp.resend.com",
        "smtp_port": 465,
        "smtp_user": "resend",
        "smtp_password": "re_live_test_12345",
        "from_email": "notifications@myduiliao.com",
        "from_name": "对撩研判",
        "default_recipients": "boss@myduiliao.com",
    }
    res_data = admin_client.put("/settings/email", update_payload)
    assert res_data["smtp_host"] == "smtp.resend.com"
    assert res_data["from_email"] == "notifications@myduiliao.com"
    assert "••••" in res_data["smtp_password"]


def test_clean_html_for_llm():
    from app.services.ai.formatter import clean_html_for_llm, format_scraped_data_for_ai

    sample_html = """<!DOCTYPE html>
<html>
<head>
    <style id="s1"><style>.card { color: red; } body { margin: 0; }</style></style>
    <script>function doAd(){ alert('ad'); }</script>
</head>
<body>
    <!-- Comment: module header -->
    <div class="content-module" data-name="内幕大师" style="background-image: radial-gradient(#fff, #000); box-shadow: 0 0 10px red; font-size: 14px;">
        <table style="border-collapse: collapse; width: 100%;">
            <tr style="height: 40px;"><td style="color: blue; padding: 4px;">第263期</td><td style="font-weight: bold;">特码: 15</td></tr>
        </table>
    </div>



</body>
</html>"""
    cleaned = clean_html_for_llm(sample_html)
    assert "<style>" not in cleaned
    assert "</style>" not in cleaned
    assert "doAd" not in cleaned
    assert "<!-- Comment" not in cleaned
    assert "<table>" in cleaned
    assert "第263期" in cleaned
    assert "特码: 15" in cleaned
    assert "radial-gradient" not in cleaned
    assert "box-shadow" not in cleaned
    assert "style=" not in cleaned
    assert "\n\n\n" not in cleaned

    formatted = format_scraped_data_for_ai({"html": sample_html}, mode="raw_html")
    assert "<style>" not in formatted
    assert "style=" not in formatted
    assert "<table>" in formatted


def test_504_gateway_timeout_format():
    import httpx
    from app.services.ai.client import _format_http_error

    resp = httpx.Response(
        status_code=504,
        content=b"<!DOCTYPE html><html><head><title>504 Gateway Time-out</title></head></html>",
        request=httpx.Request("POST", "https://api.deepseek.com/v1/chat/completions"),
    )
    err = _format_http_error(resp, "OpenAI/DeepSeek", "https://api.deepseek.com/v1")
    assert "504" in str(err)
    assert "网关超时" in str(err) or "Gateway" in str(err)
    assert "Cloudflare" in str(err)
    assert "<!DOCTYPE" not in str(err)  # Clean message without dumping ugly HTML tags


def test_ai_client_timeout_and_settings():
    from app.services.ai.client import get_ai_client
    from app.services.settings_service import get_all_ai_settings, save_ai_settings

    db = SessionLocal()
    try:
        # Check default timeout
        settings_dict = get_all_ai_settings(db=db, mask=False)
        assert settings_dict.get("timeout") >= 300.0

        # Save custom timeout
        save_ai_settings(db, {"timeout": 450.0})
        updated = get_all_ai_settings(db=db, mask=False)
        assert updated.get("timeout") == 450.0

        # Verify client picks up custom timeout
        client = get_ai_client(api_key="sk-mock-key-for-test")
        assert client.timeout == 450.0

        # Verify explicit timeout override
        client_override = get_ai_client(api_key="sk-mock-key-for-test", timeout=120.0)
        assert client_override.timeout == 120.0
    finally:
        # Reset timeout
        save_ai_settings(db, {"timeout": 300.0})
        db.close()


