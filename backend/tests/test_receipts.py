"""Tests for the receipt upload service and endpoint."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.config import Environment, Settings
from app.core.exceptions import (
    NotFoundError,
    PayloadTooLargeError,
    UnsupportedMediaTypeError,
)
from app.core.security import AuthenticatedUser
from app.main import create_app
from app.schemas.receipt import ReceiptStatus
from app.services.receipts import (
    MAX_PAGES_PER_RECEIPT,
    MAX_UPLOAD_BYTES,
    ReceiptService,
)


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
    """Stands in for ReceiptRepository."""

    def __init__(self, *, fail: bool = False, rows: dict[str, Any] | None = None) -> None:
        self.fail = fail
        self.created: list[dict[str, Any]] = []
        self.deleted: list[str] = []
        self.rows: dict[str, Any] = rows or {}

    async def create_pending(self, *, receipt_id: Any, user_id: Any) -> dict[str, Any]:
        if self.fail:
            raise RuntimeError("db down")
        row = {
            "id": str(receipt_id),
            "user_id": str(user_id),
            "status": "pending",
            "created_at": "2026-07-16T00:00:00+00:00",
        }
        self.created.append(row)
        self.rows[str(receipt_id)] = row
        return row

    async def get_owned(self, *, receipt_id: Any, user_id: Any) -> dict[str, Any] | None:
        row = self.rows.get(str(receipt_id))
        if row is None or row["user_id"] != str(user_id):
            return None
        return row

    async def list_for_user(
        self, *, user_id: Any, limit: int = 20, offset: int = 0
    ) -> list[dict[str, Any]]:
        return [r for r in self.rows.values() if r["user_id"] == str(user_id)]

    async def delete(self, *, receipt_id: Any) -> None:
        self.deleted.append(str(receipt_id))
        self.rows.pop(str(receipt_id), None)


class _FakeImages:
    """Stands in for ReceiptImageRepository."""

    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.images: list[dict[str, Any]] = []

    async def add_image(
        self, *, receipt_id: Any, user_id: Any, image_url: str, page_number: int
    ) -> dict[str, Any]:
        if self.fail:
            raise RuntimeError("db down")
        row = {
            "id": str(uuid4()),
            "receipt_id": str(receipt_id),
            "user_id": str(user_id),
            "image_url": image_url,
            "page_number": page_number,
            "created_at": "2026-07-16T00:00:00+00:00",
        }
        self.images.append(row)
        return row

    async def list_for_receipt(self, *, receipt_id: Any) -> list[dict[str, Any]]:
        return [i for i in self.images if i["receipt_id"] == str(receipt_id)]

    async def next_page_number(self, *, receipt_id: Any) -> int:
        pages = [i["page_number"] for i in self.images if i["receipt_id"] == str(receipt_id)]
        return (max(pages) + 1) if pages else 1

    async def delete_for_receipt(self, *, receipt_id: Any) -> None:
        self.images = [i for i in self.images if i["receipt_id"] != str(receipt_id)]


def _user() -> AuthenticatedUser:
    return AuthenticatedUser(id=uuid4(), email="u@example.com", role="authenticated", claims={})


def _service(
    bucket: _FakeBucket, repo: _FakeRepo, images: _FakeImages | None = None
) -> ReceiptService:
    return ReceiptService(_FakeClient(bucket), repo, images or _FakeImages())  # type: ignore[arg-type]


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
    bucket, repo, images, user = _FakeBucket(), _FakeRepo(), _FakeImages(), _user()
    receipt = await _service(bucket, repo, images).upload_receipt(
        user=user, data=b"\xff\xd8\xff-jpeg-bytes", content_type="image/jpeg"
    )

    assert receipt.status is ReceiptStatus.PENDING
    # Object stored under the owner's folder, with the extension for the content type.
    assert len(bucket.uploaded) == 1
    assert bucket.uploaded[0].startswith(f"{user.id}/")
    assert bucket.uploaded[0].endswith("/page_1.jpg")
    # A new receipt starts at exactly one page, pointing at the uploaded object.
    assert receipt.page_count == 1
    assert receipt.images[0].image_url == bucket.uploaded[0]
    assert receipt.images[0].page_number == 1
    assert len(repo.created) == 1
    assert bucket.removed == []  # no cleanup on success


async def test_upload_cleans_up_object_when_image_insert_fails() -> None:
    bucket, repo = _FakeBucket(), _FakeRepo()
    with pytest.raises(RuntimeError, match="db down"):
        await _service(bucket, repo, _FakeImages(fail=True)).upload_receipt(
            user=_user(), data=b"jpegbytes", content_type="image/jpeg"
        )
    # The orphaned storage object is removed...
    assert bucket.uploaded == bucket.removed
    assert len(bucket.removed) == 1
    # ...and the pageless receipt row is deleted rather than left as an empty bill.
    assert len(repo.deleted) == 1


# ---- Multi-page: add to an existing bill ----


async def test_add_image_appends_next_page() -> None:
    bucket, repo, images, user = _FakeBucket(), _FakeRepo(), _FakeImages(), _user()
    service = _service(bucket, repo, images)

    created = await service.upload_receipt(user=user, data=b"page-one", content_type="image/jpeg")
    receipt = await service.add_image(
        user=user, receipt_id=created.id, data=b"page-two", content_type="image/jpeg"
    )

    # Same bill, now two pages — the server assigns the number.
    assert receipt.id == created.id
    assert receipt.page_count == 2
    assert [i.page_number for i in receipt.images] == [1, 2]
    assert bucket.uploaded[1].endswith("/page_2.jpg")


async def test_add_image_to_unknown_receipt_is_404() -> None:
    with pytest.raises(NotFoundError):
        await _service(_FakeBucket(), _FakeRepo(), _FakeImages()).add_image(
            user=_user(), receipt_id=uuid4(), data=b"x", content_type="image/jpeg"
        )


async def test_add_image_to_another_users_receipt_is_404() -> None:
    bucket, repo, images = _FakeBucket(), _FakeRepo(), _FakeImages()
    service = _service(bucket, repo, images)
    owner = await service.upload_receipt(user=_user(), data=b"mine", content_type="image/jpeg")

    # Reads as absent, not forbidden — the endpoint never confirms the id exists.
    with pytest.raises(NotFoundError):
        await service.add_image(
            user=_user(), receipt_id=owner.id, data=b"x", content_type="image/jpeg"
        )


async def test_add_image_enforces_the_page_cap() -> None:
    bucket, repo, images, user = _FakeBucket(), _FakeRepo(), _FakeImages(), _user()
    service = _service(bucket, repo, images)
    created = await service.upload_receipt(user=user, data=b"p1", content_type="image/jpeg")

    for _ in range(MAX_PAGES_PER_RECEIPT - 1):
        await service.add_image(
            user=user, receipt_id=created.id, data=b"p", content_type="image/jpeg"
        )

    with pytest.raises(PayloadTooLargeError, match="at most"):
        await service.add_image(
            user=user, receipt_id=created.id, data=b"p", content_type="image/jpeg"
        )


async def test_list_receipts_includes_pages() -> None:
    bucket, repo, images, user = _FakeBucket(), _FakeRepo(), _FakeImages(), _user()
    service = _service(bucket, repo, images)
    created = await service.upload_receipt(user=user, data=b"p1", content_type="image/jpeg")
    await service.add_image(user=user, receipt_id=created.id, data=b"p2", content_type="image/jpeg")

    listed = await service.list_receipts(user=user)
    assert len(listed) == 1
    assert listed[0].page_count == 2


# ---- Endpoint auth ----


def test_upload_requires_auth_when_configured(auth_client: TestClient) -> None:
    # A file is sent so only the missing token fails the request (→ 401, not 422).
    resp = auth_client.post(
        "/v1/receipts/upload",
        files={"file": ("r.jpg", b"\xff\xd8\xffjpeg", "image/jpeg")},
    )
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"
