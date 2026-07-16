"""Aggregate router for API v1.

Every v1 route module is included here; ``app.main`` mounts this single router under
the configured version prefix (``/v1``). New feature routers (auth, receipts,
analytics, ...) are added to this file as their tasks land.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.routes import auth, health, receipts

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(receipts.router)
