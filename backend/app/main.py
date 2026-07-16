"""Application factory and ASGI entrypoint.

``create_app()`` wires configuration, logging, middleware, exception handlers, and the
versioned router into a ``FastAPI`` instance. Keeping construction in a factory (rather
than a module-level singleton) makes the app trivially re-buildable in tests with
overridden settings, and keeps import side effects out of the module body.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import __version__
from app.api.v1.router import api_router
from app.core.config import Settings, get_settings
from app.core.exceptions import register_exception_handlers
from app.core.logging import configure_logging, get_logger
from app.core.middleware import RequestContextMiddleware
from app.core.security import build_jwt_verifier
from app.integrations.supabase import create_supabase_client

logger = get_logger("app.main")


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Startup/shutdown hooks. Shared clients/pools are opened and closed here."""

    settings: Settings = app.state.settings
    logger.info(
        "app_startup",
        extra={"environment": settings.environment.value, "version": __version__},
    )

    # Build the shared service-role Supabase client if configured. Left as None when
    # unconfigured (e.g. unit tests) — the SupabaseDep dependency then returns 503.
    if settings.supabase_configured:
        app.state.supabase = await create_supabase_client(settings)
    else:
        app.state.supabase = None
        logger.warning("supabase_not_configured")

    # Build the JWT verifier (needs only the Supabase URL for JWKS). None when auth is
    # unconfigured — the CurrentUser dependency then returns 503.
    if settings.auth_configured:
        app.state.jwt_verifier = build_jwt_verifier(settings)
    else:
        app.state.jwt_verifier = None

    yield

    logger.info("app_shutdown")


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build and configure the FastAPI application."""

    settings = settings or get_settings()
    configure_logging(level=settings.log_level, json_output=settings.log_json)

    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        debug=settings.debug,
        # Hide interactive docs in production; expose them everywhere else.
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None if settings.is_production else "/redoc",
        openapi_url=None if settings.is_production else "/openapi.json",
        lifespan=_lifespan,
    )
    app.state.settings = settings

    # Order matters: request-context (id + access log) wraps everything, CORS outermost.
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    register_exception_handlers(app)
    app.include_router(api_router, prefix=settings.api_v1_prefix)

    return app


# ASGI entrypoint for `uvicorn app.main:app`.
app = create_app()
