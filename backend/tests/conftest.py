"""Shared pytest fixtures."""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.core.config import Environment, Settings
from app.main import create_app


@pytest.fixture
def settings() -> Settings:
    """Test-scoped settings: never touches a real ``.env`` file."""

    return Settings(
        environment=Environment.TEST,
        _env_file=None,  # type: ignore[call-arg]  # pydantic-settings runtime kwarg
    )


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    """A ``TestClient`` bound to an app built with test settings."""

    app = create_app(settings)
    with TestClient(app) as test_client:
        yield test_client
