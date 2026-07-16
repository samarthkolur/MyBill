-- Local test harness — NOT a migration, never applied to real Supabase.
--
-- Supabase provides the `auth` and `storage` schemas, the `auth.uid()` function, and the
-- `authenticated` / `anon` / `service_role` roles out of the box. A plain Postgres does
-- not, so this file stubs just enough of that surface for the production migrations to
-- apply and for RLS to be exercised realistically against a throwaway database.
--
-- The stubs mirror Supabase's real behaviour: auth.uid() reads the JWT `sub` claim from
-- the `request.jwt.claim.sub` GUC exactly as Supabase's own definition does, so tests can
-- impersonate a user with:  set local request.jwt.claim.sub = '<uuid>';

-- ---- Roles (Supabase's PostgREST roles) ----
do $$
begin
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;

-- ---- auth schema ----
create schema if not exists auth;

create table if not exists auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               text unique,
  raw_user_meta_data  jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now()
);

-- Faithful reproduction of Supabase's auth.uid(): pull `sub` from the request JWT claims.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- ---- storage schema ----
create schema if not exists storage;

create table if not exists storage.buckets (
  id      text primary key,
  name    text not null,
  public  boolean not null default false
);

create table if not exists storage.objects (
  id          uuid primary key default gen_random_uuid(),
  bucket_id   text references storage.buckets (id),
  name        text not null,
  owner       uuid,
  created_at  timestamptz not null default now()
);

-- Real Supabase ships storage.objects with RLS already enabled; our migration only adds
-- policies. Enable it here so the harness reflects that baseline.
alter table storage.objects enable row level security;

-- Supabase's helper: split an object path into its folder segments.
create or replace function storage.foldername(name text)
returns text[]
language sql
immutable
as $$
  -- Drop the final segment (the filename); return the folder path segments.
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1];
$$;

-- Schema usage + privileges on the harness-owned storage tables. (Real Supabase already
-- grants these to the authenticated role; here we stub them.) Grants on public.users
-- live in that table's own migration — production-correct, so not duplicated here.
grant usage on schema public, storage to authenticated, anon;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;
