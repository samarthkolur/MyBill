"""Smoke tests for the health endpoint and the response envelope."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.core.middleware import REQUEST_ID_HEADER


def test_health_returns_ok_envelope(client: TestClient) -> None:
    response = client.get("/v1/health")

    assert response.status_code == 200
    body = response.json()

    # Envelope shape (MyBill.md §5).
    assert body["success"] is True
    assert body["error"] is None
    assert body["data"]["status"] == "ok"
    assert body["data"]["environment"] == "test"
    assert body["data"]["version"]


def test_health_stamps_request_id(client: TestClient) -> None:
    response = client.get("/v1/health")

    # A request id is generated, echoed in the header, and mirrored into meta.
    header_id = response.headers.get(REQUEST_ID_HEADER)
    assert header_id
    assert response.json()["meta"]["request_id"] == header_id


def test_health_reuses_inbound_request_id(client: TestClient) -> None:
    incoming = "test-correlation-id-123"
    response = client.get("/v1/health", headers={REQUEST_ID_HEADER: incoming})

    assert response.headers.get(REQUEST_ID_HEADER) == incoming
    assert response.json()["meta"]["request_id"] == incoming


def test_unknown_route_returns_error_envelope(client: TestClient) -> None:
    response = client.get("/v1/does-not-exist")

    assert response.status_code == 404
    body = response.json()
    assert body["success"] is False
    assert body["data"] is None
    assert body["error"]["code"] == "http_404"
