# syntax=docker/dockerfile:1.9
#
# Multi-stage image for the MyBill FastAPI backend.
#
#   builder → resolves + installs the locked dependency set into a self-contained .venv
#   runtime → copies just that .venv + app onto a slim base, runs as a non-root user
#
# Dependencies are installed from uv.lock with --frozen so the image is reproducible and
# never silently drifts from the committed lockfile. Layers are ordered so that a change
# to application code does NOT invalidate the (slow) dependency-install layer.

ARG PYTHON_VERSION=3.12

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS builder

# Pinned uv, copied from the official distroless uv image.
COPY --from=ghcr.io/astral-sh/uv:0.5.9 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# 1) Install ONLY third-party deps first (no project code) — cached until the lockfile
#    or pyproject changes. --no-dev keeps test/lint tooling out of the runtime image.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# 2) Add the application and install the project itself into the venv.
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS runtime

# curl is used by the container HEALTHCHECK below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    # Non-root runtime user (never run the app as root).
    && groupadd --system app \
    && useradd --system --gid app --home /app --no-create-home app

WORKDIR /app

# Bring over the fully-built virtual environment and the application source.
COPY --from=builder --chown=app:app /app /app

# Put the venv first on PATH so `python`/`uvicorn`/`celery` resolve to it.
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://localhost:8000/v1/health || exit 1

# Production default. Compose overrides this with --reload for local dev.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
