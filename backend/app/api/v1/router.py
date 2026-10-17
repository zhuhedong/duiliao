"""Aggregate v1 API router."""
from fastapi import APIRouter

from typing import Any

from app import collector_bridge as cb
from app.api.v1 import ai, auth, collector, crypto, mobile, settings, users

api_router = APIRouter()
api_router.include_router(crypto.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(collector.router)
api_router.include_router(mobile.router)
api_router.include_router(ai.router)
api_router.include_router(settings.router)


@api_router.get("/trend/getTrend", tags=["trend"])
def get_trend_compatible(lottery: str = "macau", limit: int = 100, force_refresh: bool = False) -> dict[str, Any]:
    return cb.get_trend(lottery=lottery, limit=limit, force_refresh=force_refresh)


@api_router.get("/health", tags=["meta"])
def health() -> dict:
    return {"status": "ok"}

