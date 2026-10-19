"""Multi-model AI adapter supporting OpenAI-compatible, Google Gemini, and Anthropic Claude APIs."""
from __future__ import annotations

import json
import logging
import time
from abc import ABC, abstractmethod
from collections.abc import Generator
from dataclasses import dataclass, field
from typing import Any

import httpx

log = logging.getLogger("duiliao.ai")

# Gateways often cut a chunked SSE body without an error frame. Retry those,
# then fall back to one non-streaming completion.
_STREAM_DROPPED = (
    httpx.RemoteProtocolError,
    httpx.ReadError,
    httpx.ConnectError,
    httpx.ReadTimeout,
    httpx.WriteError,
)


def _format_http_error(resp: httpx.Response, provider_name: str, base_url: str) -> RuntimeError:
    status_code = resp.status_code
    detail = ""
    try:
        body = resp.read()
        parsed = json.loads(body.decode("utf-8", errors="replace"))
        if isinstance(parsed, dict):
            if "error" in parsed:
                err = parsed["error"]
                detail = err.get("message") if isinstance(err, dict) else str(err)
            elif "message" in parsed:
                detail = str(parsed["message"])
            else:
                detail = json.dumps(parsed, ensure_ascii=False)
    except Exception:
        try:
            detail = resp.text[:200]
        except Exception:
            detail = ""

    detail_suffix = f"：{detail}" if detail else ""

    if status_code == 401:
        return RuntimeError(
            f"{provider_name} 授权失败 (HTTP 401): API Key 无效或未授权，请前往系统设置配置有效 Key{detail_suffix}"
        )
    elif status_code == 403:
        return RuntimeError(
            f"{provider_name} 拒绝访问 (HTTP 403): 权限不足或账户受限{detail_suffix}"
        )
    elif status_code == 429:
        return RuntimeError(
            f"{provider_name} 请求受限或额度不足 (HTTP 429): 请检查账户余额或稍后重试{detail_suffix}"
        )
    elif status_code == 404:
        return RuntimeError(
            f"{provider_name} 接口不存在 (HTTP 404): 当前配置的 Base URL 为 {base_url}{detail_suffix}"
        )
    elif status_code >= 500:
        return RuntimeError(
            f"{provider_name} 服务端异常 (HTTP {status_code}): 上游大模型服务暂时故障，请稍后重试{detail_suffix}"
        )
    return RuntimeError(
        f"{provider_name} 接口调用失败 (HTTP {status_code}){detail_suffix}"
    )


def _format_network_error(exc: Exception, provider_name: str, base_url: str) -> RuntimeError:
    if isinstance(exc, httpx.ConnectTimeout):
        return RuntimeError(f"连接 {provider_name} 超时: 无法连接至 {base_url}，请检查网络或代理设置")
    elif isinstance(exc, httpx.ReadTimeout):
        return RuntimeError(f"{provider_name} 响应超时: 大模型未在规定时间内返回数据")
    elif isinstance(exc, (httpx.ConnectError, httpx.NetworkError)):
        return RuntimeError(f"网络连接失败: 无法连接至 {provider_name} ({base_url})，请检查网络连接")
    elif isinstance(exc, httpx.RemoteProtocolError):
        return RuntimeError(f"{provider_name} 连接被上游提前关闭或重置")
    return RuntimeError(f"{provider_name} 网络请求异常: {str(exc)}")


@dataclass
class AIResponse:
    content: str
    provider: str
    model: str
    usage: dict[str, int] = field(default_factory=dict)
    elapsed_sec: float = 0.0
    raw: dict[str, Any] = field(default_factory=dict)


