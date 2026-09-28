-- ═══════════════════════════════════════════════════════════════════════════════
-- Madrassa-360 — Phase 11 Authorization Model Test Suite
-- supabase/tests/phase11_authorization.sql
--
-- PURPOSE
--   Prove the authorization model with executable assertions:
--     §1  Precedence: explicit deny > explicit grant > delegation >
--         role grant > default-deny.
--     §2  Tenant isolation: no cross-tenant reads/writes via app
--         services (helper level + RLS policy level).
--     §3  Delegation ceilings: cannot delegate what you don't hold;
--         no self-delegation; expiry enforced; revocation immediate;
--         no chaining; delegatee must be a member.
--     §4  Principal / last-owner safety: cannot remove, deactivate or
--         re-role the last active tenant_owner; cannot strip the last
--         roles.assign grant in a tenant.
--     §5  Scope narrowing (migration 022): grants never widen beyond
--         the granter's scope; scope_allows() is fail-CLOSED when no
--         permission_scopes row exists; starts_at/expires_at honored;
--         provisioning triggers keep future grants working.
--     §6  RPC/trigger interplay + migration idempotency guards.
--
--   40+ assertions (P/I/D/O/S/G numbered). Any FAIL raises an EXCEPTION
--   which aborts the run (run with -v ON_ERROR_STOP=1).
--
-- STATUS
--   EXECUTED 2026-09-26 against the local Phase-11 harness (PostgreSQL
--   16, migrations 001–005 + 019–022 applied with the minimal legacy
--   stubs listed below): ALL 68 ASSERTIONS PASSED, exit 0, final
--   NOTICE 'ALL PHASE-11 AUTHORIZATION TESTS PASSED'. To re-run:
--     psql "host=/tmp/pgrun port=5544 dbname=m360test user=pgtest" \
--       -v ON_ERROR_STOP=1 -f supabase/tests/phase11_authorization.sql
--   The pre-existing cross_tenant_isolation.sql remains the
--   staging-target suite; this file is the authorization-model suite
--   and runs wherever the harness stubs exist.
--
-- PREREQUISITES
--   1. Migrations 001, 002, 004, 005, 019, 020, 021, 022 applied.
--   2. Run as a superuser / BYPASSRLS role (setup inserts bypass RLS
--      deliberately; scenario blocks impersonate users, see below).
--   3. pgcrypto extension.
--   4. A fresh database (fixed test UUIDs / slugs below).
--   5. Harness stubs (local-only; on a real Supabase project the real
--      auth schema and legacy tables exist instead):
--        CREATE EXTENSION pgcrypto;
--        CREATE SCHEMA auth;
--        CREATE TABLE auth.users (id uuid PRIMARY KEY);
--        -- auth.uid() honors the test.auth_uid setting so scenarios can
--        -- impersonate users without JWTs:
--        CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
--          $$ SELECT NULLIF(current_setting('test.auth_uid', true), '')::uuid; $$;
--        CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS
--          $$ SELECT current_setting('role', true); $$;
--        CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
--        CREATE ROLE service_role NOLOGIN;
--        -- minimal legacy stubs (empty): public.madrasas, public.profiles,
--        -- public.user_roles, public.roles, public.role_permissions,
--        -- public.permissions, public.audit_logs,
--        -- public.teacher_class_assignments, public.classes,
--        -- public.students, public.attendance, public.exams, public.results
--        -- (see phase-11 notes for exact DDL).
--
-- HOW TO RUN
--   psql "$DB_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/phase11_authorization.sql
--
-- EXPECTED RESULT
--   A stream of `NOTICE: PASS: ...` lines, one per assertion, ending
--   with `NOTICE: ALL PHASE-11 AUTHORIZATION TESTS PASSED`.
--   The script ends with ROLLBACK, so the database is left untouched.
--
-- AUTH-CONTEXT HELPER
--   PERFORM public._t11_set_user('<uuid>') impersonates a user for the
--   rest of the transaction (sets test.auth_uid, honored by the
--   harness auth.uid() stub; request.jwt.claims is set too so the same
--   script also works on a real Supabase project). RLS scenarios
--   additionally do SET LOCAL role TO t11_app (a NOLOGIN role granted
--   the authenticated role, so RLS policies evaluate as for a real
--   signed-in app user), then RESET role.
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── assertion + impersonation helpers ─────────────────────────────────

CREATE OR REPLACE FUNCTION public._t11_assert(p_name TEXT, p_cond BOOLEAN)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NOT coalesce(p_cond, false) THEN
    RAISE EXCEPTION 'FAIL: %', p_name;
  END IF;
  RAISE NOTICE 'PASS: %', p_name;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._t11_set_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  PERFORM set_config('test.auth_uid', p_user_id::text, true);
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public._t11_assert(TEXT, BOOLEAN) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public._t11_set_user(UUID) TO PUBLIC;

-- ═══════════════════════════════════════════════════════════════════════
-- CONTRACT GUARDS — the objects under test exist with the 022 contract
-- ═══════════════════════════════════════════════════════════════════════

