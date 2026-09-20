"""FastAPI application entrypoint."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.crypto import session_store
from app.core.ratelimit import limiter
from app.db.session import init_db
from app.middleware.encryption import EncryptionMiddleware
from app.middleware.security_headers import SecurityHeadersMiddleware


from app.services.draw_scheduler import draw_scheduler
from app.services.source_scheduler import source_scheduler


async def _purge_expired_sessions():
    """Periodically purge expired session keys (every 5 minutes)."""
    while True:
        await asyncio.sleep(300)
        session_store.purge_expired()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    try:
        from app.services.settings_service import auto_sync_on_startup
        auto_sync_on_startup()
    except Exception:
        pass
    task_purge = asyncio.create_task(_purge_expired_sessions())
    task_draw = asyncio.create_task(draw_scheduler.run_loop())
    task_source = asyncio.create_task(source_scheduler.run_loop())
    yield
    task_purge.cancel()
    task_draw.cancel()
    task_source.cancel()


app = FastAPI(
    title=settings.APP_NAME,
    version="1.0.0",
    docs_url="/docs" if not settings.is_production else None,
    redoc_url="/redoc" if not settings.is_production else None,
    openapi_url="/openapi.json" if not settings.is_production else None,
    lifespan=lifespan,
)

# --- Rate limiting ---
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# --- Middleware stack (added inner -> outer; last added is outermost) ---
# Innermost: transparent payload encryption/decryption.
app.add_middleware(EncryptionMiddleware)
# Then response hardening headers.
app.add_middleware(SecurityHeadersMiddleware)
# Outermost: CORS, so preflight + headers apply to the final (encrypted) reply.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Session-Id",
        "X-Timestamp",
        "X-Nonce",
        "X-Signature",
        "X-App-Id",
    ],
    expose_headers=["X-Encrypted"],
    max_age=600,
)

app.include_router(api_router, prefix=settings.API_V1_PREFIX)


@app.get("/health", tags=["meta"])
def health() -> dict:
    return {"status": "ok", "env": settings.APP_ENV}


# --- Static SPA Frontend Serving (if built frontend dist exists) ---
_FRONTEND_DIST = Path(__file__).resolve().parent.parent.parent / "frontend" / "dist"
if not _FRONTEND_DIST.exists():
    _ALT_DIST = Path("/app/frontend/dist")
    if _ALT_DIST.exists():
        _FRONTEND_DIST = _ALT_DIST

if _FRONTEND_DIST.exists():
    _assets_dir = _FRONTEND_DIST / "assets"
    if _assets_dir.exists():
        app.mount("/assets", StaticFiles(directory=str(_assets_dir)), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    async def serve_spa(full_path: str):
        if full_path.startswith("api/") or full_path == "api":
            from fastapi import HTTPException
            raise HTTPException(status_code=404, detail="API route not found")
        target = _FRONTEND_DIST / full_path
        if full_path and target.is_file():
            return FileResponse(target)
        return FileResponse(_FRONTEND_DIST / "index.html")
