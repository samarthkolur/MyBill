# DESIGN.md — MyBill Build Log & Task Tracker

> Single source of truth for build status. Updated after every completed task.
> Architecture/product spec lives in [`MyBill.md`](./MyBill.md) — this file tracks _execution_, not design intent (except where we deviate from or extend that spec, which is recorded in [Design Decisions](#design-decisions)).

---

## Current Phase

**Phase 1 — Foundation** — **all backend work complete and verified** across Milestones
1.1–1.3, and **Milestone 1.2 (Authentication) is now complete on Flutter too**: the SDK is
installed, so auth state/persistence, the Login/Sign Up/Forgot Password screens, the route
guard, and logout (1.2.4–1.2.9) have landed.

The remaining Phase 1 tasks are Milestone 1.3's Flutter half — camera/scan + client-side
image prep (1.3.1–1.3.2) and the upload wiring (1.3.5) — after which Phase 1's exit
criteria are met. The backend is separately ready for **Phase 2 — OCR Pipeline**.

> **The Flutter SDK is installed** (3.35.6). Backend/infra tasks were reordered ahead of
> the mobile work while it was blocked (see Design Decision 8); that block is now lifted.

> **Password reset is not end-to-end.** 1.2.7 sends Supabase's recovery email, but the
> `io.mybill.app://reset-password` deep link isn't registered in the Android manifest /
> iOS `Info.plist` and there's no set-new-password screen yet. Tracked as outstanding.

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

| #     | Task                                                                                                | Status                                      |
| ----- | --------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| 1.2.1 | Supabase client setup (backend `supabase-py` client + Flutter `supabase_flutter` client)            | ✅ Done                                     |
| 1.2.2 | JWT verification middleware (FastAPI dependency, validates Supabase-issued JWT on protected routes) | ✅ Done (ES256 via JWKS)                    |
| 1.2.3 | User profile sync (on first authenticated request, ensure a row exists in `users`)                  | ✅ Done (DB trigger + app-layer safety-net) |
| 1.2.4 | Flutter: auth state (Riverpod notifier) + secure token persistence (`flutter_secure_storage`)       | ✅ Done                                     |
| 1.2.5 | Flutter: Login screen                                                                               | ✅ Done                                     |
| 1.2.6 | Flutter: Sign Up screen                                                                             | ✅ Done                                     |
| 1.2.7 | Flutter: Forgot Password screen                                                                     | 🟢 Sends recovery email; deep link pending  |
| 1.2.8 | GoRouter route guards (redirect unauthenticated users to login)                                     | ✅ Done                                     |
| 1.2.9 | Logout flow (clear token, revoke Supabase session, redirect)                                        | ✅ Done                                     |

### Milestone 1.3 — Camera & Upload

| #     | Task                                                                                              | Status                                                        |
| ----- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| 1.3.1 | Flutter: Scan screen — camera capture + gallery picker                                            | ✅ Done (via `image_picker`, decision 23)                     |
| 1.3.2 | Flutter: pre-upload crop/rotate (`image_cropper`) + client-side compression (≤2MB, quality 85%)   | ✅ Done                                                       |
| 1.3.3 | Backend: `POST /v1/receipts/upload` — stores image in Supabase Storage (`receipts/{user_id}/...`) | ✅ Done                                                       |
| 1.3.4 | Backend: create `receipts` row with `status = pending` on upload                                  | ✅ Done                                                       |
| 1.3.5 | Flutter: wire upload flow end-to-end + progress UI, persisted upload queue for offline retry      | 🟢 Upload + progress + multi-page done; offline queue pending |

**Phase 1 exit criteria** (from `MyBill.md`): user can register, log in, photograph a receipt, and see it uploaded.

---

## Phase 2 — OCR Pipeline (milestone-level, not yet broken into tasks)

- ✅ **DB write targets** — `categories` (seeded ×10) + `receipt_items` + `price_history`,
  applied live (`…140000_ocr_tables`)
- ✅ **`OCRProvider` interface + concrete implementation** — RapidOCR (PP-OCR via
  onnxruntime), offline and free (decision on engine choice below)
- ✅ **`ReceiptParser` interface + first implementation** — `HeuristicReceiptParser`:
  geometry + regex, OCRResult → CanonicalReceipt (store, date/time, totals, line items),
  preliminary category-by-keyword, low-confidence review flagging
- ✅ **Normalisation layer (Stage 4)** — `ReceiptNormaliser` writes a CanonicalReceipt to
  `receipts` + `receipt_items` + `price_history`: alias-aware store resolution, category
  name→id lookup, idempotent replace-by-receipt, receipt flipped to `done`. New
  repositories: `reference` (categories/stores), `parsed` (items/price_history)
- ✅ **Celery + Redis async job queue** — `ReceiptPipeline` chains OCR → parse → normalise
  (multi-page receipts stacked into one document); `app/worker.py` is the Celery app +
  `process_receipt` task; a successful upload enqueues via the `TaskQueue` seam. Compose
  `worker` enabled; image installs the `ocr` group. **Not yet run in-container against live
  Redis + real OCR** (needs a docker build with ONNX model download).
- ✅ **Processing status polling** — `GET /receipts/{id}` returns the receipt's status;
  the Flutter processing screen (route `/processing/:receiptId`) polls it after a new-bill
  upload, animating a "reading" state until done/failed with retry on timeout
- ⬜ Image pre-processing service (resize, deskew, binarise) — slots in ahead of OCR
- ⬜ **Store alias table (seed 20 chains)** — store resolution today matches within a user's
  own stores (space-insensitive aliases); a global known-chain seed is still to add

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

- **1.2.2 — JWT verification middleware** (2026-07-16)
  Protected routes now require a valid Supabase access token. The project signs tokens with
  **asymmetric ES256** (confirmed by inspecting a real token + the JWKS endpoint), so:
  - `pyjwt[crypto]` added; `app/core/security.py` — `JwtVerifier` fetches/caches the project
    JWKS (`PyJWKClient`) and validates signature, `exp`, issuer (`<url>/auth/v1`), and
    audience (`authenticated`), pinned to ES256 (algorithm-confusion defence). Returns an
    `AuthenticatedUser` (id/email/role/claims). Config gained JWKS-URL/issuer/audience props.
  - Verifier built once in the lifespan (None when unconfigured); `app/api/deps.py` —
    `CurrentUserDep` extracts the bearer token (via `HTTPBearer`, off-loop verify) → 401 on
    missing/invalid, 503 when auth unconfigured.
  - `GET /v1/auth/me` (`routes/auth.py`) — first protected endpoint.
  - `tests/test_auth.py` — 11 hermetic tests (local ES256 keypair, stubbed JWKS): valid,
    expired, wrong issuer/audience, wrong key, missing/non-UUID sub, endpoint 200/401/503.
    **Verified live** against the running app + real project: minted a real token →
    `/v1/auth/me` 200 with correct id; missing/garbage → 401. Test user cleaned up.

- **1.2.3 — User profile sync (app-layer safety-net)** (2026-07-16)
  Established the Router→Service→Repository layering (`MyBill.md` §2) and completed profile
  sync. `app/repositories/users.py` (`UserRepository`), `app/services/users.py`
  (`UserService.ensure_profile` — returns the profile, upserting it if the DB signup trigger
  somehow didn't), `app/schemas/user.py` (`UserProfile`). `GET /v1/auth/me` now ensures +
  returns the real DB profile. `tests/test_users.py` — 5 tests (existing→no write,
  missing→provision, metadata name extraction). **Verified live:** `/v1/auth/me` returns the
  trigger-created profile with `full_name` from metadata + `INR`/`Asia/Kolkata` defaults.

- **1.3.3 / 1.3.4 — Receipt upload endpoint + pending row** (2026-07-16)
  `POST /v1/receipts/upload` (auth-required) validates the image, stores the original in the
  private `receipts` bucket under `{user_id}/{receipt_id}/original.<ext>`, and inserts a
  `status=pending` receipt row; OCR (Phase 2) fills the rest. Delivered:
  - New migration `…093000_stores_and_receipts` — `stores` + `receipts` tables, both with
    RLS (`enable+force`, `for all` policy on `auth.uid()=user_id`), grants, `updated_at`
    triggers, indexes, and a `status` CHECK. `receipts.date`/`total` are NULLABLE
    (deviation from §4 — a pending receipt has neither until OCR; see decision 18). Applied
    live + a 6th RLS assertion added to `tests/test_rls.sql` (all pass locally).
  - `python-multipart` added; `schemas/receipt.py`, `repositories/receipts.py`,
    `services/receipts.py` (validation → 415/413, storage upload, orphan-object cleanup on
    DB failure), `routes/receipts.py`, `ReceiptServiceDep`.
  - `tests/test_receipts.py` — 7 tests (415/413 validation, happy path stores+creates,
    cleanup-on-failure, endpoint 401). Full suite: **32 passed**.
    **Verified live** end-to-end: real token → upload 201 pending; DB row present under the
    owner's folder; storage object present; PDF → 415; no token → 401. Project left clean.

- **1.2.1 (Flutter half) / 1.2.4–1.2.9 — Mobile authentication** (2026-07-17)
  The Flutter SDK (3.35.6) is installed, unblocking the mobile track. Milestone 1.2 is now
  complete on the client: sign in / sign up / password-reset request, session persistence,
  route guarding, and logout. Delivered:
  - `supabase_flutter` + `flutter_secure_storage` added. `core/storage/secure_local_storage.dart`
    — a `LocalStorage` implementation persisting the session to the platform keystore instead
    of the SDK's default plain-text `SharedPreferences` (a session string carries a live
    access token _and_ a long-lived refresh token). Wired via `FlutterAuthClientOptions`.
  - `features/auth/data/auth_repository.dart` — wraps Supabase Auth so screens never import
    the SDK. `features/auth/application/auth_controller.dart` — `AuthController` mirrors
    `onAuthStateChange` (so background refresh/expiry is reflected app-wide) and exposes
    `AuthStatus.{unknown,authenticated,unauthenticated}`; `unknown` parks on a new splash so
    a returning user never sees a login flash.
  - Screens: Login (1.2.5), Sign Up (1.2.6, `full_name` → user metadata → the 1.2.3 trigger),
    Forgot Password (1.2.7), plus a shared `AuthErrorBanner` and `core/utils/validators.dart`.
  - `core/router/app_router.dart` — the guard (1.2.8) as one `redirect` rule, so new routes
    are protected by default; logout (1.2.9) on the home screen just clears state and lets
    the guard redirect. Router built once, refreshed via a `ValueNotifier` bridge.
  - Config via `--dart-define` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`); boot fails loudly when
    absent. `mobile/README.md` rewritten (config, run, architecture, auth model).
  - `test/widget_test.dart` — 5 widget tests over a fake repository (guard redirects both
    ways, sign-in → home, sign-out → login, client-side validation). **All 5 pass**;
    `flutter analyze` clean; `flutter build web` compiles. The tests caught a real
    `RenderFlex` overflow in the login/signup footer rows (now `Wrap`).
  - **Not verified against a live Supabase project** — no emulator on this machine, so the
    flows are covered by widget tests + a real compile, not a manual end-to-end run.

- **Multi-page receipts (`receipt_images`) — DB + API + mobile** (2026-07-17)
  A receipt now holds 1..N pages, so a long receipt can be photographed in several shots and
  appended to the same bill instead of becoming several unrelated ones. Delivered:
  - Migration `…120000_receipt_images` — new table (RLS enable+force, owner policy, grants,
    indexes, `(receipt_id, page_number)` unique, `page_number > 0` CHECK, cascade from
    receipts), backfills `receipts.image_url` as page 1, then drops that column's NOT NULL.
    The column is retained (nullable, deprecated) for rollback. **Applied live** 2026-07-17.
  - `ReceiptImageRepository`; `ReceiptRepository` gains `get_owned`/`list_for_user`/`delete`.
    `ReceiptService` gains `add_image`/`list_receipts`; upload writes page 1 to
    `receipt_images` and deletes the receipt row if the page fails to store (decision 25).
    Routes: `POST /v1/receipts/{id}/images`, `GET /v1/receipts`. Pages capped at 20.
  - Mobile: `ScanTarget` (new bill vs existing), a bottom-sheet picker backed by
    `GET /receipts`, `Receipt`/`ReceiptImage` models. Defaults to a new bill.
  - Tests: backend **37 passed** (ruff + ruff format + mypy strict clean); mobile **16
    passed**, analyze clean; RLS harness **7/7** including the new receipt_images assertions.
  - **Verified live end-to-end** against the real Supabase project + a running backend:
    upload → 201 with page 1; two appends → pages 2 and 3 on the same receipt with
    server-assigned numbers; `GET /v1/receipts` returned the receipt with all 3 pages;
    unknown receipt → 404; non-image → 415; no token → 401. DB and Storage confirmed
    (1 receipt, 3 images, 3 objects under the owner's folder). Test user and all artifacts
    deleted afterwards — **project left clean** (receipts=0, receipt_images=0, objects=0).
    Not yet driven from the phone UI (see Technical Debt).

---

## Pending Tasks

**All Phase 1 backend work is done, and Milestone 1.2 is now complete on Flutter.** Remaining
Phase 1 tasks are Milestone 1.3's Flutter half: scan/crop (1.3.1–1.3.2) and upload wiring
(1.3.5) — after which Phase 1's exit criteria are met. Also outstanding: the password-reset
deep link (see Technical Debt). The backend is separately ready for **Phase 2 — OCR
Pipeline**. See full task list above.

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

16. **JWT verification uses asymmetric ES256 via JWKS, not the legacy HS256 shared secret.**
    Inspecting a real access token showed `alg: ES256` with a `kid` resolving to the
    project's JWKS endpoint. So `JwtVerifier` validates against the published public keys
    (PyJWT `PyJWKClient`, cached), pinned to `["ES256"]` to prevent algorithm confusion, and
    checks issuer + audience + expiry. **Why:** it's how this project actually signs tokens;
    JWKS also rotates keys without a redeploy. `SUPABASE_JWT_SECRET` (HS256) is kept in config
    as an unused fallback only. The (cached, occasional-network) verify runs in a threadpool
    so it never blocks the event loop.

17. **Backend layered as Router → Service → Repository** (`MyBill.md` §2), with
    `app/schemas/` (Pydantic models), `app/repositories/` (Supabase data access, one per
    table), `app/services/` (business logic), and routes staying in `app/api/v1/routes/`.
    **Why:** keeps HTTP, business rules, and data access independently testable — services
    are unit-tested against fake repositories with no network. Deps.py wires each service to
    the shared client.

18. **`receipts.date` and `receipts.total` are nullable, deviating from `MyBill.md` §4
    (NOT NULL).** A receipt is created at upload time as `status=pending` with only the image;
    the parsed date and total don't exist until OCR runs. **Why:** enforcing NOT NULL would
    make the upload→pending→parse flow impossible. They're expected non-null once
    `status='done'` (a future CHECK/validation can enforce that conditionally).

19. **`receipts.image_url` stores the Storage object key, not a public/signed URL.** Upload
    writes `{user_id}/{receipt_id}/original.<ext>` and stores that key. **Why:** the bucket is
    private and signed URLs expire (§11), so persisting a URL would rot; short-lived signed
    URLs are minted on read (Phase 3). The upload also deletes the orphaned object if the DB
    insert fails, so Storage and DB don't drift.

20. **OCR provider, LLM provider, and other Phase 2/6 technology choices are deliberately
    deferred**, not decided now.
    **Why:** `MyBill.md` already designs these behind swappable interfaces
    (`OCRProvider`, `ReceiptParser`, `LLMProvider`); picking a concrete implementation before
    we reach that phase would be a decision made without the context (pricing at the time,
    receipt sample quality) needed to make it well.

21. **Supabase sessions persist to the platform keystore via a custom `LocalStorage`,
    not the SDK's default `SharedPreferences`.**
    **Why:** the SDK's default writes the session as plain text on disk, and that session
    carries both a live access token and a long-lived refresh token — the refresh token is
    the durable credential, so leaking it is worse than leaking a short-lived JWT. Task
    1.2.4 already called for `flutter_secure_storage`; implementing `LocalStorage` against
    it satisfies that _and_ keeps the SDK's automatic refresh, which hand-rolling token
    storage would have forced us to reimplement.

22. **The auth guard is a single `redirect` rule in the router; screens never navigate on
    sign-in/sign-out.**
    **Why:** redirect logic duplicated per screen drifts, and the failure mode is a route
    that silently isn't protected. One rule inverts the default — a new route is protected
    unless it opts into `AppRoutes.unauthenticated` — and because the rule keys off
    `AuthController` (which mirrors the SDK's auth stream), a session that expires or is
    refreshed in the background is handled by the same path as an explicit sign-out.

23. **Scan capture uses `image_picker` (the OS camera/gallery), not the `camera` package's
    in-app viewfinder** — a deviation from `MyBill.md` §15/§17.
    **Why:** the OS camera already solves permissions, lifecycle, orientation, and
    device-specific quirks, and it gets Phase 1 to its exit criteria (photograph → upload)
    with a fraction of the code. A branded in-app viewfinder is a UX upgrade we can make
    later behind the same `ImagePipeline` seam, without touching the upload path.

24. **Multi-image ("add to an existing bill") receipts: single-image upload shipped first,
    then the multi-page stack.** ✅ _Both now landed._
    **Why (sequencing):** the requirement (raised 2026-07-17) implies multi-page receipts,
    which the schema could not represent — `receipts.image_url` was a single `not null`
    column, one storage object per receipt — and needed a `GET /v1/receipts` list endpoint
    so the user had bills to choose between. Shipping single-image capture first closed
    Phase 1's exit criteria against the live endpoint rather than leaving a half-built
    client path.
    **How it landed:** `receipt_images` (1 → N) is the source of truth;
    `receipts.image_url` was backfilled as page 1 and made nullable rather than dropped, so
    a rollback keeps its data. `user_id` is denormalised onto the table so RLS is checkable
    without a join. `(receipt_id, page_number)` is unique — that constraint, not the
    read-then-write in `next_page_number`, is what actually prevents two concurrent uploads
    claiming a page. Pages are capped at 20 per receipt.

25. **A receipt whose first page fails to store is deleted, not left behind.**
    **Why:** the row and its image are written separately, so a storage failure after the
    insert would leave a pageless receipt — a bill the user can see, can't open, and didn't
    ask for. Deleting the row makes a failed upload a no-op instead of visible litter. (The
    previous single-image flow had the inverse cleanup: remove the orphaned object.)

26. **Unknown and not-yours both answer 404 on receipt routes.**
    **Why:** a 403 for someone else's receipt would confirm the id exists. Scoping the
    lookup by `user_id` as well as `id` makes the two cases indistinguishable, so the
    endpoint can't be used to probe for valid ids.

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
│   │   ├── core/              # config, logging, middleware, responses, exceptions, security
│   │   ├── integrations/      # external-service clients (supabase.py; OCR/LLM later)
│   │   ├── schemas/           # Pydantic models (user, receipt)
│   │   ├── repositories/      # Supabase data access (users, receipts)
│   │   ├── services/          # business logic (users, receipts)
│   │   └── api/
│   │       ├── deps.py        # Settings/Supabase/CurrentUser/UserService/ReceiptService deps
│   │       └── v1/
│   │           ├── router.py
│   │           └── routes/    # health, auth (/me), receipts (/upload)
│   ├── tests/                 # health, supabase, auth, users, receipts
│   ├── Dockerfile             # multi-stage uv image, non-root, healthcheck
│   ├── .dockerignore
│   ├── pyproject.toml
│   ├── .env.example
│   └── README.md
├── mobile/                    # Flutter app
│   ├── lib/
│   │   ├── main.dart          # Supabase init (secure session storage) → runApp
│   │   ├── app.dart           # MaterialApp.router + theme
│   │   ├── core/              # constants (dart-define config), router (+ auth guard),
│   │   │                      #   storage (keystore LocalStorage), theme, utils (validators)
│   │   └── features/
│   │       ├── auth/          # data/ (repository), application/ (AuthController), presentation/
│   │       ├── home/          # placeholder dashboard (behind the guard)
│   │       └── splash/        # shown while the session is restored
│   ├── test/                  # widget tests (guard, sign-in/out, validation)
│   └── README.md              # config, run, architecture, auth model
├── infra/
│   ├── docker-compose.yml     # local dev stack: api + redis (worker: Phase 2)
│   └── supabase/
│       ├── migrations/        # 5 idempotent migrations (users, auth-sync, storage, stores+receipts)
│       ├── tests/             # harness.sql + test_rls.sql (6 assertions) + run_tests.sh
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

| Method | Path                       | Auth | Status  | Notes                                                                                     |
| ------ | -------------------------- | ---- | ------- | ----------------------------------------------------------------------------------------- |
| `GET`  | `/v1/health`               | no   | ✅ Live | Liveness; always 200 when up. Readiness (`/health/ready`, DB/Redis) to follow.            |
| `GET`  | `/v1/auth/me`              | yes  | ✅ Live | Verifies the Supabase JWT; ensures + returns the caller's profile. 401 if invalid.        |
| `POST` | `/v1/receipts/upload`      | yes  | ✅ Live | Multipart image → private Storage + `pending` receipt row (page 1). 415/413 on bad image. |
| `POST` | `/v1/receipts/{id}/images` | yes  | ✅ Live | Append a page to an existing bill; server assigns the page number. 404/415/413.           |
| `GET`  | `/v1/receipts`             | yes  | ✅ Live | The caller's receipts (newest first, with pages). Backs the add-to-existing picker.       |

All responses use the standard envelope from `MyBill.md` §5 via `app.core.responses`.

---

## Database Schema Status

Migrations live in `infra/supabase/migrations/`, verified against Postgres 16.

| Table / object                                            | Status                    | Migration                     |
| --------------------------------------------------------- | ------------------------- | ----------------------------- |
| `public.users` (+ RLS, grants, `updated_at` trigger)      | ✅ Created                | `…090100_create_users`        |
| `handle_new_user()` auth-sync trigger                     | ✅ Created                | `…090200_auth_user_sync`      |
| `receipts` Storage bucket (private) + policies            | ✅ Created                | `…090300_receipts_storage`    |
| `stores` (+ RLS, grants, `updated_at`)                    | ✅ Created                | `…093000_stores_and_receipts` |
| `receipts` (+ RLS, grants, indexes, status CHECK)         | ✅ Created                | `…093000_stores_and_receipts` |
| `receipt_images` (+ RLS, grants, indexes, page CHECK)     | ✅ Created (applied live) | `…120000_receipt_images`      |
| `receipt_items` (+ RLS, grants, indexes, price/qty CHECK) | ✅ Created (applied live) | `…140000_ocr_tables`          |
| `categories` (global reference data, seeded ×10)          | ✅ Created (applied live) | `…140000_ocr_tables`          |
| `price_history` (+ RLS, grants, indexes, price CHECK)     | ✅ Created (applied live) | `…140000_ocr_tables`          |
| `analytics_cache`                                         | ⬜ Pending                | Phase 4                       |

Full target schema is `MyBill.md` §4. Migrations through `…093000_stores_and_receipts` were
**applied and verified on the live Supabase project** (ref `fkowzsdvwqbhrjykjrcb`, region
ap-south-1) on 2026-07-16 — all objects confirmed present; the auth-sync trigger and the
upload→pending-receipt flow were both exercised end-to-end against the live DB + Storage.
DB left clean (0 rows). Note `receipts.date`/`total` are nullable (decision 18).

`…120000_receipt_images` was **applied to the live project on 2026-07-17** and verified:
table present, `receipts.image_url` now nullable, RLS enabled + forced, the owner policy,
the `(receipt_id, page_number)` unique key, and the `page_number > 0` CHECK all confirmed.
The backfill was a no-op (0 existing receipts), so no data was touched.

`…140000_ocr_tables` (categories + receipt_items + price_history, the OCR pipeline's write
targets) was first **verified against the throwaway Postgres harness** — new assertions
(Tests 8–10) confirm categories is readable-by-all/writable-by-none, and that
receipt_items/price_history are owner-scoped with their price/quantity CHECKs and
cascade-on-receipt-delete — then **applied to the live project on 2026-07-18** and confirmed
there: all three tables present with RLS enabled + forced, the 10 categories seeded, all
three policies (categories SELECT-only; the two owner ALL policies), and all three CHECK
constraints in place. No existing rows, so no data was touched.

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
- **Upload endpoint has no rate limiting** — `MyBill.md` §11 specifies 30 uploads/hour/user
  to cap OCR cost. Not implemented yet (needs the Redis-based limiter); add before Phase 2
  OCR wiring makes uploads expensive.
- **No conditional NOT NULL on parsed receipt fields** — `date`/`total` are nullable for the
  pending state (decision 18); once OCR lands, enforce non-null when `status='done'` (CHECK
  or app-level validation).
- **`AuthenticatedUser.claims` typed as `dict[str, object]`** — callers needing specific
  claims re-narrow types. Fine for now; tighten with a typed claims model if it spreads.
- **Supabase CLI not adopted** — migrations live in `infra/supabase/migrations/`, but the
  CLI expects `supabase/migrations/`. Move/symlink when we adopt `supabase db push`
  (decision 11).
- **`receipts.image_url` still exists (nullable, deprecated)** — superseded by
  `receipt_images` but kept for rollback safety. Drop it once nothing reads it.
- **The "add to an existing bill" picker is unconfirmed on-device** — capture → crop →
  upload was exercised by hand on a Pixel 9 (2026-07-17) and works, and the append/list API
  is verified live; but tapping **Change** to send a page to an existing bill has only
  unit-test coverage so far.
- **Password reset isn't end-to-end** — 1.2.7 sends Supabase's recovery email, but the
  `io.mybill.app://reset-password` deep link is not registered in the Android manifest / iOS
  `Info.plist`, and there's no set-new-password screen. The link currently goes nowhere.
- **Mobile auth not verified against a live Supabase project** — covered by widget tests
  against a fake repository plus a real web compile; no emulator on this machine, so the
  flows haven't been exercised end-to-end. Do a manual pass before relying on them.
- **Flutter jobs still absent from CI** — the SDK is installed locally now, so the reason
  for deferring them (decision 14) is gone; add `flutter analyze` + `flutter test` jobs.
- **Dart/Flutter not covered by the pre-commit hooks** — `.pre-commit-config.yaml` gates
  Python (ruff/mypy) and YAML/JSON/Markdown (prettier), but nothing runs `dart format` or
  `flutter analyze`, so mobile regressions aren't caught before commit.

---

## Next Recommended Task

**Phase 1 backend is complete, and Milestone 1.2 (Authentication) is now complete on Flutter
too.** The SDK is installed, so the mobile track is no longer blocked.

**Recommended next: finish Milestone 1.3's Flutter half** — the Scan screen (camera capture +
gallery picker, 1.3.1), pre-upload crop/rotate + compression (1.3.2), and the upload wiring
with progress UI + offline retry queue (1.3.5). That closes Phase 1's exit criteria
(register → log in → photograph → upload) end-to-end against the already-live
`POST /v1/receipts/upload`.

Then either:

1. **Close the auth loose end** — register the `io.mybill.app://reset-password` deep link and
   add a set-new-password screen so 1.2.7 is genuinely end-to-end.
2. **Begin Phase 2 — OCR Pipeline** on the backend: choose the OCR provider (recommended:
   Google Document AI), stand up Celery + Redis (compose `worker` already stubbed), define the
   `OCRProvider`/`ReceiptParser` interfaces, and process a `pending` receipt into
   `receipt_items` + `price_history`. The upload endpoint already produces the `pending` rows
   this consumes.