DO $do$
BEGIN
  PERFORM public._t11_assert('G1 permission_scopes has 022 columns',
    (SELECT count(*) = 4 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'permission_scopes'
        AND column_name IN ('starts_at','expires_at','name_ur','name_en')));
  PERFORM public._t11_assert('G1b new columns are nullable',
    (SELECT bool_and(is_nullable = 'YES') FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'permission_scopes'
        AND column_name IN ('starts_at','expires_at','name_ur','name_en')));
  PERFORM public._t11_assert('G2 022 recorded in schema_migrations',
    EXISTS (SELECT 1 FROM public.schema_migrations WHERE version = '022_scope_failclosed'));
  PERFORM public._t11_assert('G3 scope_allows is the fail-closed 022 version',
    (SELECT prosrc ILIKE '%no scope row%fail closed%'
       FROM pg_proc WHERE pronamespace = 'public'::regnamespace
         AND proname = 'scope_allows'
         AND pg_get_function_identity_arguments(oid) = 'p_tenant_id uuid, p_user_id uuid, p_code text, p_class_id uuid'));
  PERFORM public._t11_assert('G4 four provisioning triggers exist',
    (SELECT count(*) = 4 FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
     WHERE NOT t.tgisinternal AND t.tgname IN
       ('provision_scope_rows_membership','provision_scope_rows_role_grant',
        'provision_scope_rows_user_grant','provision_scope_rows_delegation')));
  PERFORM public._t11_assert('G5 helper/RPC signatures present',
    (SELECT count(*) = 8 FROM pg_proc
      WHERE pronamespace = 'public'::regnamespace AND proname IN
        ('tenant_has_permission','user_effective_permission','user_code_denied',
         'get_my_permissions_detailed','delegate_permission','set_role_permissions',
         'assign_tenant_role','protect_last_owner')));
  PERFORM public._t11_assert('G6 RLS enabled on the five 019 tables',
    (SELECT count(*) = 5 FROM pg_tables
      WHERE schemaname = 'public' AND rowsecurity
        AND tablename IN ('tenant_roles','tenant_role_permissions',
          'user_permissions','permission_scopes','permission_delegations')));
END
$do$;

-- ═══════════════════════════════════════════════════════════════════════
-- SETUP (superuser — RLS bypassed)
--   Tenant A  aaaaaaaa-…  slug 't11-a'      Tenant B  bbbbbbbb-…  slug 't11-b'
--   u_owner_a   11111111-…  tenant_owner of A
--   u_teacher1  22222222-…  teacher of A (class-scoped for attendance.mark)
--   u_teacher2  33333333-…  teacher of A
--   u_teacher3  44444444-…  teacher of A (created later — provisioning)
--   u_owner_b   55555555-…  tenant_owner of B
--   u_platform  66666666-…  platform_admin (no membership)
--   u_nobody    77777777-…  auth user, member of nothing
--   u_staff_a   88888888-…  member of A (created later — role-grant prov.)
--   u_newbie    99999999-…  member of A (created later — RPC prov.)
-- ═══════════════════════════════════════════════════════════════════════

INSERT INTO public.tenants (id, name, slug) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'T11 Madrasa A', 't11-a'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'T11 Madrasa B', 't11-b');

INSERT INTO auth.users (id) VALUES
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333'),
  ('44444444-4444-4444-4444-444444444444'),
  ('55555555-5555-5555-5555-555555555555'),
  ('66666666-6666-6666-6666-666666666666'),
  ('77777777-7777-7777-7777-777777777777'),
  ('88888888-8888-8888-8888-888888888888'),
  ('99999999-9999-9999-9999-999999999999');

-- Materialize the tenant role catalog for the new test tenants
-- (replicates the 019(e) backfill, which only ran for pre-019 tenants).
INSERT INTO public.tenant_roles (tenant_id, key, display_name, display_urdu, template_key)
SELECT t.id, r.name, r.display_name, r.display_urdu, r.name
  FROM public.tenants t
 CROSS JOIN public.roles r
 WHERE t.slug IN ('t11-a','t11-b')
   AND r.is_system AND r.scope IN ('madrasa','external')
ON CONFLICT (tenant_id, key) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
SELECT tr.id, rp.permission_id
  FROM public.tenant_roles tr
  JOIN public.tenants t ON t.id = tr.tenant_id
  JOIN public.roles r ON r.name = tr.template_key
  JOIN public.role_permissions rp ON rp.role_id = r.id
 WHERE t.slug IN ('t11-a','t11-b')
ON CONFLICT (tenant_role_id, permission_id) DO NOTHING;

INSERT INTO public.platform_admins (user_id, role) VALUES
  ('66666666-6666-6666-6666-666666666666', 'platform_owner');

-- Memberships. The 022 provisioning trigger fires here and creates the
-- initial 'all' scope rows for every effective code.
INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'tenant_owner', true),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'teacher',      true),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'teacher',      true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '55555555-5555-5555-5555-555555555555', 'tenant_owner', true);

