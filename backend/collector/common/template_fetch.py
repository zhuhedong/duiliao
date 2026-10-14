"""Config-driven fetch helpers for 588080 columns identified by upstream_id.

Preferred path for new sources of common play types:
1. Register a source with ``site_family=dingjian_dashi``
2. Set ``extra.upstream_id`` + an accepted ``extra.parser``
3. Let ``registry.render_template`` emit the script

This module exposes the URL list so other tooling (catalog batch, tests) can
build the same request without copying host-pool logic.
"""
from __future__ import annotations

from typing import Any


def byid_path(upstream_id: str | int) -> str:
    uid = str(upstream_id).strip()
    if not uid.isdigit():
        raise ValueError("upstream_id 必须为数字")
    return f"/api/v1/index/config/byid/{uid}"


def urls_for_upstream(upstream_id: str | int) -> list[str]:
    """Resolve host-pool bases + byid path for a 588080 column."""
    from common.sites.dingjian import STATIC_API_HOSTS, load_cached_api_hosts, origin

    path = byid_path(upstream_id)
    hosts: list[str] = []
    try:
        from host_pool import load_pool

        hosts.extend(load_pool().get("hosts") or [])
    except Exception:
        pass
    hosts.extend(load_cached_api_hosts())
    hosts.extend(STATIC_API_HOSTS)
    result: list[str] = []
    for host in hosts:
        base = origin(str(host))
        if base and base not in result:
            result.append(base + path)
    return result


def source_extra_template(
    *,
    upstream_id: str | int,
    parser: str,
    kind: str = "xiao",
) -> dict[str, Any]:
    """Build the ``extra`` dict expected by the dynamic site template renderer."""
    return {
        "upstream_id": str(upstream_id),
        "path": byid_path(upstream_id),
        "parser": parser,
        "kind": kind,
    }
