"""Route discovery and cache helpers for the 588080 / 顶尖大师 site family.

Only standalone collector processes use these helpers. The web service starts
those processes, but does not proxy third-party responses to browsers.
"""

from __future__ import annotations

import ipaddress
import json
import logging
import os
import re
import socket
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urljoin, urlparse

from common import ROOT
from common.http import get, get_json, get_text

log = logging.getLogger("pred.dingjian")

AM_URL_RE = re.compile(
    r"""(?:src\s*=\s*|url\s*=\s*|href\s*=\s*)['"](https?://[^'"]+)['"]""",
    re.I,
)
AM_BARE_RE = re.compile(r'''https?://[^\s<>"']+''')
IFRAME_RE = re.compile(r"""<iframe[^>]+src=['"]([^'"]+)['"]""", re.I)
TAG_URL_RE = re.compile(r"""(?:src|href)\s*=\s*['"]([^'"]+)['"]""", re.I)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)

DEFAULT_ENTRIES = ("https://588080.com/",)
STATIC_API_HOSTS = (
    "https://n4k7p2m.medi.a268yu.com",
    "https://x3c8f5v.medi.a268yu.com",
    "https://h6b1g9z.medi.a268yu.com",
    "https://w9e2p7q.medi.a268yu.com",
    "https://r5u8a3x.medi.a268yu.com",
    "https://n4k7p2m.gamen.a268yu.com",
    "https://x3c8f5v.gamen.a268yu.com",
    "https://h6b1g9z.gamen.a268yu.com",
    "https://w9e2p7q.gamen.a268yu.com",
    "https://r5u8a3x.gamen.a268yu.com",
)
WEBSITE_CONFIG_PATH = "/api/v1/index/website/config"
CATALOG_PATH = "/api/v1/index/config/lazy"
CACHE_SCHEMA = "dingjian-hosts.v1"


class DingjianError(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(value for value in values if value))


def origin(url: str) -> str | None:
    parsed = urlparse(url.strip())
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return None
    try:
        port = parsed.port
    except ValueError:
        return None
    suffix = f":{port}" if port and port not in {80, 443} else ""
    return f"{parsed.scheme}://{parsed.hostname}{suffix}"


def parse_am_js(text: str, base: str) -> list[str]:
    """Extract iframe/redirect targets from a route file."""
    urls: list[str] = []
    for match in AM_URL_RE.finditer(text):
        urls.append(urljoin(base, match.group(1)))
    for match in IFRAME_RE.finditer(text):
        urls.append(urljoin(base, match.group(1)))
    for match in AM_BARE_RE.finditer(text):
        value = match.group(0).rstrip("\\;,)]}")
        if "js" in urlparse(value).path and value.endswith(".js"):
            continue
        urls.append(value)
    return _unique(urls)


def page_urls(text: str, base: str, *, ignore_comments: bool = True) -> list[str]:
    """Extract absolute navigation and script URLs from a landing page."""
    visible = HTML_COMMENT_RE.sub("", text) if ignore_comments else text
    urls = [match.group(0).rstrip("\\;,)]}") for match in AM_BARE_RE.finditer(visible)]
    urls.extend(urljoin(base, match.group(1)) for match in TAG_URL_RE.finditer(visible))
    return _unique(urls)


def _global_ip(value: str) -> bool:
    try:
        ip = ipaddress.ip_address(value)
        if ip in ipaddress.ip_network("198.18.0.0/15"):
            return True
        return ip.is_global
    except ValueError:
        return False


def public_https_url(url: str) -> bool:
    """Reject local/private redirect targets before following upstream HTML."""
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        return False
    try:
        if parsed.port not in {None, 443}:
            return False
    except ValueError:
        return False
    host = parsed.hostname.rstrip(".").lower()
    if host == "localhost" or host.endswith((".localhost", ".local", ".internal")):
        return False
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        try:
            addresses = {row[4][0] for row in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)}
        except OSError:
            return False
        return bool(addresses) and all(_global_ip(address) for address in addresses)
    return literal.is_global


def _tracking_url(url: str) -> bool:
    host = (urlparse(url).hostname or "").lower()
    return host.endswith("baidu.com") or host.endswith("google-analytics.com")


def _valid_site_config(payload: Any, expected_title: str) -> bool:
    if not isinstance(payload, dict) or payload.get("code") != 0 or not isinstance(payload.get("data"), dict):
        return False
    data = payload["data"]
    title = " ".join(str(data.get(key) or "") for key in ("webSiteTitle", "webSiteDesc", "webSiteKeywords"))
    return expected_title in title


