-- ═══════════════════════════════════════════════════════════════════
-- 04_cross_tenant_isolation.sql — tenant-isolation plan §(c) DB items
--
--   (1) RLS read isolation: A-member sees zero B rows.
--   (2) RLS write isolation: A-member cannot INSERT/UPDATE/DELETE B rows.
--   (3) tenant_id move attempt blocked (trg_prevent_tenant_id_change).
--   (4) user_accounts: plain members read nothing cross-tenant (029);
--       users.view holders can read (positive control).
--   (5) madrasas_member_select references qualified madrasas.id (030/SEC-H7).
--   (6) parameterized permission oracles revoked from authenticated (031).
--
-- RUN: psql "<staging-direct-url>" -v ON_ERROR_STOP=1 -f test/db/04_cross_tenant_isolation.sql
--      Wrapped in a transaction, rolled back at the end.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── fixtures ─────────────────────────────────────────────────────
INSERT INTO auth.users (id, aud, role, email, encrypted_password,
                       email_confirmed_at, created_at, updated_at,
                       raw_app_meta_data, raw_user_meta_data, is_super_admin)
VALUES
  ('a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1', 'authenticated', 'authenticated',
   'sec-parent-a@example.com', 'dummy', now(), now(), now(), '{}', '{}', false),
  ('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2', 'authenticated', 'authenticated',
   'sec-teacher-b@example.com', 'dummy', now(), now(), now(), '{}', '{}', false),
  ('c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3', 'authenticated', 'authenticated',
   'sec-hr-a@example.com', 'dummy', now(), now(), now(), '{}', '{}', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenants (id, name, slug) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SEC Test Tenant A', 'sec-test-a'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'SEC Test Tenant B', 'sec-test-b')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1', 'parent', true),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2', 'teacher', true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3', 'staff', true)
ON CONFLICT (user_id, tenant_id) DO NOTHING;

-- fixture HR user holds users.view (but nothing else)
INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect, reason)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       'c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3',
       p.id, 'grant', 'security test fixture'
FROM public.permissions p WHERE p.code = 'users.view'
ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;

-- one student per tenant (as superuser; RLS bypassed)
INSERT INTO public.students (id, tenant_id, roll_no, name, father_name) VALUES
  ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SEC-A-1', 'SEC Student A', 'SEC Father A'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'SEC-B-1', 'SEC Student B', 'SEC Father B')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_count INT;
  v_def TEXT;
BEGIN
  -- ── (1) read isolation ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
                       'role','authenticated')::text, true);
  SELECT count(*) INTO v_count FROM public.students
   WHERE tenant_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL (1): A-member read % B-tenant student rows', v_count;
  END IF;
  RAISE NOTICE 'PASS (1): RLS read isolation — zero B rows visible to A-member';
  RESET ROLE;

  -- ── (2) write isolation ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
                       'role','authenticated')::text, true);
  BEGIN
    INSERT INTO public.students (tenant_id, roll_no, name, father_name)
    VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'SEC-X', 'SEC X', 'SEC FX');
    RAISE EXCEPTION 'FAIL (2a): A-member inserted a B-tenant student';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS (2a): cross-tenant INSERT blocked by RLS';
  END;

  UPDATE public.students SET name = 'SEC Tampered'
   WHERE id = '22222222-2222-4222-8222-222222222222';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL (2b): A-member updated a B-tenant student';
  END IF;
  RAISE NOTICE 'PASS (2b): cross-tenant UPDATE affected 0 rows';

  DELETE FROM public.students
   WHERE id = '22222222-2222-4222-8222-222222222222';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL (2c): A-member deleted a B-tenant student';
  END IF;
  RAISE NOTICE 'PASS (2c): cross-tenant DELETE affected 0 rows';
  RESET ROLE;

  -- ── (3) tenant_id move attempt blocked ──
  -- (as superuser: trigger fires regardless of role)
  BEGIN
    UPDATE public.students SET tenant_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
     WHERE id = '11111111-1111-4111-8111-111111111111';
    RAISE EXCEPTION 'FAIL (3): tenant_id move was not blocked';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (3)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (3): tenant_id move blocked: %', SQLERRM;
  END;
  IF (SELECT tenant_id FROM public.students
      WHERE id = '11111111-1111-4111-8111-111111111111')
     <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' THEN
    RAISE EXCEPTION 'FAIL (3): student tenant_id changed despite trigger';
  END IF;

  -- ── (4) user_accounts scoping (029) ──
  -- plain member (no users.view): must read nothing
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
                       'role','authenticated')::text, true);
  SELECT count(*) INTO v_count FROM public.user_accounts;
  RESET ROLE;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FAIL (4a/SEC-H5): plain member read % user_accounts rows', v_count;
  END IF;
  RAISE NOTICE 'PASS (4a): user_accounts not readable by plain members';

  -- users.view holder: positive control (029 grants SELECT)
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3',
                       'role','authenticated')::text, true);
  BEGIN
    SELECT count(*) INTO v_count FROM public.user_accounts;
    RAISE NOTICE 'PASS (4b): users.view holder can read user_accounts (% rows)', v_count;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE EXCEPTION 'FAIL (4b): users.view holder blocked from user_accounts';
  END;
  RESET ROLE;

  -- ── (5) madrasas_member_select scoping (030/SEC-H7 static check) ──
  SELECT definition INTO v_def FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'madrasas'
     AND policyname = 'madrasas_member_select';
  IF v_def IS NULL THEN
    RAISE NOTICE 'SKIP (5): madrasas_member_select policy not found';
  ELSIF v_def NOT LIKE '%madrasas.id%' THEN
    RAISE EXCEPTION 'FAIL (5/SEC-H7): policy does not qualify madrasas.id — unqualified id binds to tenants.id';
  ELSE
    RAISE NOTICE 'PASS (5): madrasas_member_select qualifies madrasas.id';
  END IF;

  -- ── (6) permission oracles revoked from authenticated (031) ──
  IF to_regprocedure('public.user_effective_permission(uuid,uuid,text)') IS NULL THEN
    RAISE NOTICE 'SKIP (6): user_effective_permission(uuid,uuid,text) not found';
  ELSIF has_function_privilege('authenticated',
        'public.user_effective_permission(uuid,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL (6/SEC-M6): authenticated can still call user_effective_permission with arbitrary args';
  ELSE
    RAISE NOTICE 'PASS (6): parameterized permission helpers revoked from authenticated';
  END IF;
END $$;

ROLLBACK;
