# Supabase — Schema, RLS & Storage

Database migrations, Row-Level Security policies, and Storage configuration for MyBill.
See [`../../MyBill.md`](../../MyBill.md) §4 (schema) and §11 (security) for the design intent.

## Layout

```
infra/supabase/
├── migrations/                         # Applied to real Supabase, in filename order
│   ├── 20260716090000_init_extensions_and_helpers.sql
│   ├── 20260716090100_create_users.sql          # users table + RLS + grants
│   ├── 20260716090200_auth_user_sync.sql        # auto-provision profile on signup
│   └── 20260716090300_receipts_storage.sql      # private bucket + owner-scoped policies
└── tests/                              # Local verification only — never applied to Supabase
    ├── harness.sql                     # stubs Supabase's auth/storage schemas for plain PG
    ├── test_rls.sql                    # RLS + auth-sync assertions
    └── run_tests.sh                    # spins throwaway Postgres, applies + asserts
```

Migrations reference Supabase-managed objects (`auth.users`, `auth.uid()`,
`storage.objects`, the `authenticated` role) and **do not** create them — Supabase already
provides them. The `tests/` harness stubs just enough of that surface so the same
migrations can be verified against a plain Postgres.

## Verify locally (no Supabase account needed)

Requires Docker + `psql`:

```bash
cd infra/supabase/tests
./run_tests.sh
```

This spins up a throwaway `postgres:16` container, applies the harness + every migration,
then asserts: the signup trigger provisions a profile, RLS isolates each user's profile on
SELECT/INSERT/UPDATE, and Storage policies scope files to the owner's folder. Any failure
exits non-zero.

## One-time Supabase project setup (manual — cloud console)

These steps create the actual cloud project and can't be scripted from here:

1. **Create the project** at <https://supabase.com/dashboard> → note the project ref.
2. **Auth:** Authentication → Providers → enable **Email**; enable **Google** for OAuth
   (MyBill.md §11). Configure the mobile redirect URL when the app exists (task 1.2.x).
3. **Grab credentials** (Project Settings → API) into `backend/.env`:
   - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
   - `SUPABASE_JWT_SECRET` (Project Settings → API → JWT Settings) — used by the FastAPI
     JWT-verification middleware (task 1.2.2).

## Applying migrations to Supabase

**Option A — Supabase CLI (recommended once adopted):**

```bash
supabase link --project-ref <your-ref>
supabase db push          # applies infra/supabase/migrations in order
```

> Note: the CLI expects migrations under `supabase/migrations/`. When we adopt the CLI
> (deferred — see DESIGN.md decision), either move this folder or symlink it. Until then,
> use Option B.

**Option B — SQL editor / psql (works today):** run each file in
`migrations/` in filename order against the project database (Dashboard → SQL Editor, or
`psql "$SUPABASE_DB_URL" -f <file>`). Files are idempotent — safe to re-run.

> **IPv4 gotcha — use the connection pooler, not the direct host.** Supabase's _direct_
> connection (`db.<ref>.supabase.co:5432`) is **IPv6-only**. From an IPv4-only network it
> fails with `Network is unreachable`. Use the **Supavisor Session pooler** connection
> string instead (Dashboard → Project Settings → Database → Connection string → _Session
> pooler_), which is IPv4-compatible:
> `postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`
> Session mode (port 5432) is required for DDL/migrations; transaction mode (6543) is for
> short-lived app queries.

## What these migrations establish

| Object                               | Purpose                                                                 |
| ------------------------------------ | ----------------------------------------------------------------------- |
| `public.users`                       | App profile, 1:1 with `auth.users`; RLS-restricted to `auth.uid() = id` |
| `public.set_updated_at()`            | Reusable trigger keeping `updated_at` fresh                             |
| `public.handle_new_user()` + trigger | Auto-creates a profile row on every Auth signup                         |
| `receipts` storage bucket            | **Private**; files laid out as `receipts/{user_id}/…`                   |
| Storage policies                     | Every op restricted to files under the caller's own `{user_id}/` folder |

## Conventions for future migrations

- **Filename:** `YYYYMMDDHHMMSS_snake_case_description.sql` (lexicographic = apply order).
- **Idempotent:** `create ... if not exists`, `drop policy if exists` before `create policy`,
  `on conflict do nothing` — so a file can be re-run safely.
- **RLS on every user-scoped table** (MyBill.md §11): `enable` + `force row level security`,
  policies scoped on `auth.uid() = user_id` (or `= id` for `users`).
- **Grant base privileges to `authenticated`** on new tables — RLS filters rows, but
  PostgREST still needs table-level SELECT/INSERT/UPDATE grants to reach them.
- Add a matching assertion to `tests/test_rls.sql` when a migration adds a policy.
