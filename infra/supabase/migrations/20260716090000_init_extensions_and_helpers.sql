-- Migration: init extensions and shared helpers
-- Phase 1 · task 1.1.4
--
-- Idempotent bootstrap shared by every later migration. Runs first (lexicographic
-- timestamp order). Creates the pgcrypto extension (gen_random_uuid) and a reusable
-- trigger function that maintains `updated_at` on any table that opts in.

-- gen_random_uuid() is core in Postgres 13+, but Supabase conventionally enables
-- pgcrypto; keep it explicit so the schema is self-describing and portable.
create extension if not exists pgcrypto;

-- Reusable BEFORE UPDATE trigger: stamps updated_at = now() on every row update.
-- Tables attach this with:  create trigger set_updated_at before update on <t>
--   for each row execute function public.set_updated_at();
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Generic trigger to keep updated_at current on row UPDATE. MyBill.md §4.';
