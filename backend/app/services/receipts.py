"""Receipt upload business logic.

Handles the pending-receipt creation flow (MyBill.md §2): validate the image, store it in
the private ``receipts`` bucket under ``{user_id}/{receipt_id}/``, then record it. A
receipt holds 1..N pages (decision 24) — the first is created with the receipt, and
further pages are appended to an existing one for receipts too long to photograph in a
single shot. Stored paths are storage object keys (not public URLs); short-lived signed
URLs are generated on read (Phase 3). OCR (Phase 2) fills the rest.
"""

from __future__ import annotations

from uuid import UUID, uuid4

from supabase import AsyncClient

from app.core.exceptions import (
    NotFoundError,
    PayloadTooLargeError,
    UnsupportedMediaTypeError,
)
from app.core.logging import get_logger
from app.core.security import AuthenticatedUser
from app.integrations.tasks import TaskQueue
from app.repositories.receipts import ReceiptImageRepository, ReceiptRepository
from app.schemas.receipt import Receipt, ReceiptImage

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

# Cap on pages per receipt. Even a very long receipt is a handful of photos; a limit keeps
# one bill from becoming an unbounded upload target.
MAX_PAGES_PER_RECEIPT = 20


class ReceiptService:
    """Orchestrates receipt upload over Supabase Storage + the receipt repositories."""

    def __init__(
        self,
        client: AsyncClient,
        repository: ReceiptRepository,
        images: ReceiptImageRepository,
        queue: TaskQueue | None = None,
    ):
        self._client = client
        self._repository = repository
        self._images = images
        # Optional so the service stays usable without a broker (unit tests, or a deployment
        # that runs OCR out of band). When set, a new upload kicks off background processing.
        self._queue = queue

    async def upload_receipt(
        self, *, user: AuthenticatedUser, data: bytes, content_type: str | None
    ) -> Receipt:
        """Create a new receipt from its first page.

        Raises:
            UnsupportedMediaTypeError: content type isn't an accepted image (415).
            PayloadTooLargeError: image is empty or exceeds ``MAX_UPLOAD_BYTES`` (413).
        """

        extension = self._validate(content_type, data)
        receipt_id = uuid4()

        row = await self._repository.create_pending(receipt_id=receipt_id, user_id=user.id)
        try:
            image = await self._store_page(
                user=user,
                receipt_id=receipt_id,
                data=data,
                content_type=content_type,
                extension=extension,
                page_number=1,
            )
        except Exception:
            # The receipt row exists but has no page — an unusable record. Remove it so a
            # failed upload doesn't leave an empty bill in the user's list.
            logger.warning("receipt_page_failed_cleanup", extra={"receipt_id": str(receipt_id)})
            await self._repository.delete(receipt_id=receipt_id)
            raise

        logger.info(
            "receipt_uploaded",
            extra={"receipt_id": str(receipt_id), "user_id": str(user.id)},
        )
        # Hand the finished upload to the OCR pipeline. Enqueued only after the row and its
        # first page are safely stored, so the worker always finds a page to read. Only the
        # first page triggers processing; appended pages ride the same eventual run.
        if self._queue is not None:
            self._queue.enqueue_receipt_processing(receipt_id=receipt_id, user_id=user.id)

        return Receipt(**row, images=[image])

    async def add_image(
        self,
        *,
        user: AuthenticatedUser,
        receipt_id: UUID,
        data: bytes,
        content_type: str | None,
    ) -> Receipt:
        """Append a page to an existing receipt.

        Raises:
            NotFoundError: no such receipt for this user (404).
            UnsupportedMediaTypeError: content type isn't an accepted image (415).
            PayloadTooLargeError: image is empty, too large, or the page cap is hit (413).
        """

        extension = self._validate(content_type, data)

        row = await self._repository.get_owned(receipt_id=receipt_id, user_id=user.id)
        if row is None:
            # Also the answer when the receipt belongs to someone else — never confirm
            # that an id exists to a user who doesn't own it.
            raise NotFoundError("Receipt not found.")

        existing = await self._images.list_for_receipt(receipt_id=receipt_id)
        if len(existing) >= MAX_PAGES_PER_RECEIPT:
            raise PayloadTooLargeError(f"A receipt can have at most {MAX_PAGES_PER_RECEIPT} pages.")

        page_number = await self._images.next_page_number(receipt_id=receipt_id)
        image = await self._store_page(
            user=user,
            receipt_id=receipt_id,
            data=data,
            content_type=content_type,
            extension=extension,
            page_number=page_number,
        )

        logger.info(
            "receipt_page_added",
            extra={"receipt_id": str(receipt_id), "page_number": page_number},
        )
        images = [ReceiptImage.model_validate(i) for i in existing] + [image]
        return Receipt(**row, images=images)

    async def list_receipts(
        self, *, user: AuthenticatedUser, limit: int = 20, offset: int = 0
    ) -> list[Receipt]:
        """A user's receipts, newest first, each with its pages."""

        rows = await self._repository.list_for_user(user_id=user.id, limit=limit, offset=offset)
        receipts: list[Receipt] = []
        for row in rows:
            images = await self._images.list_for_receipt(receipt_id=UUID(row["id"]))
            receipts.append(Receipt(**row, images=[ReceiptImage.model_validate(i) for i in images]))
        return receipts

    async def _store_page(
        self,
        *,
        user: AuthenticatedUser,
        receipt_id: UUID,
        data: bytes,
        content_type: str | None,
        extension: str,
        page_number: int,
    ) -> ReceiptImage:
        """Upload one page to Storage and record it, cleaning up the object on failure."""

        # Object key inside the private bucket. First segment is the owner id so it matches
        # the storage RLS policy from migration 20260716090300.
        object_key = f"{user.id}/{receipt_id}/page_{page_number}.{extension}"

        await self._client.storage.from_(_BUCKET).upload(
            path=object_key,
            file=data,
            file_options={"content-type": content_type or "application/octet-stream"},
        )

        try:
            image_row = await self._images.add_image(
                receipt_id=receipt_id,
                user_id=user.id,
                image_url=object_key,
                page_number=page_number,
            )
        except Exception:
            # Don't leave an orphaned object if the DB insert fails (e.g. two uploads raced
            # for the same page number and the unique constraint rejected this one).
            logger.warning("receipt_image_insert_failed_cleanup", extra={"key": object_key})
            await self._client.storage.from_(_BUCKET).remove([object_key])
            raise

        return ReceiptImage.model_validate(image_row)

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
