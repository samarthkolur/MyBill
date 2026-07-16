"""Authentication-related routes."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import CurrentUserDep, UserServiceDep
from app.core.responses import ApiResponse, success
from app.schemas.user import UserProfile

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get(
    "/me",
    response_model=ApiResponse[UserProfile],
    summary="Get the authenticated user's profile",
)
async def me(user: CurrentUserDep, users: UserServiceDep) -> ApiResponse[UserProfile]:
    """Return the caller's profile, provisioning it if missing.

    Requires a valid ``Authorization: Bearer`` token (401 otherwise, via the standard
    envelope). On the first authenticated request the profile row is guaranteed to exist
    (app-layer safety-net complementing the DB signup trigger — task 1.2.3).
    """

    profile = await users.ensure_profile(user)
    return success(profile)
