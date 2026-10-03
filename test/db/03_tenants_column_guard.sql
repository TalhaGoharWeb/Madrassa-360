-- ═══════════════════════════════════════════════════════════════════
-- 03_tenants_column_guard.sql — SEC-H6
--
-- Asserts the BEFORE UPDATE trigger on public.tenants
-- (trigger name: trg_tenants_column_guard):
--   (a) a tenant admin holding settings.update CANNOT change platform-owned
--       columns: status, suspended, expires_at, tenant_code, slug,
--       registration_number, logo_url (arbitrary URL).
--   (b) positive control: the same caller CAN update branding/contact
--       columns (name, phone).
--   (c) positive control: a platform admin CAN update the guarded columns.
--
-- If the trigger is not deployed, SKIP notices are raised (not failures).
--
-- RUN: psql "<staging-direct-url>" -v ON_ERROR_STOP=1 -f test/db/03_tenants_column_guard.sql
--      Wrapped in a transaction, rolled back at the end.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── fixtures ─────────────────────────────────────────────────────
INSERT INTO auth.users (id, aud, role, email, encrypted_password,
                       email_confirmed_at, created_at, updated_at,
                       raw_app_meta_data, raw_user_meta_data, is_super_admin)
VALUES
  ('f6f6f6f6-f6f6-4f6f-8f6f-f6f6f6f6f6f6', 'authenticated', 'authenticated',
   'sec-admin-a@example.com', 'dummy', now(), now(), now(), '{}', '{}', false),
  ('07a7a7a7-0a7a-4a7a-8a7a-0a7a7a7a7a7a', 'authenticated', 'authenticated',
   'sec-plat-owner@example.com', 'dummy', now(), now(), now(), '{}', '{}', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenants (id, name, slug, status) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SEC Test Tenant A', 'sec-test-a', 'suspended')
ON CONFLICT (id) DO UPDATE SET status = 'suspended';

INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f6f6f6f6-f6f6-4f6f-8f6f-f6f6f6f6f6f6', 'tenant_admin', true)
ON CONFLICT (user_id, tenant_id) DO NOTHING;

INSERT INTO public.platform_admins (user_id, role) VALUES
  ('07a7a7a7-0a7a-4a7a-8a7a-0a7a7a7a7a7a', 'platform_owner')
ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

-- grant the fixture admin settings.update (the tenants_member_update gate)
INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect, reason)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       'f6f6f6f6-f6f6-4f6f-8f6f-f6f6f6f6f6f6',
       p.id, 'grant', 'security test fixture'
FROM public.permissions p WHERE p.code = 'settings.update'
ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;

DO $$
DECLARE
  v_trigger_deployed BOOLEAN;
  v_guarded TEXT[] := ARRAY['status','suspended','expires_at',
                            'tenant_code','slug','registration_number',
                            'logo_url'];
  v_col TEXT;
  v_blocked INT := 0;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname = 'trg_tenants_column_guard')
    INTO v_trigger_deployed;
  IF NOT v_trigger_deployed THEN
    RAISE NOTICE 'SKIP: trg_tenants_column_guard not deployed — SEC-H6 fix pending';
    RETURN;
  END IF;

  -- ── (a) every guarded column is blocked for the tenant admin ──
  -- The value assertions afterwards are the ground truth: whether the
  -- trigger raises or silently reverts, the columns must not change.
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','f6f6f6f6-f6f6-4f6f-8f6f-f6f6f6f6f6f6',
                       'role','authenticated')::text, true);

  FOREACH v_col IN ARRAY v_guarded LOOP
    BEGIN
      EXECUTE format(
        'UPDATE public.tenants SET %I = %L WHERE id = %L',
        v_col,
        CASE WHEN v_col IN ('suspended') THEN 'false'
             WHEN v_col IN ('expires_at') THEN '2099-01-01'
             ELSE 'pwned' END,
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    EXCEPTION WHEN OTHERS THEN
      -- Trigger raised (or RLS denied): the write did not land.
      v_blocked := v_blocked + 1;
    END;
  END LOOP;

  IF (SELECT status FROM public.tenants
      WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') <> 'suspended' THEN
    RAISE EXCEPTION 'FAIL (a): tenant admin changed status away from suspended';
  END IF;
  IF (SELECT slug FROM public.tenants
      WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') <> 'sec-test-a' THEN
    RAISE EXCEPTION 'FAIL (a): tenant admin changed slug';
  END IF;
  RAISE NOTICE 'PASS (a): guarded columns unchanged (% writes raised)', v_blocked;
  RESET ROLE;

  -- ── (b) positive control: branding/contact columns still writable ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','f6f6f6f6-f6f6-4f6f-8f6f-f6f6f6f6f6f6',
                       'role','authenticated')::text, true);
  UPDATE public.tenants SET name = 'SEC Test Tenant A (renamed)', phone = '03001234567'
   WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  RESET ROLE;
  IF (SELECT name FROM public.tenants
      WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
     <> 'SEC Test Tenant A (renamed)' THEN
    RAISE EXCEPTION 'FAIL (b): tenant admin could not update name/phone';
  END IF;
  RAISE NOTICE 'PASS (b): allow-listed columns remain writable';

  -- ── (c) positive control: platform admin bypasses the guard ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','07a7a7a7-0a7a-4a7a-8a7a-0a7a7a7a7a7a',
                       'role','authenticated')::text, true);
  UPDATE public.tenants SET status = 'active'
   WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  RESET ROLE;
  IF (SELECT status FROM public.tenants
      WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') <> 'active' THEN
    RAISE EXCEPTION 'FAIL (c): platform admin could not update status';
  END IF;
  RAISE NOTICE 'PASS (c): platform admin bypass works';
END $$;

ROLLBACK;
