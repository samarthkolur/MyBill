-- Migration: create public.users (user profile) + Row-Level Security
-- Phase 1 · task 1.1.4
--
-- The application-level profile row, one-to-one with a Supabase Auth identity
-- (auth.users). Auth itself (credentials, sessions, OAuth) is owned by Supabase; this
-- table holds the app's own per-user data (display name, currency, timezone).
--
-- RLS (MyBill.md §11): a user may only ever see or mutate their own profile row. The
-- primary key IS the auth user id, so every policy is scoped on `auth.uid() = id`.

create table if not exists public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null unique,
  full_name   text,
  currency    text not null default 'INR',
  timezone    text not null default 'Asia/Kolkata',
  created_at  timestamptz not null default now(),
  -- Not in the MyBill.md §4 users example, but §4's preamble states all tables carry
  -- updated_at unless noted; profile fields (currency/timezone) are user-editable, so
  -- tracking last-modified is worth the column.
  updated_at  timestamptz not null default now()
);

comment on table public.users is
  'Application user profile, 1:1 with auth.users. MyBill.md §4.';

-- Keep updated_at fresh on profile edits.
drop trigger if exists set_updated_at on public.users;
create trigger set_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- PostgREST executes client requests as the `authenticated` role, so it needs base
-- table privileges; RLS (below) is what actually restricts *which rows* it may touch.
-- No DELETE — profile rows are removed only via auth.users cascade (see note below).
grant select, insert, update on public.users to authenticated;

-- ---------------------------------------------------------------------------
-- Row-Level Security
-- ---------------------------------------------------------------------------
alter table public.users enable row level security;
-- Enforce RLS even for the table owner so no code path accidentally bypasses it.
alter table public.users force row level security;

-- Idempotent re-create: drop any prior policy of the same name first.
drop policy if exists "Users can view own profile"   on public.users;
drop policy if exists "Users can insert own profile" on public.users;
drop policy if exists "Users can update own profile" on public.users;

create policy "Users can view own profile"
  on public.users for select
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.users for insert
  with check (auth.uid() = id);

create policy "Users can update own profile"
  on public.users for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Note: no DELETE policy. Profile rows are removed only via ON DELETE CASCADE when the
-- underlying auth.users identity is deleted (account deletion), never by the user
-- directly. Account deletion is a service-role operation (Phase 6+).
