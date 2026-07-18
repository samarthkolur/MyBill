"""Normalisation + persistence — the OCR pipeline's Stage 4 (MyBill.md §6).

Takes the ``CanonicalReceipt`` a parser produced and writes it into the database: resolves
the store (alias-aware) and the category names to ids, replaces the receipt's line items and
price observations, and fills the parsed columns on the receipt itself, flipping it to
``done``. It is the step that turns a ``pending`` receipt of images into structured,
queryable data.

Runs as a system operation after OCR, so it takes a ``user_id`` directly rather than an
authenticated request, and writes through the service-role repositories — every row still
carries ``user_id`` so the owner RLS policies hold. Idempotent: re-running for the same
receipt converges on one clean set of rows (the item/price writes replace by receipt id).
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.core.exceptions import NotFoundError
from app.core.logging import get_logger
from app.repositories.parsed import PriceHistoryRepository, ReceiptItemRepository
from app.repositories.receipts import ReceiptRepository
from app.repositories.reference import CategoryRepository, StoreRepository
from app.schemas.parser import CanonicalReceipt
from app.schemas.receipt import ReceiptStatus

logger = get_logger("app.normalisation")


class ReceiptNormaliser:
    """Persists a parsed receipt across the receipts / items / price-history tables."""

    def __init__(
        self,
        *,
        receipts: ReceiptRepository,
        stores: StoreRepository,
        categories: CategoryRepository,
        items: ReceiptItemRepository,
        prices: PriceHistoryRepository,
    ):
        self._receipts = receipts
        self._stores = stores
        self._categories = categories
        self._items = items
        self._prices = prices

    async def persist(
        self, *, receipt_id: UUID, user_id: UUID, canonical: CanonicalReceipt
    ) -> dict[str, Any]:
        """Write ``canonical`` for a receipt and return the updated receipt row.

        Raises:
            NotFoundError: the receipt doesn't exist for this user.
        """

        receipt = await self._receipts.get_owned(receipt_id=receipt_id, user_id=user_id)
        if receipt is None:
            raise NotFoundError("Receipt not found.")

        # A price observation needs a point on the time axis; when OCR found no date, the
        # upload day is the best estimate (see the price_history.date column comment).
        upload_date = _date_of(receipt.get("created_at"))
        observation_date = canonical.date or upload_date

        store_id = (
            await self._stores.resolve(
                user_id=user_id,
                name=canonical.store.name,
                chain=canonical.store.chain,
                address=canonical.store.address,
            )
            if canonical.store.name
            else None
        )

        category_ids = await self._categories.name_to_id()

        item_rows: list[dict[str, Any]] = []
        price_rows: list[dict[str, Any]] = []
        for item in canonical.items:
            category_id = category_ids.get(item.category.lower()) if item.category else None
            item_rows.append(
                {
                    "receipt_id": str(receipt_id),
                    "user_id": str(user_id),
                    "name": item.name,
                    "name_normalised": item.name_normalised,
                    "brand": item.brand,
                    "category_id": category_id,
                    "quantity": _num(item.quantity),
                    "unit": item.unit,
                    "unit_price": _num(item.unit_price),
                    "total_price": _num(item.total_price),
                    "ocr_confidence": item.ocr_confidence,
                }
            )
            price_rows.append(
                {
                    "user_id": str(user_id),
                    "name_normalised": item.name_normalised,
                    "store_id": store_id,
                    "unit_price": _num(item.unit_price),
                    "quantity": _num(item.quantity),
                    "unit": item.unit,
                    "receipt_id": str(receipt_id),
                    "date": observation_date.isoformat(),
                }
            )

        # Items and their price observations first, then flip the receipt to done — a reader
        # that sees status=done can trust the items are already there.
        await self._items.replace_for_receipt(receipt_id=receipt_id, rows=item_rows)
        await self._prices.replace_for_receipt(receipt_id=receipt_id, rows=price_rows)

        fields: dict[str, Any] = {
            "store_id": store_id,
            "date": canonical.date.isoformat() if canonical.date else None,
            "time": canonical.time.isoformat() if canonical.time else None,
            "total": _num(canonical.totals.total),
            "tax": _num(canonical.totals.tax),
            "discount": _num(canonical.totals.discount),
            "payment_method": canonical.payment_method,
            "ocr_confidence": canonical.ocr_confidence,
            "canonical_json": canonical.model_dump(mode="json"),
            "status": ReceiptStatus.DONE.value,
        }
        updated = await self._receipts.update_fields(
            receipt_id=receipt_id, user_id=user_id, fields=fields
        )
        if updated is None:  # pragma: no cover - the ownership check above already passed
            raise NotFoundError("Receipt not found.")

        logger.info(
            "receipt_normalised",
            extra={
                "receipt_id": str(receipt_id),
                "items": len(item_rows),
                "store_resolved": store_id is not None,
                "needs_review": canonical.needs_review,
            },
        )
        return updated

    async def mark_failed(self, *, receipt_id: UUID, user_id: UUID) -> None:
        """Flip a receipt to ``failed`` (e.g. after a parse exception, MyBill.md §6)."""

        await self._receipts.update_fields(
            receipt_id=receipt_id,
            user_id=user_id,
            fields={"status": ReceiptStatus.FAILED.value},
        )


def _num(value: Decimal | None) -> str | None:
    """Serialise a Decimal for a numeric column as a string — avoids the float round-trip
    that would drift a reconciled total off the printed one."""

    return None if value is None else str(value)


def _date_of(created_at: Any) -> date:
    """The date part of a receipt's ``created_at`` (an ISO timestamp), for the price-history
    fallback. Defaults to today if the timestamp is missing or unparseable."""

    if isinstance(created_at, str):
        try:
            return datetime.fromisoformat(created_at.replace("Z", "+00:00")).date()
        except ValueError:
            pass
    return datetime.now().date()
