"""Data access for ``public.users``.

Wraps the Supabase (PostgREST) calls for the users table. Uses the shared service-role
client, so every method here is responsible for scoping by the caller's ``user_id`` —
RLS is the database-level backstop, not the only guard (MyBill.md §11).
"""

from __future__ import annotations

from typing import Any, cast
from uuid import UUID

from supabase import AsyncClient

_TABLE = "users"


class UserRepository:
    """CRUD for the user profile table."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def get(self, user_id: UUID) -> dict[str, Any] | None:
        """Return the profile row for ``user_id``, or None if it doesn't exist."""

        resp = (
            await self._client.table(_TABLE).select("*").eq("id", str(user_id)).limit(1).execute()
        )
        rows = cast("list[dict[str, Any]]", resp.data or [])
        return rows[0] if rows else None

    async def upsert(self, *, user_id: UUID, email: str, full_name: str | None) -> dict[str, Any]:
        """Insert-or-update the profile row keyed on the primary key ``id``.

        Idempotent: safe to call on every authenticated request. Only the identity
        columns are written here — user-editable fields (currency, timezone) keep their
        existing/default values and are changed via a dedicated profile-update path.
        """

        payload: dict[str, Any] = {"id": str(user_id), "email": email}
        if full_name is not None:
            payload["full_name"] = full_name

        resp = await self._client.table(_TABLE).upsert(payload).execute()
        rows = cast("list[dict[str, Any]]", resp.data or [])
        if not rows:
            raise RuntimeError("Upsert of user profile returned no row.")
        return rows[0]
