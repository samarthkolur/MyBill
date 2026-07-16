# DESIGN.md — MyBill Build Log & Task Tracker

> Single source of truth for build status. Updated after every completed task.
> Architecture/product spec lives in [`MyBill.md`](./MyBill.md) — this file tracks _execution_, not design intent (except where we deviate from or extend that spec, which is recorded in [Design Decisions](#design-decisions)).

---

## Current Phase

**Phase 1 — Foundation** — Milestone 1.1 (Scaffolding) complete except deferred Flutter;
**Milestone 1.2 — Authentication** in progress (backend-first; Flutter parts deferred).

> **1.1.3 (Flutter) is deferred** — the Flutter SDK isn't installed on this machine.
> Backend/infra tasks were reordered ahead of it (see Design Decision 8). Flutter resumes
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

| #     | Task                                                                                                                              | Status                               |
| ----- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| 1.1.1 | Create root folder structure (`backend/`, `mobile/`, `infra/`, `docs/`, `.github/workflows/`) + `.gitignore` + root `README.md`   | ✅ Done                              |
| 1.1.2 | Configure FastAPI project (dependency management, app factory, settings, structured logging, `/health` endpoint)                  | ✅ Done                              |
| 1.1.3 | Configure Flutter project (`flutter create`, Riverpod + GoRouter + Freezed deps, lint config, folder skeleton per `MyBill.md` §7) | ⏸️ Deferred (needs Flutter SDK)      |
| 1.1.4 | Configure Supabase project (Auth enabled, `users` table + RLS, `receipts` Storage bucket + policy)                                | ✅ Done (applied live)               |
| 1.1.5 | Docker Compose for local dev (`api`, `worker`, `redis`)                                                                           | ✅ Done (worker deferred to Phase 2) |
| 1.1.6 | CI pipeline (GitHub Actions: `ruff` + `mypy` + tests on backend + Docker build; Flutter jobs when SDK lands)                      | ✅ Done                              |

### Milestone 1.2 — Authentication

| #     | Task                                                                                                | Status                                                                |
| ----- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 1.2.1 | Supabase client setup (backend `supabase-py` client + Flutter `supabase_flutter` client)            | 🟢 Backend done; Flutter half deferred (SDK)                          |
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
    plus handlers rendering every failure through the envelope; 500s logged, never leaked.
  - `app/api/deps.py` — `SettingsDep` reads settings off `app.state` (not the global) so
    test overrides propagate.
  - `app/api/v1/router.py` + `routes/health.py` — `GET /v1/health`.
  - `tests/` — 4 passing smoke tests (envelope shape, request-id generation/reuse, 404
    envelope). Verified live: `uvicorn` boots, `/v1/health` returns 200 with correct
    envelope + `x-request-id` header, `/docs` + `/openapi.json` served in non-prod.
  - `.env.example`, `backend/README.md`.
    Quality gates green: `ruff check`, `ruff format --check`, `mypy app` (strict), `pytest`.

- **1.1.4 — Configure Supabase (schema + RLS + Storage)** (2026-07-16)
  _Reordered ahead of 1.1.3 because the Flutter SDK isn't installed (decision 8)._
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
  **Verified locally** against a throwaway `postgres:16` Docker container via
  `infra/supabase/tests/run_tests.sh`: a harness stubs Supabase's auth/storage surface,
  all migrations apply, and 5 assertions pass — signup trigger provisions a profile; RLS
  isolates SELECT/INSERT/UPDATE per user; Storage scopes files to the owner's folder. Also
  confirmed migrations are idempotent (clean re-apply). Setup guide in
  `infra/supabase/README.md`.
  **Applied live** (2026-07-16) to the real project once creds were added: ref
  `fkowzsdvwqbhrjykjrcb`, ap-south-1. Connection required the Supavisor **session pooler**
  on the newer `aws-1-ap-south-1.pooler.supabase.com` fleet (direct host is IPv6-only, this
  machine is IPv4-only). All objects verified present; end-to-end auth-sync test
  (admin-create user → profile auto-created with correct defaults → delete → cascade) passed;
  DB left clean. `.env` now separates `SUPABASE_URL` (API) from `SUPABASE_DB_URL` (pooler).

- **1.1.5 — Docker Compose for local dev** (2026-07-16)
  Delivered `backend/Dockerfile` (multi-stage, uv, `--frozen` lockfile install, non-root
  `app` user, container HEALTHCHECK on `/v1/health`), `backend/.dockerignore` (keeps secrets
  - caches + tests out of the build context/image), and `infra/docker-compose.yml` wiring:
  * `api` — builds the image, hot-reloads via a `--reload` command override + read-only
    mount of just `backend/app/` (so the container's pre-built `.venv` isn't shadowed),
    published on `localhost:8000`, waits on redis health.
  * `redis` — `redis:7-alpine` with a `redis-cli ping` healthcheck; broker/cache ready
    for Phase 2. Not host-published by default.
  * `worker` (Celery) — defined but **commented out** until the Celery app exists (Phase 2);
    including a service that can't start would be placeholder scaffolding.

  **Verified live:** `docker compose config` valid; image builds; `docker compose up` brings
  the stack up; `GET /v1/health` returns the correct envelope through the container; uvicorn
  runs with the WatchFiles reloader; the api container healthcheck reaches **healthy**;
  `docker compose down` tears down cleanly. Docker usage documented in `backend/README.md`.

- **1.1.6 — CI pipeline** (2026-07-16)
  Delivered `.github/workflows/ci.yml` (GitHub Actions) running on PRs into `main` and pushes
  to `main`, with `concurrency` cancellation and least-privilege `permissions`:
  - **backend job** — `astral-sh/setup-uv` (pinned 0.5.9, cached on `uv.lock`), `uv sync
--dev --frozen`, then `ruff check` (GitHub annotations), `ruff format --check`,
    `mypy app` (strict), and `pytest`.
  - **docker-build job** — builds `backend/Dockerfile` via Buildx + `build-push-action`
    (GHA layer cache), then boots the image and smoke-tests `/v1/health` through it.
  - Flutter jobs (`flutter analyze` / `flutter test`) noted as added once the SDK + app exist.

  **Verified locally:** workflow is valid YAML; the exact backend commands all pass under
  `--frozen` (`uv sync`, ruff lint, ruff format check, mypy, 4 pytest); and the docker-build
  job's logic (build → run → curl `/v1/health` → 200 envelope) was reproduced end-to-end and
  cleaned up. (`act` isn't installed, so steps were run manually rather than in a runner.)

- **1.2.1 — Supabase client setup (backend)** (2026-07-16)
  Backend now holds a shared **service-role** async Supabase client. Delivered:
  - `supabase>=2.10` added to `pyproject.toml` (the task that introduces the dep).
  - `app/core/config.py` — `supabase_url` + `supabase_anon_key` / `supabase_service_role_key`
    / `supabase_jwt_secret` (the keys as `SecretStr` so they can't leak into logs), all
    optional so the app still boots unconfigured, plus a `supabase_configured` property.
  - `app/integrations/supabase.py` — `create_supabase_client()`: builds the async
    service-role client, raises a clear `RuntimeError` if unconfigured, logs readiness
    without ever logging a secret.
  - `app/main.py` lifespan — creates the client at startup when configured, stores it on
    `app.state.supabase` (None otherwise).
  - `app/api/deps.py` — `SupabaseDep` returns the client or raises 503 (`ServiceUnavailableError`,
    added to `app/core/exceptions.py`) when unconfigured.
  - `tests/test_supabase.py` — 6 tests (config property, factory guard, DI 503/return,
    SecretStr masking). Full suite: 10 passed.

  **Verified live:** the app's own factory, loaded from the real `.env`, connected to the
  live project and listed storage buckets → `['receipts']` (private). The full app also boots
  with real creds, creating the client in the lifespan (`supabase_client_created` logged, no
  secret) with `/v1/health` responding. Quality gates green (ruff, ruff format, mypy strict,
  pytest).
  _Flutter `supabase_flutter` client half deferred with the SDK (1.1.3)._

---

## Pending Tasks

Milestone 1.1 complete (except deferred Flutter 1.1.3). In **Milestone 1.2 —
Authentication**: 1.2.1 backend done; next is **1.2.2 — JWT verification middleware**. See
full task list above.

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
   `MyBill.md` §12 Docker Compose block, which lives at `infra/docker-compose.yml`.

4. **`.gitkeep` used for now-empty scaffolded directories**, deleted the moment real content
   lands in the directory.
   **Why:** git doesn't track empty directories; `.gitkeep` is a placeholder _file_, not
   placeholder _code_.

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
   overrides silently don't apply (caught in 1.1.2 — the health test initially reported
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

11. **Supabase CLI adoption deferred; migrations applied via psql for now.** The CLI expects
    migrations under `supabase/migrations/`; ours live under `infra/supabase/migrations/`
    (decision 3). **Why:** committing to its directory convention now would fight our
    monorepo layout, and there's no migration-ledger need yet. When adopted, we move/symlink
    the folder. Recorded as tech debt.

12. **Compose `worker` service shipped commented-out; `redis` shipped live.** The Celery
    `worker` in `MyBill.md` §12 can't start until `app/worker.py` (the Celery app) exists in
    Phase 2, so enabling it now would be placeholder scaffolding that crash-loops — it's kept
    as a commented target block instead. `redis` _is_ enabled now because it's zero-code real
    infrastructure and having the broker/cache present makes the local stack match the target.
    **Why:** honours "no placeholder code" while still delivering a working dev stack.

13. **Dev hot-reload mounts only `backend/app/`, not the whole `backend/`.** Mounting the
    entire backend dir over `/app` would shadow the image's pre-built `/app/.venv` with the
    host (wrong/absent venv) and break the container. Mounting just the source package (read
    only) gives live reload while preserving the installed venv.

14. **CI scoped to backend gates + a Docker build/smoke job; Flutter jobs deferred.** The
    workflow installs deps with `--frozen` (fails on lockfile drift) and mirrors the exact
    local quality gates, plus builds the image and curls `/v1/health` through it. Flutter
    `analyze`/`test` jobs are added when the app exists (1.1.3). The Supabase migration test
    (`run_tests.sh`) is not yet a CI job — recorded as tech debt. **Why:** keeps the task
    small and every step reproducible locally, matching what's actually buildable today.

15. **Backend holds one shared service-role Supabase client, not per-request user-scoped
    clients.** External-service clients live in a new `app/integrations/` package (separate
    from `core` framework code and the `api` HTTP layer). The single client uses the
    service-role key and is created once in the lifespan.
    **Why:** matches `MyBill.md` §11 — "the FastAPI layer uses service-role calls only for
    system operations" and "FastAPI enforces `user_id` scoping in every query." The app
    filters by `user_id` explicitly; RLS is the DB-level backstop. Trade-off: service-role
    bypasses RLS, so every query/storage path here MUST include the owner's id by hand —
    called out in `app/integrations/supabase.py`. Keys are `SecretStr` and config is optional
    so the app still boots (and unit tests run) unconfigured, with `SupabaseDep` returning 503.

16. **OCR provider, LLM provider, and other Phase 2/6 technology choices are deliberately
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
│   └── workflows/
│       └── ci.yml             # backend gates + Docker build smoke test
├── backend/                   # FastAPI service
│   ├── app/
│   │   ├── main.py            # create_app() factory + ASGI app (+ lifespan clients)
│   │   ├── core/              # config, logging, middleware, responses, exceptions
│   │   ├── integrations/      # external-service clients (supabase.py; OCR/LLM later)
│   │   └── api/
│   │       ├── deps.py        # SettingsDep, SupabaseDep
│   │       └── v1/
│   │           ├── router.py
│   │           └── routes/health.py
│   ├── tests/                 # conftest + test_health + test_supabase
│   ├── Dockerfile             # multi-stage uv image, non-root, healthcheck
│   ├── .dockerignore
│   ├── pyproject.toml
│   ├── .env.example
│   └── README.md
├── mobile/                    # Flutter app (empty — task 1.1.3, deferred)
├── infra/
│   ├── docker-compose.yml     # local dev stack: api + redis (worker: Phase 2)
│   └── supabase/
│       ├── migrations/        # 4 idempotent SQL migrations (users, auth-sync, storage)
│       ├── tests/             # harness.sql + test_rls.sql + run_tests.sh (local verify)
│       └── README.md          # Supabase setup + migration guide
├── docs/                      # Supplementary docs (empty)
├── .pre-commit-config.yaml    # prek hooks: ruff/mypy (backend) + prettier (docs), auto-fix
├── .gitignore
├── README.md
├── MyBill.md                  # Architecture & product spec (source doc)
└── DESIGN.md                  # This file
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
- **Supabase migration test not in CI** — `infra/supabase/tests/run_tests.sh` runs locally
  only; add it as a CI job (Postgres service container) so RLS regressions are caught on PRs.
- **Supabase CLI not adopted** — migrations live in `infra/supabase/migrations/`, but the
  CLI expects `supabase/migrations/`. Move/symlink when we adopt `supabase db push`
  (decision 11).
- **`flutter` SDK not installed** — task 1.1.3, Flutter CI jobs, and all mobile work blocked
  until it is.

---

## Next Recommended Task

**1.2.2 — JWT verification middleware**: a FastAPI dependency (`CurrentUserDep`) that
validates the Supabase-issued JWT on the `Authorization: Bearer` header and yields the
authenticated user's id/claims; protected routes depend on it, unauthenticated requests get
401 via the existing envelope. Decide verification path in the task — symmetric
`SUPABASE_JWT_SECRET` (HS256, already in config) vs. asymmetric JWKS (`SUPABASE_JWKS_URL`,
newer projects) — and add `python-jose`/`pyjwt` accordingly. Verifiable with unit tests
(valid token → user id; expired/tampered/missing → 401) plus a temporary protected route
exercised end-to-end with a real token minted from the live project. Foundation for every
authenticated endpoint (upload, analytics, …).
