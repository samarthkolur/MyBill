"""Tests for JWT verification and the /v1/auth/me endpoint.

Uses a locally-generated ES256 keypair and a stubbed ``PyJWKClient`` so the tests are
hermetic (no network, no real Supabase). This exercises the exact verification path the
app uses — signature, issuer, audience, expiry, and required claims — plus the endpoint's
401/503 behaviour.
"""

from __future__ import annotations

import datetime as dt
from collections.abc import Iterator
from uuid import uuid4

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app.api.deps import get_user_service
from app.core.config import Environment, Settings
from app.core.security import AuthenticatedUser, AuthError, JwtVerifier
from app.main import create_app
from app.schemas.user import UserProfile

SUPABASE_URL = "https://test.supabase.co"
ISSUER = f"{SUPABASE_URL}/auth/v1"
AUDIENCE = "authenticated"


@pytest.fixture(scope="module")
def ec_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


def _make_token(
    ec_key: ec.EllipticCurvePrivateKey,
    *,
    sub: str | None = None,
    iss: str = ISSUER,
    aud: str = AUDIENCE,
    expires_in: int = 3600,
    email: str = "user@example.com",
    role: str = "authenticated",
) -> str:
    now = dt.datetime.now(tz=dt.UTC)
    payload: dict[str, object] = {
        "iss": iss,
        "aud": aud,
        "iat": now,
        "exp": now + dt.timedelta(seconds=expires_in),
        "email": email,
        "role": role,
    }
    if sub is not None:
        payload["sub"] = sub
    return jwt.encode(payload, ec_key, algorithm="ES256")


def _stub_jwks(verifier: JwtVerifier, ec_key: ec.EllipticCurvePrivateKey) -> None:
    """Point a verifier's JWKS lookup at our local public key (no network)."""

    class _Signing:
        key = ec_key.public_key()

    verifier._jwks_client.get_signing_key_from_jwt = lambda _token: _Signing()  # type: ignore[method-assign]


# ---- JwtVerifier unit tests ----


@pytest.fixture
def verifier(ec_key: ec.EllipticCurvePrivateKey) -> JwtVerifier:
    v = JwtVerifier(jwks_url="https://test/jwks", issuer=ISSUER, audience=AUDIENCE)
    _stub_jwks(v, ec_key)
    return v


def test_verify_valid_token(verifier: JwtVerifier, ec_key: ec.EllipticCurvePrivateKey) -> None:
    uid = str(uuid4())
    user = verifier.verify(_make_token(ec_key, sub=uid))
    assert str(user.id) == uid
    assert user.email == "user@example.com"
    assert user.role == "authenticated"
    assert user.claims["iss"] == ISSUER


def test_reject_expired_token(verifier: JwtVerifier, ec_key: ec.EllipticCurvePrivateKey) -> None:
    with pytest.raises(AuthError):
        verifier.verify(_make_token(ec_key, sub=str(uuid4()), expires_in=-10))


def test_reject_wrong_issuer(verifier: JwtVerifier, ec_key: ec.EllipticCurvePrivateKey) -> None:
    with pytest.raises(AuthError):
        verifier.verify(_make_token(ec_key, sub=str(uuid4()), iss="https://evil/auth/v1"))


def test_reject_wrong_audience(verifier: JwtVerifier, ec_key: ec.EllipticCurvePrivateKey) -> None:
    with pytest.raises(AuthError):
        verifier.verify(_make_token(ec_key, sub=str(uuid4()), aud="anon"))


def test_reject_token_signed_by_other_key(verifier: JwtVerifier) -> None:
    other = ec.generate_private_key(ec.SECP256R1())
    with pytest.raises(AuthError):
        verifier.verify(_make_token(other, sub=str(uuid4())))


def test_reject_missing_sub(verifier: JwtVerifier, ec_key: ec.EllipticCurvePrivateKey) -> None:
    with pytest.raises(AuthError):
        verifier.verify(_make_token(ec_key, sub=None))


def test_reject_non_uuid_sub(verifier: JwtVerifier, ec_key: ec.EllipticCurvePrivateKey) -> None:
    with pytest.raises(AuthError):
        verifier.verify(_make_token(ec_key, sub="not-a-uuid"))


# ---- Endpoint-level: /v1/auth/me ----


class _FakeUserService:
    """Stub UserService: echoes the authenticated user into a profile, no DB."""

    async def ensure_profile(self, user: AuthenticatedUser) -> UserProfile:
        return UserProfile(
            id=user.id,
            email=user.email or "unknown@example.com",
            full_name="Test User",
            currency="INR",
            timezone="Asia/Kolkata",
            created_at=dt.datetime.now(tz=dt.UTC),
        )


@pytest.fixture
def auth_client(ec_key: ec.EllipticCurvePrivateKey) -> Iterator[TestClient]:
    """A client with auth configured (JWKS stubbed) and the user service faked (no DB)."""

    settings = Settings(
        environment=Environment.TEST,
        supabase_url=SUPABASE_URL,
        _env_file=None,  # type: ignore[call-arg]
    )
    app = create_app(settings)
    app.dependency_overrides[get_user_service] = _FakeUserService
    with TestClient(app) as client:
        _stub_jwks(app.state.jwt_verifier, ec_key)  # verifier built during lifespan
        yield client


def test_me_returns_profile_for_valid_token(
    auth_client: TestClient, ec_key: ec.EllipticCurvePrivateKey
) -> None:
    uid = str(uuid4())
    token = _make_token(ec_key, sub=uid, email="me@example.com")
    resp = auth_client.get("/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is True
    assert body["data"]["id"] == uid
    assert body["data"]["email"] == "me@example.com"
    assert body["data"]["currency"] == "INR"
    assert body["data"]["timezone"] == "Asia/Kolkata"


def test_me_rejects_missing_token(auth_client: TestClient) -> None:
    resp = auth_client.get("/v1/auth/me")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"


def test_me_rejects_expired_token(
    auth_client: TestClient, ec_key: ec.EllipticCurvePrivateKey
) -> None:
    token = _make_token(ec_key, sub=str(uuid4()), expires_in=-10)
    resp = auth_client.get("/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401


def test_me_returns_503_when_auth_unconfigured(client: TestClient) -> None:
    # The default test app (from conftest) has no Supabase settings, so no verifier is
    # wired up; a bearer token should surface 503 (auth not configured), not a crash.
    resp = client.get("/v1/auth/me", headers={"Authorization": "Bearer whatever"})
    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "service_unavailable"
