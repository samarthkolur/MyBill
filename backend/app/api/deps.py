"""Reusable FastAPI dependencies.

Dependencies read shared resources off ``request.app.state`` (populated by the app
factory) rather than from module-level globals. This keeps handlers decoupled from the
cached ``get_settings()`` singleton so a test app built with overridden settings behaves
correctly, and gives future resources (DB session, Supabase client) a consistent
injection point.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request

from app.core.config import Settings


def get_settings(request: Request) -> Settings:
    """Return the settings the running app was built with."""

    settings: Settings = request.app.state.settings
    return settings


SettingsDep = Annotated[Settings, Depends(get_settings)]
