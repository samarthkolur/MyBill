# MyBill — Grocery Bill Intelligence App

Photograph a grocery receipt, get it turned into structured data automatically, and see
spending analytics, price trends, and bill comparisons over time.

- **Architecture & product spec:** [`MyBill.md`](./MyBill.md) — the full system design (data flow, DB schema, API design, OCR pipeline, phased roadmap).
- **Build status & task tracker:** [`DESIGN.md`](./DESIGN.md) — single source of truth for what's done, what's next, and every design decision made along the way. Read this before picking up any task.

## Stack

- **Mobile:** Flutter (Riverpod, GoRouter, `supabase_flutter`, Dio)
- **Backend:** FastAPI (`uv`, Supabase client; Celery + Redis for the OCR pipeline in Phase 2)
- **Data:** Supabase (PostgreSQL + RLS, Auth, Storage)

## Repository layout

```
MyBill/
├── backend/    # FastAPI service (API, OCR pipeline, workers)
├── mobile/     # Flutter app — see mobile/README.md for config & run
├── infra/      # Docker Compose, Supabase migrations/config
├── docs/       # Supplementary docs
├── MyBill.md   # Architecture & product spec
└── DESIGN.md   # Living build log / task tracker
```

## Getting started

Secrets live in `backend/.env` (gitignored) — copy `backend/.env.example` and fill it in.
Nothing secret is committed, and the mobile app takes its config at build time rather than
from a bundled file.

### Backend

```sh
cd backend
uv sync
uv run uvicorn app.main:app --reload    # http://localhost:8000/v1
```

Gates (all must pass before committing):

```sh
uv run ruff check . && uv run ruff format --check .
uv run mypy app
uv run pytest
```

### Mobile

```sh
cd mobile
./scripts/run.sh                 # reads Supabase config from backend/.env
./scripts/run.sh -d <device-id>  # a specific device — see `flutter devices`
flutter analyze && flutter test
```

A physical Android device needs USB debugging enabled. `localhost` on a phone means the
_phone_, so to reach a backend on your machine pass its LAN address:
`./scripts/run.sh --dart-define=API_BASE_URL=http://<your-ip>:8000/v1`.

Auth talks to Supabase directly, so sign-in/sign-up work without the backend running;
only receipt upload needs it.

### Database

Migrations are plain SQL in `infra/supabase/migrations/`, applied in filename order and
written to be idempotent (safe to re-run):

```sh
psql "$SUPABASE_DB_URL" -f infra/supabase/migrations/<file>.sql
```

Verify them — and the RLS policies — against a throwaway Postgres before touching a real
project (requires Docker):

```sh
./infra/supabase/tests/run_tests.sh
```

### Pre-commit hooks

[prek](https://github.com/j178/prek) runs the gates on `git commit`
(`.pre-commit-config.yaml`). Install once per clone:

```sh
prek install
prek run --all-files   # to run them manually
```

## How it fits together

Authentication is **client-to-Supabase**: the app signs in against Supabase Auth and sends
the resulting JWT to the backend, which only _verifies_ it (ES256 via JWKS) — the backend
issues no credentials of its own. Row-level security is the ultimate authority on data
access, so every table is scoped to `auth.uid() = user_id`.

Uploads go to a **private** Storage bucket under `{user_id}/{receipt_id}/page_{n}.{ext}`;
stored paths are object keys, not public URLs. A receipt holds **1..N pages**, so a long
receipt can be photographed in several shots and appended to the same bill. Every endpoint
answers with the same envelope (`{ success, data, meta, error }`).

## Status

**Phase 1 — Foundation**, nearly complete. Working today, end-to-end:

- Sign up / log in / log out, with the session in the platform keystore and route guarding
- Scan a receipt (camera or gallery) → crop → compress → upload
- Add another page to an existing bill (multi-page receipts)

Not done yet: the offline upload-retry queue, the password-reset deep link, and OCR —
receipts land as `pending` and nothing parses them until Phase 2. See
[`DESIGN.md`](./DESIGN.md) for the current milestone, the next task, and known gaps.
