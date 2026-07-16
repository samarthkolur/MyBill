"""Data access for ``public.receipts``.

Uses the shared service-role client, so every method scopes by ``user_id`` explicitly;
RLS is the database-level backstop (MyBill.md §11).
"""

from __future__ import annotations

from typing import Any, cast
from uuid import UUID

from supabase import AsyncClient

_TABLE = "receipts"


class ReceiptRepository:
    """Writes/reads for the receipts table."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def create_pending(
        self, *, receipt_id: UUID, user_id: UUID, image_url: str
    ) -> dict[str, Any]:
        """Insert a new receipt in the ``pending`` state and return the created row."""

        payload = {
            "id": str(receipt_id),
            "user_id": str(user_id),
            "image_url": image_url,
            "status": "pending",
        }
        resp = await self._client.table(_TABLE).insert(payload).execute()
        rows = cast("list[dict[str, Any]]", resp.data or [])
        if not rows:
            raise RuntimeError("Insert of receipt returned no row.")
        return rows[0]
