"""Service for reading and writing system settings, with fallback to environment config."""
from __future__ import annotations

import ipaddress
import logging
import socket
import time
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.setting import SystemSetting

log = logging.getLogger("duiliao.settings")

_ALLOWED_PROVIDER_SCHEMES = {"http", "https"}
_MAX_AI_REQUEST_TIMEOUT = 20.0


def validate_external_url(value: str, *, resolve_dns: bool = True) -> str:
    """Validate a provider URL before the server makes an outbound request.

    Custom providers are supported, but endpoints that resolve to loopback,
    private, link-local, multicast, reserved, or unspecified addresses are not.
    Redirects are disabled at the call site because validating only the initial
    URL cannot make an unvalidated redirect safe.
    """
    raw = (value or "").strip()
    if not raw:
        raise ValueError("Base URL 不能为空")
    parsed = urlsplit(raw)
    if parsed.scheme.lower() not in _ALLOWED_PROVIDER_SCHEMES:
        raise ValueError("Base URL 必须使用 http 或 https")
    if not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Base URL 必须包含有效主机名，且不能包含账号密码")
    if parsed.fragment:
        raise ValueError("Base URL 不能包含 fragment")
    try:
        port = parsed.port
    except ValueError as exc:
        raise ValueError("Base URL 端口无效") from exc
    port = port or (443 if parsed.scheme.lower() == "https" else 80)
    host = parsed.hostname.rstrip(".").lower()

    def _blocked(address: str) -> bool:
        ip = ipaddress.ip_address(address)
        return (
            ip.is_loopback
            or ip.is_private
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        )

    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        literal = None
    if literal is not None:
        if _blocked(str(literal)):
            raise ValueError("Base URL 不允许指向本机或内网地址")
    elif host in {"localhost", "localhost.localdomain"} or host.endswith(".local"):
        raise ValueError("Base URL 不允许使用本地域名")
    elif resolve_dns:
        try:
            addresses = {
                item[4][0]
                for item in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
            }
        except OSError as exc:
            raise ValueError("Base URL 主机名无法解析") from exc
        if not addresses or any(_blocked(address) for address in addresses):
            raise ValueError("Base URL 不允许解析到本机或内网地址")

    # Keep paths (for OpenAI-compatible gateways) but discard a fragment and
    # normalize the trailing slash. Query strings are not needed for provider
    # base URLs and make endpoint validation harder to reason about.
    if parsed.query:
        raise ValueError("Base URL 不能包含 query 参数")
    return urlunsplit((parsed.scheme.lower(), parsed.netloc, parsed.path.rstrip("/"), "", ""))

# Mapping of setting keys
AI_SETTING_KEYS = [
    "ai_default_provider",
    "ai_openai_base_url",
    "ai_openai_api_key",
    "ai_openai_model",
    "ai_gemini_base_url",
    "ai_gemini_api_key",
    "ai_gemini_model",
    "ai_anthropic_base_url",
    "ai_anthropic_api_key",
    "ai_anthropic_model",
]


def mask_api_key(key: str | None) -> str:
    """Mask an API key for safe display in UI."""
    if not key:
        return ""
    key = key.strip()
    if len(key) <= 8:
        return "••••••••"
    return f"{key[:3]}••••••••{key[-4:]}"


def is_masked_key(val: str | None) -> bool:
    """Check if the provided key is already masked."""
    if not val:
        return False
    return "••••" in val


def get_setting_value(db: Session, key: str, default: str = "") -> str:
    """Get a raw setting value from DB, returning default if not found."""
    row = db.scalar(select(SystemSetting).where(SystemSetting.key == key))
    if row is not None and row.value is not None:
        return row.value
    return default


def set_setting_value(
    db: Session, key: str, value: str, description: str | None = None
) -> SystemSetting:
    """Set or update a setting in DB."""
    row = db.scalar(select(SystemSetting).where(SystemSetting.key == key))
    if row is None:
        row = SystemSetting(key=key, value=value, description=description)
        db.add(row)
    else:
        row.value = value
        if description is not None:
            row.description = description
    return row


