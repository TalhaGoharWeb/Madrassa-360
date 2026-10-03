-- ═══════════════════════════════════════════════════════════════════
-- 06_role_rpc_ceilings.sql — SEC-H1
--
-- Asserts the grant ceilings deployed by migration 036 on the role-
-- management RPCs:
--   (a) assign_tenant_role: a caller with roles.assign (but not
--       tenant_owner) CANNOT assign the tenant_owner key (Ceiling 1).
--   (b) assign_tenant_role: a caller CANNOT assign a role whose effective
--       permission set exceeds their own (Ceiling 2).
--   (c) set_role_permissions: a caller CANNOT add a permission code they
--       do not themselves hold.
--   (d) Positive control: a tenant_owner CAN assign tenant_owner.
-- Each block SKIPs gracefully when 036 is not deployed.
--
-- RUN: psql "<staging-direct-url>" -v ON_ERROR_STOP=1 -f test/db/06_role_rpc_ceilings.sql
--      (postgres superuser / service_role connection string; everything is
--      wrapped in a transaction and ROLLED BACK at the end.)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── fixtures ─────────────────────────────────────────────────────
INSERT INTO auth.users (id, aud, role, email, encrypted_password,
                       email_confirmed_at, created_at, updated_at,
                       raw_app_meta_data, raw_user_meta_data, is_super_admin)
VALUES
  ('aa11aa11-aa11-4a11-8a11-aa11aa11aa11', 'authenticated', 'authenticated',
   'sec-owner@example.com', 'dummy', now(), now(), now(), '{}', '{}', false),
  ('bb22bb22-bb22-4b22-8b22-bb22bb22bb22', 'authenticated', 'authenticated',
   'sec-junior@example.com', 'dummy', now(), now(), now(), '{}', '{}', false),
  ('cc33cc33-cc33-4c33-8c33-cc33cc33cc33', 'authenticated', 'authenticated',
   'sec-target@example.com', 'dummy', now(), now(), now(), '{}', '{}', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenants (id, name, slug) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SEC Test Tenant A', 'sec-test-a')
ON CONFLICT (id) DO NOTHING;

-- Owner, junior admin (custom role), and a plain target user.
INSERT INTO public.tenant_roles (tenant_id, key, display_name, display_urdu, is_active)
VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'tenant_owner', 'Tenant Owner', 'مالک', true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'junior_admin', 'Junior Admin', 'جونیئر ایڈمن', true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'power_role', 'Power Role', 'پاور رول', true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'staff', 'Staff', 'عملہ', true)
ON CONFLICT (tenant_id, key) DO NOTHING;

INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aa11aa11-aa11-4a11-8a11-aa11aa11aa11', 'tenant_owner', true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bb22bb22-bb22-4b22-8b22-bb22bb22bb22', 'junior_admin', true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cc33cc33-cc33-4c33-8c33-cc33cc33cc33', 'staff', true)
ON CONFLICT (user_id, tenant_id) DO NOTHING;

-- Junior admin holds roles.assign (and only that) via a direct grant.
INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect, reason)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       'bb22bb22-bb22-4b22-8b22-bb22bb22bb22',
       p.id, 'grant', 'security test fixture'
FROM public.permissions p WHERE p.code = 'roles.assign'
ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;

-- power_role grants finance.approve, which the junior admin does NOT hold.
INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
SELECT tr.id, p.id
FROM public.tenant_roles tr, public.permissions p
WHERE tr.tenant_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  AND tr.key = 'power_role'
  AND p.code = 'finance.approve'
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_036 BOOLEAN;
  v_owner_probe BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'assign_tenant_role'
      AND pg_get_functiondef(oid) LIKE '%only a tenant_owner may assign tenant_owner%'
  ) INTO v_036;
  IF NOT v_036 THEN
    RAISE NOTICE 'SKIP: 036 grant ceilings not deployed — assign_tenant_role lacks Ceiling 1';
    RETURN;
  END IF;
  RAISE NOTICE 'PASS (presence): 036 grant ceilings deployed';

  -- ── (a) junior admin (roles.assign, not owner) cannot mint an owner ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','bb22bb22-bb22-4b22-8b22-bb22bb22bb22','role','authenticated')::text, true);
  BEGIN
    PERFORM public.assign_tenant_role(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'cc33cc33-cc33-4c33-8c33-cc33cc33cc33',
      'tenant_owner');
    RAISE EXCEPTION 'FAIL (a): roles.assign holder minted a tenant_owner';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (a)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (a): owner-mint blocked: %', SQLERRM;
  END;

  -- ── (b) cannot assign a role granting unheld permissions ──
  BEGIN
    PERFORM public.assign_tenant_role(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'cc33cc33-cc33-4c33-8c33-cc33cc33cc33',
      'power_role');
    RAISE EXCEPTION 'FAIL (b): assigned role granting finance.approve, which caller lacks';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (b)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (b): over-ceiling role assignment blocked: %', SQLERRM;
  END;
  RESET ROLE;

  -- ── (c) cannot add an unheld code via set_role_permissions ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','bb22bb22-bb22-4b22-8b22-bb22bb22bb22','role','authenticated')::text, true);
  BEGIN
    PERFORM public.set_role_permissions(
      (SELECT id FROM public.tenant_roles
        WHERE tenant_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' AND key = 'junior_admin'),
      ARRAY['finance.approve']);
    RAISE EXCEPTION 'FAIL (c): granted unheld finance.approve via set_role_permissions';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (c)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (c): unheld-code grant blocked: %', SQLERRM;
  END;
  RESET ROLE;

  -- ── (d) positive control: the real owner CAN assign tenant_owner ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','aa11aa11-aa11-4a11-8a11-aa11aa11aa11','role','authenticated')::text, true);
  BEGIN
    PERFORM public.assign_tenant_role(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'cc33cc33-cc33-4c33-8c33-cc33cc33cc33',
      'tenant_owner');
    -- Verify it actually landed.
    SELECT EXISTS (
      SELECT 1 FROM public.tenant_memberships
      WHERE tenant_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        AND user_id = 'cc33cc33-cc33-4c33-8c33-cc33cc33cc33'
        AND role = 'tenant_owner' AND is_active
    ) INTO v_owner_probe;
    IF NOT v_owner_probe THEN
      RAISE EXCEPTION 'FAIL (d): owner assignment returned but row not found';
    END IF;
    RAISE NOTICE 'PASS (d): tenant_owner can assign tenant_owner (no regression)';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (d)%' THEN RAISE; END IF;
    RAISE EXCEPTION 'FAIL (d): legitimate owner assignment blocked: %', SQLERRM;
  END;
  RESET ROLE;
END $$;

ROLLBACK;
