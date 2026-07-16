-- Migration: auto-provision public.users on Supabase Auth signup
-- Phase 1 · task 1.1.4 (also fulfils the DB half of task 1.2.3 — user profile sync)
--
-- When Supabase Auth creates a new identity (email signup or OAuth), a matching profile
-- row must appear in public.users. Doing this with a database trigger — rather than in
-- the FastAPI layer — means the invariant "every auth user has a profile" holds no
-- matter which client created the account, and can never be skipped by an app bug.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
-- SECURITY DEFINER: runs as the function owner so it can insert into public.users
-- regardless of the (minimal) privileges of the auth subsystem's role.
security definer
-- Pin search_path to avoid any privilege-escalation via a hijacked search_path
-- (standard hardening for SECURITY DEFINER functions).
set search_path = public
as $$
begin
  insert into public.users (id, email, full_name)
  values (
    new.id,
    new.email,
    -- Supabase stores OAuth/display metadata in raw_user_meta_data; use it when present.
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
  )
  on conflict (id) do nothing;  -- idempotent: never fail a signup on a duplicate
  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Creates a public.users profile row whenever a new auth.users identity is inserted.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
