-- ═══════════════════════════════════════════════════════════════════
-- 01_sync_apply_role_boundaries.sql — SEC-C1 / SEC-C3
--
-- Asserts the offline-sync RPC enforces the permission model
-- (migration 032: sync_required_permission + enforcement in sync_apply):
--   (a) sync_required_permission(entity, op) maps every whitelisted
--       entity/op to a verified code and DENIES (NULL) unknown
--       entities/ops — deny by default. The expected codes below are
--       copied from 032; any drift between the migration and this
--       script is itself a FAIL.
--   (b) BEHAVIORAL: a tenant member WITHOUT the mapped code gets ok=false
--       from sync_apply (fails on pre-032 code — expected canary).
--   (c) Cross-tenant write via sync_apply is rejected (membership check).
--
-- RUN: psql "<staging-direct-url>" -v ON_ERROR_STOP=1 -f test/db/01_sync_apply_role_boundaries.sql
--      (use the postgres superuser / service_role connection string, NOT the
--      anon key — fixtures need auth.users writes; everything is wrapped in
--      a transaction and ROLLED BACK at the end, so staging is untouched.)
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
   'sec-teacher-b@example.com', 'dummy', now(), now(), now(), '{}', '{}', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenants (id, name, slug) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SEC Test Tenant A', 'sec-test-a'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'SEC Test Tenant B', 'sec-test-b')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1', 'parent', true),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2', 'teacher', true)
ON CONFLICT (user_id, tenant_id) DO NOTHING;

-- Belt-and-braces: the fixture parent must NOT hold fees.collect even if a
-- template grants it (deny > grant precedence per 020).
INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect, reason)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
       p.id, 'deny', 'security test fixture'
FROM public.permissions p WHERE p.code = 'fees.collect'
ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;

-- ── (a) contract: sync_required_permission deny-by-default ─────────
DO $$
DECLARE
  v_entities TEXT[] := ARRAY[
    'darjas','classes','students','staff','attendance','fees','exams',
    'results','announcements','darja_sections','library_books','book_issues',
    'finance_transactions','accounts','fee_structures','fee_items',
    'invoices','invoice_items','payments','payment_allocations','refunds',
    'discounts','scholarships','expenses','income','transactions'];
  v_e TEXT; v_o TEXT; v_code TEXT;
BEGIN
  IF to_regprocedure('public.sync_required_permission(text,text)') IS NULL THEN
    RAISE NOTICE 'SKIP (a): sync_required_permission() not deployed — migration 032 pending';
    RETURN;
  END IF;

  -- unknown entity / op → NULL (deny)
  IF public.sync_required_permission('platform_admins','insert') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: must deny platform_admins/insert';
  END IF;
  IF public.sync_required_permission('tenant_memberships','update') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: must deny tenant_memberships/update';
  END IF;
  IF public.sync_required_permission('students','upsert') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: must deny unknown op';
  END IF;
  IF public.sync_required_permission('','insert') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: must deny empty entity';
  END IF;

  -- every whitelisted entity maps every op
  FOREACH v_e IN ARRAY v_entities LOOP
    FOREACH v_o IN ARRAY ARRAY['insert','update','delete'] LOOP
      v_code := public.sync_required_permission(v_e, v_o);
      IF v_code IS NULL THEN
        RAISE EXCEPTION 'FAIL: %/% has no mapped permission code', v_e, v_o;
      END IF;
    END LOOP;
  END LOOP;

  -- spot checks against the 032 map (drift = FAIL)
  IF public.sync_required_permission('payments','insert') <> 'fees.collect' THEN
    RAISE EXCEPTION 'FAIL: payments/insert should require fees.collect';
  END IF;
  IF public.sync_required_permission('payments','delete') <> 'fees.delete' THEN
    RAISE EXCEPTION 'FAIL: payments/delete should require fees.delete';
  END IF;
  IF public.sync_required_permission('results','insert') <> 'results.enter' THEN
    RAISE EXCEPTION 'FAIL: results/insert should require results.enter';
  END IF;
  IF public.sync_required_permission('results','update') <> 'results.edit' THEN
    RAISE EXCEPTION 'FAIL: results/update should require results.edit';
  END IF;
  IF public.sync_required_permission('announcements','delete') <> 'announcements.send' THEN
    RAISE EXCEPTION 'FAIL: announcements/delete should require announcements.send';
  END IF;
  IF public.sync_required_permission('fee_structures','update') <> 'fees.create' THEN
    RAISE EXCEPTION 'FAIL: fee_structures/update should require fees.create';
  END IF;
  RAISE NOTICE 'PASS (a): sync_required_permission deny-by-default contract';
