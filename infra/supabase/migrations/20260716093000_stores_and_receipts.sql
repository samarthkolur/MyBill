-- Migration: stores + receipts tables (upload target for the pending-receipt flow)
-- Phase 1 · tasks 1.3.3 / 1.3.4
--
-- `receipts` is the row created at upload time with status = 'pending' (MyBill.md §2 data
-- flow); the OCR pipeline (Phase 2) later fills store, date, totals, and line items.
-- `stores` is created here so receipts.store_id can reference it (assigned during parsing).
--
-- DEVIATION from MyBill.md §4: `receipts.date` and `receipts.total` are NULLABLE here.
-- The spec marks them NOT NULL, but a freshly-uploaded pending receipt has no parsed date
-- or total yet — those are populated when OCR completes. Enforcing NOT NULL would make the
-- upload → pending → parse flow impossible. They are expected non-null once status='done'.

-- ---------------------------------------------------------------------------
-- stores
-- ---------------------------------------------------------------------------
create table if not exists public.stores (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users (id) on delete cascade,
  name         text not null,
  name_aliases text[],
  address      text,
  city         text,
  chain_name   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (user_id, name)
);

comment on table public.stores is 'Per-user grocery stores/chains. MyBill.md §4.';

create index if not exists stores_user_id_idx on public.stores (user_id);

drop trigger if exists set_updated_at on public.stores;
create trigger set_updated_at
  before update on public.stores
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- receipts
-- ---------------------------------------------------------------------------
create table if not exists public.receipts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.users (id) on delete cascade,
  store_id       uuid references public.stores (id) on delete set null,
  date           date,                       -- nullable until OCR (see header note)
  time           time,
  total          numeric(10, 2),             -- nullable until OCR (see header note)
  tax            numeric(10, 2) default 0,
  discount       numeric(10, 2) default 0,
  payment_method text,
  image_url      text not null,              -- Supabase Storage path (original)
  ocr_json_url   text,
  canonical_json jsonb,
  status         text not null default 'pending'
    check (status in ('pending', 'processing', 'done', 'failed')),
  ocr_confidence numeric(4, 3),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.receipts is
  'Uploaded receipts. Created as status=pending; OCR fills the rest. MyBill.md §4.';

-- Common access patterns: a user's receipts newest-first, and polling by status.
create index if not exists receipts_user_id_date_idx
  on public.receipts (user_id, date desc);
create index if not exists receipts_user_id_status_idx
  on public.receipts (user_id, status);

drop trigger if exists set_updated_at on public.receipts;
create trigger set_updated_at
  before update on public.receipts
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Grants + Row-Level Security (both tables scoped to auth.uid() = user_id)
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on public.stores to authenticated;
grant select, insert, update, delete on public.receipts to authenticated;

alter table public.stores enable row level security;
alter table public.stores force row level security;
alter table public.receipts enable row level security;
alter table public.receipts force row level security;

-- stores policies
drop policy if exists "Users manage own stores" on public.stores;
create policy "Users manage own stores"
  on public.stores for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- receipts policies
drop policy if exists "Users manage own receipts" on public.receipts;
create policy "Users manage own receipts"
  on public.receipts for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