def get_all_ai_settings(db: Session | None = None, mask: bool = True) -> dict[str, Any]:
    """Retrieve all AI settings, prioritizing DB values and falling back to env."""
    close_db = False
    if db is None:
        db = SessionLocal()
        close_db = True

    try:
        default_provider = get_setting_value(
            db, "ai_default_provider", settings.AI_DEFAULT_PROVIDER or "openai"
        )

        openai_url = get_setting_value(
            db, "ai_openai_base_url", settings.OPENAI_BASE_URL or "https://api.openai.com/v1"
        )
        openai_key = get_setting_value(db, "ai_openai_api_key", settings.OPENAI_API_KEY or "")
        openai_model = get_setting_value(
            db, "ai_openai_model", settings.OPENAI_MODEL or "deepseek-chat"
        )

        gemini_url = get_setting_value(
            db,
            "ai_gemini_base_url",
            settings.GEMINI_BASE_URL or "https://generativelanguage.googleapis.com",
        )
        gemini_key = get_setting_value(db, "ai_gemini_api_key", settings.GEMINI_API_KEY or "")
        gemini_model = get_setting_value(
            db, "ai_gemini_model", settings.GEMINI_MODEL or "gemini-2.5-flash"
        )

        anthropic_url = get_setting_value(
            db, "ai_anthropic_base_url", settings.ANTHROPIC_BASE_URL or "https://api.anthropic.com"
        )
        anthropic_key = get_setting_value(
            db, "ai_anthropic_api_key", settings.ANTHROPIC_API_KEY or ""
        )
        anthropic_model = get_setting_value(
            db, "ai_anthropic_model", settings.ANTHROPIC_MODEL or "claude-3-5-sonnet-20241022"
        )

        return {
            "default_provider": default_provider,
            "openai": {
                "base_url": openai_url,
                "api_key": mask_api_key(openai_key) if mask else openai_key,
                "model": openai_model,
                "is_configured": bool(openai_key.strip()),
            },
            "gemini": {
                "base_url": gemini_url,
                "api_key": mask_api_key(gemini_key) if mask else gemini_key,
                "model": gemini_model,
                "is_configured": bool(gemini_key.strip()),
            },
            "anthropic": {
                "base_url": anthropic_url,
                "api_key": mask_api_key(anthropic_key) if mask else anthropic_key,
                "model": anthropic_model,
                "is_configured": bool(anthropic_key.strip()),
            },
        }
    finally:
        if close_db:
            db.close()


def save_ai_settings(db: Session, data: dict[str, Any]) -> dict[str, Any]:
    """Save AI settings to DB. Masked keys or untouched keys will not overwrite existing keys."""
    # 1. Default provider
    if "default_provider" in data and data["default_provider"]:
        set_setting_value(
            db,
            "ai_default_provider",
            str(data["default_provider"]).strip(),
            "默认 AI 服务商 (openai / gemini / anthropic)",
        )

    # Helper to update a provider block
    def _update_provider(provider: str, prefix: str):
        block = data.get(provider)
        if not isinstance(block, dict):
            return

        if "base_url" in block and block["base_url"] is not None:
            url = str(block["base_url"]).strip()
            if url:
                url = validate_external_url(url)
                set_setting_value(db, f"{prefix}_base_url", url, f"{provider} API Base URL")

        if "model" in block and block["model"] is not None:
            m = str(block["model"]).strip()
            if m:
                set_setting_value(db, f"{prefix}_model", m, f"{provider} 默认模型")

        if "api_key" in block and block["api_key"] is not None:
            key_input = str(block["api_key"]).strip()
            # If user provided a new unmasked key, save it; if blank or masked, ignore
            if key_input and not is_masked_key(key_input):
                set_setting_value(db, f"{prefix}_api_key", key_input, f"{provider} API Key")

    _update_provider("openai", "ai_openai")
    _update_provider("gemini", "ai_gemini")
    _update_provider("anthropic", "ai_anthropic")

    db.commit()

    # Synchronize to .env and in-memory settings for multi-layer persistence
    try:
        sync_ai_settings_to_env_and_memory(db)
    except Exception as exc:
        log.warning("同步配置至 .env 遇到异常: %s", exc)

    return get_all_ai_settings(db, mask=True)


