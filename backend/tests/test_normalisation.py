"""Tests for the Stage 4 normalisation/persistence layer.

These wire the *real* repositories to an in-memory fake Supabase client, so a test exercises
the whole path — store-alias resolution, category lookup, the item/price writes, and the
receipt update — against a simulated database rather than mocking each repository.
"""

from __future__ import annotations

from datetime import date, time
from decimal import Decimal
from typing import Any
from uuid import uuid4

import pytest

from app.core.exceptions import NotFoundError
from app.repositories.parsed import PriceHistoryRepository, ReceiptItemRepository
from app.repositories.receipts import ReceiptRepository
from app.repositories.reference import CategoryRepository, StoreRepository
from app.schemas.parser import (
    CanonicalItem,
    CanonicalReceipt,
    CanonicalStore,
    CanonicalTotals,
)
from app.services.normalisation import ReceiptNormaliser

_PARSER_VERSION = "heuristic-0.1.0"


# ---------------------------------------------------------------------------
# In-memory fake Supabase client (supports the query-builder chain the repos use)
# ---------------------------------------------------------------------------
class _Resp:
    def __init__(self, data: list[dict[str, Any]]) -> None:
        self.data = data


class _Query:
    def __init__(self, store: dict[str, list[dict[str, Any]]], table: str) -> None:
        self._store = store
        self._table = table
        self._op = "select"
        self._filters: list[tuple[str, Any]] = []
        self._payload: Any = None

    def select(self, _cols: str = "*") -> _Query:
        self._op = "select"
        return self

    def insert(self, payload: Any) -> _Query:
        self._op, self._payload = "insert", payload
        return self

    def update(self, fields: Any) -> _Query:
        self._op, self._payload = "update", fields
        return self

    def delete(self) -> _Query:
        self._op = "delete"
        return self

    def eq(self, col: str, val: Any) -> _Query:
        self._filters.append((col, val))
        return self

    def order(self, *_a: Any, **_k: Any) -> _Query:
        return self

    def limit(self, _n: int) -> _Query:
        return self

    def range(self, *_a: Any, **_k: Any) -> _Query:
        return self

    async def execute(self) -> _Resp:
        rows = self._store.setdefault(self._table, [])

        def match(row: dict[str, Any]) -> bool:
            return all(str(row.get(c)) == str(v) for c, v in self._filters)

        if self._op == "select":
            return _Resp([r for r in rows if match(r)])
        if self._op == "insert":
            payload = self._payload if isinstance(self._payload, list) else [self._payload]
            inserted: list[dict[str, Any]] = []
            for item in payload:
                row = dict(item)
                row.setdefault("id", str(uuid4()))
                rows.append(row)
                inserted.append(row)
            return _Resp(inserted)
        if self._op == "update":
            updated = [r for r in rows if match(r)]
            for row in updated:
                row.update(self._payload)
            return _Resp(updated)
        if self._op == "delete":
            self._store[self._table] = [r for r in rows if not match(r)]
            return _Resp([])
        return _Resp([])


class _FakeClient:
    def __init__(self, store: dict[str, list[dict[str, Any]]]) -> None:
        self._store = store

    def table(self, name: str) -> _Query:
        return _Query(self._store, name)


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------
def _seed(
    *,
    receipt: dict[str, Any] | None,
    categories: tuple[str, ...] = ("Dairy", "Bakery"),
    stores: tuple[dict[str, Any], ...] = (),
) -> dict[str, list[dict[str, Any]]]:
    return {
        "receipts": [receipt] if receipt else [],
        "categories": [{"id": f"cat-{n.lower()}", "name": n} for n in categories],
        "stores": [dict(s) for s in stores],
        "receipt_items": [],
        "price_history": [],
    }


def _normaliser(store: dict[str, list[dict[str, Any]]]) -> ReceiptNormaliser:
    client = _FakeClient(store)
    return ReceiptNormaliser(
        receipts=ReceiptRepository(client),  # type: ignore[arg-type]
        stores=StoreRepository(client),  # type: ignore[arg-type]
        categories=CategoryRepository(client),  # type: ignore[arg-type]
        items=ReceiptItemRepository(client),  # type: ignore[arg-type]
        prices=PriceHistoryRepository(client),  # type: ignore[arg-type]
    )


def _receipt_row(
    receipt_id: Any, user_id: Any, *, created_at: str = "2026-07-16T10:00:00+00:00"
) -> dict[str, Any]:
    return {
        "id": str(receipt_id),
        "user_id": str(user_id),
        "status": "pending",
        "created_at": created_at,
    }


def _item(name: str, category: str | None, unit_price: str, total: str, **kw: Any) -> CanonicalItem:
    return CanonicalItem(
        name=name,
        name_normalised=name.lower(),
        category=category,
        unit_price=Decimal(unit_price),
        total_price=Decimal(total),
        **kw,
    )