class BaseAIProvider(ABC):
    """Abstract base class for LLM providers."""

    def __init__(self, api_key: str, base_url: str, default_model: str, timeout: float = 180.0):
        self.api_key = api_key.strip()
        self.base_url = base_url.rstrip("/")
        self.default_model = default_model
        self.timeout = timeout

    @abstractmethod
    def generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        """Synchronously send chat completion request."""
        raise NotImplementedError

    def generate_stream(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> Generator[str, None, None]:
        """Stream response tokens as they arrive."""
        resp = self.generate(
            messages,
            model=model,
            temperature=temperature,
            max_tokens=max_tokens,
            **kwargs,
        )
        yield resp.content

    @abstractmethod
    async def async_generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        """Asynchronously send chat completion request."""
        raise NotImplementedError


class OpenAIProvider(BaseAIProvider):
    """Adapter for OpenAI-compatible API endpoints (OpenAI, DeepSeek, Qwen, Kimi, Local LLM)."""

    def generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        m = model or self.default_model
        url = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload: dict[str, Any] = {
            "model": m,
            "messages": messages,
            "temperature": temperature,
            **kwargs,
        }
        if max_tokens:
            payload["max_tokens"] = max_tokens

        t0 = time.perf_counter()
        try:
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.post(url, headers=headers, json=payload)
                if resp.status_code != 200:
                    raise _format_http_error(resp, "OpenAI/DeepSeek", self.base_url)
                data = resp.json()
        except httpx.HTTPStatusError as exc:
            raise _format_http_error(exc.response, "OpenAI/DeepSeek", self.base_url) from exc
        except (httpx.ConnectTimeout, httpx.ReadTimeout, httpx.ConnectError, httpx.NetworkError, httpx.RemoteProtocolError) as exc:
            raise _format_network_error(exc, "OpenAI/DeepSeek", self.base_url) from exc

        elapsed = time.perf_counter() - t0
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
        usage = data.get("usage", {})
        return AIResponse(
            content=content,
            provider="openai",
            model=m,
            usage=usage,
            elapsed_sec=round(elapsed, 2),
            raw=data,
        )

    def generate_stream(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> Generator[str, None, None]:
        m = model or self.default_model
        url = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload: dict[str, Any] = {
            "model": m,
            "messages": messages,
            "temperature": temperature,
            "stream": True,
            **kwargs,
        }
        if max_tokens:
            payload["max_tokens"] = max_tokens
        # Some gateways gzip a chunked SSE body and then drop the connection.
        headers["Accept-Encoding"] = "identity"

        last_error: Exception | None = None
        for attempt in range(2):
            emitted = False
            try:
                for piece in self._iter_chat_deltas(url, headers, payload):
                    emitted = True
                    yield piece
                return
            except RuntimeError:
                # Fatal or formatted API error (e.g. 401 Unauthorized) -> raise immediately
                raise
            except _STREAM_DROPPED as exc:
                last_error = exc
                if emitted:
                    log.warning("AI stream broke after partial output: %s", exc)
                    raise _format_network_error(exc, "OpenAI/DeepSeek", self.base_url) from exc
                log.warning("AI stream closed before any token (attempt %s): %s", attempt + 1, exc)
        log.warning("AI stream unavailable, requesting a single response: %s", last_error)
        try:
            response = self.generate(
                messages,
                model=model,
                temperature=temperature,
                max_tokens=max_tokens,
                **kwargs,
            )
            if response.content:
                yield response.content
        except Exception as exc:
            if last_error:
                raise _format_network_error(last_error, "OpenAI/DeepSeek", self.base_url) from exc
            raise

    def _iter_chat_deltas(self, url: str, headers: dict[str, str], payload: dict[str, Any]) -> Generator[str, None, None]:
        timeout = httpx.Timeout(300.0, connect=20.0, read=300.0)
        try:
            with httpx.Client(timeout=timeout) as client:
                with client.stream("POST", url, headers=headers, json=payload) as resp:
                    if resp.status_code != 200:
                        raise _format_http_error(resp, "OpenAI/DeepSeek", self.base_url)
                    for line in resp.iter_lines():
                        line = line.strip()
                        if not line or not line.startswith("data:"):
                            continue
                        data_str = line[len("data:"):].strip()
                        if data_str == "[DONE]":
                            break
                        try:
                            chunk = json.loads(data_str)
                        except Exception:
                            continue
                        error = chunk.get("error")
                        if error:
                            message = error.get("message") if isinstance(error, dict) else str(error)
                            raise RuntimeError(message or "模型流式接口返回错误")
                        choices = chunk.get("choices", [])
                        if choices:
                            delta = choices[0].get("delta", {})
                            content = delta.get("content", "")
                            if content:
                                yield content
        except httpx.HTTPStatusError as exc:
            raise _format_http_error(exc.response, "OpenAI/DeepSeek", self.base_url) from exc

    async def async_generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        m = model or self.default_model
        url = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload: dict[str, Any] = {
            "model": m,
            "messages": messages,
            "temperature": temperature,
            **kwargs,
        }
        if max_tokens:
            payload["max_tokens"] = max_tokens

        t0 = time.perf_counter()
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.post(url, headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()

        elapsed = time.perf_counter() - t0
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
        usage = data.get("usage", {})
        return AIResponse(
            content=content,
            provider="openai",
            model=m,
            usage=usage,
            elapsed_sec=round(elapsed, 2),
            raw=data,
        )


class GeminiProvider(BaseAIProvider):
    """Adapter for Google Gemini generateContent REST API."""

    def _convert_messages(self, messages: list[dict[str, str]]) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
        system_instruction = None
        contents: list[dict[str, Any]] = []

        for msg in messages:
            role = msg.get("role", "user")
            text = msg.get("content", "")
            if role == "system":
                system_instruction = {"parts": [{"text": text}]}
            elif role == "assistant":
                contents.append({"role": "model", "parts": [{"text": text}]})
            else:
                contents.append({"role": "user", "parts": [{"text": text}]})

        return system_instruction, contents

    def generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        m = model or self.default_model
        clean_model = m.replace("models/", "")
        url = f"{self.base_url}/v1beta/models/{clean_model}:generateContent"
        params = {"key": self.api_key}

        system_instruction, contents = self._convert_messages(messages)
        gen_config: dict[str, Any] = {"temperature": temperature}
        if max_tokens:
            gen_config["maxOutputTokens"] = max_tokens

        payload: dict[str, Any] = {
            "contents": contents,
            "generationConfig": gen_config,
            **kwargs,
        }
        if system_instruction:
            payload["systemInstruction"] = system_instruction

        t0 = time.perf_counter()
        try:
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.post(url, params=params, json=payload)
                if resp.status_code != 200:
                    raise _format_http_error(resp, "Google Gemini", self.base_url)
                data = resp.json()
        except httpx.HTTPStatusError as exc:
            raise _format_http_error(exc.response, "Google Gemini", self.base_url) from exc
        except (httpx.ConnectTimeout, httpx.ReadTimeout, httpx.ConnectError, httpx.NetworkError, httpx.RemoteProtocolError) as exc:
            raise _format_network_error(exc, "Google Gemini", self.base_url) from exc

        elapsed = time.perf_counter() - t0
        candidates = data.get("candidates", [])
        content = ""
        if candidates:
            parts = candidates[0].get("content", {}).get("parts", [])
            content = "".join(p.get("text", "") for p in parts)

        meta = data.get("usageMetadata", {})
        usage = {
            "prompt_tokens": meta.get("promptTokenCount", 0),
            "completion_tokens": meta.get("candidatesTokenCount", 0),
            "total_tokens": meta.get("totalTokenCount", 0),
        }

        return AIResponse(
            content=content,
            provider="gemini",
            model=m,
            usage=usage,
            elapsed_sec=round(elapsed, 2),
            raw=data,
        )

    def generate_stream(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> Generator[str, None, None]:
        m = model or self.default_model
        clean_model = m.replace("models/", "")
        url = f"{self.base_url}/v1beta/models/{clean_model}:streamGenerateContent?key={self.api_key}&alt=sse"

        system_instruction, contents = self._convert_messages(messages)
        gen_config: dict[str, Any] = {"temperature": temperature}
        if max_tokens:
            gen_config["maxOutputTokens"] = max_tokens

        payload: dict[str, Any] = {
            "contents": contents,
            "generationConfig": gen_config,
            **kwargs,
        }
        if system_instruction:
            payload["systemInstruction"] = system_instruction

        timeout = httpx.Timeout(180.0, connect=20.0, read=180.0)
        try:
            with httpx.Client(timeout=timeout) as client:
                with client.stream("POST", url, json=payload) as resp:
                    if resp.status_code != 200:
                        raise _format_http_error(resp, "Google Gemini", self.base_url)
                    for line in resp.iter_lines():
                        line = line.strip()
                        if not line or not line.startswith("data:"):
                            continue
                        data_str = line[len("data:"):].strip()
                        try:
                            chunk = json.loads(data_str)
                            candidates = chunk.get("candidates", [])
                            if candidates:
                                parts = candidates[0].get("content", {}).get("parts", [])
                                text = "".join(p.get("text", "") for p in parts)
                                if text:
                                    yield text
                        except Exception:
                            continue
        except httpx.HTTPStatusError as exc:
            raise _format_http_error(exc.response, "Google Gemini", self.base_url) from exc
        except (httpx.ConnectTimeout, httpx.ReadTimeout, httpx.ConnectError, httpx.NetworkError, httpx.RemoteProtocolError) as exc:
            raise _format_network_error(exc, "Google Gemini", self.base_url) from exc

    async def async_generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        m = model or self.default_model
        clean_model = m.replace("models/", "")
        url = f"{self.base_url}/v1beta/models/{clean_model}:generateContent"
        params = {"key": self.api_key}

        system_instruction, contents = self._convert_messages(messages)
        gen_config: dict[str, Any] = {"temperature": temperature}
        if max_tokens:
            gen_config["maxOutputTokens"] = max_tokens

        payload: dict[str, Any] = {
            "contents": contents,
            "generationConfig": gen_config,
            **kwargs,
        }
        if system_instruction:
            payload["systemInstruction"] = system_instruction

        t0 = time.perf_counter()
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.post(url, params=params, json=payload)
            resp.raise_for_status()
            data = resp.json()

        elapsed = time.perf_counter() - t0
        candidates = data.get("candidates", [])
        content = ""
        if candidates:
            parts = candidates[0].get("content", {}).get("parts", [])
            content = "".join(p.get("text", "") for p in parts)

        meta = data.get("usageMetadata", {})
        usage = {
            "prompt_tokens": meta.get("promptTokenCount", 0),
            "completion_tokens": meta.get("candidatesTokenCount", 0),
            "total_tokens": meta.get("totalTokenCount", 0),
        }

        return AIResponse(
            content=content,
            provider="gemini",
            model=m,
            usage=usage,
            elapsed_sec=round(elapsed, 2),
            raw=data,
        )


class AnthropicProvider(BaseAIProvider):
    """Adapter for Anthropic Claude /v1/messages REST API."""

    def _convert_messages(self, messages: list[dict[str, str]]) -> tuple[str | None, list[dict[str, str]]]:
        system_text = None
        formatted: list[dict[str, str]] = []

        for msg in messages:
            role = msg.get("role", "user")
            text = msg.get("content", "")
            if role == "system":
                system_text = text if not system_text else f"{system_text}\n\n{text}"
            else:
                formatted.append({"role": role, "content": text})

        return system_text, formatted

    def generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        m = model or self.default_model
        url = f"{self.base_url}/v1/messages"
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        }

        system_text, formatted_msgs = self._convert_messages(messages)
        payload: dict[str, Any] = {
            "model": m,
            "messages": formatted_msgs,
            "max_tokens": max_tokens or 4096,
            "temperature": temperature,
            **kwargs,
        }
        if system_text:
            payload["system"] = system_text

        t0 = time.perf_counter()
        try:
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.post(url, headers=headers, json=payload)
                if resp.status_code != 200:
                    raise _format_http_error(resp, "Anthropic Claude", self.base_url)
                data = resp.json()
        except httpx.HTTPStatusError as exc:
            raise _format_http_error(exc.response, "Anthropic Claude", self.base_url) from exc
        except (httpx.ConnectTimeout, httpx.ReadTimeout, httpx.ConnectError, httpx.NetworkError, httpx.RemoteProtocolError) as exc:
            raise _format_network_error(exc, "Anthropic Claude", self.base_url) from exc

        elapsed = time.perf_counter() - t0
        content = "".join(block.get("text", "") for block in data.get("content", []) if block.get("type") == "text")
        usage_data = data.get("usage", {})
        usage = {
            "prompt_tokens": usage_data.get("input_tokens", 0),
            "completion_tokens": usage_data.get("output_tokens", 0),
            "total_tokens": usage_data.get("input_tokens", 0) + usage_data.get("output_tokens", 0),
        }

        return AIResponse(
            content=content,
            provider="anthropic",
            model=m,
            usage=usage,
            elapsed_sec=round(elapsed, 2),
            raw=data,
        )

    def generate_stream(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> Generator[str, None, None]:
        m = model or self.default_model
        url = f"{self.base_url}/v1/messages"
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        }

        system_text, formatted_msgs = self._convert_messages(messages)
        payload: dict[str, Any] = {
            "model": m,
            "messages": formatted_msgs,
            "max_tokens": max_tokens or 4096,
            "temperature": temperature,
            "stream": True,
            **kwargs,
        }
        if system_text:
            payload["system"] = system_text

        timeout = httpx.Timeout(180.0, connect=20.0, read=180.0)
        try:
            with httpx.Client(timeout=timeout) as client:
                with client.stream("POST", url, headers=headers, json=payload) as resp:
                    if resp.status_code != 200:
                        raise _format_http_error(resp, "Anthropic Claude", self.base_url)
                    for line in resp.iter_lines():
                        line = line.strip()
                        if not line or not line.startswith("data:"):
                            continue
                        data_str = line[len("data:"):].strip()
                        try:
                            chunk = json.loads(data_str)
                            if chunk.get("type") == "content_block_delta":
                                text = chunk.get("delta", {}).get("text", "")
                                if text:
                                    yield text
                        except Exception:
                            continue
        except httpx.HTTPStatusError as exc:
            raise _format_http_error(exc.response, "Anthropic Claude", self.base_url) from exc
        except (httpx.ConnectTimeout, httpx.ReadTimeout, httpx.ConnectError, httpx.NetworkError, httpx.RemoteProtocolError) as exc:
            raise _format_network_error(exc, "Anthropic Claude", self.base_url) from exc

    async def async_generate(
        self,
        messages: list[dict[str, str]],
        *,
        model: str | None = None,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        **kwargs: Any,
    ) -> AIResponse:
        m = model or self.default_model
        url = f"{self.base_url}/v1/messages"
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        }

        system_text, formatted_msgs = self._convert_messages(messages)
        payload: dict[str, Any] = {
            "model": m,
            "messages": formatted_msgs,
            "max_tokens": max_tokens or 4096,
            "temperature": temperature,
            **kwargs,
        }
        if system_text:
            payload["system"] = system_text

        t0 = time.perf_counter()
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.post(url, headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()

        elapsed = time.perf_counter() - t0
        content = "".join(block.get("text", "") for block in data.get("content", []) if block.get("type") == "text")
        usage_data = data.get("usage", {})
        usage = {
            "prompt_tokens": usage_data.get("input_tokens", 0),
            "completion_tokens": usage_data.get("output_tokens", 0),
            "total_tokens": usage_data.get("input_tokens", 0) + usage_data.get("output_tokens", 0),
        }

        return AIResponse(
            content=content,
            provider="anthropic",
            model=m,
            usage=usage,
            elapsed_sec=round(elapsed, 2),
            raw=data,
        )


def _require_api_key(api_key: str, provider: str) -> None:
    if not str(api_key or "").strip():
        raise ValueError(f"未配置 {provider} 的 API Key，请先到系统设置填写后再研判")


def get_ai_client(
    provider: str | None = None,
    *,
    api_key: str | None = None,
    base_url: str | None = None,
    model: str | None = None,
    timeout: float = 60.0,
) -> BaseAIProvider:
    """Factory creating the appropriate AI provider instance.
    Checks dynamic system settings first, falling back to environment config.
    """
    from app.services.settings_service import get_all_ai_settings

    # Load dynamic real settings (unmasked)
    all_settings = get_all_ai_settings(mask=False)
    target_provider = (provider or all_settings.get("default_provider") or "openai").lower().strip()

    if target_provider in ("openai", "deepseek", "qwen", "kimi"):
        cfg = all_settings.get("openai", {})
        key = api_key if api_key is not None else cfg.get("api_key", "")
        url = base_url if base_url is not None else cfg.get("base_url", "https://api.openai.com/v1")
        default_model = model or cfg.get("model", "deepseek-chat")
        _require_api_key(key, target_provider)
        return OpenAIProvider(api_key=key, base_url=url, default_model=default_model, timeout=timeout)

    elif target_provider == "gemini":
        cfg = all_settings.get("gemini", {})
        key = api_key if api_key is not None else cfg.get("api_key", "")
        url = base_url if base_url is not None else cfg.get("base_url", "https://generativelanguage.googleapis.com")
        default_model = model or cfg.get("model", "gemini-2.5-flash")
        _require_api_key(key, target_provider)
        return GeminiProvider(api_key=key, base_url=url, default_model=default_model, timeout=timeout)

    elif target_provider in ("anthropic", "claude"):
        cfg = all_settings.get("anthropic", {})
        key = api_key if api_key is not None else cfg.get("api_key", "")
        url = base_url if base_url is not None else cfg.get("base_url", "https://api.anthropic.com")
        default_model = model or cfg.get("model", "claude-3-5-sonnet-20241022")
        _require_api_key(key, target_provider)
        return AnthropicProvider(api_key=key, base_url=url, default_model=default_model, timeout=timeout)

    else:
        raise ValueError(f"不支持的 AI Provider: {provider}。支持: openai, gemini, anthropic")
