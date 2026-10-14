"""588080 / 顶尖大师 API host pool: discover, health-check, persist, serve.

Persists to:
1. Setting key ``dingjian_host_pool`` (collector DB) — shared across processes
2. File cache via ``common.sites.dingjian.save_api_hosts`` — offline scripts

Callers must not pass arbitrary user-controlled hosts into refresh without
going through ``public_https_url`` / SSRF guards used by discovery.
"""
from __future__ import annotations

import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import select

from common.sites.dingjian import (
    DEFAULT_ENTRIES,
    STATIC_API_HOSTS,
    WEBSITE_CONFIG_PATH,
    discover_api_hosts,
    load_cached_api_hosts,
    origin,
    public_https_url,
    save_api_hosts,
)
from common.http import get_json, assert_safe_url
from db import session_scope
from schema import Setting

log = logging.getLogger("pred.host_pool")

SETTING_KEY = "dingjian_host_pool"
SCHEMA = "dingjian-host-pool.v1"
TZ8 = timezone(timedelta(hours=8))

# Soft TTL: still usable after this, but refresh is recommended.
DEFAULT_MAX_AGE_SEC = 30 * 60


def _now_iso() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def _empty_pool() -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "updated_at": None,
        "entry_urls": list(DEFAULT_ENTRIES),
        "hosts": [],
        "primary": None,
        "errors": [],
        "health": {},
    }


def load_pool() -> dict[str, Any]:
    """Load pool from DB Setting, falling back to file cache then static hosts."""
    try:
        with session_scope() as session:
            row = session.get(Setting, SETTING_KEY)
            if row and isinstance(row.value, dict) and row.value.get("schema") == SCHEMA:
                return dict(row.value)
    except Exception as exc:
        log.warning("host pool DB read failed: %s", exc)

    cached = load_cached_api_hosts()
    if cached:
        return {
            **_empty_pool(),
            "updated_at": None,
            "hosts": cached,
            "primary": cached[0],
            "source": "file_cache",
        }
    static = [origin(h) or h for h in STATIC_API_HOSTS]
    static = [h for h in static if h]
    return {
        **_empty_pool(),
        "hosts": static,
        "primary": static[0] if static else None,
        "source": "static",
    }


def save_pool(pool: dict[str, Any]) -> dict[str, Any]:
    payload = {
        "schema": SCHEMA,
        "updated_at": pool.get("updated_at") or _now_iso(),
        "entry_urls": list(pool.get("entry_urls") or DEFAULT_ENTRIES),
        "hosts": list(pool.get("hosts") or []),
        "primary": pool.get("primary"),
        "errors": list(pool.get("errors") or [])[-20:],
        "health": dict(pool.get("health") or {}),
    }
    with session_scope() as session:
        session.merge(Setting(key=SETTING_KEY, value=payload))
    try:
        save_api_hosts(payload["hosts"], entry_urls=payload["entry_urls"])
    except OSError as exc:
        log.warning("host pool file cache write failed: %s", exc)
    return payload


def health_check(host: str, *, timeout: float = 6.0) -> dict[str, Any]:
    """Probe website/config; reject private targets before requesting."""
    base = origin(host) or (host or "").rstrip("/")
    started = time.perf_counter()
    result: dict[str, Any] = {
        "host": base,
        "ok": False,
        "elapsed_ms": 0,
        "error": None,
        "checked_at": _now_iso(),
    }
    if not base:
        result["error"] = "empty_host"
        return result
    try:
        assert_safe_url(base + "/")
        if not public_https_url(base + "/"):
            result["error"] = "unsafe_host"
            result["elapsed_ms"] = int((time.perf_counter() - started) * 1000)
            return result
        payload = get_json(base + WEBSITE_CONFIG_PATH, timeout=timeout, retries=0)
        ok = isinstance(payload, dict) and payload.get("code") == 0 and isinstance(payload.get("data"), dict)
        result["ok"] = bool(ok)
        if not ok:
            result["error"] = "bad_config"
    except Exception as exc:
        result["error"] = str(exc)
    result["elapsed_ms"] = int((time.perf_counter() - started) * 1000)
    return result


def refresh(
    *,
    entries: list[str] | tuple[str, ...] | None = None,
    deadline_sec: float = 35.0,
    max_valid: int = 8,
) -> dict[str, Any]:
    """Discover hosts, health-check each, persist the pool."""
    entry_urls = [str(e).rstrip("/") + "/" for e in (entries or DEFAULT_ENTRIES)]
    for entry in entry_urls:
        assert_safe_url(entry)
        if not public_https_url(entry):
            raise ValueError(f"拒绝不安全入口: {entry}")

    errors: list[str] = []
    hosts: list[str] = []
    try:
        discovered, disc_errors = discover_api_hosts(
            entry_urls,
            fallback_hosts=STATIC_API_HOSTS,
            deadline_sec=deadline_sec,
            max_valid=max_valid,
        )
        hosts = list(discovered)
        errors.extend(disc_errors or [])
    except Exception as exc:
        errors.append(str(exc))
        # Fall back to previous pool + static so refresh never leaves us empty
        # when discovery partially fails.
        prev = load_pool()
        hosts = list(prev.get("hosts") or []) + [origin(h) or h for h in STATIC_API_HOSTS]

    # Deduplicate preserving order
    seen: set[str] = set()
    unique: list[str] = []
    for h in hosts:
        base = origin(h) or (h or "").rstrip("/")
        if base and base not in seen:
            seen.add(base)
            unique.append(base)

    prev_health = dict((load_pool() or {}).get("health") or {})
    health: dict[str, Any] = {}
    healthy: list[str] = []
    for host in unique[:max_valid]:
        check = _merge_health(prev_health.get(host), health_check(host))
        health[host] = check
        if check["ok"]:
            healthy.append(host)
        else:
            errors.append(f"{host}: {check.get('error')}")

    if not healthy and unique:
        # Keep last-known hosts so collectors can still try fallbacks.
        healthy = unique[:max_valid]

    pool = {
        "schema": SCHEMA,
        "updated_at": _now_iso(),
        "entry_urls": entry_urls,
        "hosts": healthy,
        "primary": healthy[0] if healthy else None,
        "errors": errors[-20:],
        "health": health,
        "ok": bool(healthy),
    }
    return save_pool(pool)