-- Classes for the scope tests.
INSERT INTO public.classes (id, tenant_id) VALUES
  ('aa11aa11-aa11-aa11-aa11-aa11aa11aa11', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('aa22aa22-aa22-aa22-aa22-aa22aa22aa22', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('bb11bb11-bb11-bb11-bb11-bb11bb11bb11', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

-- Narrow u_teacher1's attendance.mark to class_a1 (their other codes stay 'all').
UPDATE public.permission_scopes ps
   SET scope_type = 'classes',
       scope_ref  = jsonb_build_object('class_ids', jsonb_build_array('aa11aa11-aa11-aa11-aa11-aa11aa11aa11'))
  FROM public.permissions p
 WHERE ps.permission_id = p.id
   AND p.code = 'attendance.mark'
   AND ps.tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
   AND ps.user_id   = '22222222-2222-2222-2222-222222222222';

-- RLS test role: a plain app role that inherits `authenticated`
-- (exactly like a real signed-in client).
CREATE ROLE t11_app NOLOGIN;
GRANT authenticated TO t11_app;
GRANT ALL ON public.permission_scopes, public.attendance, public.results TO t11_app;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.results   ENABLE ROW LEVEL SECURITY;

DO $do$
BEGIN
  PERFORM public._t11_assert('SETUP provisioning created all-rows for teacher1 (9 codes)',
    (SELECT count(*) = 9 FROM public.permission_scopes
      WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        AND user_id   = '22222222-2222-2222-2222-222222222222'));
  PERFORM public._t11_assert('SETUP provisioning created all-rows for owner_a (61 codes)',
    (SELECT count(*) = 61 FROM public.permission_scopes
      WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        AND user_id   = '11111111-1111-1111-1111-111111111111'));
  PERFORM public._t11_assert('SETUP teacher1 attendance.mark narrowed to class_a1',
    (SELECT scope_type = 'classes' FROM public.permission_scopes ps
       JOIN public.permissions p ON p.id = ps.permission_id
      WHERE ps.tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        AND ps.user_id   = '22222222-2222-2222-2222-222222222222'
        AND p.code = 'attendance.mark'));
END
$do$;

-- ═══════════════════════════════════════════════════════════════════════
-- §1  PRECEDENCE: deny > grant > delegation > role grant > default-deny
-- ═══════════════════════════════════════════════════════════════════════

DO $do$
BEGIN
  -- P1 (canary): role grant resolves. Also proves the auth stub works —
  -- if impersonation were broken, this would fail loudly instead of
  -- letting the denial tests below pass vacuously.
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222');
  PERFORM public._t11_assert('P1 role grant: teacher1 has attendance.mark in A',
    public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'attendance.mark'));

  -- P2: explicit deny beats the role grant.
  INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', p.id, 'deny'
    FROM public.permissions p WHERE p.code = 'attendance.mark';
  PERFORM public._t11_assert('P2 deny beats role grant',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'attendance.mark'));
  DELETE FROM public.user_permissions
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id   = '22222222-2222-2222-2222-222222222222';
  PERFORM public._t11_assert('P2b grant restored after deny removed',
    public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'attendance.mark'));

  -- P3: explicit grant covers a code the role lacks.
  PERFORM public._t11_assert('P3a teacher1 lacks fees.collect by role',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.collect'));
  INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', p.id, 'grant'
    FROM public.permissions p WHERE p.code = 'fees.collect';
  PERFORM public._t11_assert('P3b explicit grant adds fees.collect',
    public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.collect'));

  -- P4: deny beats the explicit grant too.
  UPDATE public.user_permissions SET effect = 'deny'
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id   = '22222222-2222-2222-2222-222222222222'
     AND permission_id = (SELECT id FROM public.permissions WHERE code = 'fees.collect');
  PERFORM public._t11_assert('P4 deny beats explicit grant',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.collect'));
  DELETE FROM public.user_permissions
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id   = '22222222-2222-2222-2222-222222222222';

  -- P5: delegation grants a code held neither by role nor override.
  PERFORM public._t11_set_user('11111111-1111-1111-1111-111111111111'); -- owner_a delegates
  PERFORM public.delegate_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '33333333-3333-3333-3333-333333333333', 'fees.collect', 'all', '{}',
    now() + interval '1 day');
  PERFORM public._t11_set_user('33333333-3333-3333-3333-333333333333'); -- teacher2
  PERFORM public._t11_assert('P5 delegation grants fees.collect to teacher2',
    public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.collect'));
  PERFORM public._t11_assert('P5b provenance is delegation',
    EXISTS (SELECT 1 FROM public.get_my_permissions_detailed('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
             WHERE code = 'fees.collect' AND source = 'delegation'));

  -- P6: deny beats the delegation.
  INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', p.id, 'deny'
    FROM public.permissions p WHERE p.code = 'fees.collect';
  PERFORM public._t11_assert('P6 deny beats delegation',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.collect'));

  -- P7: default-deny — no grant anywhere.
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222'); -- teacher1
  PERFORM public._t11_assert('P7 default-deny: teacher1 lacks fees.refund everywhere',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.refund'));

  -- P8: provenance labels across sources.
  PERFORM public._t11_assert('P8a role source reported',
    EXISTS (SELECT 1 FROM public.get_my_permissions_detailed('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
             WHERE code = 'attendance.mark' AND source = 'role'));
  INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', p.id, 'grant'
    FROM public.permissions p WHERE p.code = 'fees.collect';
  PERFORM public._t11_assert('P8b override source reported',
    EXISTS (SELECT 1 FROM public.get_my_permissions_detailed('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
             WHERE code = 'fees.collect' AND source = 'override'));
  PERFORM public._t11_assert('P8c denied code excluded from the effective set',
    (SELECT NOT EXISTS (
       SELECT 1 FROM public.get_my_permissions('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
        WHERE code = 'fees.collect')
     FROM (SELECT public._t11_set_user('33333333-3333-3333-3333-333333333333')) s));
  DELETE FROM public.user_permissions
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id IN ('22222222-2222-2222-2222-222222222222',
                     '33333333-3333-3333-3333-333333333333');
END
$do$;

-- ═══════════════════════════════════════════════════════════════════════
-- §2  TENANT ISOLATION
-- ═══════════════════════════════════════════════════════════════════════

DO $do$
BEGIN
  -- I1: helper level — teacher1 (A only) has nothing in B.
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222');
  PERFORM public._t11_assert('I1 no cross-tenant permission (helper)',
    NOT public.tenant_has_permission('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'students.view'));
  PERFORM public._t11_set_user('66666666-6666-6666-6666-666666666666'); -- u_platform
  PERFORM public._t11_assert('I1b platform admin still passes everywhere',
    public.tenant_has_permission('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'students.view'));
END
$do$;

-- I2: RLS SELECT on permission_scopes — B's rows invisible to A's teacher.
DO $do$
DECLARE
  v_a int; v_b int;
BEGIN
  SET LOCAL role TO t11_app;
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222');
  SELECT count(*) INTO v_a FROM public.permission_scopes
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  SELECT count(*) INTO v_b FROM public.permission_scopes
   WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  RESET role;
  PERFORM public._t11_assert('I2a own-tenant scope rows visible (positive control)', v_a > 0);
  PERFORM public._t11_assert('I2b cross-tenant scope rows invisible', v_b = 0);
END
$do$;

-- I3: RLS INSERT into permission_scopes for the foreign tenant is denied.
DO $do$
DECLARE
  v_denied boolean := false;
  v_pid uuid;
BEGIN
  SELECT id INTO v_pid FROM public.permissions WHERE code = 'students.view';
  SET LOCAL role TO t11_app;
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222');
  BEGIN
    INSERT INTO public.permission_scopes (tenant_id, user_id, permission_id, scope_type)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            '22222222-2222-2222-2222-222222222222', v_pid, 'all');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_denied := true; END IF;
  END;
  RESET role;
  PERFORM public._t11_assert('I3 cross-tenant scope write denied by RLS', v_denied);
END
$do$;

-- I4/I5: attendance write policy — cross-tenant denied, same-tenant
-- in-scope class allowed (end-to-end through scope_allows).
DO $do$
DECLARE
  v_cross_denied boolean := false;
  v_own_ok boolean := false;
BEGIN
  SET LOCAL role TO t11_app;
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222'); -- teacher1, classes{class_a1}
  BEGIN
    INSERT INTO public.attendance (tenant_id, class_id)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bb11bb11-bb11-bb11-bb11-bb11bb11bb11');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '42501' THEN v_cross_denied := true; END IF;
  END;
  BEGIN
    INSERT INTO public.attendance (tenant_id, class_id)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aa11aa11-aa11-aa11-aa11-aa11aa11aa11');
    v_own_ok := true;
  EXCEPTION WHEN OTHERS THEN
    v_own_ok := false;
  END;
  RESET role;
  PERFORM public._t11_assert('I4 cross-tenant attendance insert denied', v_cross_denied);
  PERFORM public._t11_assert('I5 same-tenant in-scope attendance insert allowed', v_own_ok);
  DELETE FROM public.attendance
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
END
$do$;

-- I6: a user with no membership anywhere sees nothing and can do nothing.
DO $do$
DECLARE
  v_n int;
BEGIN
  SET LOCAL role TO t11_app;
  PERFORM public._t11_set_user('77777777-7777-7777-7777-777777777777'); -- u_nobody
  SELECT count(*) INTO v_n FROM public.permission_scopes;
  RESET role;
  PERFORM public._t11_assert('I6 member-of-nothing sees zero scope rows', v_n = 0);
  PERFORM public._t11_assert('I6b member-of-nothing has no permission',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'students.view'));
END
$do$;

-- ═══════════════════════════════════════════════════════════════════════
-- §3  DELEGATION CEILINGS
-- ═══════════════════════════════════════════════════════════════════════

DO $do$
DECLARE
  v_raise boolean;
  v_msg   text;
BEGIN
  -- D1: no self-delegation (RPC guard).
  PERFORM public._t11_set_user('11111111-1111-1111-1111-111111111111'); -- owner_a
  v_raise := false;
  BEGIN
    PERFORM public.delegate_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '11111111-1111-1111-1111-111111111111', 'fees.collect');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM ILIKE '%yourself%' THEN v_raise := true; END IF;
  END;
  PERFORM public._t11_assert('D1 self-delegation refused', v_raise);

  -- D2: delegator without roles.assign (and not owner/admin) is refused,
  -- even though they hold the code itself.
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222'); -- teacher1
  v_raise := false; v_msg := '';
  BEGIN
    PERFORM public.delegate_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '33333333-3333-3333-3333-333333333333', 'attendance.mark');
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('D2 delegator without roles.assign refused',
    v_raise AND v_msg ILIKE '%roles.assign%');

  -- D3: cannot delegate a code you do not effectively hold.
  INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', p.id, 'grant'
    FROM public.permissions p WHERE p.code = 'roles.assign';
  v_raise := false; v_msg := '';
  BEGIN
    PERFORM public.delegate_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '33333333-3333-3333-3333-333333333333', 'fees.refund'); -- teacher1 lacks it
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('D3 cannot delegate an unheld code',
    v_raise AND v_msg ILIKE '%do not effectively hold%');
  DELETE FROM public.user_permissions
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id   = '22222222-2222-2222-2222-222222222222';

  -- D4: delegations never chain — teacher2 holds fees.collect ONLY via
  -- delegation (P5), so even with roles.assign they cannot re-delegate it.
  INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', p.id, 'grant'
    FROM public.permissions p WHERE p.code = 'roles.assign';
  PERFORM public._t11_set_user('33333333-3333-3333-3333-333333333333'); -- teacher2
  v_raise := false; v_msg := '';
  BEGIN
    PERFORM public.delegate_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '22222222-2222-2222-2222-222222222222', 'fees.collect');
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('D4 delegated codes cannot be re-delegated (no chaining)',
    v_raise AND v_msg ILIKE '%do not effectively hold%');
  DELETE FROM public.user_permissions
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id   = '33333333-3333-3333-3333-333333333333';

  -- D5: expiry is enforced at read time. (Direct INSERTs: the RPC
  -- requires a future expiry, and the ceiling trigger requires
  -- expires_at > starts_at, so the "expired" case is built with a
  -- starts_at two hours ago and an expires_at one hour ago.)
  INSERT INTO public.permission_delegations
    (tenant_id, delegator_id, delegatee_id, permission_id, starts_at, expires_at)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
         '11111111-1111-1111-1111-111111111111',
         '22222222-2222-2222-2222-222222222222',
         p.id, now() - interval '2 hours', now() + interval '1 hour'
    FROM public.permissions p WHERE p.code = 'fees.collect';
  PERFORM public._t11_set_user('22222222-2222-2222-2222-222222222222'); -- teacher1
  PERFORM public._t11_assert('D5a unexpired delegation grants',
    public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.collect'));
  UPDATE public.permission_delegations
     SET expires_at = now() - interval '1 hour'
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND delegatee_id = '22222222-2222-2222-2222-222222222222'
     AND permission_id = (SELECT id FROM public.permissions WHERE code = 'fees.collect');
  PERFORM public._t11_assert('D5b expired delegation grants nothing',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.collect'));
  DELETE FROM public.permission_delegations
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND delegatee_id = '22222222-2222-2222-2222-222222222222';

  -- D6: not-yet-started delegation grants nothing.
  INSERT INTO public.permission_delegations
    (tenant_id, delegator_id, delegatee_id, permission_id, starts_at)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
         '11111111-1111-1111-1111-111111111111',
         '22222222-2222-2222-2222-222222222222',
         p.id, now() + interval '1 hour'
    FROM public.permissions p WHERE p.code = 'fees.refund';
  PERFORM public._t11_assert('D6a delegation row was created (not a vacuous pass)',
    EXISTS (SELECT 1 FROM public.permission_delegations
             WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
               AND delegatee_id = '22222222-2222-2222-2222-222222222222'));
  PERFORM public._t11_assert('D6 future delegation grants nothing yet',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.refund'));
  DELETE FROM public.permission_delegations
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND delegatee_id = '22222222-2222-2222-2222-222222222222';

  -- D7: revocation (row delete) is immediate.
  PERFORM public._t11_set_user('11111111-1111-1111-1111-111111111111'); -- owner_a
  PERFORM public.delegate_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '33333333-3333-3333-3333-333333333333', 'fees.refund', 'all', '{}', now() + interval '1 day');
  PERFORM public._t11_set_user('33333333-3333-3333-3333-333333333333'); -- teacher2
  PERFORM public._t11_assert('D7a delegation grants before revocation',
    public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.refund'));
  DELETE FROM public.permission_delegations
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND delegatee_id = '33333333-3333-3333-3333-333333333333'
     AND permission_id = (SELECT id FROM public.permissions WHERE code = 'fees.refund');
  PERFORM public._t11_assert('D7b revocation is immediate',
    NOT public.tenant_has_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'fees.refund'));

  -- D8: delegatee must be a tenant member (ceiling trigger).
  v_raise := false; v_msg := '';
  BEGIN
    INSERT INTO public.permission_delegations
      (tenant_id, delegator_id, delegatee_id, permission_id)
    SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
           '11111111-1111-1111-1111-111111111111',
           '77777777-7777-7777-7777-777777777777', -- u_nobody: no membership
           p.id
      FROM public.permissions p WHERE p.code = 'fees.collect';
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('D8 delegatee must be a tenant member',
    v_raise AND v_msg ILIKE '%not a member%');
END
$do$;

-- ═══════════════════════════════════════════════════════════════════════
-- §4  PRINCIPAL / LAST-OWNER SAFETY
-- ═══════════════════════════════════════════════════════════════════════

DO $do$
DECLARE
  v_raise boolean;
  v_msg   text;
  v_owner_role uuid;
  v_temp_role  uuid;
  v_r          uuid;
BEGIN
  -- O1: cannot DELETE the last active owner.
  v_raise := false; v_msg := '';
  BEGIN
    DELETE FROM public.tenant_memberships
     WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       AND user_id   = '11111111-1111-1111-1111-111111111111';
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('O1 cannot delete the last active owner',
    v_raise AND v_msg ILIKE '%last active tenant_owner%');

  -- O2: cannot DEACTIVATE the last active owner.
  v_raise := false; v_msg := '';
  BEGIN
    UPDATE public.tenant_memberships SET is_active = false
     WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       AND user_id   = '11111111-1111-1111-1111-111111111111';
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('O2 cannot deactivate the last active owner',
    v_raise AND v_msg ILIKE '%last active tenant_owner%');

  -- O3: cannot RE-ROLE the last active owner away.
  v_raise := false; v_msg := '';
  BEGIN
    UPDATE public.tenant_memberships SET role = 'teacher'
     WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       AND user_id   = '11111111-1111-1111-1111-111111111111';
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('O3 cannot re-role the last active owner',
    v_raise AND v_msg ILIKE '%last active tenant_owner%');

  -- O4: with a second owner present, removing the first succeeds —
  -- then the first is re-added so later scenarios keep working.
  INSERT INTO auth.users (id) VALUES ('12121212-1212-1212-1212-121212121212');
  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '12121212-1212-1212-1212-121212121212', 'tenant_owner', true);
  DELETE FROM public.tenant_memberships
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     AND user_id   = '11111111-1111-1111-1111-111111111111';
  PERFORM public._t11_assert('O4 owner removable when a second owner exists',
    NOT EXISTS (SELECT 1 FROM public.tenant_memberships
                 WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                   AND user_id   = '11111111-1111-1111-1111-111111111111'));
  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'tenant_owner', true);

  -- O5: the last roles.assign grant in the tenant cannot be stripped.
  -- (tenant_owner keeps its fee codes so later delegation scenarios
  -- keep working; only roles.assign moves around.)
  PERFORM public._t11_set_user('11111111-1111-1111-1111-111111111111'); -- owner_a
  SELECT id INTO v_owner_role FROM public.tenant_roles
   WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND key = 'tenant_owner';
  v_temp_role := public.create_tenant_role('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    't11_temp', 'عارضی کردار', 'teacher');
  PERFORM public.set_role_permissions(v_temp_role, ARRAY['roles.assign']);
  -- tenant_owner gives up roles.assign (keeps fee codes): fine while
  -- t11_temp still holds it.
  PERFORM public.set_role_permissions(v_owner_role,
    ARRAY['fees.collect','fees.create','fees.refund']);
  PERFORM public._t11_assert('O5a roles.assign moved off tenant_owner while t11_temp holds it',
    NOT EXISTS (SELECT 1 FROM public.tenant_role_permissions trp
                 JOIN public.permissions p ON p.id = trp.permission_id
                WHERE trp.tenant_role_id = v_owner_role AND p.code = 'roles.assign')
    AND public.user_effective_permission('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          '11111111-1111-1111-1111-111111111111', 'fees.create'));
  -- The legacy materialized roles (tenant_admin, mohtamim, naib_mohtamim)
  -- also hold roles.assign; strip them so t11_temp becomes the SOLE holder.
  -- Each strip is legal because t11_temp still holds it throughout.
  FOR v_r IN
    SELECT tr.id
      FROM public.tenant_roles tr
      JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = tr.id
      JOIN public.permissions p ON p.id = trp.permission_id
     WHERE tr.tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       AND tr.id <> v_temp_role
       AND p.code = 'roles.assign'
  LOOP
    PERFORM public.set_role_permissions(v_r, ARRAY[]::text[]);
  END LOOP;
  PERFORM public._t11_assert('O5b t11_temp is now the sole roles.assign holder',
    (SELECT count(*) = 1 FROM public.tenant_roles tr
       JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = tr.id
       JOIN public.permissions p ON p.id = trp.permission_id
      WHERE tr.tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        AND tr.is_active AND p.code = 'roles.assign'
        AND tr.id = v_temp_role));
  -- stripping the LAST holder is refused
  v_raise := false; v_msg := '';
  BEGIN
    PERFORM public.set_role_permissions(v_temp_role, ARRAY[]::text[]);
  EXCEPTION WHEN OTHERS THEN
    v_raise := true; v_msg := SQLERRM;
  END;
  PERFORM public._t11_assert('O5c last roles.assign grant cannot be stripped',
    v_raise AND v_msg ILIKE '%last roles.assign%');
END
$do$;

-- ═══════════════════════════════════════════════════════════════════════
-- §5  SCOPE NARROWING + 022 FAIL-CLOSED
-- ═══════════════════════════════════════════════════════════════════════

DO $do$
DECLARE
  v_a1 uuid := 'aa11aa11-aa11-aa11-aa11-aa11aa11aa11';
  v_a2 uuid := 'aa22aa22-aa22-aa22-aa22-aa22aa22aa22';
  v_t1 uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_u1 uuid := '22222222-2222-2222-2222-222222222222'; -- teacher1
  v_u2 uuid := '33333333-3333-3333-3333-333333333333'; -- teacher2
  v_u3 uuid := '44444444-4444-4444-4444-444444444444'; -- teacher3
  v_pid uuid;
BEGIN
  -- S1: the 022 window/label columns are usable (nullable, no backfill).
  SELECT id INTO v_pid FROM public.permissions WHERE code = 'students.view';
  PERFORM public._t11_assert('S1 new columns accept labels + window',
    (SELECT count(*) = 1 FROM public.permission_scopes ps
      WHERE ps.tenant_id = v_t1 AND ps.user_id = v_u1 AND ps.permission_id = v_pid
        AND ps.name_ur IS NULL AND ps.starts_at IS NULL));

  -- S2: no row → FALSE (the 022 flip; pre-022 this was fail-open TRUE).
  -- teacher2 holds students.view by role; delete their 'all' row.
  DELETE FROM public.permission_scopes
   WHERE tenant_id = v_t1 AND user_id = v_u2 AND permission_id = v_pid;
  PERFORM public._t11_assert('S2a permission still held without a scope row',
    public.user_effective_permission(v_t1, v_u2, 'students.view'));
  PERFORM public._t11_assert('S2b missing scope row is fail-closed',
    NOT public.scope_allows(v_t1, v_u2, 'students.view', NULL));
  -- restore the fixture row (S2's proof stands: at check time the row
  -- was missing and the decision was deny)
  INSERT INTO public.permission_scopes (tenant_id, user_id, permission_id, scope_type, scope_ref)
  VALUES (v_t1, v_u2, v_pid, 'all', '{}'::jsonb);

  -- S3: an 'all' row still allows.
  PERFORM public._t11_assert('S3 all-scope row allows',
    public.scope_allows(v_t1, v_u1, 'students.view', NULL));

  -- S4: narrowed classes scope — inside allows, outside/unknown denies.
  PERFORM public._t11_assert('S4a in-scope class allowed',
    public.scope_allows(v_t1, v_u1, 'attendance.mark', v_a1));
  PERFORM public._t11_assert('S4b out-of-scope class denied',
    NOT public.scope_allows(v_t1, v_u1, 'attendance.mark', v_a2));
  PERFORM public._t11_assert('S4c unverifiable target denied (fail-closed)',
    NOT public.scope_allows(v_t1, v_u1, 'attendance.mark', NULL));

  -- S5/S6: the row window is honored.
  UPDATE public.permission_scopes
     SET expires_at = now() - interval '1 hour'
   WHERE tenant_id = v_t1 AND user_id = v_u1 AND permission_id = v_pid;
  PERFORM public._t11_assert('S5 expired scope row denies',
    NOT public.scope_allows(v_t1, v_u1, 'students.view', NULL));
  UPDATE public.permission_scopes
     SET expires_at = NULL, starts_at = now() + interval '1 hour'
   WHERE tenant_id = v_t1 AND user_id = v_u1 AND permission_id = v_pid;
  PERFORM public._t11_assert('S6 not-yet-started scope row denies',
    NOT public.scope_allows(v_t1, v_u1, 'students.view', NULL));
  UPDATE public.permission_scopes
     SET starts_at = NULL
   WHERE tenant_id = v_t1 AND user_id = v_u1 AND permission_id = v_pid;
  PERFORM public._t11_assert('S6b window cleared: allows again',
    public.scope_allows(v_t1, v_u1, 'students.view', NULL));

  -- S7: provisioning — a brand-new membership gets 'all' rows.
  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
  VALUES (v_t1, v_u3, 'teacher', true);
  SELECT id INTO v_pid FROM public.permissions WHERE code = 'attendance.mark';
  PERFORM public._t11_assert('S7 new membership auto-provisioned with all-scope',
    EXISTS (SELECT 1 FROM public.permission_scopes
             WHERE tenant_id = v_t1 AND user_id = v_u3
               AND permission_id = v_pid AND scope_type = 'all'));

  -- S8: provisioning — an explicit grant gets its row.
  SELECT id INTO v_pid FROM public.permissions WHERE code = 'fees.collect';
  INSERT INTO public.user_permissions (tenant_id, user_id, permission_id, effect)
  VALUES (v_t1, v_u3, v_pid, 'grant');
  PERFORM public._t11_assert('S8 explicit grant auto-provisioned with all-scope',
    EXISTS (SELECT 1 FROM public.permission_scopes
             WHERE tenant_id = v_t1 AND user_id = v_u3
               AND permission_id = v_pid AND scope_type = 'all'));

  -- S9: provisioning — a delegation gets the delegatee's row.
  PERFORM public._t11_set_user('11111111-1111-1111-1111-111111111111'); -- owner_a
  PERFORM public.delegate_permission(v_t1, v_u2, 'fees.create', 'all', '{}', now() + interval '1 day');
  SELECT id INTO v_pid FROM public.permissions WHERE code = 'fees.create';
  PERFORM public._t11_assert('S9 delegation auto-provisioned with all-scope',
    EXISTS (SELECT 1 FROM public.permission_scopes
             WHERE tenant_id = v_t1 AND user_id = v_u2
               AND permission_id = v_pid AND scope_type = 'all'));
  DELETE FROM public.permission_delegations
   WHERE tenant_id = v_t1 AND delegatee_id = v_u2 AND permission_id = v_pid;

  -- S10: provisioning — a role gaining a permission provisions members.
  DECLARE
    v_role uuid;
    v_staff uuid := '88888888-8888-8888-8888-888888888888';
  BEGIN
    v_role := public.create_tenant_role(v_t1, 't11_clerk', 'کلرک', 'teacher');
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES (v_t1, v_staff, 't11_clerk', true);
    PERFORM public.set_role_permissions(v_role, ARRAY['students.view','fees.collect']);
    PERFORM public._t11_assert('S10 role gaining a code provisions members (all-scope)',
      EXISTS (SELECT 1 FROM public.permission_scopes ps
               JOIN public.permissions p ON p.id = ps.permission_id
              WHERE ps.tenant_id = v_t1 AND ps.user_id = v_staff
                AND p.code = 'fees.collect' AND ps.scope_type = 'all'));
  END;

  -- S11: end-to-end through the results write policy — narrow results.enter
  -- to class_a1, then prove out-of-scope writes are denied by RLS.
  SELECT id INTO v_pid FROM public.permissions WHERE code = 'results.enter';
  UPDATE public.permission_scopes
     SET scope_type = 'classes',
         scope_ref  = jsonb_build_object('class_ids', jsonb_build_array(v_a1::text))
   WHERE tenant_id = v_t1 AND user_id = v_u1 AND permission_id = v_pid;
  INSERT INTO public.exams (id, tenant_id, class_id) VALUES
    ('e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', v_t1, v_a1),
    ('e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2', v_t1, v_a2);
  INSERT INTO public.students (id, tenant_id, class_id) VALUES
    ('d1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1', v_t1, v_a1),
    ('d2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2', v_t1, v_a2);

  DECLARE
    v_out_denied boolean := false;
    v_in_ok      boolean := false;
  BEGIN
    SET LOCAL role TO t11_app;
    PERFORM public._t11_set_user(v_u1); -- teacher1, results.enter scoped to class_a1
    BEGIN
      INSERT INTO public.results (tenant_id, exam_id, student_id)
      VALUES (v_t1, 'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2', 'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2');
    EXCEPTION WHEN OTHERS THEN
      IF SQLSTATE = '42501' THEN v_out_denied := true; END IF;
    END;
    BEGIN
      INSERT INTO public.results (tenant_id, exam_id, student_id)
      VALUES (v_t1, 'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1');
      v_in_ok := true;
    EXCEPTION WHEN OTHERS THEN
      v_in_ok := false;
    END;
    RESET role;
    PERFORM public._t11_assert('S11a out-of-scope results insert denied by RLS', v_out_denied);
    PERFORM public._t11_assert('S11b in-scope results insert allowed', v_in_ok);
  END;
  DELETE FROM public.results WHERE tenant_id = v_t1;
END
$do$;

-- ═══════════════════════════════════════════════════════════════════════
-- §6  RPC / TRIGGER INTERPLAY + IDEMPOTENCY GUARDS
-- ═══════════════════════════════════════════════════════════════════════

DO $do$
DECLARE
  v_before bigint;
  v_after  bigint;
BEGIN
  -- G7: assign_tenant_role provisions scope rows for the new member.
  PERFORM public._t11_set_user('11111111-1111-1111-1111-111111111111'); -- owner_a
  PERFORM public.assign_tenant_role('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '99999999-9999-9999-9999-999999999999', 'teacher');
  PERFORM public._t11_assert('G7 assign_tenant_role provisions all-scope rows',
    EXISTS (SELECT 1 FROM public.permission_scopes ps
             JOIN public.permissions p ON p.id = ps.permission_id
            WHERE ps.tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
              AND ps.user_id   = '99999999-9999-9999-9999-999999999999'
              AND p.code = 'attendance.mark' AND ps.scope_type = 'all'));

  -- G8: re-running the 022 backfill is a data no-op (idempotent).
  SELECT count(*) INTO v_before FROM public.permission_scopes;

  INSERT INTO public.permission_scopes
    (tenant_id, user_id, permission_id, scope_type, scope_ref)
  SELECT tm.tenant_id, tm.user_id, p.id, 'all', '{}'::jsonb
    FROM public.tenant_memberships tm
   CROSS JOIN public.permissions p
   WHERE tm.is_active
     AND public.user_effective_permission(tm.tenant_id, tm.user_id, p.code)
     AND NOT EXISTS (
           SELECT 1 FROM public.permission_scopes ps
            WHERE ps.tenant_id = tm.tenant_id
              AND ps.user_id   = tm.user_id
              AND ps.permission_id = p.id)
  ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;

  INSERT INTO public.permission_scopes
    (tenant_id, user_id, permission_id, scope_type, scope_ref)
  SELECT d.tenant_id, d.delegatee_id, d.permission_id, 'all', '{}'::jsonb
    FROM public.permission_delegations d
    JOIN public.permissions p ON p.id = d.permission_id
   WHERE (d.starts_at IS NULL OR d.starts_at <= now())
     AND (d.expires_at IS NULL OR d.expires_at > now())
     AND NOT public.user_code_denied(d.tenant_id, d.delegatee_id, p.code)
     AND NOT EXISTS (
           SELECT 1 FROM public.permission_scopes ps
            WHERE ps.tenant_id = d.tenant_id
              AND ps.user_id   = d.delegatee_id
              AND ps.permission_id = d.permission_id)
  ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;

  SELECT count(*) INTO v_after FROM public.permission_scopes;
  PERFORM public._t11_assert('G8 022 backfill re-run changes nothing',
    v_after = v_before);
END
$do$;

DO $do$
BEGIN
  RAISE NOTICE 'ALL PHASE-11 AUTHORIZATION TESTS PASSED';
END
$do$;

ROLLBACK;
