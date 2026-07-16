"""Health-check endpoint.

Consumed by uptime monitoring (MyBill.md §12 — "Uptime robot: /health endpoint")
and by container orchestration liveness probes. Intentionally dependency-free: it must
answer even when downstream services (DB, Redis) are degraded, so a future ``/health/ready``
readiness probe — which *does* check dependencies — will live alongside it.
"""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from app.api.deps import SettingsDep
from app.core.responses import ApiResponse, success

router = APIRouter(tags=["health"])


class HealthStatus(BaseModel):
    """Liveness payload."""

    status: str
    service: str
    environment: str
    version: str


@router.get(
    "/health",
    response_model=ApiResponse[HealthStatus],
    summary="Liveness check",
)
async def health(settings: SettingsDep) -> ApiResponse[HealthStatus]:
    """Return service liveness. Always 200 when the process is up."""

    from app import __version__

    return success(
        HealthStatus(
            status="ok",
            service=settings.app_name,
            environment=settings.environment.value,
            version=__version__,
        )
    )