def active_hosts(*, max_age_sec: float | None = DEFAULT_MAX_AGE_SEC) -> list[str]:
    """Return usable hosts; auto-refresh when empty or stale."""
    pool = load_pool()
    hosts = [h for h in (pool.get("hosts") or []) if h]
    updated = pool.get("updated_at")
    stale = False
    if max_age_sec is not None and updated:
        try:
            ts = datetime.fromisoformat(str(updated))
            if ts.tzinfo is None:
                ts = ts.replace(tzinfo=TZ8)
            age = (datetime.now(TZ8) - ts.astimezone(TZ8)).total_seconds()
            stale = age > max_age_sec
        except ValueError:
            stale = True
    if not hosts or (stale and pool.get("source") != "static"):
        try:
            pool = refresh()
            hosts = list(pool.get("hosts") or [])
        except Exception as exc:
            log.warning("host pool refresh failed: %s", exc)
            if not hosts:
                hosts = [origin(h) or h for h in STATIC_API_HOSTS]
                hosts = [h for h in hosts if h]
    return hosts


def primary_host() -> str | None:
    hosts = active_hosts()
    return hosts[0] if hosts else None


def status() -> dict[str, Any]:
    pool = load_pool()
    return {
        "ok": bool(pool.get("hosts")),
        "schema": pool.get("schema"),
        "updated_at": pool.get("updated_at"),
        "primary": pool.get("primary") or (pool.get("hosts") or [None])[0],
        "hosts": list(pool.get("hosts") or []),
        "entry_urls": list(pool.get("entry_urls") or DEFAULT_ENTRIES),
        "errors": list(pool.get("errors") or [])[-10:],
        "health": dict(pool.get("health") or {}),
        "host_count": len(pool.get("hosts") or []),
    }


def _merge_health(prev: dict[str, Any] | None, check: dict[str, Any]) -> dict[str, Any]:
    """Attach consecutive_failures / last_ok_at onto a fresh health-check result."""
    prev = prev or {}
    out = dict(check)
    if check.get("ok"):
        out["consecutive_failures"] = 0
        out["last_ok_at"] = check.get("checked_at") or prev.get("last_ok_at")
    else:
        out["consecutive_failures"] = int(prev.get("consecutive_failures") or 0) + 1
        out["last_ok_at"] = prev.get("last_ok_at")
    return out


def probe(*, full_refresh_if_empty: bool = True) -> dict[str, Any]:
    """Health-check hosts already in the pool; refresh only when empty or all fail.

    Safer default for the background worker than always re-running discovery.
    """
    pool = load_pool()
    hosts = [h for h in (pool.get("hosts") or []) if h]
    if not hosts:
        if full_refresh_if_empty:
            refreshed = refresh()
            refreshed["action"] = "refresh"
            return refreshed
        status_payload = status()
        status_payload["action"] = "noop_empty"
        return status_payload

    prev_health = dict(pool.get("health") or {})
    health: dict[str, Any] = {}
    healthy: list[str] = []
    for host in hosts:
        check = _merge_health(prev_health.get(host), health_check(host))
        health[host] = check
        if check.get("ok"):
            healthy.append(host)

    if not healthy:
        refreshed = refresh()
        refreshed["action"] = "refresh_after_probe_fail"
        # Preserve consecutive failure counts for hosts that still fail.
        merged_health = dict(refreshed.get("health") or {})
        for host, check in health.items():
            if host in merged_health and not merged_health[host].get("ok"):
                merged_health[host] = _merge_health(check, merged_health[host])
            elif host not in merged_health:
                merged_health[host] = check
        refreshed["health"] = merged_health
        return save_pool(refreshed) | {"action": "refresh_after_probe_fail"}

    # Keep unhealthy hosts at the end so collectors still have fallbacks recorded.
    ordered = healthy + [h for h in hosts if h not in healthy]
    payload = {
        "schema": SCHEMA,
        "updated_at": _now_iso(),
        "entry_urls": list(pool.get("entry_urls") or DEFAULT_ENTRIES),
        "hosts": ordered,
        "primary": healthy[0],
        "errors": list(pool.get("errors") or [])[-20:],
        "health": health,
        "ok": True,
        "action": "probe",
    }
    saved = save_pool(payload)
    saved["action"] = "probe"
    return saved
