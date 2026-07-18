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

-- ===========================================================================
-- Test 7: receipt_images RLS + page numbering constraints
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  declare
    v_receipt_id uuid;
  begin
    insert into public.receipts (user_id)
      values ('11111111-1111-1111-1111-111111111111')
      returning id into v_receipt_id;

    -- Allowed: pages on the caller's own receipt.
    insert into public.receipt_images (receipt_id, user_id, image_url, page_number)
      values (v_receipt_id, '11111111-1111-1111-1111-111111111111', 'a/r1/page_1.jpg', 1);
    insert into public.receipt_images (receipt_id, user_id, image_url, page_number)
      values (v_receipt_id, '11111111-1111-1111-1111-111111111111', 'a/r1/page_2.jpg', 2);

    -- Blocked: attributing a page to another user.
    begin
      insert into public.receipt_images (receipt_id, user_id, image_url, page_number)
        values (v_receipt_id, '22222222-2222-2222-2222-222222222222', 'b/r1/page_1.jpg', 3);
      raise exception 'Test 7 FAILED: inserting a receipt image for another user was allowed';
    exception when insufficient_privilege then
      null;  -- expected
    end;

    -- Blocked: two pages claiming the same position in one receipt.
    begin
      insert into public.receipt_images (receipt_id, user_id, image_url, page_number)
        values (v_receipt_id, '11111111-1111-1111-1111-111111111111', 'a/r1/dupe.jpg', 2);
      raise exception 'Test 7 FAILED: duplicate page_number was allowed';
    exception when unique_violation then
      null;  -- expected
    end;

    -- Blocked: page numbers start at 1.
    begin
      insert into public.receipt_images (receipt_id, user_id, image_url, page_number)
        values (v_receipt_id, '11111111-1111-1111-1111-111111111111', 'a/r1/zero.jpg', 0);
      raise exception 'Test 7 FAILED: page_number = 0 was allowed';
    exception when check_violation then
      null;  -- expected
    end;

    assert (select count(*) from public.receipt_images) = 2,
      'Test 7 FAILED: caller sees receipt images other than their own';

    -- Deleting the receipt cascades to its pages, so no orphan rows survive.
    delete from public.receipts where id = v_receipt_id;
    assert (select count(*) from public.receipt_images where receipt_id = v_receipt_id) = 0,
      'Test 7 FAILED: receipt images were not cascaded on receipt delete';

    raise notice 'Test 7 PASSED: receipt_images RLS + page constraints + cascade';
  end $$;
rollback;

-- ===========================================================================
-- Test 8 — categories: global reference data, readable by all, writable by none
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  begin
    -- Readable: the migration seeds 10 categories, visible to every authenticated user
    -- (no user_id, no owner policy — it is shared reference data).
    assert (select count(*) from public.categories) = 10,
      'Test 8 FAILED: the 10 seeded categories are not all readable';

    -- Writable by none: authenticated has SELECT only, so a write is a privilege error,
    -- not an RLS row miss.
    begin
      insert into public.categories (name) values ('Contraband');
      raise exception 'Test 8 FAILED: authenticated user was allowed to insert a category';
    exception when insufficient_privilege then
      null;  -- expected
    end;

    raise notice 'Test 8 PASSED: categories are readable by all, writable by none';
  end $$;
rollback;

-- ===========================================================================
-- Test 9 — receipt_items: owner RLS + price/quantity checks + cascade on delete
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  declare
    v_receipt_id uuid;
  begin
    insert into public.receipts (user_id)
      values ('11111111-1111-1111-1111-111111111111')
      returning id into v_receipt_id;

    -- Allowed: a line item on the caller's own receipt. A 0.00 total is legitimate
    -- (free/promotional lines), so it must be accepted.
    insert into public.receipt_items
      (receipt_id, user_id, name, name_normalised, quantity, unit_price, total_price)
      values (v_receipt_id, '11111111-1111-1111-1111-111111111111',
              'AMUL MILK 1L', 'amul milk 1l', 1, 66.00, 66.00);
    insert into public.receipt_items
      (receipt_id, user_id, name, name_normalised, quantity, unit_price, total_price)
      values (v_receipt_id, '11111111-1111-1111-1111-111111111111',
              'FREE SAMPLE', 'free sample', 1, 0.00, 0.00);

    -- Blocked: attributing an item to another user.
    begin
      insert into public.receipt_items
        (receipt_id, user_id, name, name_normalised, quantity, unit_price, total_price)
        values (v_receipt_id, '22222222-2222-2222-2222-222222222222',
                'STOLEN', 'stolen', 1, 1.00, 1.00);
      raise exception 'Test 9 FAILED: inserting a receipt item for another user was allowed';
    exception when insufficient_privilege then
      null;  -- expected
    end;

    -- Blocked: a negative price is a parse failure, not a purchase.
    begin
      insert into public.receipt_items
        (receipt_id, user_id, name, name_normalised, quantity, unit_price, total_price)
        values (v_receipt_id, '11111111-1111-1111-1111-111111111111',
                'GLITCH', 'glitch', 1, -1.00, -1.00);
      raise exception 'Test 9 FAILED: a negative price was allowed';
    exception when check_violation then
      null;  -- expected
    end;

    -- Blocked: a non-positive quantity.
    begin
      insert into public.receipt_items
        (receipt_id, user_id, name, name_normalised, quantity, unit_price, total_price)
        values (v_receipt_id, '11111111-1111-1111-1111-111111111111',
                'ZERO QTY', 'zero qty', 0, 1.00, 0.00);
      raise exception 'Test 9 FAILED: a zero quantity was allowed';
    exception when check_violation then
      null;  -- expected
    end;

    assert (select count(*) from public.receipt_items) = 2,
      'Test 9 FAILED: caller sees receipt items other than their own';

    -- Deleting the receipt cascades to its items, so no orphan rows survive.
    delete from public.receipts where id = v_receipt_id;
    assert (select count(*) from public.receipt_items where receipt_id = v_receipt_id) = 0,
      'Test 9 FAILED: receipt items were not cascaded on receipt delete';

    raise notice 'Test 9 PASSED: receipt_items RLS + price/quantity checks + cascade';
  end $$;
rollback;

-- ===========================================================================
-- Test 10 — price_history: owner RLS + non-negative price check
-- ===========================================================================
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  do $$
  begin
    -- Allowed: a price observation owned by the caller.
    insert into public.price_history (user_id, name_normalised, unit_price, date)
      values ('11111111-1111-1111-1111-111111111111', 'amul milk 1l', 66.00, current_date);

    -- Blocked: a price observation attributed to another user.
    begin
      insert into public.price_history (user_id, name_normalised, unit_price, date)
        values ('22222222-2222-2222-2222-222222222222', 'amul milk 1l', 66.00, current_date);
      raise exception 'Test 10 FAILED: inserting price history for another user was allowed';
    exception when insufficient_privilege then
      null;  -- expected
    end;

    -- Blocked: a negative price.
    begin
      insert into public.price_history (user_id, name_normalised, unit_price, date)
        values ('11111111-1111-1111-1111-111111111111', 'glitch', -1.00, current_date);
      raise exception 'Test 10 FAILED: a negative price was allowed';
    exception when check_violation then
      null;  -- expected
    end;

    assert (select count(*) from public.price_history) = 1,
      'Test 10 FAILED: caller sees price history other than their own';

    raise notice 'Test 10 PASSED: price_history RLS + non-negative price check';
  end $$;
rollback;

\echo '---------------------------------------------'
\echo 'All RLS / auth-sync assertions passed.'
\echo '---------------------------------------------'
