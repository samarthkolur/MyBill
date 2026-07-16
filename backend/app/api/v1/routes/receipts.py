"""Receipt routes."""

from __future__ import annotations

from fastapi import APIRouter, File, UploadFile, status

from app.api.deps import CurrentUserDep, ReceiptServiceDep
from app.core.responses import ApiResponse, success
from app.schemas.receipt import Receipt

router = APIRouter(prefix="/receipts", tags=["receipts"])


@router.post(
    "/upload",
    response_model=ApiResponse[Receipt],
    status_code=status.HTTP_201_CREATED,
    summary="Upload a receipt image",
)
async def upload_receipt(
    user: CurrentUserDep,
    receipts: ReceiptServiceDep,
    file: UploadFile = File(..., description="Receipt image (JPEG, PNG, or WebP)"),
) -> ApiResponse[Receipt]:
    """Store a receipt image and create its ``pending`` record.

    The image is saved to the private ``receipts`` bucket under the caller's folder and a
    receipt row is created with ``status = pending``; the OCR pipeline (Phase 2) fills in
    store, date, totals, and line items. Returns the new receipt id and status.

    Errors (standard envelope): 401 (no/invalid token), 415 (unsupported image type),
    413 (empty or too large).
    """

    data = await file.read()
    receipt = await receipts.upload_receipt(user=user, data=data, content_type=file.content_type)
    return success(receipt)
