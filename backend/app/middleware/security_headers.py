"""Adds hardening HTTP response headers to every response."""
from __future__ import annotations

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import settings

_BASE_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"referrer-policy", b"no-referrer"),
    (b"cross-origin-opener-policy", b"same-origin"),
    (b"cross-origin-resource-policy", b"same-origin"),
    (b"permissions-policy", b"geolocation=(), microphone=(), camera=()"),
]

# API responses are JSON only, so they can use a completely isolated policy.
_API_CSP = b"default-src 'none'; frame-ancestors 'none'"

# The backend also serves the compiled React SPA. Keep its policy limited to
# the resources the app actually needs instead of applying the API policy to
# the HTML document and blocking every bundle. Cloudflare Web Analytics adds
# its beacon at the edge, so its script origin is listed explicitly.
#
# - script-src-elem is set explicitly so browsers don't fall back to
#   script-src / default-src, which caused Cloudflare beacon blocks.
# - style-src-elem is set explicitly for the same reason with stylesheets.
_SPA_CSP = (
    b"default-src 'self'; "
    b"base-uri 'self'; "
    b"object-src 'none'; "
    b"frame-ancestors 'none'; "
    b"script-src 'self' 'unsafe-inline' https://static.cloudflareinsights.com; "
    b"script-src-elem 'self' https://static.cloudflareinsights.com; "
    b"script-src-attr 'none'; "
    b"style-src 'self' 'unsafe-inline'; "
    b"style-src-elem 'self' 'unsafe-inline'; "
    b"img-src 'self' data: blob:; "
    b"font-src 'self' data:; "
    b"connect-src 'self' https://cloudflareinsights.com"
)


def _is_api_request(path: str) -> bool:
    """Return whether *path* serves an API or API metadata response."""
    # Static SPA assets (JS/CSS/fonts/images) must never get the API CSP.
    if path.startswith("/assets/") or path.startswith("/static/"):
        return False
    api_prefix = settings.API_V1_PREFIX.rstrip("/")
    return (
        path == "/health"
        or path == "/api"
        or path.startswith("/api/")
        or path == api_prefix
        or path.startswith(f"{api_prefix}/")
        or path == "/docs"
        or path.startswith("/docs/")
        or path == "/redoc"
        or path.startswith("/redoc/")
        or path == "/openapi.json"
    )


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = message.setdefault("headers", [])
                existing = {k.lower() for k, _ in headers}
                for key, value in _BASE_HEADERS:
                    if key not in existing:
                        headers.append((key, value))
                csp = _API_CSP if _is_api_request(scope["path"]) else _SPA_CSP
                if b"content-security-policy" not in existing:
                    headers.append((b"content-security-policy", csp))
                if settings.is_production:
                    headers.append(
                        (b"strict-transport-security", b"max-age=63072000; includeSubDomains; preload")
                    )
            await send(message)

        await self.app(scope, receive, send_with_headers)
