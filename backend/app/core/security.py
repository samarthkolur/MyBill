"""Authentication — Supabase JWT verification.

Incoming requests carry a Supabase-issued access token (``Authorization: Bearer <jwt>``).
This project signs those tokens with **asymmetric ES256**; the public keys are published
at the project's JWKS endpoint. ``JwtVerifier`` fetches and caches those keys (via PyJWT's
``PyJWKClient``) and validates a token's signature, expiry, issuer, and audience, returning
the authenticated principal.

RLS at the database is the ultimate authority on data access (``MyBill.md`` §11); this
layer establishes *who* the caller is so handlers can scope their queries by ``user_id``.
"""

from __future__ import annotations

from uuid import UUID

import jwt
from jwt import PyJWKClient
from pydantic import BaseModel

from app.core.config import Settings
from app.core.logging import get_logger

logger = get_logger("app.security")

# The project's tokens are ES256. Listed explicitly so a token can't request a weaker/
# unexpected algorithm (algorithm-confusion defence).
_ALGORITHMS = ["ES256"]


class AuthError(Exception):
    """Raised when a token is missing required data or fails verification."""


class AuthenticatedUser(BaseModel):
    """The verified principal extracted from a valid access token."""

    id: UUID
    email: str | None = None
    role: str | None = None
    # Full decoded claim set, for handlers/middleware that need more than id/email/role.
    claims: dict[str, object]


class JwtVerifier:
    """Verifies Supabase ES256 access tokens against the project's JWKS.

    Construct once (keys are fetched lazily and cached by ``PyJWKClient``) and reuse for
    the process lifetime — see the app lifespan in ``app.main``.
    """

    def __init__(self, *, jwks_url: str, issuer: str, audience: str):
        self._jwks_client = PyJWKClient(jwks_url, cache_keys=True)
        self._issuer = issuer
        self._audience = audience

    def verify(self, token: str) -> AuthenticatedUser:
        """Validate ``token`` and return the authenticated user.

        Raises:
            AuthError: for any missing key, bad signature, wrong issuer/audience,
                expiry, or malformed token. Callers map this to HTTP 401.
        """

        try:
            signing_key = self._jwks_client.get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=_ALGORITHMS,
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "sub"]},
            )
        except (jwt.InvalidTokenError, jwt.PyJWKClientError) as exc:
            # Never log the token itself.
            logger.info("jwt_verification_failed", extra={"reason": type(exc).__name__})
            raise AuthError("Invalid or expired authentication token.") from exc

        sub = claims.get("sub")
        if not sub:
            raise AuthError("Token is missing the subject (sub) claim.")

        try:
            user_id = UUID(str(sub))
        except ValueError as exc:
            raise AuthError("Token subject is not a valid user id.") from exc

        return AuthenticatedUser(
            id=user_id,
            email=claims.get("email"),
            role=claims.get("role"),
            claims=claims,
        )


def build_jwt_verifier(settings: Settings) -> JwtVerifier:
    """Construct a ``JwtVerifier`` from settings (call once at startup)."""

    return JwtVerifier(
        jwks_url=settings.effective_jwks_url,
        issuer=settings.supabase_issuer,
        audience=settings.supabase_jwt_audience,
    )
