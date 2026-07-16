-- Migration: private "receipts" storage bucket + owner-scoped access policies
-- Phase 1 · task 1.1.4
--
-- Receipt images (originals + enhanced) live in Supabase Storage, never in a public
-- bucket (MyBill.md §11: "Image URLs are signed ... not publicly accessible"). Files are
-- laid out as  receipts/{user_id}/{receipt_id}/{filename}  so the first path segment is
-- always the owner's id. The policies below restrict every operation to files whose
-- first folder equals the caller's auth.uid().

-- Private bucket (public = false → only signed URLs / RLS-authorised access).
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

-- storage.foldername(name) returns the path segments as text[]; [1] is the top folder,
-- which our upload convention sets to the owning user's id.
drop policy if exists "Users read own receipt images"   on storage.objects;
drop policy if exists "Users upload own receipt images"  on storage.objects;
drop policy if exists "Users update own receipt images"  on storage.objects;
drop policy if exists "Users delete own receipt images"  on storage.objects;

create policy "Users read own receipt images"
  on storage.objects for select
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users upload own receipt images"
  on storage.objects for insert
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users update own receipt images"
  on storage.objects for update
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users delete own receipt images"
  on storage.objects for delete
  using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
