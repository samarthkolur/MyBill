"""Tests for Supabase configuration, the client factory, and the DI provider."""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi import Request

from app.api.deps import get_supabase
from app.core.config import Environment, Settings
from app.core.exceptions import ServiceUnavailableError
from app.integrations.supabase import create_supabase_client


def _settings(**overrides: object) -> Settings:
    base: dict[str, object] = {"environment": Environment.TEST, "_env_file": None}
    return Settings(**{**base, **overrides})  # type: ignore[arg-type]


def test_supabase_configured_false_when_unset() -> None:
    assert _settings().supabase_configured is False


def test_supabase_configured_requires_both_url_and_service_key() -> None:
    assert _settings(supabase_url="https://x.supabase.co").supabase_configured is False
    assert _settings(supabase_service_role_key="key").supabase_configured is False
    assert (
        _settings(
            supabase_url="https://x.supabase.co", supabase_service_role_key="key"
        ).supabase_configured
        is True
    )


async def test_create_client_raises_when_unconfigured() -> None:
    with pytest.raises(RuntimeError, match="not configured"):
        await create_supabase_client(_settings())


def _fake_request(supabase: object) -> Request:
    # get_supabase only touches request.app.state.supabase, so a light stand-in suffices.
    app = SimpleNamespace(state=SimpleNamespace(supabase=supabase))
    return SimpleNamespace(app=app)  # type: ignore[return-value]


def test_get_supabase_raises_503_when_client_missing() -> None:
    with pytest.raises(ServiceUnavailableError) as exc:
        get_supabase(_fake_request(None))
    assert exc.value.status_code == 503


def test_get_supabase_returns_client_when_present() -> None:
    sentinel = object()
    assert get_supabase(_fake_request(sentinel)) is sentinel


def test_secret_keys_not_leaked_in_repr() -> None:
    # SecretStr must mask the value in repr/str so it never lands in logs.
    settings = _settings(supabase_service_role_key="super-secret-value")
    assert "super-secret-value" not in repr(settings)
    assert "super-secret-value" not in str(settings.supabase_service_role_key)
