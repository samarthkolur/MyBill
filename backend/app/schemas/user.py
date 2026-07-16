"""User profile schemas."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class UserProfile(BaseModel):
    """A row of ``public.users`` — the application-level user profile (MyBill.md §4)."""

    id: UUID
    email: str
    full_name: str | None = None
    currency: str
    timezone: str
    created_at: datetime
