from __future__ import annotations

import logging
import time
from typing import Any

import httpx

from common.config import http_retries, http_timeout

log = logging.getLogger("pred.http")

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)


def _timeout(timeout: float | httpx.Timeout | None) -> httpx.Timeout:
    if isinstance(timeout, httpx.Timeout):
        return timeout
    sec = float(timeout if timeout is not None else http_timeout())
    connect = min(4.0, sec)
    return httpx.Timeout(connect=connect, read=sec, write=sec, pool=connect)


def client(timeout: float | None = None) -> httpx.Client:
    return httpx.Client(
        timeout=_timeout(timeout),
        follow_redirects=True,
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
                    r = c.get(url, headers=headers)
                    r.raise_for_status()
                    return r
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
