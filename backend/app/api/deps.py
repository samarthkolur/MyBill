"""Reusable FastAPI dependencies.

Dependencies read shared resources off ``request.app.state`` (populated by the app
factory) rather than from module-level globals. This keeps handlers decoupled from the
cached ``get_settings()`` singleton so a test app built with overridden settings behaves
correctly, and gives future resources (DB session, Supabase client) a consistent
injection point.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from supabase import AsyncClient

from app.core.config import Settings
from app.core.exceptions import ServiceUnavailableError, UnauthorizedError
from app.core.security import AuthenticatedUser, AuthError, JwtVerifier
from app.integrations.tasks import CeleryTaskQueue
from app.repositories.parsed import ReceiptItemRepository
from app.repositories.receipts import ReceiptImageRepository, ReceiptRepository
from app.repositories.reference import CategoryRepository, StoreRepository
from app.repositories.users import UserRepository
from app.services.receipts import ReceiptService
from app.services.users import UserService


def get_settings(request: Request) -> Settings:
    """Return the settings the running app was built with."""

    settings: Settings = request.app.state.settings
    return settings


SettingsDep = Annotated[Settings, Depends(get_settings)]


def get_supabase(request: Request) -> AsyncClient:
    """Return the shared service-role Supabase client.

    Raises 503 if Supabase isn't configured for this deployment, rather than failing
    deep inside a handler with an ``AttributeError``.
    """

    client: AsyncClient | None = getattr(request.app.state, "supabase", None)
    if client is None:
        raise ServiceUnavailableError("Supabase client is not configured.")
    return client


SupabaseDep = Annotated[AsyncClient, Depends(get_supabase)]


# HTTPBearer surfaces the "Authorize" button in the OpenAPI docs and extracts the token.
# auto_error=False so we raise our own envelope-shaped 401 instead of FastAPI's default.
_bearer_scheme = HTTPBearer(auto_error=False, description="Supabase access token")


async def get_current_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
) -> AuthenticatedUser:
    """Resolve and verify the caller's Supabase JWT, or raise 401.

    Depend on this from any route that requires authentication. Returns the verified
    principal (``id``, ``email``, ``role``, full ``claims``).
    """

    verifier: JwtVerifier | None = getattr(request.app.state, "jwt_verifier", None)
    if verifier is None:
        raise ServiceUnavailableError("Authentication is not configured.")

    if credentials is None or not credentials.credentials:
        raise UnauthorizedError("Missing authentication token.")

    try:
        # PyJWKClient does (cached) network I/O + crypto; run off the event loop.
        return await run_in_threadpool(verifier.verify, credentials.credentials)
    except AuthError as exc:
        raise UnauthorizedError(str(exc)) from exc


CurrentUserDep = Annotated[AuthenticatedUser, Depends(get_current_user)]


def get_user_service(supabase: Annotated[AsyncClient, Depends(get_supabase)]) -> UserService:
    """Provide a ``UserService`` backed by the shared Supabase client."""

    return UserService(UserRepository(supabase))


UserServiceDep = Annotated[UserService, Depends(get_user_service)]


def get_receipt_service(
    supabase: Annotated[AsyncClient, Depends(get_supabase)],
) -> ReceiptService:
    """Provide a ``ReceiptService`` backed by the shared Supabase client.

    Wired with the Celery queue so a successful upload enqueues OCR processing.
    """

    return ReceiptService(
        supabase,
        ReceiptRepository(supabase),
        ReceiptImageRepository(supabase),
        CeleryTaskQueue(),
        stores=StoreRepository(supabase),
        categories=CategoryRepository(supabase),
        items=ReceiptItemRepository(supabase),
    )


ReceiptServiceDep = Annotated[ReceiptService, Depends(get_receipt_service)]
