"""Search routes (MyBill.md §5)."""

from __future__ import annotations

from fastapi import APIRouter, Query

from app.api.deps import CurrentUserDep, ReceiptServiceDep
from app.core.responses import ApiResponse, success
from app.schemas.receipt import ItemSearchResult

router = APIRouter(prefix="/search", tags=["search"])


@router.get(
    "/items",
    response_model=ApiResponse[list[ItemSearchResult]],
    summary="Search the caller's purchased items by name",
)
async def search_items(
    user: CurrentUserDep,
    receipts: ReceiptServiceDep,
    q: str = Query(..., min_length=1, description="Search text"),
    limit: int = Query(50, ge=1, le=100),
) -> ApiResponse[list[ItemSearchResult]]:
    """Find line items across the caller's bills whose name matches ``q``.

    Each result includes the store and date of the bill it came from, and its
    ``receipt_id`` so the client can open the full receipt.

    Errors (standard envelope): 401.
    """

    items = await receipts.search_items(user=user, query=q, limit=limit)
    return success(items, total=len(items))
