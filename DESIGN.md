# DESIGN.md — MyBill Build Log & Task Tracker

> Single source of truth for build status. Updated after every completed task.
> Architecture/product spec lives in [`MyBill.md`](./MyBill.md) — this file tracks *execution*, not design intent (except where we deviate from or extend that spec, which is recorded in [Design Decisions](#design-decisions)).

---

## Current Phase

**Phase 1 — Foundation**, Milestone 1.1 — Project Scaffolding (task 1.1.3 next)

---

## Overall Roadmap

| Phase | Goal | Status |
|---|---|---|
| 1. Foundation | Auth + camera capture + upload working end-to-end | 🔵 In progress |
| 2. OCR Pipeline | Images become structured data | ⚪ Not started |
| 3. Digital Bill Viewer | Browse, view, correct bills | ⚪ Not started |
| 4. Analytics & Charts | Spending intelligence dashboard | ⚪ Not started |
| 5. Bill Comparison | Item-level diff between two bills | ⚪ Not started |
| 6. AI Insights | NL Q&A over purchase history | ⚪ Not started |

Full detail for the phase currently in progress (Phase 1) is broken into milestones and
tiny, independently-testable tasks below. Phases 2–6 are listed at milestone granularity
for now (mirroring `MyBill.md` §13) and will be broken into tasks as we approach them.

---

## Phase 1 — Foundation

### Milestone 1.1 — Project Scaffolding

| # | Task | Status |
|---|---|---|
| 1.1.1 | Create root folder structure (`backend/`, `mobile/`, `infra/`, `docs/`, `.github/workflows/`) + `.gitignore` + root `README.md` | ✅ Done |
| 1.1.2 | Configure FastAPI project (dependency management, app factory, settings, structured logging, `/health` endpoint) | ✅ Done |
| 1.1.3 | Configure Flutter project (`flutter create`, Riverpod + GoRouter + Freezed deps, lint config, folder skeleton per `MyBill.md` §7) | ⬜ Pending |
| 1.1.4 | Configure Supabase project (Auth enabled, `users` table + RLS, `receipts` Storage bucket + policy) | ⬜ Pending |
| 1.1.5 | Docker Compose for local dev (`api`, `worker`, `redis`) | ⬜ Pending |
| 1.1.6 | CI pipeline (GitHub Actions: `ruff` + `mypy` on backend, `flutter analyze` + `flutter test` on mobile, on every PR) | ⬜ Pending |

### Milestone 1.2 — Authentication

| # | Task | Status |
|---|---|---|
| 1.2.1 | Supabase client setup (backend `supabase-py` client + Flutter `supabase_flutter` client) | ⬜ Pending |
| 1.2.2 | JWT verification middleware (FastAPI dependency, validates Supabase-issued JWT on protected routes) | ⬜ Pending |
| 1.2.3 | User profile sync (on first authenticated request, ensure a row exists in `users`) | ⬜ Pending |
| 1.2.4 | Flutter: auth state (Riverpod notifier) + secure token persistence (`flutter_secure_storage`) | ⬜ Pending |
| 1.2.5 | Flutter: Login screen | ⬜ Pending |
| 1.2.6 | Flutter: Sign Up screen | ⬜ Pending |
| 1.2.7 | Flutter: Forgot Password screen | ⬜ Pending |
| 1.2.8 | GoRouter route guards (redirect unauthenticated users to login) | ⬜ Pending |
| 1.2.9 | Logout flow (clear token, revoke Supabase session, redirect) | ⬜ Pending |

### Milestone 1.3 — Camera & Upload

| # | Task | Status |
|---|---|---|
| 1.3.1 | Flutter: Scan screen — camera capture + gallery picker | ⬜ Pending |
| 1.3.2 | Flutter: pre-upload crop/rotate (`image_cropper`) + client-side compression (≤2MB, quality 85%) | ⬜ Pending |
| 1.3.3 | Backend: `POST /v1/receipts/upload` — stores image in Supabase Storage (`receipts/{user_id}/...`) | ⬜ Pending |
| 1.3.4 | Backend: create `receipts` row with `status = pending` on upload | ⬜ Pending |
| 1.3.5 | Flutter: wire upload flow end-to-end + progress UI, persisted upload queue for offline retry | ⬜ Pending |

**Phase 1 exit criteria** (from `MyBill.md`): user can register, log in, photograph a receipt, and see it uploaded.

---

## Phase 2 — OCR Pipeline (milestone-level, not yet broken into tasks)

- Choose + integrate OCR provider (Google Document AI recommended)
- Image pre-processing service (resize, deskew, binarise)
- Celery + Redis async job queue
- `OCRProvider` interface + concrete implementation
- `ReceiptParser` interface + first implementation
- Category keyword mapping (seed 10 categories) + store alias table (seed 20 chains)
- Normalisation layer → write to `receipts`, `receipt_items`, `price_history`
- Processing status polling endpoint + Flutter animated processing screen

## Phase 3 — Digital Bill Viewer (milestone-level)

- Bill list + bill detail screens
- Inline item correction UI + `PATCH` endpoint
- Search endpoint + search screen
- Receipt soft-delete, low-confidence review highlighting

## Phase 4 — Analytics & Charts (milestone-level)

- Analytics service layer (9 metrics per `MyBill.md` §8) + cache + invalidation
- Dashboard, monthly/category/store charts, top items, price history chart
- Date range filters, JSON/PDF export

## Phase 5 — Bill Comparison (milestone-level)

- Comparison engine (normalise → alias → cosine similarity)
- `POST /v1/compare` + picker screen + diff view + delta indicators

## Phase 6 — AI Insights (milestone-level)

- `LLMProvider` interface, context builder, `POST /v1/ai/ask`, streaming chat UI
- Restock reminders, budget prediction, cheapest-store recommendation
- Feature-flagged, opt-in

---

## Completed Tasks

- **1.1.1 — Create root folder structure** (2026-07-16)
  Created `backend/`, `mobile/`, `infra/supabase/migrations/`, `docs/`, `.github/workflows/`
  (empty dirs hold `.gitkeep` until real content lands), root `.gitignore` covering
  Python/Flutter/Docker/editor artifacts, and root `README.md` pointing to this file and
  to `MyBill.md`.

- **1.1.2 — Configure FastAPI project** (2026-07-16)
  Backend now boots and serves `GET /v1/health`. Delivered:
  - `pyproject.toml` — `uv`-managed, Python 3.12+, minimal runtime deps (fastapi, uvicorn,
    pydantic, pydantic-settings) + dev group (pytest, httpx, ruff, mypy). Ruff (strict rule
    set) + mypy (`strict = true`) + pytest all configured here.
  - `app/main.py` — `create_app()` factory (re-buildable in tests) + ASGI `app`, with CORS,
    request-context middleware, exception handlers, versioned router mount, and a lifespan
    hook reserved for future DB/Redis pools.
  - `app/core/config.py` — `Settings` (pydantic-settings) + cached `get_settings()`.
  - `app/core/logging.py` — structured logging, JSON in prod / console locally, `request_id`
    `ContextVar` stamped on every line; PII-free by contract.
  - `app/core/middleware.py` — `RequestContextMiddleware`: per-request id (reused from
    inbound `X-Request-ID` or generated), access logging, id echoed to response + logs.
  - `app/core/responses.py` — standard envelope (`success()` / `error()`, `ApiResponse[T]`).
  - `app/core/exceptions.py` — `AppError` hierarchy (`NotFound`/`Unauthorized`/`Forbidden`)
    + handlers rendering every failure through the envelope; 500s logged, never leaked.
  - `app/api/deps.py` — `SettingsDep` reads settings off `app.state` (not the global) so
    test overrides propagate.
  - `app/api/v1/router.py` + `routes/health.py` — `GET /v1/health`.
  - `tests/` — 4 passing smoke tests (envelope shape, request-id generation/reuse, 404
    envelope). Verified live: `uvicorn` boots, `/v1/health` returns 200 with correct
    envelope + `x-request-id` header, `/docs` + `/openapi.json` served in non-prod.
  - `.env.example`, `backend/README.md`.
  Quality gates green: `ruff check`, `ruff format --check`, `mypy app` (strict), `pytest`.

---

## Pending Tasks

Next up: **1.1.3 — Configure Flutter project**. See full Phase 1 task list above.

---

## Design Decisions

1. **Repo layout: single monorepo, not multi-repo.**
   `backend/`, `mobile/`, `infra/` live side by side in one repo.
   **Why:** Phase 1–5 backend and mobile evolve in lockstep (new endpoint ↔ new screen in the
   same PR most of the time); a monorepo keeps those changes atomic and keeps `DESIGN.md`
   as one true tracker instead of three drifting ones. Revisit only if CI time or team size
   makes independent deploy cadences necessary (not expected before Phase 4+).

2. **Phase 1 split into 3 milestones (Scaffolding → Auth → Camera/Upload) rather than one
   flat checklist**, deviating from the flatter list in `MyBill.md` §13 Phase 1.
   **Why:** the instruction driving this build requires every task to be independently
   completable and testable in isolation; the original phase-1 checklist mixes
   infra setup, auth, and camera/upload in one flat list. Splitting them gives clean
   "can I ship just this?" boundaries and clear exit criteria per milestone.

3. **`infra/` holds Docker Compose and Supabase migrations/config**, not a top-level
   `supabase/` or `docker/` directory.
   **Why:** keeps all non-application-code operational concerns in one place; matches the
   `MyBill.md` §12 Docker Compose block, which we'll drop into `infra/docker-compose.yml`
   in task 1.1.5.

4. **`.gitkeep` used for now-empty scaffolded directories.**
   **Why:** git doesn't track empty directories; `.gitkeep` is a placeholder *file*, not
   placeholder *code* — it will be deleted the moment real content (e.g. `backend/app/main.py`)
   lands in that directory in task 1.1.2.

5. **Backend dependency management via `uv`, dependencies declared incrementally.**
   `uv` is already installed on this machine (0.5.9); it's fast and lockfile-based.
   Only the deps actually used *now* are declared — SQLAlchemy, Alembic, supabase-py,
   Celery, Redis, Pillow, python-jose, httpx (runtime) are added by the tasks that
   introduce them. **Why:** declaring unused deps bloats installs/CI and invites version
   drift on packages we haven't yet exercised. `MyBill.md` §3 remains the target dep set.

6. **`Settings` injected via a FastAPI dependency (`SettingsDep`), not read from the
   cached global inside handlers.** The global `get_settings()` still exists (and is the
   default the ASGI `app` is built with), but handlers pull settings off
   `request.app.state.settings`. **Why:** the `create_app(settings=...)` factory lets tests
   build an app with overridden settings; if handlers read the cached global instead, those
   overrides silently don't apply (caught in this task — the health test initially reported
   `development` instead of `test`). This also gives DB session / Supabase client the same
   clean injection point later.

7. **PEP 695 type parameter syntax** (`class ApiResponse[T]`, `def success[T]`) for
   generics, targeting Python 3.12. **Why:** it's the modern idiom Ruff enforces at
   `target-version = py312`, and pydantic v2.13 supports it for generic models.

8. **OCR provider, LLM provider, and other Phase 2/6 technology choices are deliberately
   deferred**, not decided now.
   **Why:** `MyBill.md` already designs these behind swappable interfaces
   (`OCRProvider`, `ReceiptParser`, `LLMProvider`); picking a concrete implementation before
   we reach that phase would be a decision made without the context (pricing at the time,
   receipt sample quality) needed to make it well.

---

## Folder Structure (current)

```
MyBill/
├── .github/
│   └── workflows/            # CI pipelines (empty — task 1.1.6)
├── backend/                   # FastAPI service
│   ├── app/
│   │   ├── main.py            # create_app() factory + ASGI app
│   │   ├── core/             # config, logging, middleware, responses, exceptions
│   │   └── api/
│   │       ├── deps.py       # SettingsDep (+ future DB/Supabase deps)
│   │       └── v1/
│   │           ├── router.py
│   │           └── routes/health.py
│   ├── tests/                # conftest + test_health
│   ├── pyproject.toml
│   ├── .env.example
│   └── README.md
├── mobile/                    # Flutter app (empty — task 1.1.3)
├── infra/
│   └── supabase/
│       └── migrations/        # SQL migrations (empty — task 1.1.4)
├── docs/                      # Supplementary docs (empty)
├── .gitignore
├── README.md
├── MyBill.md                   # Architecture & product spec (source doc)
└── DESIGN.md                   # This file
```

---

## APIs Implemented

| Method | Path | Status | Notes |
|---|---|---|---|
| `GET` | `/v1/health` | ✅ Live | Liveness check; always 200 when process is up. Readiness (`/health/ready`, checks DB/Redis) to follow. |

First data endpoint (`POST /v1/receipts/upload`) targeted at task 1.3.3.

All responses use the standard envelope from `MyBill.md` §5 via `app.core.responses`.

---

## Database Schema Status

No tables created yet. Full schema (`users`, `stores`, `receipts`, `receipt_items`,
`categories`, `price_history`, `analytics_cache`) is specified in `MyBill.md` §4.
`users` table + RLS is the first to be created, at task 1.1.4.

---

## Technical Debt

- **Starlette `TestClient` deprecation warning** — `starlette.testclient` warns that using
  `httpx` with it is deprecated in favour of `httpx2`. Cosmetic; tests pass. Revisit if it
  becomes an error on a future Starlette bump.
- **`/health` is liveness only** — no readiness probe yet. Add `/health/ready` (checks DB +
  Redis) once those dependencies exist (Phase 1 task 1.1.4 / Phase 2).

---

## Next Recommended Task

**1.1.3 — Configure Flutter project**: `flutter create` into `mobile/`, add core
dependencies (`flutter_riverpod`, `go_router`, `freezed` + `json_serializable`, `dio`),
configure `analysis_options.yaml` (lints) and build_runner, and lay down the
feature-first folder skeleton from `MyBill.md` §7 (`core/`, `features/`, `shared/`) with
a runnable app shell + a trivial widget test. (Requires the Flutter SDK — will confirm
it's installed before starting.)