def sync_ai_settings_to_env_and_memory(db: Session | None = None) -> None:
    """Sync real unmasked AI settings from DB to backend/.env and in-memory settings object."""
    from pathlib import Path
    from app.core.config import BACKEND_DIR, settings

    real_settings = get_all_ai_settings(db, mask=False)
    env_updates: dict[str, str] = {
        "AI_DEFAULT_PROVIDER": real_settings.get("default_provider") or "openai",
    }

    openai_cfg = real_settings.get("openai", {})
    if openai_cfg.get("base_url"):
        env_updates["OPENAI_BASE_URL"] = openai_cfg["base_url"]
    if openai_cfg.get("model"):
        env_updates["OPENAI_MODEL"] = openai_cfg["model"]
    if openai_cfg.get("api_key"):
        env_updates["OPENAI_API_KEY"] = openai_cfg["api_key"]

    gemini_cfg = real_settings.get("gemini", {})
    if gemini_cfg.get("base_url"):
        env_updates["GEMINI_BASE_URL"] = gemini_cfg["base_url"]
    if gemini_cfg.get("model"):
        env_updates["GEMINI_MODEL"] = gemini_cfg["model"]
    if gemini_cfg.get("api_key"):
        env_updates["GEMINI_API_KEY"] = gemini_cfg["api_key"]

    anthropic_cfg = real_settings.get("anthropic", {})
    if anthropic_cfg.get("base_url"):
        env_updates["ANTHROPIC_BASE_URL"] = anthropic_cfg["base_url"]
    if anthropic_cfg.get("model"):
        env_updates["ANTHROPIC_MODEL"] = anthropic_cfg["model"]
    if anthropic_cfg.get("api_key"):
        env_updates["ANTHROPIC_API_KEY"] = anthropic_cfg["api_key"]

    # 1. Update in-memory settings
    for k, v in env_updates.items():
        if hasattr(settings, k):
            setattr(settings, k, v)

    # 2. Write to backend/.env safely
    env_path = BACKEND_DIR / ".env"
    if not env_path.exists():
        env_path = Path(".env")

    try:
        lines = []
        if env_path.exists():
            lines = env_path.read_text(encoding="utf-8").splitlines()

        written_keys = set()
        new_lines = []
        for line in lines:
            stripped = line.strip()
            if stripped and not stripped.startswith("#") and "=" in stripped:
                key = stripped.split("=", 1)[0].strip()
                if key in env_updates:
                    new_lines.append(f"{key}={env_updates[key]}")
                    written_keys.add(key)
                    continue
            new_lines.append(line)

        # Append missing keys
        for k, v in env_updates.items():
            if k not in written_keys and v:
                new_lines.append(f"{k}={v}")

        env_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        log.info("AI 配置已持久化双写至: %s", env_path)
    except Exception as e:
        log.warning("双写同步 AI 配置到 .env 失败: %s", e)


def auto_sync_on_startup() -> None:
    """Ensure consistency between SQLite system_settings and .env on server boot."""
    with SessionLocal() as db:
        try:
            has_any_in_db = db.scalar(
                select(SystemSetting.key).where(SystemSetting.key.in_(AI_SETTING_KEYS)).limit(1)
            )
            if not has_any_in_db:
                # Seed DB from settings / .env if DB is fresh
                log.info("检测到数据库系统配置为空，正在从环境变量/.env初始化持久化设置...")
                seed_data = {
                    "default_provider": settings.AI_DEFAULT_PROVIDER or "openai",
                    "openai": {
                        "base_url": settings.OPENAI_BASE_URL,
                        "model": settings.OPENAI_MODEL,
                        "api_key": settings.OPENAI_API_KEY,
                    },
                    "gemini": {
                        "base_url": settings.GEMINI_BASE_URL,
                        "model": settings.GEMINI_MODEL,
                        "api_key": settings.GEMINI_API_KEY,
                    },
                    "anthropic": {
                        "base_url": settings.ANTHROPIC_BASE_URL,
                        "model": settings.ANTHROPIC_MODEL,
                        "api_key": settings.ANTHROPIC_API_KEY,
                    },
                }
                save_ai_settings(db, seed_data)
            else:
                # Ensure .env also has whatever is saved in DB
                sync_ai_settings_to_env_and_memory(db)
        except Exception as e:
            log.warning("启动自动同步设置出现非致命异常: %s", e)


