"""Application settings.

All runtime configuration is read from environment variables (or a local ``.env``
file during development) and validated once at startup via a cached ``Settings``
instance. Nothing else in the codebase should read ``os.environ`` directly — inject
``get_settings()`` instead so configuration stays typed and testable.
"""

from __future__ import annotations

from enum import StrEnum
from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Environment(StrEnum):
    """Deployment environment. Mirrors MyBill.md §12."""

    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"
    TEST = "test"


class Settings(BaseSettings):
    """Typed, validated application configuration.

    Field names map to upper-cased environment variables (``app_name`` ← ``APP_NAME``).
    See ``.env.example`` for the full set of supported variables.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ---- App ----
    app_name: str = "MyBill API"
    environment: Environment = Environment.DEVELOPMENT
    debug: bool = False
    api_v1_prefix: str = "/v1"

    # ---- Server ----
    host: str = "0.0.0.0"  # noqa: S104 — binding all interfaces is intended inside the container
    port: int = 8000

    # ---- Logging ----
    log_level: str = "INFO"
    # JSON logs in deployed envs, human-readable console logs locally.
    log_json: bool = False

    # ---- CORS ----
    # Comma-separated list of allowed origins for the mobile app / web clients.
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    # ---- Supabase ----
    # All optional so the app still boots (and unit tests run) without Supabase
    # configured; the client provider fails loudly if used while unconfigured.
    # Keys are SecretStr so they can never be accidentally logged or serialised.
    supabase_url: str = ""
    supabase_anon_key: SecretStr = SecretStr("")
    supabase_service_role_key: SecretStr = SecretStr("")
    # Legacy symmetric JWT signing secret — used by the JWT verification middleware
    # (task 1.2.2). Newer projects can verify via JWKS instead.
    supabase_jwt_secret: SecretStr = SecretStr("")

    @property
    def is_production(self) -> bool:
        return self.environment == Environment.PRODUCTION

    @property
    def supabase_configured(self) -> bool:
        """True when the server-side (service-role) Supabase client can be built."""

        return bool(self.supabase_url and self.supabase_service_role_key.get_secret_value())


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide, cached ``Settings`` instance.

    Cached so the ``.env`` file and environment are parsed exactly once. Tests that
    need to override configuration should call ``get_settings.cache_clear()`` after
    mutating the environment.
    """

    return Settings()
