"""Route discovery and cache helpers for the 70246.com / 神算集团 site family.

Follows entry (https://70246.com/) -> fetches hubs.dat -> fetches pools.dat from
random hub subdomain -> resolves wildcard content pool hosts (*.yyrxzj.com) ->
authenticates and health-checks via XOR-encrypted API endpoint /api/index/content_list/2.
"""

from __future__ import annotations

import json
import logging
import os
import random
import re
import string
import time
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from common import ROOT
from common.http import get

log = logging.getLogger("pred.shensuan")

DEFAULT_ENTRIES = (
    "https://70246.com/",
)

STATIC_API_HOSTS = (
    "https://*.yyrxzj.com",
    "https://ss49.com",
)

CACHE_SCHEMA = "shensuan-hosts.v1"
HEALTH_CHECK_PATH = "/api/index/content_list/2"


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(value for value in values if value))


def rand_str(length: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=length))


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


def base_domain_of(host_or_url: str) -> str:
    parsed = urlparse(host_or_url.strip())
    hostname = parsed.hostname or host_or_url.strip().split("/")[0]
    parts = hostname.split(".")
    if len(parts) >= 2:
        return ".".join(parts[-2:])
    return hostname


def xor_decrypt(data_str: str, key_str: str) -> str:
    """Decrypt payload using repeating key XOR (mirrors detector.js decryptData)."""
    if not data_str or not key_str:
        return data_str
    chars = []
    k_len = len(key_str)
    for i, ch in enumerate(data_str):
        kc = ord(key_str[i % k_len])
        c = ord(ch)
        chars.append(chr(c ^ kc))
    return "".join(chars)


def _cache_path() -> Path:
    target = os.getenv("PRED_SHENSUAN_CACHE", "").strip()
    if target:
        path = Path(target)
        return path if path.is_absolute() else (ROOT / path).resolve()
    return (ROOT / "data" / "shensuan-hosts.json").resolve()


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
    """Test if a Shensuan content host responds with decryptable content."""
    url = f"{host.rstrip('/')}{HEALTH_CHECK_PATH}"
    key = base_domain_of(host)
    try:
        r = get(url, timeout=timeout_sec, retries=0, headers={"Referer": f"{host}/"})
        if r.status_code != 200:
            return False
        data = r.json().get("data", "")
        if not data:
            return False
        decrypted = xor_decrypt(data, key)
        return "24464" in decrypted or "一肖一码" in decrypted
    except Exception:
        return False


def discover_api_hosts(
    entries: list[str] | tuple[str, ...] = DEFAULT_ENTRIES,
    *,
    fallback_hosts: list[str] | tuple[str, ...] = STATIC_API_HOSTS,
    deadline_sec: float = 30.0,
) -> tuple[list[str], list[str]]:
    """Resolve entry -> hubs.dat -> pools.dat -> active content hosts."""
    started = time.monotonic()
    errors: list[str] = []
    discovered: list[str] = []

    for entry in entries:
        if time.monotonic() - started >= deadline_sec:
            break
        try:
            hubs_url = f"{entry.rstrip('/')}/hubs.dat"
            r = get(hubs_url, timeout=8, retries=1)
            hubs_data = r.json()
            hubs = hubs_data.get("hubs", []) if isinstance(hubs_data, dict) else []
            for hub_tmpl in hubs:
                if time.monotonic() - started >= deadline_sec:
                    break
                hub_host = str(hub_tmpl).replace("*", rand_str(8))
                hub_url = f"https://{hub_host}/pools.dat"
                try:
                    r_pool = get(hub_url, timeout=8, retries=1)
                    pools_data = r_pool.json()
                    tmpls: list[str] = []
                    if isinstance(pools_data, dict):
                        for val in pools_data.values():
                            if isinstance(val, list):
                                tmpls.extend(val)
                            elif isinstance(val, str):
                                tmpls.append(val)
                    elif isinstance(pools_data, list):
                        tmpls.extend(pools_data)
                    for tmpl in tmpls:
                        target = tmpl.replace("*", rand_str(13)).strip()
                        h = origin(target)
                        if h and h not in discovered:
                            discovered.append(h)
                except Exception as exc:
                    errors.append(f"获取 pools.dat 失败 ({hub_url}): {exc}")
        except Exception as exc:
            errors.append(f"入口 {entry} 探测失败: {exc}")

    # Expand any wildcard fallbacks
    resolved_fallbacks: list[str] = []
    for f in fallback_hosts:
        if "*" in f:
            resolved_fallbacks.append(f.replace("*", rand_str(13)))
        else:
            resolved_fallbacks.append(f)

    candidates = _unique([*discovered, *resolved_fallbacks])
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

    return list(resolved_fallbacks), errors


def api_hosts() -> list[str]:
    """Return prioritized host list: env config -> cached -> auto-discovered -> static fallbacks."""
    configured = re.split(r"[,;\s]+", os.getenv("PRED_SHENSUAN_HOSTS", "").strip())
    clean_conf = [c for c in configured if c]
    cached = load_cached_api_hosts()
    if not cached and not clean_conf:
        try:
            discovered, _ = discover_api_hosts(deadline_sec=12.0)
            cached = discovered
        except Exception:
            pass

    values = [*clean_conf, *cached]
    if not values:
        for s in STATIC_API_HOSTS:
            if "*" in s:
                values.append(s.replace("*", rand_str(13)))
            else:
                values.append(s)

    result: list[str] = []
    for value in values:
        h = origin(str(value))
        if h and h not in result:
            result.append(h)
    return result


def urls_for(path: str) -> list[str]:
    """Given a relative path like '/api/index/content_list/2', return full URLs across all hosts."""
    suffix = "/" + path.lstrip("/")
    return [host + suffix for host in api_hosts()]


def fetch_decrypted_articles(path: str = HEALTH_CHECK_PATH, fixture: str | Path | None = None) -> tuple[list[dict[str, Any]], str]:
    """Fetch content list and decrypt into articles JSON list. Returns (articles, final_url)."""
    if fixture:
        fpath = Path(fixture)
        raw = fpath.read_text(encoding="utf-8")
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return parsed, f"file://{fpath.as_posix()}"
            if isinstance(parsed, dict) and "data" in parsed:
                # If wrapped, attempt decrypt or return data
                if isinstance(parsed["data"], list):
                    return parsed["data"], f"file://{fpath.as_posix()}"
                key = base_domain_of(str(fpath.name))
                dec = xor_decrypt(parsed["data"], key)
                return json.loads(dec), f"file://{fpath.as_posix()}"
        except Exception:
            pass
        return [], f"file://{fpath.as_posix()}"

    hosts = api_hosts()
    last_err: Exception | None = None
    for h in hosts:
        key = base_domain_of(h)
        url = f"{h.rstrip('/')}/{path.lstrip('/')}"
        try:
            r = get(url, timeout=10, retries=1, headers={"Referer": f"{h}/"})
            if r.status_code == 200:
                data = r.json().get("data", "")
                dec = xor_decrypt(data, key)
                articles = json.loads(dec)
                if isinstance(articles, list):
                    return articles, str(r.url)
        except Exception as exc:
            last_err = exc
    raise RuntimeError(f"请求所有神算集团节点失败: {last_err}")