def discover_api_hosts(
    entries: list[str] | tuple[str, ...] = DEFAULT_ENTRIES,
    *,
    fallback_hosts: list[str] | tuple[str, ...] = STATIC_API_HOSTS,
    expected_title: str = "顶尖大师",
    deadline_sec: float = 35.0,
    max_valid: int = 8,
    url_guard: Callable[[str], bool] = public_https_url,
) -> tuple[list[str], list[str]]:
    """Resolve canonical entry -> jump page -> route JS -> validated API hosts."""
    started = time.monotonic()
    errors: list[str] = []
    hubs: list[str] = []
    candidates: list[str] = []

    for entry in entries:
        if time.monotonic() - started >= deadline_sec:
            break
        if not url_guard(entry):
            errors.append(f"拒绝不安全入口: {entry}")
            continue
        try:
            html = get_text(entry, timeout=6, retries=0)
        except Exception as exc:
            errors.append(f"入口 {entry}: {exc}")
            continue
        for url in page_urls(html, entry):
            value = origin(url)
            if value and not _tracking_url(url) and value != origin(entry):
                hubs.append(value)

    for hub in _unique(hubs)[:8]:
        if time.monotonic() - started >= deadline_sec:
            break
        if not url_guard(hub):
            errors.append(f"拒绝不安全跳板: {hub}")
            continue
        try:
            html = get_text(hub + "/", timeout=6, retries=0)
        except Exception as exc:
            errors.append(f"跳板 {hub}: {exc}")
            continue
        documents = [html]
        scripts = [url for url in page_urls(html, hub + "/") if urlparse(url).path.lower().endswith(".js")]
        preferred = [url for url in scripts if re.search(r"(?:^|/)(?:am|url)[^/]*\.js$", urlparse(url).path, re.I)]
        for script_url in (preferred or scripts[:1])[:3]:
            if not url_guard(script_url):
                continue
            try:
                documents.append(get_text(script_url, timeout=6, retries=0))
            except Exception as exc:
                errors.append(f"线路文件 {script_url}: {exc}")
        for document in documents:
            for url in parse_am_js(document, hub):
                value = origin(url)
                if value and value != hub and not _tracking_url(url):
                    candidates.append(value)
        if candidates:
            break

    candidates.extend(origin(host) or "" for host in fallback_hosts)
    valid: list[str] = []
    for host in _unique(candidates):
        if len(valid) >= max_valid or time.monotonic() - started >= deadline_sec:
            break
        if not url_guard(host):
            continue
        try:
            payload = get_json(host + WEBSITE_CONFIG_PATH, timeout=6, retries=0)
            if _valid_site_config(payload, expected_title):
                valid.append(host)
            else:
                errors.append(f"站点身份不符: {host}")
        except Exception as exc:
            errors.append(f"验证 {host}: {exc}")
    if not valid:
        raise DingjianError("discovery_failed", "未发现可验证的顶尖大师内容线路；" + "；".join(errors[-6:]))
    return valid, errors


def host_cache_path() -> Path:
    raw = os.getenv("PRED_DINGJIAN_HOST_CACHE", "").strip()
    return Path(raw) if raw else ROOT / "out" / "source-catalog" / "hosts.json"


def load_cached_api_hosts(*, max_age_sec: float | None = None, path: Path | None = None) -> list[str]:
    target = path or host_cache_path()
    try:
        if max_age_sec is not None and time.time() - target.stat().st_mtime > max_age_sec:
            return []
        payload = json.loads(target.read_text(encoding="utf-8"))
        if payload.get("schema") != CACHE_SCHEMA:
            return []
        return _unique(origin(str(value)) or "" for value in payload.get("hosts") or [])
    except (OSError, ValueError, TypeError, AttributeError):
        return []


def save_api_hosts(hosts: list[str], *, entry_urls: list[str] | None = None, path: Path | None = None) -> Path:
    target = path or host_cache_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": CACHE_SCHEMA,
        "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "entry_urls": entry_urls or list(DEFAULT_ENTRIES),
        "hosts": _unique(origin(value) or "" for value in hosts),
    }
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(target)
    return target


def probe_hosts(hosts: list[str], *, am_js: str = "/am.js", deadline_sec: float = 12.0) -> str:
    """Compatibility helper for older source scripts with explicit jump hosts."""
    if not hosts:
        raise DingjianError("config", "脚本没有传入 hosts")
    last_err: Exception | None = None
    errors: list[str] = []
    started = time.monotonic()
    for host in hosts:
        if time.monotonic() - started > deadline_sec:
            break
        host = host.rstrip("/")
        try:
            am_url = urljoin(host + "/", am_js.lstrip("/"))
            try:
                js = get_text(am_url, timeout=4, retries=0)
                found = parse_am_js(js, host)
                if found:
                    return origin(found[0]) or found[0].rstrip("/")
            except Exception as exc:
                last_err = exc
                errors.append(f"{host} am.js: {exc}")
            response = get(host, timeout=4, retries=0)
            if response.status_code < 400:
                iframe = IFRAME_RE.search(response.text)
                if iframe:
                    return origin(urljoin(host + "/", iframe.group(1))) or host
                return host
        except Exception as exc:
            last_err = exc
            errors.append(f"{host}: {exc}")
            log.info("probe fail %s: %s", host, exc)
    raise DingjianError("probe_fail", f"no live host: {'; '.join(errors) or last_err}")
