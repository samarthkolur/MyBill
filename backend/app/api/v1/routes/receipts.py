"""Receipt routes."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, File, Query, UploadFile, status

from app.api.deps import CurrentUserDep, ReceiptServiceDep
from app.core.responses import ApiResponse, success
from app.schemas.receipt import Receipt

router = APIRouter(prefix="/receipts", tags=["receipts"])


@router.post(
    "/upload",
    response_model=ApiResponse[Receipt],
    status_code=status.HTTP_201_CREATED,
    summary="Upload a receipt image as a new bill",
)
async def upload_receipt(
    user: CurrentUserDep,
    receipts: ReceiptServiceDep,
    file: UploadFile = File(..., description="Receipt image (JPEG, PNG, or WebP)"),
) -> ApiResponse[Receipt]:
    """Create a new receipt from its first page.

    The image is saved to the private ``receipts`` bucket under the caller's folder and a
    receipt row is created with ``status = pending``; the OCR pipeline (Phase 2) fills in
    store, date, totals, and line items. To add further pages to this receipt, use
    ``POST /v1/receipts/{receipt_id}/images``.

    Errors (standard envelope): 401 (no/invalid token), 415 (unsupported image type),
    413 (empty or too large).
    """

    data = await file.read()
    receipt = await receipts.upload_receipt(user=user, data=data, content_type=file.content_type)
    return success(receipt)


@router.post(
    "/{receipt_id}/images",
    response_model=ApiResponse[Receipt],
    status_code=status.HTTP_201_CREATED,
    summary="Add another page to an existing bill",
)
async def add_receipt_image(
    receipt_id: UUID,
    user: CurrentUserDep,
    receipts: ReceiptServiceDep,
    file: UploadFile = File(..., description="Receipt image (JPEG, PNG, or WebP)"),
) -> ApiResponse[Receipt]:
    """Append a page to a receipt the caller owns.

    For receipts too long to photograph in one shot. The page number is assigned by the
    server. Returns the receipt with all of its pages.

    Errors (standard envelope): 401, 404 (no such receipt for this user), 415, 413
    (empty, too large, or the per-receipt page cap reached).
    """

    data = await file.read()
    receipt = await receipts.add_image(
        user=user, receipt_id=receipt_id, data=data, content_type=file.content_type
    )
    return success(receipt)


@router.get(
    "/{receipt_id}",
    response_model=ApiResponse[Receipt],
    summary="Get a receipt (processing status + pages)",
)
async def get_receipt(
    receipt_id: UUID,
    user: CurrentUserDep,
    receipts: ReceiptServiceDep,
) -> ApiResponse[Receipt]:
    """Fetch one receipt the caller owns, with its current ``status`` and pages.

    Backs the client's post-upload polling: after a receipt is uploaded it sits at
    ``pending``/``processing`` until the OCR pipeline settles it on ``done`` or ``failed``.

    Errors (standard envelope): 401 (no/invalid token), 404 (no such receipt for this user).
    """

    receipt = await receipts.get_receipt(user=user, receipt_id=receipt_id)
    return success(receipt)


@router.get(
    "",
    response_model=ApiResponse[list[Receipt]],
    summary="List the caller's receipts",
)
async def list_receipts(
    user: CurrentUserDep,
    receipts: ReceiptServiceDep,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> ApiResponse[list[Receipt]]:
    """Return the caller's receipts, newest first, each with its pages.

    Backs the client's "add to an existing bill" picker. Ordered by creation time rather
    than the parsed date, which is null until OCR runs.

    Errors (standard envelope): 401.
    """

    items = await receipts.list_receipts(user=user, limit=limit, offset=offset)
    return success(items, page=(offset // limit) + 1, total=len(items))
