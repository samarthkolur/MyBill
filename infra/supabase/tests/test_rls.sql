-- RLS + auth-sync assertions. Run with `psql -v ON_ERROR_STOP=1` so any failing
-- assertion aborts the run with a non-zero exit code. Assumes harness.sql and all
-- migrations have already been applied to the target database.
--
-- Impersonation model (mirrors Supabase/PostgREST): within a transaction we
--   set local role authenticated;
--   set local request.jwt.claim.sub = '<user-uuid>';
-- so auth.uid() resolves to that user and RLS policies apply as they would in prod.

\set userA '11111111-1111-1111-1111-111111111111'
\set userB '22222222-2222-2222-2222-222222222222'

-- ===========================================================================
-- Test 1 — auth signup trigger auto-creates a matching public.users profile
-- ===========================================================================
insert into auth.users (id, email, raw_user_meta_data) values
  (:'userA', 'alice@example.com', '{"full_name": "Alice"}'::jsonb),
  (:'userB', 'bob@example.com',   '{}'::jsonb);

do $$
begin
  assert (select count(*) from public.users) = 2,
    'Test 1 FAILED: signup trigger did not create both profile rows';
  assert exists (
    select 1 from public.users
    where id = '11111111-1111-1111-1111-111111111111'
      and email = 'alice@example.com'
      and full_name = 'Alice'
  ), 'Test 1 FAILED: Alice profile missing or metadata not copied';
  raise notice 'Test 1 PASSED: auth signup trigger provisions public.users';
end $$;

-- ===========================================================================
-- Test 2 — RLS SELECT isolation: a user sees only their own profile row
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  begin
    assert (select count(*) from public.users) = 1,
      'Test 2 FAILED: authenticated user can see rows other than their own';
    assert (select id from public.users) = '11111111-1111-1111-1111-111111111111',
      'Test 2 FAILED: the single visible row is not the caller''s own';
    raise notice 'Test 2 PASSED: RLS SELECT isolates users to their own profile';
  end $$;
rollback;

-- ===========================================================================
-- Test 3 — RLS INSERT WITH CHECK: cannot create a profile for another user id
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  begin
    begin
      insert into public.users (id, email) values
        ('22222222-2222-2222-2222-222222222222', 'evil@example.com');
      raise exception 'Test 3 FAILED: insert for another user''s id was allowed';
    exception when insufficient_privilege then
      raise notice 'Test 3 PASSED: RLS blocks inserting a profile for another user';
    end;
  end $$;
rollback;

-- ===========================================================================
-- Test 4 — RLS UPDATE: a user cannot modify another user's profile row
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  declare
    affected int;
  begin
    -- The other user's row is invisible under RLS, so this update matches 0 rows.
    update public.users set currency = 'USD'
      where id = '22222222-2222-2222-2222-222222222222';
    get diagnostics affected = row_count;
    assert affected = 0,
      'Test 4 FAILED: update touched another user''s row';
    raise notice 'Test 4 PASSED: RLS prevents updating another user''s profile';
  end $$;
rollback;

-- ===========================================================================
-- Test 5 — Storage RLS: users can only write/read files under their own folder
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  begin
    -- Allowed: file under the caller's own {user_id}/ prefix.
    insert into storage.objects (bucket_id, name)
      values ('receipts', '11111111-1111-1111-1111-111111111111/r1/original.jpg');

    -- Blocked: file under another user's prefix.
    begin
      insert into storage.objects (bucket_id, name)
        values ('receipts', '22222222-2222-2222-2222-222222222222/r1/original.jpg');
      raise exception 'Test 5 FAILED: upload under another user''s folder was allowed';
    exception when insufficient_privilege then
      null;  -- expected
    end;

    assert (select count(*) from storage.objects) = 1,
      'Test 5 FAILED: caller sees storage objects other than their own';
    raise notice 'Test 5 PASSED: storage RLS scopes files to the owner''s folder';
  end $$;
rollback;

-- ===========================================================================
-- Test 6 — receipts RLS: a user can insert/see only their own receipts
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  begin
    -- Allowed: a receipt owned by the caller.
    insert into public.receipts (user_id, image_url)
      values ('11111111-1111-1111-1111-111111111111', 'receipts/a/r1/original.jpg');

    -- Blocked: a receipt owned by someone else.
    begin
      insert into public.receipts (user_id, image_url)
        values ('22222222-2222-2222-2222-222222222222', 'receipts/b/r1/original.jpg');
      raise exception 'Test 6 FAILED: inserting a receipt for another user was allowed';
    exception when insufficient_privilege then
      null;  -- expected
    end;

    assert (select count(*) from public.receipts) = 1,
      'Test 6 FAILED: caller sees receipts other than their own';
    assert (select status from public.receipts) = 'pending',
      'Test 6 FAILED: new receipt did not default to status=pending';
    raise notice 'Test 6 PASSED: receipts RLS + default status=pending';
  end $$;
rollback;

\echo '---------------------------------------------'
\echo 'All RLS / auth-sync assertions passed.'
\echo '---------------------------------------------'
