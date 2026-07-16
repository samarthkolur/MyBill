"""User profile business logic."""

from __future__ import annotations

from typing import Any

from app.core.logging import get_logger
from app.core.security import AuthenticatedUser
from app.repositories.users import UserRepository
from app.schemas.user import UserProfile

logger = get_logger("app.users")


class UserService:
    """Orchestrates user-profile operations over the repository."""

    def __init__(self, repository: UserRepository):
        self._repository = repository

    async def ensure_profile(self, user: AuthenticatedUser) -> UserProfile:
        """Return the caller's profile, creating it if it doesn't exist yet.

        The database trigger ``handle_new_user`` normally provisions a profile at signup
        (see ``infra/supabase``). This is the app-layer safety-net (MyBill.md task 1.2.3)
        for accounts that predate the trigger or a signup where it didn't run: on the
        first authenticated request the row is guaranteed to exist. Idempotent.
        """

        existing = await self._repository.get(user.id)
        if existing is not None:
            return UserProfile.model_validate(existing)

        logger.info("provisioning_missing_profile", extra={"user_id": str(user.id)})
        row: dict[str, Any] = await self._repository.upsert(
            user_id=user.id,
            email=user.email or "",
            full_name=_full_name_from_claims(user),
        )
        return UserProfile.model_validate(row)


def _full_name_from_claims(user: AuthenticatedUser) -> str | None:
    """Best-effort display name from Supabase user_metadata (OAuth/signup)."""

    metadata = user.claims.get("user_metadata")
    if isinstance(metadata, dict):
        name = metadata.get("full_name") or metadata.get("name")
        if isinstance(name, str) and name:
            return name
    return None