def _canonical(**kw: Any) -> CanonicalReceipt:
    defaults: dict[str, Any] = {"parser_version": _PARSER_VERSION}
    return CanonicalReceipt(**{**defaults, **kw})


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------
async def test_persist_writes_items_prices_and_marks_done() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))
    canonical = _canonical(
        store=CanonicalStore(name="DMart", chain="DMart"),
        date=date(2025, 6, 15),
        time=time(18, 42),
        payment_method="UPI",
        totals=CanonicalTotals(total=Decimal("164.00"), tax=Decimal("10.00")),
        items=[
            _item("Amul Milk", "Dairy", "62.00", "124.00"),
            _item("Brown Bread", "Bakery", "40.00", "40.00"),
        ],
        ocr_confidence=0.96,
    )

    updated = await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    # Receipt flipped to done with the parsed columns filled.
    assert updated["status"] == "done"
    assert updated["total"] == "164.00"
    assert updated["date"] == "2025-06-15"
    assert updated["store_id"] is not None
    assert updated["canonical_json"]["parser_version"] == _PARSER_VERSION

    # Line items written with categories resolved to ids.
    items = store["receipt_items"]
    assert {i["name"] for i in items} == {"Amul Milk", "Brown Bread"}
    by_name = {i["name"]: i for i in items}
    assert by_name["Amul Milk"]["category_id"] == "cat-dairy"
    assert by_name["Brown Bread"]["category_id"] == "cat-bakery"

    # One price observation per item, dated and attributed to the resolved store.
    prices = store["price_history"]
    assert len(prices) == 2
    assert all(p["date"] == "2025-06-15" for p in prices)
    assert all(p["store_id"] == updated["store_id"] for p in prices)


async def test_decimals_are_written_as_strings() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))
    canonical = _canonical(items=[_item("Amul Milk", "Dairy", "62.00", "124.00")])

    await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    item = store["receipt_items"][0]
    # Strings, not floats — the numeric column keeps 2dp without a float round-trip.
    assert item["unit_price"] == "62.00"
    assert item["total_price"] == "124.00"
    assert isinstance(item["unit_price"], str)


# ---------------------------------------------------------------------------
# Store alias resolution
# ---------------------------------------------------------------------------
async def test_store_alias_reuses_existing_store() -> None:
    rid, uid = uuid4(), uuid4()
    existing = {
        "id": "store-1",
        "user_id": str(uid),
        "name": "DMart",
        "name_aliases": ["dmart"],
    }
    store = _seed(receipt=_receipt_row(rid, uid), stores=(existing,))
    # A different spelling of the same store.
    canonical = _canonical(
        store=CanonicalStore(name="D-MART"),
        items=[_item("Amul Milk", "Dairy", "62.00", "62.00")],
    )

    updated = await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    assert updated["store_id"] == "store-1"
    assert len(store["stores"]) == 1  # no duplicate store created


async def test_new_store_is_created_when_unmatched() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))
    canonical = _canonical(
        store=CanonicalStore(name="Reliance Fresh"),
        items=[_item("Amul Milk", "Dairy", "62.00", "62.00")],
    )

    await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    assert len(store["stores"]) == 1
    created = store["stores"][0]
    assert created["name"] == "Reliance Fresh"  # readable name preserved
    assert created["name_aliases"] == ["reliancefresh"]  # spaceless match key recorded


async def test_no_store_name_leaves_store_null() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))
    canonical = _canonical(items=[_item("Amul Milk", "Dairy", "62.00", "62.00")])

    updated = await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    assert updated["store_id"] is None
    assert store["stores"] == []
    assert store["price_history"][0]["store_id"] is None


# ---------------------------------------------------------------------------
# Category resolution
# ---------------------------------------------------------------------------
async def test_unknown_category_resolves_to_null() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))
    canonical = _canonical(items=[_item("Mystery Gadget", None, "10.00", "10.00")])

    await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    assert store["receipt_items"][0]["category_id"] is None


# ---------------------------------------------------------------------------
# Date fallback
# ---------------------------------------------------------------------------
async def test_price_date_falls_back_to_upload_day_when_undated() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid, created_at="2026-07-16T10:00:00+00:00"))
    canonical = _canonical(date=None, items=[_item("Amul Milk", "Dairy", "62.00", "62.00")])

    await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    # No parsed date → the upload day is the price observation's date.
    assert store["price_history"][0]["date"] == "2026-07-16"


# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------
async def test_reprocessing_replaces_rather_than_duplicates() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))
    canonical = _canonical(
        items=[
            _item("Amul Milk", "Dairy", "62.00", "124.00"),
            _item("Brown Bread", "Bakery", "40.00", "40.00"),
        ]
    )
    normaliser = _normaliser(store)

    await normaliser.persist(receipt_id=rid, user_id=uid, canonical=canonical)
    await normaliser.persist(receipt_id=rid, user_id=uid, canonical=canonical)

    # Re-running converges on one clean set — not four rows.
    assert len(store["receipt_items"]) == 2
    assert len(store["price_history"]) == 2


async def test_empty_items_still_marks_done() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))
    canonical = _canonical(items=[])

    updated = await _normaliser(store).persist(receipt_id=rid, user_id=uid, canonical=canonical)

    assert updated["status"] == "done"
    assert store["receipt_items"] == []
    assert store["price_history"] == []


# ---------------------------------------------------------------------------
# Failure paths
# ---------------------------------------------------------------------------
async def test_unknown_receipt_raises_not_found() -> None:
    store = _seed(receipt=None)
    canonical = _canonical(items=[_item("Amul Milk", "Dairy", "62.00", "62.00")])

    with pytest.raises(NotFoundError):
        await _normaliser(store).persist(receipt_id=uuid4(), user_id=uuid4(), canonical=canonical)


async def test_another_users_receipt_raises_not_found() -> None:
    rid, owner, other = uuid4(), uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, owner))
    canonical = _canonical(items=[_item("Amul Milk", "Dairy", "62.00", "62.00")])

    # Scoped by user_id, so another user's receipt reads as absent.
    with pytest.raises(NotFoundError):
        await _normaliser(store).persist(receipt_id=rid, user_id=other, canonical=canonical)


async def test_mark_failed_sets_status() -> None:
    rid, uid = uuid4(), uuid4()
    store = _seed(receipt=_receipt_row(rid, uid))

    await _normaliser(store).mark_failed(receipt_id=rid, user_id=uid)

    assert store["receipts"][0]["status"] == "failed"
