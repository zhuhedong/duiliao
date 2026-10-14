from __future__ import annotations

import ipaddress
import logging
import socket
import time
from typing import Any
from urllib.parse import urljoin, urlsplit

import httpx

from common.config import http_retries, http_timeout

log = logging.getLogger("pred.http")

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)

_MAX_REDIRECTS = 5
_ALLOWED_SCHEMES = {"http", "https"}


def _timeout(timeout: float | httpx.Timeout | None) -> httpx.Timeout:
    if isinstance(timeout, httpx.Timeout):
        return timeout
    sec = float(timeout if timeout is not None else http_timeout())
    connect = min(4.0, sec)
    return httpx.Timeout(connect=connect, read=sec, write=sec, pool=connect)


def _host_is_blocked(hostname: str, port: int | None = None, *, resolve_dns: bool = True) -> bool:
    """Reject loopback / private / link-local / metadata targets (SSRF guard)."""
    host = (hostname or "").rstrip(".").lower()
    if not host:
        return True
    if host in {"localhost", "localhost.localdomain"} or host.endswith(".local"):
        return True

    def _ip_blocked(address: str) -> bool:
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
        return _ip_blocked(str(literal))
    if not resolve_dns:
        return False

    try:
        infos = socket.getaddrinfo(host, port or 0, type=socket.SOCK_STREAM)
    except OSError:
        # Unresolvable hosts are not private; let the HTTP client surface the error.
        return False
    addresses = {item[4][0] for item in infos}
    return (not addresses) or any(_ip_blocked(addr) for addr in addresses)


def assert_safe_url(url: str, *, resolve_dns: bool = True) -> str:
    """Validate a URL before any outbound request or redirect hop."""
    raw = (url or "").strip()
    if not raw:
        raise ValueError("URL 不能为空")
    parts = urlsplit(raw)
    if parts.scheme.lower() not in _ALLOWED_SCHEMES:
        raise ValueError("URL 必须使用 http 或 https")
    if not parts.hostname or parts.username or parts.password:
        raise ValueError("URL 主机无效")
    try:
        port = parts.port
    except ValueError as exc:
        raise ValueError("URL 端口无效") from exc
    if _host_is_blocked(parts.hostname, port, resolve_dns=resolve_dns):
        raise ValueError("禁止请求本机或内网地址")
    return raw


def client(timeout: float | None = None) -> httpx.Client:
    # Redirects are followed manually in get() so each hop can be re-validated.
    return httpx.Client(
        timeout=_timeout(timeout),
        follow_redirects=False,
        headers={
            "User-Agent": UA,
            "Accept": "application/json,text/html,*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        },
    )


def get(
    url: str,
    *,
    timeout: float | None = None,
    retries: int | None = None,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    n = retries if retries is not None else http_retries()
    last: Exception | None = None
    try:
        with client(timeout) as c:
            for i in range(n + 1):
                try:
                    return _get_following_redirects(c, url, headers=headers)
                except Exception as e:
                    last = e
                    log.warning("GET %s failed (%s/%s): %s", url, i + 1, n + 1, e)
                    if i < n:
                        time.sleep(0.4 * (i + 1))
    finally:
        pass
    if last is None:
        raise RuntimeError("HTTP request did not run")
    raise last


def _get_following_redirects(
    c: httpx.Client,
    url: str,
    *,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    current = assert_safe_url(url)
    for _ in range(_MAX_REDIRECTS + 1):
        response = c.get(current, headers=headers)
        if response.status_code not in {301, 302, 303, 307, 308}:
            response.raise_for_status()
            return response
        location = response.headers.get("location")
        if not location:
            response.raise_for_status()
            return response
        nxt = urljoin(current, location)
        current = assert_safe_url(nxt)
    raise ValueError(f"重定向次数过多: {url}")


def get_text(url: str, **kw: Any) -> str:
    return get(url, **kw).text


def get_bytes(url: str, **kw: Any) -> bytes:
    return get(url, **kw).content


def get_json(url: str, **kw: Any) -> Any:
    r = get(url, **kw)
    try:
        return r.json()
    except Exception as e:
        raise ValueError(f"not json: {url}") from e
