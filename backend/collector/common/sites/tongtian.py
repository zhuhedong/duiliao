"""Route discovery and cache helpers for the 83191.com / 通天 site family.

Follows entry -> 301 redirect -> iframe /zy/ -> decodes char codes -> discovers
and health-checks mirror CDN hosts (e.g. tt822f.83191a.app:8443).
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

log = logging.getLogger("pred.tongtian")

DEFAULT_ENTRIES = (
    "https://83191.com/",
    "https://59631a.com/",
    "https://83191b.com/",
)

STATIC_API_HOSTS = (
    "https://tt822f.83191a.app:8443",
    "https://tt726.www83191b.com:8443",
    "https://tt91f.www59631.com:8443",
)

CACHE_SCHEMA = "tongtian-hosts.v1"
HEALTH_CHECK_PATH = "/chajie/6xiao.js"


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
    target = os.getenv("PRED_TONGTIAN_CACHE", "").strip()
    if target:
        path = Path(target)
        return path if path.is_absolute() else (ROOT / path).resolve()
    return (ROOT / "data" / "tongtian-hosts.json").resolve()


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
    """Test if a Tongtian mirror host responds with valid 6xiao prediction content."""
    url = f"{host.rstrip('/')}{HEALTH_CHECK_PATH}"
    try:
        r = get(url, timeout=timeout_sec, retries=0)
        return r.status_code == 200 and ("六肖" in r.text or "期" in r.text)
    except Exception:
        return False


def discover_api_hosts(
    entries: list[str] | tuple[str, ...] = DEFAULT_ENTRIES,
    *,
    fallback_hosts: list[str] | tuple[str, ...] = STATIC_API_HOSTS,
    deadline_sec: float = 30.0,
) -> tuple[list[str], list[str]]:
    """Resolve entry -> 301 jump -> iframe /zy/ -> decode uu -> alive mirror hosts."""
    started = time.monotonic()
    errors: list[str] = []
    discovered: list[str] = []

    for entry in entries:
        if time.monotonic() - started >= deadline_sec:
            break
        try:
            r = get(entry, timeout=8, retries=1)
            # The final url is often https://svip.yuminship11.com:808/#z/
            parsed = urlparse(str(r.url))
            port_part = f":{parsed.port}" if parsed.port and parsed.port not in {80, 443} else ""
            zy_url = f"{parsed.scheme}://{parsed.hostname}{port_part}/zy/"

            r_zy = get(zy_url, timeout=8, retries=1)
            uu_matches = re.findall(r"""uu\d*\s*=\s*['"](\d+)['"]""", r_zy.text)
            for raw_uu in uu_matches:
                decoded = decode_char_codes(raw_uu)
                h = origin(decoded)
                if h and h not in discovered:
                    # Filter out non-tongtian utility pages like fangjiechi
                    if "fangjiechi" not in decoded and "fjc" not in h:
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

    # If no live check succeeded (e.g. offline/isolated test), return fallback
    return list(fallback_hosts), errors


def api_hosts() -> list[str]:
    """Return prioritized host list: env config -> cached -> static fallbacks."""
    configured = re.split(r"[,;\s]+", os.getenv("PRED_TONGTIAN_HOSTS", "").strip())
    values = [*configured, *load_cached_api_hosts(), *STATIC_API_HOSTS]
    result: list[str] = []
    for value in values:
        h = origin(str(value))
        if h and h not in result:
            result.append(h)
    return result


def urls_for(path: str) -> list[str]:
    """Given a relative path like '/chajie/6xiao.js', return full URLs across all hosts."""
    suffix = "/" + path.lstrip("/")
    return [host + suffix for host in api_hosts()]
