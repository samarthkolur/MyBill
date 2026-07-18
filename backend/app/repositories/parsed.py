"""Write access for the parser's output tables (MyBill.md §6, Stage 4).

``receipt_items`` and ``price_history`` are filled when OCR + parsing complete. Both are
written with ``replace_for_receipt``: delete this receipt's rows, then insert the current
set. That makes re-processing a receipt idempotent — re-running the pipeline with the same
receipt id converges on one clean set of rows instead of accumulating duplicates
(MyBill.md §6, "Each task is idempotent").

Both use the shared service-role client and carry ``user_id`` on every row so RLS and the
owner policies still hold for data written by a system (non-user) operation.
"""

from __future__ import annotations

from typing import Any, cast
from uuid import UUID

from supabase import AsyncClient

_ITEMS_TABLE = "receipt_items"
_PRICE_HISTORY_TABLE = "price_history"


class ReceiptItemRepository:
    """Writes/reads for ``public.receipt_items`` (a receipt's line items)."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def replace_for_receipt(
        self, *, receipt_id: UUID, rows: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """Replace this receipt's line items with ``rows`` and return the inserted rows."""

        await self._client.table(_ITEMS_TABLE).delete().eq("receipt_id", str(receipt_id)).execute()
        if not rows:
            return []
        resp = await self._client.table(_ITEMS_TABLE).insert(cast("Any", rows)).execute()
        return cast("list[dict[str, Any]]", resp.data or [])

    async def list_for_receipt(self, *, receipt_id: UUID) -> list[dict[str, Any]]:
        """A receipt's line items, in insertion order."""

        resp = (
            await self._client.table(_ITEMS_TABLE)
            .select("*")
            .eq("receipt_id", str(receipt_id))
            .execute()
        )
        return cast("list[dict[str, Any]]", resp.data or [])

    async def search(self, *, user_id: UUID, query: str, limit: int = 50) -> list[dict[str, Any]]:
        """A user's line items whose name matches ``query`` (case-insensitive substring).

        Each row embeds its receipt's ``date`` and ``store_id`` (a PostgREST join) so a
        search result can show where and when the item was bought without a second round
        trip. Newest first.
        """

        resp = (
            await self._client.table(_ITEMS_TABLE)
            .select("*, receipts(date, store_id)")
            .eq("user_id", str(user_id))
            .ilike("name_normalised", f"%{query}%")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return cast("list[dict[str, Any]]", resp.data or [])


class PriceHistoryRepository:
    """Writes for ``public.price_history`` (per-item price observations)."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def replace_for_receipt(
        self, *, receipt_id: UUID, rows: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """Replace this receipt's price observations with ``rows``.

        Keyed on ``receipt_id`` so a re-parse rewrites only this receipt's observations and
        leaves the rest of the user's price history untouched.
        """

        await (
            self._client.table(_PRICE_HISTORY_TABLE)
            .delete()
            .eq("receipt_id", str(receipt_id))
            .execute()
        )
        if not rows:
            return []
        resp = await self._client.table(_PRICE_HISTORY_TABLE).insert(cast("Any", rows)).execute()
        return cast("list[dict[str, Any]]", resp.data or [])
