# DESIGN.md — MyBill Build Log & Task Tracker

> Single source of truth for build status. Updated after every completed task.
> Architecture/product spec lives in [`MyBill.md`](./MyBill.md) — this file tracks *execution*, not design intent (except where we deviate from or extend that spec, which is recorded in [Design Decisions](#design-decisions)).

---

## Current Phase

**Phase 1 — Foundation**, Milestone 1.1 — Project Scaffolding

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
| 1.1.2 | Configure FastAPI project (dependency management, app factory, settings, structured logging, `/health` endpoint) | ⬜ Pending |
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

---

## Pending Tasks

Next up: **1.1.2 — Configure FastAPI project**. See full Phase 1 task list above.

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

5. **OCR provider, LLM provider, and other Phase 2/6 technology choices are deliberately
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
│   └── workflows/        # CI pipelines (empty — task 1.1.6)
├── backend/               # FastAPI service (empty — task 1.1.2)
├── mobile/                # Flutter app (empty — task 1.1.3)
├── infra/
│   └── supabase/
│       └── migrations/    # SQL migrations (empty — task 1.1.4)
├── docs/                  # Supplementary docs (empty)
├── .gitignore
├── README.md
├── MyBill.md               # Architecture & product spec (source doc)
└── DESIGN.md               # This file
```

---

## APIs Implemented

None yet. First endpoint (`POST /v1/receipts/upload`) targeted at task 1.3.3.

---

## Database Schema Status

No tables created yet. Full schema (`users`, `stores`, `receipts`, `receipt_items`,
`categories`, `price_history`, `analytics_cache`) is specified in `MyBill.md` §4.
`users` table + RLS is the first to be created, at task 1.1.4.

---

## Technical Debt

None yet — project just scaffolded.

---

## Next Recommended Task

**1.1.2 — Configure FastAPI project**: dependency management (`pyproject.toml` via
`uv`/`poetry`), app factory pattern, `Settings` (pydantic-settings) for env config,
structured logging, and a `GET /health` endpoint, with a basic `pytest` smoke test.
