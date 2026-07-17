-- Migration: receipt_images — a receipt holds many pages
-- Phase 1 · multi-page receipts (DESIGN.md decision 24)
--
-- Until now a receipt was exactly one image: `receipts.image_url` was a single NOT NULL
-- column and storage held one object per receipt. Real grocery receipts are often longer
-- than one photograph, so a receipt becomes 1 → N images and the user can add a page to
-- an existing bill instead of creating a second, unrelated one.
--
-- `receipt_images` becomes the source of truth for a receipt's pages. `receipts.image_url`
-- is backfilled into it as page 1 and then made NULLABLE, kept only so anything still
-- reading it (and any rollback) doesn't break — new code must not write it. It is dropped
-- in a later migration once nothing references it.
--
-- `user_id` is denormalised onto this table on purpose: RLS policies must be checkable
-- without a join back to `receipts`, and storage paths are keyed by owner.

-- ---------------------------------------------------------------------------
-- receipt_images
-- ---------------------------------------------------------------------------
create table if not exists public.receipt_images (
  id          uuid primary key default gen_random_uuid(),
  receipt_id  uuid not null references public.receipts (id) on delete cascade,
  user_id     uuid not null references public.users (id) on delete cascade,
  image_url   text not null,              -- Supabase Storage object key, not a URL
  page_number int  not null,
  created_at  timestamptz not null default now(),
  -- Two pages of the same bill can't claim the same position; this also makes an
  -- accidental double-upload of the same page fail loudly rather than duplicate silently.
  unique (receipt_id, page_number),
  constraint receipt_images_page_number_positive check (page_number > 0)
);

comment on table public.receipt_images is
  'Pages of an uploaded receipt (1 → N). Source of truth for receipt imagery. MyBill.md §4.';
comment on column public.receipt_images.user_id is
  'Denormalised from receipts so RLS and storage paths need no join.';

-- Pages of one receipt, in order — the read pattern for the viewer and for OCR.
create index if not exists receipt_images_receipt_id_page_idx
  on public.receipt_images (receipt_id, page_number);
create index if not exists receipt_images_user_id_idx
  on public.receipt_images (user_id);

-- ---------------------------------------------------------------------------
-- Backfill existing single-image receipts as page 1
-- ---------------------------------------------------------------------------
-- Idempotent: `on conflict do nothing` against the (receipt_id, page_number) unique key,
-- so re-running this migration can't duplicate page 1.
insert into public.receipt_images (receipt_id, user_id, image_url, page_number)
select r.id, r.user_id, r.image_url, 1
from public.receipts r
where r.image_url is not null
on conflict (receipt_id, page_number) do nothing;

-- Now that every image lives in receipt_images, the old column must stop being required.
-- Kept (nullable) rather than dropped so a rollback still has its data and any straggling
-- reader keeps working; dropped in a follow-up once nothing references it.
alter table public.receipts alter column image_url drop not null;

comment on column public.receipts.image_url is
  'DEPRECATED — superseded by public.receipt_images. Retained nullable for rollback; do not write.';

-- ---------------------------------------------------------------------------
-- Grants + Row-Level Security (scoped to auth.uid() = user_id, as every other table)
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on public.receipt_images to authenticated;

alter table public.receipt_images enable row level security;
alter table public.receipt_images force row level security;

drop policy if exists "Users manage own receipt images" on public.receipt_images;
create policy "Users manage own receipt images"
  on public.receipt_images for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
