"""Data access for ``public.receipts`` and ``public.receipt_images``.

Uses the shared service-role client, so every method scopes by ``user_id`` explicitly;
RLS is the database-level backstop (MyBill.md §11).
"""

from __future__ import annotations

from typing import Any, cast
from uuid import UUID

from supabase import AsyncClient

_TABLE = "receipts"
_IMAGES_TABLE = "receipt_images"


class ReceiptRepository:
    """Writes/reads for the receipts table."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def create_pending(self, *, receipt_id: UUID, user_id: UUID) -> dict[str, Any]:
        """Insert a new receipt in the ``pending`` state and return the created row.

        Pages live in ``receipt_images`` (a receipt has 1..N), so nothing is written to the
        deprecated ``receipts.image_url`` column.
        """

        payload = {
            "id": str(receipt_id),
            "user_id": str(user_id),
            "status": "pending",
        }
        resp = await self._client.table(_TABLE).insert(payload).execute()
        rows = cast("list[dict[str, Any]]", resp.data or [])
        if not rows:
            raise RuntimeError("Insert of receipt returned no row.")
        return rows[0]

    async def get_owned(self, *, receipt_id: UUID, user_id: UUID) -> dict[str, Any] | None:
        """Fetch one receipt belonging to ``user_id``, or None.

        Filtering on ``user_id`` as well as ``id`` means another user's receipt reads as
        absent rather than forbidden — the endpoint never confirms that the id exists.
        """

        resp = (
            await self._client.table(_TABLE)
            .select("*")
            .eq("id", str(receipt_id))
            .eq("user_id", str(user_id))
            .limit(1)
            .execute()
        )
        rows = cast("list[dict[str, Any]]", resp.data or [])
        return rows[0] if rows else None

    async def list_for_user(
        self, *, user_id: UUID, limit: int = 20, offset: int = 0
    ) -> list[dict[str, Any]]:
        """A user's receipts, newest first.

        Ordered by ``created_at``, not the parsed ``date`` — that stays null until OCR
        runs, and a just-created pending receipt must still appear (first) so the user can
        add a page to the bill they just started.
        """

        resp = (
            await self._client.table(_TABLE)
            .select("*")
            .eq("user_id", str(user_id))
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
        return cast("list[dict[str, Any]]", resp.data or [])

    async def delete(self, *, receipt_id: UUID) -> None:
        """Remove a receipt row. Its images cascade via the FK."""

        await self._client.table(_TABLE).delete().eq("id", str(receipt_id)).execute()


class ReceiptImageRepository:
    """Writes/reads for the receipt_images table (a receipt's pages)."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def add_image(
        self, *, receipt_id: UUID, user_id: UUID, image_url: str, page_number: int
    ) -> dict[str, Any]:
        """Append a page to a receipt and return the created row."""

        # page_number is an int, so the dict isn't uniformly str-valued; the client's JSON
        # type doesn't infer through a heterogeneous literal.
        payload = cast(
            "Any",
            {
                "receipt_id": str(receipt_id),
                "user_id": str(user_id),
                "image_url": image_url,
                "page_number": page_number,
            },
        )
        resp = await self._client.table(_IMAGES_TABLE).insert(payload).execute()
        rows = cast("list[dict[str, Any]]", resp.data or [])
        if not rows:
            raise RuntimeError("Insert of receipt image returned no row.")
        return rows[0]

    async def list_for_receipt(self, *, receipt_id: UUID) -> list[dict[str, Any]]:
        """A receipt's pages, in page order."""

        resp = (
            await self._client.table(_IMAGES_TABLE)
            .select("*")
            .eq("receipt_id", str(receipt_id))
            .order("page_number")
            .execute()
        )
        return cast("list[dict[str, Any]]", resp.data or [])

    async def next_page_number(self, *, receipt_id: UUID) -> int:
        """The page number a newly-added image should take.

        Derived from the current maximum rather than a row count, so numbering stays
        monotonic even after a page is deleted from the middle. The
        ``(receipt_id, page_number)`` unique constraint is the real guard against two
        concurrent uploads racing for the same number — this only picks the candidate.
        """

        resp = (
            await self._client.table(_IMAGES_TABLE)
            .select("page_number")
            .eq("receipt_id", str(receipt_id))
            .order("page_number", desc=True)
            .limit(1)
            .execute()
        )
        rows = cast("list[dict[str, Any]]", resp.data or [])
        return (int(rows[0]["page_number"]) + 1) if rows else 1

    async def delete_for_receipt(self, *, receipt_id: UUID) -> None:
        """Remove every page of a receipt."""

        await self._client.table(_IMAGES_TABLE).delete().eq("receipt_id", str(receipt_id)).execute()
