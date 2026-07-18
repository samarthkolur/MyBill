"""Reference-data lookups used while normalising a parsed receipt (MyBill.md §6, Stage 4).

The parser emits category *names* and a raw store *name*; the database keys line items on
``categories.id`` and receipts on ``stores.id``. These repositories bridge that gap:
``CategoryRepository`` turns the global category names into ids, and ``StoreRepository``
resolves a printed store name to the user's store — matching aliases so ``D-Mart``,
``DMART`` and ``D Mart`` collapse onto one store rather than spawning three.

Both use the shared service-role client and scope every write by ``user_id`` explicitly
(RLS is the database-level backstop), the same contract as the other repositories.
"""

from __future__ import annotations

import re
from typing import Any, cast
from uuid import UUID

from supabase import AsyncClient

_CATEGORIES_TABLE = "categories"
_STORES_TABLE = "stores"


def normalise_key(value: str) -> str:
    """The store-alias match key: lowercase with every non-alphanumeric removed.

    Deliberately space-insensitive so ``D-Mart``, ``dmart``, and ``D MART`` all collapse to
    ``dmart`` and resolve to one store (MyBill.md §6, "Resolve store aliases"). Stricter than
    the parser's item-name normalisation, which keeps word boundaries.
    """

    return re.sub(r"[^a-z0-9]", "", value.lower())


class CategoryRepository:
    """Reads the global ``categories`` reference table."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def name_to_id(self) -> dict[str, str]:
        """Map lowercased category name → id, for resolving the parser's category names.

        Categories are global reference data (a handful of rows), so the whole table is
        fetched and keyed in memory rather than queried per item.
        """

        resp = await self._client.table(_CATEGORIES_TABLE).select("id, name").execute()
        rows = cast("list[dict[str, Any]]", resp.data or [])
        return {str(row["name"]).lower(): str(row["id"]) for row in rows}

    async def id_to_name(self) -> dict[str, str]:
        """Map category id → name, for labelling line items on the bill-detail read."""

        resp = await self._client.table(_CATEGORIES_TABLE).select("id, name").execute()
        rows = cast("list[dict[str, Any]]", resp.data or [])
        return {str(row["id"]): str(row["name"]) for row in rows}


class StoreRepository:
    """Resolves and creates per-user ``stores`` rows."""

    def __init__(self, client: AsyncClient):
        self._client = client

    async def resolve(
        self,
        *,
        user_id: UUID,
        name: str,
        chain: str | None = None,
        address: str | None = None,
    ) -> str:
        """Return the id of the user's store for ``name``, creating it if new.

        An existing store matches when its name — or any of its recorded aliases —
        normalises to the same key as ``name``. A newly created store records that key as
        its first alias, so the next spelling variant folds onto it instead of creating a
        duplicate.
        """

        key = normalise_key(name)
        existing = await self._list_for_user(user_id)
        for store in existing:
            names = [store.get("name") or ""] + list(store.get("name_aliases") or [])
            if key in {normalise_key(n) for n in names if n}:
                return str(store["id"])

        payload = cast(
            "Any",
            {
                "user_id": str(user_id),
                "name": name,
                "chain_name": chain,
                "address": address,
                "name_aliases": [key],
            },
        )
        resp = await self._client.table(_STORES_TABLE).insert(payload).execute()
        rows = cast("list[dict[str, Any]]", resp.data or [])
        if not rows:
            raise RuntimeError("Insert of store returned no row.")
        return str(rows[0]["id"])

    async def name_for(self, store_id: str) -> str | None:
        """The display name of a store by id, for the bill-detail header."""

        resp = (
            await self._client.table(_STORES_TABLE)
            .select("name")
            .eq("id", store_id)
            .limit(1)
            .execute()
        )
        rows = cast("list[dict[str, Any]]", resp.data or [])
        return str(rows[0]["name"]) if rows else None

    async def _list_for_user(self, user_id: UUID) -> list[dict[str, Any]]:
        resp = (
            await self._client.table(_STORES_TABLE)
            .select("id, name, name_aliases")
            .eq("user_id", str(user_id))
            .execute()
        )
        return cast("list[dict[str, Any]]", resp.data or [])