def test_ai_connection(
    provider: str,
    base_url: str | None = None,
    api_key: str | None = None,
    model: str | None = None,
    timeout: float = 15.0,
) -> dict[str, Any]:
    """Test connection to an AI provider with the specified or stored credentials."""
    t0 = time.perf_counter()
    target_provider = (provider or "openai").lower().strip()

    # Load real settings if parameters omitted or masked
    real_settings = get_all_ai_settings(mask=False)
    p_config = real_settings.get(target_provider, {})

    target_url = validate_external_url(base_url or p_config.get("base_url") or "")
    target_model = (model or p_config.get("model") or "").strip()

    if api_key is not None and not is_masked_key(api_key):
        target_key = api_key.strip()
    else:
        target_key = p_config.get("api_key") or ""

    if not target_key:
        return {
            "ok": False,
            "message": f"未配置 {target_provider} 的 API 密钥（API Key 为空）",
            "elapsed_ms": 0,
            "error": "API Key is empty",
        }

    try:
        timeout = max(3.0, min(float(timeout), _MAX_AI_REQUEST_TIMEOUT))
        with httpx.Client(
            timeout=timeout,
            follow_redirects=False,
            limits=httpx.Limits(max_connections=4, max_keepalive_connections=2),
        ) as client:
            if target_provider in ("openai", "deepseek", "qwen", "kimi"):
                url = f"{target_url}/chat/completions"
                headers = {
                    "Authorization": f"Bearer {target_key}",
                    "Content-Type": "application/json",
                }
                payload = {
                    "model": target_model or "deepseek-chat",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "max_tokens": 5,
                }
                resp = client.post(url, headers=headers, json=payload)
                resp.raise_for_status()

            elif target_provider == "gemini":
                m = target_model or "gemini-2.5-flash"
                url = f"{target_url}/v1beta/models/{m}:generateContent?key={target_key}"
                payload = {
                    "contents": [{"parts": [{"text": "Hi"}]}],
                    "generationConfig": {"maxOutputTokens": 5},
                }
                resp = client.post(url, json=payload)
                resp.raise_for_status()

            elif target_provider in ("anthropic", "claude"):
                url = f"{target_url}/v1/messages"
                headers = {
                    "x-api-key": target_key,
                    "anthropic-version": "2023-06-01",
                    "content-type": "application/json",
                }
                payload = {
                    "model": target_model or "claude-3-5-sonnet-20241022",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "max_tokens": 5,
                }
                resp = client.post(url, headers=headers, json=payload)
                resp.raise_for_status()

            else:
                return {
                    "ok": False,
                    "message": f"不支持的 AI 服务商: {target_provider}",
                    "elapsed_ms": 0,
                    "error": "Unsupported provider",
                }

            if 300 <= resp.status_code < 400:
                raise ValueError("AI 服务端返回了重定向，出于安全原因未继续跟随")

        elapsed_ms = int((time.perf_counter() - t0) * 1000)
        return {
            "ok": True,
            "message": f"连接成功！响应耗时: {elapsed_ms}ms（端点鉴权通过）",
            "elapsed_ms": elapsed_ms,
            "error": None,
        }

    except ValueError:
        raise
    except httpx.HTTPStatusError as e:
        elapsed_ms = int((time.perf_counter() - t0) * 1000)
        status = e.response.status_code
        err_msg = f"HTTP {status}: {e.response.text[:200]}"
        if status == 401:
            friendly = "API 密钥无效或未授权 (401 Unauthorized)"
        elif status == 404:
            friendly = f"端点地址不存在 (404 Not Found) - 请检查 Base URL 或模型名称 '{target_model}'"
        elif status == 429:
            friendly = "额度不足或速率受限 (429 Rate Limit / Quota Exceeded)"
        else:
            friendly = f"接口请求失败 ({status}): {err_msg}"
        return {
            "ok": False,
            "message": friendly,
            "elapsed_ms": elapsed_ms,
            "error": err_msg,
        }

    except Exception as e:
        elapsed_ms = int((time.perf_counter() - t0) * 1000)
        return {
            "ok": False,
            "message": f"网络请求失败: {str(e)}",
            "elapsed_ms": elapsed_ms,
            "error": str(e),
        }
