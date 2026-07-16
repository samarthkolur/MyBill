"""Tests for the receipt upload service and endpoint."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.config import Environment, Settings
from app.core.exceptions import PayloadTooLargeError, UnsupportedMediaTypeError
from app.core.security import AuthenticatedUser
from app.main import create_app
from app.schemas.receipt import ReceiptStatus
from app.services.receipts import MAX_UPLOAD_BYTES, ReceiptService


@pytest.fixture
def auth_client() -> Iterator[TestClient]:
    """Client for an auth-configured app (a verifier exists, so no token → 401 not 503)."""

    settings = Settings(
        environment=Environment.TEST,
        supabase_url="https://test.supabase.co",
        _env_file=None,  # type: ignore[call-arg]
    )
    with TestClient(create_app(settings)) as client:
        yield client


# ---- Fakes for the Supabase storage chain + repository ----


class _FakeBucket:
    def __init__(self) -> None:
        self.uploaded: list[str] = []
        self.removed: list[str] = []

    async def upload(self, *, path: str, file: bytes, file_options: dict[str, str]) -> None:
        self.uploaded.append(path)

    async def remove(self, paths: list[str]) -> None:
        self.removed.extend(paths)


class _FakeStorage:
    def __init__(self, bucket: _FakeBucket) -> None:
        self._bucket = bucket

    def from_(self, _name: str) -> _FakeBucket:
        return self._bucket


class _FakeClient:
    def __init__(self, bucket: _FakeBucket) -> None:
        self.storage = _FakeStorage(bucket)


class _FakeRepo:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.created: list[dict[str, Any]] = []

    async def create_pending(
        self, *, receipt_id: Any, user_id: Any, image_url: str
    ) -> dict[str, Any]:
        if self.fail:
            raise RuntimeError("db down")
        row = {
            "id": str(receipt_id),
            "user_id": str(user_id),
            "image_url": image_url,
            "status": "pending",
            "created_at": "2026-07-16T00:00:00+00:00",
        }
        self.created.append(row)
        return row


def _user() -> AuthenticatedUser:
    return AuthenticatedUser(id=uuid4(), email="u@example.com", role="authenticated", claims={})


def _service(bucket: _FakeBucket, repo: _FakeRepo) -> ReceiptService:
    return ReceiptService(_FakeClient(bucket), repo)  # type: ignore[arg-type]


# ---- Validation ----


async def test_rejects_unsupported_type() -> None:
    with pytest.raises(UnsupportedMediaTypeError):
        await _service(_FakeBucket(), _FakeRepo()).upload_receipt(
            user=_user(), data=b"x", content_type="application/pdf"
        )


async def test_rejects_empty_file() -> None:
    with pytest.raises(PayloadTooLargeError):
        await _service(_FakeBucket(), _FakeRepo()).upload_receipt(
            user=_user(), data=b"", content_type="image/png"
        )


async def test_rejects_oversized_file() -> None:
    big = b"\x00" * (MAX_UPLOAD_BYTES + 1)
    with pytest.raises(PayloadTooLargeError):
        await _service(_FakeBucket(), _FakeRepo()).upload_receipt(
            user=_user(), data=big, content_type="image/jpeg"
        )


# ---- Happy path + cleanup ----


async def test_upload_stores_and_creates_pending_row() -> None:
    bucket, repo, user = _FakeBucket(), _FakeRepo(), _user()
    receipt = await _service(bucket, repo).upload_receipt(
        user=user, data=b"\xff\xd8\xff-jpeg-bytes", content_type="image/jpeg"
    )

    assert receipt.status is ReceiptStatus.PENDING
    # Object stored under the owner's folder, with the extension for the content type.
    assert len(bucket.uploaded) == 1
    assert bucket.uploaded[0].startswith(f"{user.id}/")
    assert bucket.uploaded[0].endswith("/original.jpg")
    # The stored image_url matches the uploaded object key, and a row was created.
    assert receipt.image_url == bucket.uploaded[0]
    assert len(repo.created) == 1
    assert bucket.removed == []  # no cleanup on success


async def test_upload_cleans_up_object_when_insert_fails() -> None:
    bucket, repo = _FakeBucket(), _FakeRepo(fail=True)
    with pytest.raises(RuntimeError, match="db down"):
        await _service(bucket, repo).upload_receipt(
            user=_user(), data=b"jpegbytes", content_type="image/jpeg"
        )
    # The orphaned storage object is removed.
    assert bucket.uploaded == bucket.removed
    assert len(bucket.removed) == 1


# ---- Endpoint auth ----


def test_upload_requires_auth_when_configured(auth_client: TestClient) -> None:
    # A file is sent so only the missing token fails the request (→ 401, not 422).
    resp = auth_client.post(
        "/v1/receipts/upload",
        files={"file": ("r.jpg", b"\xff\xd8\xffjpeg", "image/jpeg")},
    )
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"