END $$;

-- ── (b) behavioral: parent without fees.collect → denied ───────────
-- 032 returns ok:false + reason (never an exception, so the client marks
-- the op failed instead of retrying). Both denial styles accepted.
DO $$
DECLARE
  v_res JSONB;
  v_denied BOOLEAN := false;
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
                       'role','authenticated')::text, true);

  BEGIN
    v_res := public.sync_apply(
      'payments', gen_random_uuid(), 0,
      jsonb_build_object('tenant_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                         'amount', 5000, 'method', 'cash', 'status', 'draft'),
      'insert');
    v_denied := (v_res->>'ok')::boolean IS DISTINCT FROM false;
  EXCEPTION WHEN OTHERS THEN
    v_denied := true;
    RAISE NOTICE 'denied via exception (acceptable): %', SQLERRM;
  END;

  IF NOT v_denied THEN
    RAISE EXCEPTION 'CANARY FAIL (SEC-C1): parent without fees.collect wrote a payment: %', v_res;
  END IF;
  RAISE NOTICE 'PASS (b): sync_apply denied the unpermitted payment write';
END $$;

-- ── (b2) unknown op on a known entity fails closed with a reason ───
DO $$
DECLARE
  v_res JSONB;
BEGIN
  IF to_regprocedure('public.sync_required_permission(text,text)') IS NULL THEN
    RAISE NOTICE 'SKIP (b2): migration 032 pending';
    RETURN;
  END IF;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
                       'role','authenticated')::text, true);
  -- known entity, unknown op: whitelist CASE passes, permission map
  -- returns NULL → ok:false + reason (never an exception).
  v_res := public.sync_apply(
    'students', gen_random_uuid(), 0, '{}'::jsonb, 'upsert');
  IF (v_res->>'ok')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL (b2): unknown op did not fail closed: %', v_res;
  END IF;
  IF (v_res->>'reason') <> 'forbidden:unknown_entity_or_op' THEN
    RAISE EXCEPTION 'FAIL (b2): unexpected reason: %', v_res;
  END IF;
  RAISE NOTICE 'PASS (b2): unknown op fails closed with reason';
END $$;

-- ── (c) cross-tenant write rejected ────────────────────────────────
DO $$
DECLARE
  v_res JSONB;
  v_row_id UUID := gen_random_uuid();
  v_denied BOOLEAN := false;
BEGIN
  -- seed a payment in tenant B directly (bypasses RLS as superuser)
  INSERT INTO public.payments (id, tenant_id, amount, method, status)
  VALUES (v_row_id, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 100, 'cash', 'draft');

  -- tenant-A parent tries to update tenant-B's payment via sync
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1',
                       'role','authenticated')::text, true);

  BEGIN
    v_res := public.sync_apply(
      'payments', v_row_id, 1,
      jsonb_build_object('amount', 99999),
      'update');
    v_denied := (v_res->>'ok')::boolean IS DISTINCT FROM false;
  EXCEPTION WHEN OTHERS THEN
    v_denied := true; -- membership exception: acceptable
    RAISE NOTICE 'denied via exception (acceptable): %', SQLERRM;
  END;

  IF NOT v_denied THEN
    RAISE EXCEPTION 'FAIL (cross-tenant): A-parent updated B payment: %', v_res;
  END IF;
  IF (SELECT amount FROM public.payments WHERE id = v_row_id) <> 100 THEN
    RAISE EXCEPTION 'FAIL (cross-tenant): B payment was modified';
  END IF;
  RAISE NOTICE 'PASS (c): cross-tenant sync write rejected, row unchanged';
END $$;

ROLLBACK;
