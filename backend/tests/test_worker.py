"""Smoke tests for the Celery worker app.

Importing the worker must not touch Redis (the API imports it to enqueue), so these only
assert the app is configured and the task is registered — no broker connection.
"""

from __future__ import annotations

from app.worker import celery_app, process_receipt


def test_task_is_registered_under_its_public_name() -> None:
    # The API enqueues by this name; if it drifts, uploads would enqueue into the void.
    assert "process_receipt" in celery_app.tasks
    assert process_receipt.name == "process_receipt"


def test_broker_and_backend_point_at_configured_redis() -> None:
    # Both default to the same Redis (settings.redis_url).
    assert celery_app.conf.broker_url == celery_app.conf.result_backend
    assert "redis://" in celery_app.conf.broker_url


def test_worker_processes_one_receipt_at_a_time() -> None:
    # OCR is CPU-bound, so a worker shouldn't prefetch a backlog behind a busy process.
    assert celery_app.conf.worker_prefetch_multiplier == 1
