-- Migration: categories + receipt_items + price_history (the OCR pipeline's write targets)
-- Phase 2 · OCR Pipeline
--
-- `receipts` is created at upload as status=pending holding only images. This adds what the
-- parser fills in: the line items, and a per-item price observation used later for price
-- trends (MyBill.md §4, §9).
--
-- `categories` is global reference data, not per-user: "Dairy" means the same thing for
-- everyone, and per-user copies would make cross-user analytics and category seeding
-- pointless work. It is therefore readable by every authenticated user and writable by
-- none of them — only migrations and the service role change it. That's why it has no
-- user_id and no owner policy, unlike every other table here.

-- ---------------------------------------------------------------------------
-- categories (global reference data)
-- ---------------------------------------------------------------------------
create table if not exists public.categories (
  id        uuid primary key default gen_random_uuid(),
  name      text not null unique,
  icon      text,
  color_hex text
);

comment on table public.categories is
  'Global grocery categories (reference data, not per-user). MyBill.md §4.';

-- Seed the 10 categories from MyBill.md §13 (Phase 2). Idempotent: name is unique, so a
-- re-run updates the icon/colour rather than erroring or duplicating.
insert into public.categories (name, icon, color_hex) values
  ('Dairy',      'egg_alt',        '#4FC3F7'),
  ('Produce',    'eco',            '#66BB6A'),
  ('Bakery',     'bakery_dining',  '#D4A574'),
  ('Meat',       'set_meal',       '#EF5350'),
  ('Beverages',  'local_cafe',     '#26A69A'),
  ('Snacks',     'cookie',         '#FFA726'),
  ('Staples',    'rice_bowl',      '#8D6E63'),
  ('Household',  'cleaning_services', '#7E57C2'),
  ('Personal Care', 'soap',        '#EC407A'),
  ('Other',      'shopping_basket', '#78909C')
on conflict (name) do update
  set icon = excluded.icon, color_hex = excluded.color_hex;

-- ---------------------------------------------------------------------------
-- receipt_items
-- ---------------------------------------------------------------------------
create table if not exists public.receipt_items (
  id              uuid primary key default gen_random_uuid(),
  receipt_id      uuid not null references public.receipts (id) on delete cascade,
  user_id         uuid not null references public.users (id) on delete cascade,
  name            text not null,              -- as printed on the receipt
  name_normalised text not null,              -- lowercased/stripped, for matching
  brand           text,
  category_id     uuid references public.categories (id) on delete set null,
  quantity        numeric(8, 3) not null default 1,
  unit            text,                       -- kg, g, L, ml, pcs
  unit_price      numeric(10, 2) not null,
  total_price     numeric(10, 2) not null,
  ocr_confidence  numeric(4, 3),
  created_at      timestamptz not null default now(),
  -- A parsed line with a negative price is a parse failure, not a purchase. Zero is
  -- allowed: free items and promotional lines legitimately print as 0.00.
  constraint receipt_items_prices_non_negative
    check (unit_price >= 0 and total_price >= 0),
  constraint receipt_items_quantity_positive check (quantity > 0)
);

comment on table public.receipt_items is
  'Line items parsed from a receipt by the OCR pipeline. MyBill.md §4.';
comment on column public.receipt_items.name_normalised is
  'Lowercased/stripped name — the join key for price history and cross-store matching.';

-- Items of one receipt (the bill detail view), and a user's purchases of one product
-- over time (price trends).
create index if not exists receipt_items_receipt_id_idx
  on public.receipt_items (receipt_id);
create index if not exists receipt_items_user_name_idx
  on public.receipt_items (user_id, name_normalised);
create index if not exists receipt_items_category_idx
  on public.receipt_items (user_id, category_id);

-- ---------------------------------------------------------------------------
-- price_history
-- ---------------------------------------------------------------------------
-- One row per item per receipt: what this user paid for this product, at this store, on
-- this date. Denormalised from receipt_items on purpose — it is written once and read by
-- range scans over (user, product, date), and joining back through receipts for every
-- trend query would be the wrong shape.
create table if not exists public.price_history (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users (id) on delete cascade,
  name_normalised text not null,
  store_id        uuid references public.stores (id) on delete set null,
  unit_price      numeric(10, 2) not null,
  quantity        numeric(8, 3),
  unit            text,
  receipt_id      uuid references public.receipts (id) on delete cascade,
  date            date not null,
  created_at      timestamptz not null default now(),
  constraint price_history_unit_price_non_negative check (unit_price >= 0)
);

comment on table public.price_history is
  'Per-item price observations for trend analysis. MyBill.md §4/§9.';
comment on column public.price_history.date is
  'Purchase date. Falls back to the receipt upload date when OCR found none — a trend '
  'needs a point on the time axis, and upload day is the best available estimate.';

-- The one query this table exists for: this user's prices for this product over time.
create index if not exists price_history_user_name_date_idx
  on public.price_history (user_id, name_normalised, date);
create index if not exists price_history_receipt_idx
  on public.price_history (receipt_id);

-- ---------------------------------------------------------------------------
-- Grants + Row-Level Security
-- ---------------------------------------------------------------------------
-- categories: readable by all authenticated users, writable by none (reference data).
grant select on public.categories to authenticated;
alter table public.categories enable row level security;
alter table public.categories force row level security;

drop policy if exists "Categories are readable by authenticated users" on public.categories;
create policy "Categories are readable by authenticated users"
  on public.categories for select
  using (true);

-- receipt_items + price_history: owner-scoped like everything else.
grant select, insert, update, delete on public.receipt_items to authenticated;
grant select, insert, update, delete on public.price_history to authenticated;

alter table public.receipt_items enable row level security;
alter table public.receipt_items force row level security;
alter table public.price_history enable row level security;
alter table public.price_history force row level security;

drop policy if exists "Users manage own receipt items" on public.receipt_items;
create policy "Users manage own receipt items"
  on public.receipt_items for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users manage own price history" on public.price_history;
create policy "Users manage own price history"
  on public.price_history for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
