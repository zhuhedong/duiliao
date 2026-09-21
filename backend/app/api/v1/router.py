"""Aggregate v1 API router."""
from fastapi import APIRouter

from app.api.v1 import ai, auth, collector, crypto, mobile, settings, users

api_router = APIRouter()
api_router.include_router(crypto.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(collector.router)
api_router.include_router(mobile.router)
api_router.include_router(ai.router)
api_router.include_router(settings.router)



@api_router.get("/health", tags=["meta"])
def health() -> dict:
    return {"status": "ok"}
