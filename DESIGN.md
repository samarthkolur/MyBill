# DESIGN.md — MyBill Build Log & Task Tracker

> Single source of truth for build status. Updated after every completed task.
> Architecture/product spec lives in [`MyBill.md`](./MyBill.md) — this file tracks _execution_, not design intent (except where we deviate from or extend that spec, which is recorded in [Design Decisions](#design-decisions)).

---

## Current Phase

**Phase 1 — Foundation**, Milestone 1.1 — Project Scaffolding

> **1.1.3 (Flutter) is deferred** — the Flutter SDK isn't installed on this machine.
> Backend/infra tasks were reordered ahead of it (see Design Decision 9). Flutter resumes
> once the SDK is installed.

---

## Overall Roadmap

| Phase                  | Goal                                              | Status         |
| ---------------------- | ------------------------------------------------- | -------------- |
| 1. Foundation          | Auth + camera capture + upload working end-to-end | 🔵 In progress |
| 2. OCR Pipeline        | Images become structured data                     | ⚪ Not started |
| 3. Digital Bill Viewer | Browse, view, correct bills                       | ⚪ Not started |
| 4. Analytics & Charts  | Spending intelligence dashboard                   | ⚪ Not started |
| 5. Bill Comparison     | Item-level diff between two bills                 | ⚪ Not started |
| 6. AI Insights         | NL Q&A over purchase history                      | ⚪ Not started |

Full detail for the phase currently in progress (Phase 1) is broken into milestones and
tiny, independently-testable tasks below. Phases 2–6 are listed at milestone granularity
for now (mirroring `MyBill.md` §13) and will be broken into tasks as we approach them.

---

## Phase 1 — Foundation

### Milestone 1.1 — Project Scaffolding

| #     | Task                                                                                                                              | Status                          |
| ----- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| 1.1.1 | Create root folder structure (`backend/`, `mobile/`, `infra/`, `docs/`, `.github/workflows/`) + `.gitignore` + root `README.md`   | ✅ Done                         |
| 1.1.2 | Configure FastAPI project (dependency management, app factory, settings, structured logging, `/health` endpoint)                  | ✅ Done                         |
| 1.1.3 | Configure Flutter project (`flutter create`, Riverpod + GoRouter + Freezed deps, lint config, folder skeleton per `MyBill.md` §7) | ⏸️ Deferred (needs Flutter SDK) |
| 1.1.4 | Configure Supabase project (Auth enabled, `users` table + RLS, `receipts` Storage bucket + policy)                                | ✅ Done                         |
| 1.1.5 | Docker Compose for local dev (`api`, `worker`, `redis`)                                                                           | ⬜ Pending                      |
| 1.1.6 | CI pipeline (GitHub Actions: `ruff` + `mypy` on backend, `flutter analyze` + `flutter test` on mobile, on every PR)               | ⬜ Pending                      |

### Milestone 1.2 — Authentication

| #     | Task                                                                                                | Status                                                                |
| ----- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 1.2.1 | Supabase client setup (backend `supabase-py` client + Flutter `supabase_flutter` client)            | ⬜ Pending                                                            |
| 1.2.2 | JWT verification middleware (FastAPI dependency, validates Supabase-issued JWT on protected routes) | ⬜ Pending                                                            |
| 1.2.3 | User profile sync (on first authenticated request, ensure a row exists in `users`)                  | 🟡 DB half done (auth trigger in 1.1.4); app-layer safety-net pending |
| 1.2.4 | Flutter: auth state (Riverpod notifier) + secure token persistence (`flutter_secure_storage`)       | ⬜ Pending                                                            |
| 1.2.5 | Flutter: Login screen                                                                               | ⬜ Pending                                                            |
| 1.2.6 | Flutter: Sign Up screen                                                                             | ⬜ Pending                                                            |
| 1.2.7 | Flutter: Forgot Password screen                                                                     | ⬜ Pending                                                            |
| 1.2.8 | GoRouter route guards (redirect unauthenticated users to login)                                     | ⬜ Pending                                                            |
| 1.2.9 | Logout flow (clear token, revoke Supabase session, redirect)                                        | ⬜ Pending                                                            |

### Milestone 1.3 — Camera & Upload

| #     | Task                                                                                              | Status     |
| ----- | ------------------------------------------------------------------------------------------------- | ---------- |
| 1.3.1 | Flutter: Scan screen — camera capture + gallery picker                                            | ⬜ Pending |
| 1.3.2 | Flutter: pre-upload crop/rotate (`image_cropper`) + client-side compression (≤2MB, quality 85%)   | ⬜ Pending |
| 1.3.3 | Backend: `POST /v1/receipts/upload` — stores image in Supabase Storage (`receipts/{user_id}/...`) | ⬜ Pending |
| 1.3.4 | Backend: create `receipts` row with `status = pending` on upload                                  | ⬜ Pending |
| 1.3.5 | Flutter: wire upload flow end-to-end + progress UI, persisted upload queue for offline retry      | ⬜ Pending |

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
    - handlers rendering every failure through the envelope; 500s logged, never leaked.
  - `app/api/deps.py` — `SettingsDep` reads settings off `app.state` (not the global) so
    test overrides propagate.
  - `app/api/v1/router.py` + `routes/health.py` — `GET /v1/health`.
  - `tests/` — 4 passing smoke tests (envelope shape, request-id generation/reuse, 404
    envelope). Verified live: `uvicorn` boots, `/v1/health` returns 200 with correct
    envelope + `x-request-id` header, `/docs` + `/openapi.json` served in non-prod.
  - `.env.example`, `backend/README.md`.
    Quality gates green: `ruff check`, `ruff format --check`, `mypy app` (strict), `pytest`.

- **1.1.4 — Configure Supabase (schema + RLS + Storage)** (2026-07-16)
  _Reordered ahead of 1.1.3 because the Flutter SDK isn't installed (decision 9)._
  Delivered four idempotent SQL migrations in `infra/supabase/migrations/`:
  - `…090000_init_extensions_and_helpers` — pgcrypto + reusable `set_updated_at()` trigger fn.
  - `…090100_create_users` — `public.users` (1:1 with `auth.users`), `updated_at` trigger,
    grants to `authenticated`, RLS `enable + force`, and SELECT/INSERT/UPDATE policies scoped
    to `auth.uid() = id`. No DELETE (profiles go only via auth cascade).
  - `…090200_auth_user_sync` — `handle_new_user()` (SECURITY DEFINER, pinned search_path) +
    `after insert on auth.users` trigger that auto-provisions a profile row. This is the DB
    half of task 1.2.3, done at the layer where the invariant can't be bypassed.
  - `…090300_receipts_storage` — private `receipts` bucket + owner-scoped SELECT/INSERT/
    UPDATE/DELETE policies on `storage.objects` (`receipts/{user_id}/…` convention).
    Migrations reference Supabase-managed `auth`/`storage`/roles and never create them.
    **Verified live** against a throwaway `postgres:16` Docker container via
    `infra/supabase/tests/run_tests.sh`: a harness stubs Supabase's auth/storage surface,
    all migrations apply, and 5 assertions pass — signup trigger provisions a profile; RLS
    isolates SELECT/INSERT/UPDATE per user; Storage scopes files to the owner's folder. Also
    confirmed migrations are idempotent (clean re-apply). Setup guide in
    `infra/supabase/README.md` (cloud project creation, credentials, `db push` vs SQL editor).
    **Applied live** (2026-07-16) to the real project once creds were added: ref
    `fkowzsdvwqbhrjykjrcb`, ap-south-1. Connection required the Supavisor **session pooler**
    on the newer `aws-1-ap-south-1.pooler.supabase.com` fleet (direct host is IPv6-only, this
    machine is IPv4-only). All objects verified present; end-to-end auth-sync test
    (admin-create user → profile auto-created with correct defaults → delete → cascade) passed;
    DB left clean. `.env` now separates `SUPABASE_URL` (API) from `SUPABASE_DB_URL` (pooler).

---

## Pending Tasks

Flutter (1.1.3) is deferred pending SDK install. Next unblocked task: **1.1.5 — Docker
Compose for local dev** (or 1.1.6 CI). See full Phase 1 task list above.

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
   **Why:** git doesn't track empty directories; `.gitkeep` is a placeholder _file_, not
   placeholder _code_ — it will be deleted the moment real content (e.g. `backend/app/main.py`)
   lands in that directory in task 1.1.2.

5. **Backend dependency management via `uv`, dependencies declared incrementally.**
   `uv` is already installed on this machine (0.5.9); it's fast and lockfile-based.
   Only the deps actually used _now_ are declared — SQLAlchemy, Alembic, supabase-py,
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

8. **Phase 1 task order changed: 1.1.3 (Flutter) deferred, backend/infra tasks pulled
   ahead** because the Flutter SDK isn't installed on this machine.
   **Why:** installing a ~1.5GB SDK into the user's home dir without knowing how they
   prefer to manage Flutter (fvm / snap / Android Studio bundle) risks conflicting with
   their eventual setup — their call, not a default to assume. Meanwhile Supabase/Docker/CI
   are fully unblocked and valuable, so momentum continues. Flutter resumes on SDK install.

9. **User-profile provisioning done as a database trigger (`handle_new_user` on
   `auth.users`), not (only) in the FastAPI layer.**
   **Why:** it makes "every auth identity has a profile row" a database-enforced
   invariant that holds regardless of which client created the account and can't be
   skipped by an app bug. Task 1.2.3's app-layer check becomes a thin idempotent
   safety-net rather than the primary mechanism. Trade-off: logic lives in SQL (less
   visible to app devs) — mitigated by documenting it in `infra/supabase/README.md`.

10. **Migrations reference Supabase-managed objects; a separate local test harness stubs
    them.** Production migrations assume `auth.*`, `storage.*`, and the `authenticated`
    role already exist (Supabase provides them). `infra/supabase/tests/harness.sql`
    recreates just enough of that surface — including a faithful `auth.uid()` reading the
    JWT `sub` claim — so the _exact same_ migration files can be applied and their RLS
    exercised against a throwaway Postgres, as real verification rather than eyeballing SQL.
    **Why:** keeps production migrations pristine (no test-only DDL) while still proving,
    concretely, that RLS isolates users.

11. **Supabase CLI adoption deferred; migrations applied via SQL editor / psql for now.**
    The CLI expects migrations under `supabase/migrations/`; ours live under
    `infra/supabase/migrations/` (decision 3). **Why:** no Supabase project exists yet and
    the CLI isn't installed; committing to its directory convention now would fight our
    monorepo layout. When adopted, we move/symlink the folder. Recorded as tech debt.

12. **OCR provider, LLM provider, and other Phase 2/6 technology choices are deliberately
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
├── mobile/                    # Flutter app (empty — task 1.1.3, deferred)
├── infra/
│   └── supabase/
│       ├── migrations/        # 4 idempotent SQL migrations (users, auth-sync, storage)
│       ├── tests/             # harness.sql + test_rls.sql + run_tests.sh (local verify)
│       └── README.md          # Supabase setup + migration guide
├── docs/                      # Supplementary docs (empty)
├── .gitignore
├── README.md
├── MyBill.md                   # Architecture & product spec (source doc)
└── DESIGN.md                   # This file
```

---

## APIs Implemented

| Method | Path         | Status  | Notes                                                                                                  |
| ------ | ------------ | ------- | ------------------------------------------------------------------------------------------------------ |
| `GET`  | `/v1/health` | ✅ Live | Liveness check; always 200 when process is up. Readiness (`/health/ready`, checks DB/Redis) to follow. |

First data endpoint (`POST /v1/receipts/upload`) targeted at task 1.3.3.

All responses use the standard envelope from `MyBill.md` §5 via `app.core.responses`.

---

## Database Schema Status

Migrations live in `infra/supabase/migrations/`, verified against Postgres 16.

| Table / object                                       | Status     | Migration                  |
| ---------------------------------------------------- | ---------- | -------------------------- |
| `public.users` (+ RLS, grants, `updated_at` trigger) | ✅ Created | `…090100_create_users`     |
| `handle_new_user()` auth-sync trigger                | ✅ Created | `…090200_auth_user_sync`   |
| `receipts` Storage bucket (private) + policies       | ✅ Created | `…090300_receipts_storage` |
| `stores`                                             | ⬜ Pending | Phase 2                    |
| `receipts`, `receipt_items`                          | ⬜ Pending | Phase 2                    |
| `categories`                                         | ⬜ Pending | Phase 2                    |
| `price_history`                                      | ⬜ Pending | Phase 2                    |
| `analytics_cache`                                    | ⬜ Pending | Phase 4                    |

Full target schema is `MyBill.md` §4. **Applied and verified on the live Supabase project**
(ref `fkowzsdvwqbhrjykjrcb`, region ap-south-1) on 2026-07-16 — all objects confirmed
present, and an end-to-end admin-create→profile-row→delete test proved the auth-sync
trigger fires and cascades correctly. DB left clean (0 rows).

---

## Technical Debt

- **Starlette `TestClient` deprecation warning** — `starlette.testclient` warns that using
  `httpx` with it is deprecated in favour of `httpx2`. Cosmetic; tests pass. Revisit if it
  becomes an error on a future Starlette bump.
- **`/health` is liveness only** — no readiness probe yet. Add `/health/ready` (checks DB +
  Redis) once those dependencies exist (Phase 2).
- **No migration ledger on the live DB** — migrations were applied by looping `psql` over
  the files, so there's no `schema_migrations`-style record of what's been applied. Fine
  while files are idempotent, but adopt Alembic (backend) or `supabase db push` before the
  schema grows, so applied state is tracked rather than re-run-everything.
- **Supabase CLI not adopted** — migrations live in `infra/supabase/migrations/`, but the
  CLI expects `supabase/migrations/`. Move/symlink when we adopt `supabase db push`
  (decision 12).
- **`flutter` SDK not installed** — task 1.1.3 and all mobile work blocked until it is.

---

## Next Recommended Task

**1.1.5 — Docker Compose for local dev**: an `infra/docker-compose.yml` wiring the `api`
(FastAPI), `worker` (Celery — placeholder until Phase 2), and `redis` services from
`MyBill.md` §12, plus a `backend/Dockerfile` (multi-stage, `uv`-based). Verifiable by
`docker compose up` bringing the API up and `GET /v1/health` responding through the
container. Unblocked and independently testable.

_(Alternative unblocked task: 1.1.6 — CI pipeline. Flutter 1.1.3 remains deferred until
the SDK is installed.)_
