"""Tests for UserService.ensure_profile (the app-layer profile safety-net)."""

from __future__ import annotations

from typing import Any
from uuid import UUID, uuid4

import pytest

from app.core.security import AuthenticatedUser
from app.services.users import UserService


class _FakeRepo:
    """In-memory stand-in for UserRepository, recording calls."""

    def __init__(self, existing: dict[str, Any] | None):
        self._existing = existing
        self.upsert_calls: list[dict[str, Any]] = []

    async def get(self, user_id: UUID) -> dict[str, Any] | None:
        return self._existing

    async def upsert(self, *, user_id: UUID, email: str, full_name: str | None) -> dict[str, Any]:
        row = {
            "id": str(user_id),
            "email": email,
            "full_name": full_name,
            "currency": "INR",
            "timezone": "Asia/Kolkata",
            "created_at": "2026-07-16T00:00:00+00:00",
        }
        self.upsert_calls.append(row)
        return row


def _user(**claims: Any) -> AuthenticatedUser:
    return AuthenticatedUser(
        id=uuid4(), email="user@example.com", role="authenticated", claims=claims
    )


async def test_returns_existing_profile_without_upsert() -> None:
    user = _user()
    existing = {
        "id": str(user.id),
        "email": "user@example.com",
        "full_name": "Existing",
        "currency": "USD",
        "timezone": "America/New_York",
        "created_at": "2026-01-01T00:00:00+00:00",
    }
    repo = _FakeRepo(existing)
    profile = await UserService(repo).ensure_profile(user)  # type: ignore[arg-type]

    assert profile.full_name == "Existing"
    assert profile.currency == "USD"
    assert repo.upsert_calls == []  # existing row → no write


async def test_provisions_profile_when_missing() -> None:
    user = _user(user_metadata={"full_name": "New Person"})
    repo = _FakeRepo(None)
    profile = await UserService(repo).ensure_profile(user)  # type: ignore[arg-type]

    assert len(repo.upsert_calls) == 1
    assert profile.id == user.id
    assert profile.full_name == "New Person"  # pulled from user_metadata
    assert profile.currency == "INR"  # DB default


@pytest.mark.parametrize(
    ("metadata", "expected"),
    [
        ({"full_name": "Full Name"}, "Full Name"),
        ({"name": "OAuth Name"}, "OAuth Name"),
        ({}, None),
    ],
)
async def test_full_name_extracted_from_metadata(
    metadata: dict[str, Any], expected: str | None
) -> None:
    repo = _FakeRepo(None)
    await UserService(repo).ensure_profile(_user(user_metadata=metadata))  # type: ignore[arg-type]
    assert repo.upsert_calls[0]["full_name"] == expected
