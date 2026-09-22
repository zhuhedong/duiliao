"""Route discovery and cache helpers for the 77452.com / 澳门顶级 / 顶级论坛 site family.

Follows entry (https://77452.com/) -> decodes char codes uu1 -> gateway page ->
decodes openUrl0..2 in /chicken/soup.html -> discovers and health-checks mirror CDN hosts.
"""

from __future__ import annotations

import json
import logging
import os
import re
import socket
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

from common import ROOT
from common.http import get, get_text

log = logging.getLogger("pred.dingji")

DEFAULT_ENTRIES = (
    "https://77452.com/",
)

STATIC_API_HOSTS = (
    "https://goncf1-1fsfhb.trueheartlight.com:2096",
    "https://rc7c3z-e772rn.trueheartlight.com:2096",
    "https://erkxiz-ulqh0v.trueheartlight.com:2096",
)

CACHE_SCHEMA = "dingji-hosts.v1"
HEALTH_CHECK_PATH = "/htm/tz/amtz/001.html"


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(value for value in values if value))


def decode_char_codes(encoded: str) -> str:
    """Decode string where every 4 digits is chr(int(chunk) - 1000)."""
    s = str(encoded).strip()
    if not s or len(s) % 4 != 0 or not s.isdigit():
        return ""
    result = []
    for j in range(4, len(s) + 1, 4):
        val = int(s[j - 4 : j]) - 1000
        if 0 < val < 65536:
            result.append(chr(val))
    return "".join(result)


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


def _cache_path() -> Path:
    target = os.getenv("PRED_DINGJI_CACHE", "").strip()
    if target:
        path = Path(target)
        return path if path.is_absolute() else (ROOT / path).resolve()
    return (ROOT / "data" / "dingji-hosts.json").resolve()


def load_cached_api_hosts() -> list[str]:
    path = _cache_path()
    if not path.is_file():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    if not isinstance(payload, dict) or payload.get("schema") != CACHE_SCHEMA:
        return []
    hosts = [origin(str(x)) for x in payload.get("hosts") or []]
    return [h for h in hosts if h]


def save_api_hosts(hosts: list[str]) -> None:
    clean = [origin(h) for h in hosts if origin(h)]
    clean = _unique([h for h in clean if h])
    if not clean:
        return
    path = _cache_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": CACHE_SCHEMA,
        "updated_at": datetime.now().isoformat(),
        "hosts": clean,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def check_host_alive(host: str, timeout_sec: float = 6.0) -> bool:
    """Test if a Dingji mirror host responds with valid prediction content."""
    url = f"{host.rstrip('/')}{HEALTH_CHECK_PATH}"
    try:
        r = get(url, timeout=timeout_sec, retries=0)
        return r.status_code == 200 and ("九肖" in r.text or "期" in r.text)
    except Exception:
        return False


def discover_api_hosts(
    entries: list[str] | tuple[str, ...] = DEFAULT_ENTRIES,
    *,
    fallback_hosts: list[str] | tuple[str, ...] = STATIC_API_HOSTS,
    deadline_sec: float = 30.0,
) -> tuple[list[str], list[str]]:
    """Resolve entry -> decode uu1 -> jump soup.html -> decode openUrl -> mirror hosts."""
    started = time.monotonic()
    errors: list[str] = []
    discovered: list[str] = []

    for entry in entries:
        if time.monotonic() - started >= deadline_sec:
            break
        try:
            r = get(entry, timeout=8, retries=1)
            uu_m = re.search(r"""uu\d*\s*=\s*['"](\d+)['"]""", r.text)
            if not uu_m:
                errors.append(f"入口 {entry} 未找到 uu 密文")
                continue
            jump_target = decode_char_codes(uu_m.group(1))
            jump_origin = origin(jump_target)
            if not jump_origin:
                errors.append(f"入口 {entry} 解码出的跳板地址无效: {jump_target}")
                continue

            # Fetch /chicken/soup.html from the jump target
            soup_url = f"{jump_origin}/chicken/soup.html"
            r_soup = get(soup_url, timeout=8, retries=1)
            code_matches = re.findall(r"""num2str\s*\(\s*['"](\d+)['"]\s*\)""", r_soup.text)
            for raw_code in code_matches:
                decoded = decode_char_codes(raw_code)
                h = origin(decoded)
                if h and h not in discovered:
                    discovered.append(h)
        except Exception as exc:
            errors.append(f"入口 {entry} 探测失败: {exc}")

    # Combine discovered + fallbacks
    candidates = _unique([*discovered, *fallback_hosts])
    valid: list[str] = []

    for host in candidates:
        if time.monotonic() - started >= deadline_sec:
            break
        if check_host_alive(host, timeout_sec=5.0):
            valid.append(host)
        else:
            errors.append(f"节点连通性检测失败: {host}")

    if valid:
        save_api_hosts(valid)
        return valid, errors

    # Fallback
    return list(fallback_hosts), errors


def api_hosts() -> list[str]:
    """Return prioritized host list: env config -> cached -> static fallbacks."""
    configured = re.split(r"[,;\s]+", os.getenv("PRED_DINGJI_HOSTS", "").strip())
    values = [*configured, *load_cached_api_hosts(), *STATIC_API_HOSTS]
    result: list[str] = []
    for value in values:
        h = origin(str(value))
        if h and h not in result:
            result.append(h)
    return result


def urls_for(path: str) -> list[str]:
    """Given a relative path like '/htm/tz/amtz/001.html', return full URLs across all hosts."""
    suffix = "/" + path.lstrip("/")
    return [host + suffix for host in api_hosts()]
