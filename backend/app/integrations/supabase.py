"""Server-side Supabase client.

The backend holds a single **service-role** async client, created once at app startup
and reused for all system operations — storage writes under ``receipts/{user_id}/``,
admin auth, and cache/OCR-completion writes (``MyBill.md`` §11). The service role
bypasses Row-Level Security, so callers here MUST scope every query by ``user_id``
themselves; RLS remains the second line of defence at the database.

Never build a client from the anon key for privileged work, and never expose the
service-role key to any client application.
"""

from __future__ import annotations

from supabase import AsyncClient, create_async_client

from app.core.config import Settings
from app.core.logging import get_logger

logger = get_logger("app.supabase")


async def create_supabase_client(settings: Settings) -> AsyncClient:
    """Create an async Supabase client authenticated with the service-role key.

    Raises:
        RuntimeError: if Supabase is not configured (guard with
            ``settings.supabase_configured`` before calling).
    """

    if not settings.supabase_configured:
        raise RuntimeError(
            "Supabase is not configured — set SUPABASE_URL and "
            "SUPABASE_SERVICE_ROLE_KEY before creating the client."
        )

    client = await create_async_client(
        settings.supabase_url,
        settings.supabase_service_role_key.get_secret_value(),
    )
    # Log that the client is ready — never log the URL's key or any secret.
    logger.info("supabase_client_created", extra={"supabase_url": settings.supabase_url})
    return client
