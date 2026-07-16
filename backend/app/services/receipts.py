"""Receipt upload business logic.

Handles the pending-receipt creation flow (MyBill.md §2): validate the image, store the
original in the private ``receipts`` bucket under ``{user_id}/{receipt_id}/``, then insert
a ``pending`` row. The stored ``image_url`` is the storage object key (not a public URL);
short-lived signed URLs are generated on read (Phase 3). OCR (Phase 2) fills the rest.
"""

from __future__ import annotations

from uuid import uuid4

from supabase import AsyncClient

from app.core.exceptions import PayloadTooLargeError, UnsupportedMediaTypeError
from app.core.logging import get_logger
from app.core.security import AuthenticatedUser
from app.repositories.receipts import ReceiptRepository
from app.schemas.receipt import Receipt

logger = get_logger("app.receipts")

_BUCKET = "receipts"

# Accepted upload content types → file extension used for the stored object.
ALLOWED_IMAGE_TYPES: dict[str, str] = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}

# Hard cap on upload size. The mobile client compresses to ≤2MB (MyBill.md §15); this
# generous server-side limit is an abuse guard, not the expected size.
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


class ReceiptService:
    """Orchestrates receipt upload over Supabase Storage + the receipts repository."""

    def __init__(self, client: AsyncClient, repository: ReceiptRepository):
        self._client = client
        self._repository = repository

    async def upload_receipt(
        self, *, user: AuthenticatedUser, data: bytes, content_type: str | None
    ) -> Receipt:
        """Validate + store an uploaded image and create its pending receipt row.

        Raises:
            UnsupportedMediaTypeError: content type isn't an accepted image (415).
            PayloadTooLargeError: image exceeds ``MAX_UPLOAD_BYTES`` (413).
        """

        extension = self._validate(content_type, data)

        receipt_id = uuid4()
        # Object key inside the private bucket. First segment is the owner id so it
        # matches the storage RLS policy from migration 20260716090300.
        object_key = f"{user.id}/{receipt_id}/original.{extension}"

        await self._client.storage.from_(_BUCKET).upload(
            path=object_key,
            file=data,
            file_options={"content-type": content_type or "application/octet-stream"},
        )

        try:
            row = await self._repository.create_pending(
                receipt_id=receipt_id, user_id=user.id, image_url=object_key
            )
        except Exception:
            # Don't leave an orphaned object if the DB insert fails.
            logger.warning("receipt_insert_failed_cleanup", extra={"receipt_id": str(receipt_id)})
            await self._client.storage.from_(_BUCKET).remove([object_key])
            raise

        logger.info(
            "receipt_uploaded",
            extra={"receipt_id": str(receipt_id), "user_id": str(user.id)},
        )
        return Receipt.model_validate(row)

    @staticmethod
    def _validate(content_type: str | None, data: bytes) -> str:
        if content_type not in ALLOWED_IMAGE_TYPES:
            allowed = ", ".join(sorted(ALLOWED_IMAGE_TYPES))
            raise UnsupportedMediaTypeError(
                f"Unsupported image type '{content_type or 'unknown'}'. Allowed: {allowed}."
            )
        if not data:
            raise PayloadTooLargeError("Uploaded file is empty.")
        if len(data) > MAX_UPLOAD_BYTES:
            mb = MAX_UPLOAD_BYTES // (1024 * 1024)
            raise PayloadTooLargeError(f"Image exceeds the {mb}MB upload limit.")
        return ALLOWED_IMAGE_TYPES[content_type]
