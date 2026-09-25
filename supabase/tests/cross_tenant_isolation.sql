-- ═══════════════════════════════════════════════════════════════════════════════
-- Madrassa-360 — Cross-Tenant Isolation Test Suite
-- supabase/tests/cross_tenant_isolation.sql
--
-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  ⚠  NOT YET EXECUTED — written 2026-09-25, awaiting a staging project.   ║
-- ║  This file has been parse-checked locally (pglast) but has NEVER been    ║
-- ║  run against a live database. Do not treat results as verified until    ║
-- ║  it is executed on staging per HOW TO RUN below.                        ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
--
-- PURPOSE
--   Negative security tests for the Phase-2 multi-tenant SaaS transformation
--   (mission §§17, 56). Proves, as real authenticated users, that:
--     1. Tenant A users cannot SELECT / INSERT / UPDATE / DELETE Tenant B rows
--        (students, attendance, fees, announcements, finance_transactions,
--        storage.objects) and vice versa.
--     2. The legacy privilege-escalation classes are dead:
--          - profiles.role is no longer client-writable (role-lock trigger),
--          - tenant_memberships cannot be self-granted (no self-join to another
--            tenant as tenant_admin).
--     3. None of the known legacy/stale RLS policy names from DATABASE_AUDIT.md
--        §10 survive (stale-policy OR-stacking regression guard).
--     4. Legitimate same-tenant access still works (positive control — proves
--        the policies are not accidentally deny-all).
--
-- PREREQUISITES
--   1. Migrations 001–010 applied on a FRESH staging Supabase project
--      (tenants, tenant_settings, tenant_modules, tenant_memberships,
--      platform_admins, SECURITY DEFINER helpers, tenant_id on all 13 business
--      tables, tenant-bound RLS rewrite, tenant storage prefixes).
--   2. pgcrypto extension available (used for test-user password hashing).
--   3. Run as the `postgres` superuser (or any BYPASSRLS role). Setup inserts
--      bypass RLS deliberately; scenario blocks then impersonate test users via
--      SET LOCAL (see AUTH-CONTEXT HELPER below).
--   4. No pre-existing rows with the test UUIDs / slugs below (use a fresh DB).
--   5. The `student-photos` bucket is created by this script if missing.
--
-- HOW TO RUN
--   psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/cross_tenant_isolation.sql
--
-- EXPECTED RESULT
--   A stream of `NOTICE: PASS: ...` lines, one per assertion, ending with
--   `NOTICE: ALL CROSS-TENANT ISOLATION TESTS PASSED`.
--   The script ends with ROLLBACK, so the staging database is left untouched
--   (no test tenants, users, or rows persist).
--   Any `FAIL` raises an EXCEPTION which aborts the run (ON_ERROR_STOP=1);
--   the aborted transaction is discarded, so staging is still untouched.
--
-- AUTH-CONTEXT HELPER PATTERN (used before every scenario block)
--   To act as user U (a UUID):
--     SET LOCAL role TO authenticated;
--     SET LOCAL "request.jwt.claims" TO '{"sub":"<U-uuid>","role":"authenticated"}';
--   After this, auth.uid() returns U and auth.role() returns 'authenticated',
--   so RLS policies evaluate exactly as they would for a real signed-in user.
--   SET LOCAL is transaction-scoped; re-setting per scenario is sufficient
--   (no RESET needed between scenarios). The S1 "sees own row" assertion is
--   the canary: if the auth context were broken, it would fail loudly instead
--   of letting denial-tests pass vacuously.
--
-- CONTRACT ASSUMED (must hold after migrations 001–010 — verified in §0):
--   tenants(id, name, slug) · tenant_memberships(tenant_id, user_id, role, is_active)
--   platform_admins exists · profiles(id, role, name) with role locked for clients
--   is_platform_admin(), is_tenant_member(uuid), tenant_has_permission(uuid, text)
--   — all SECURITY DEFINER. NOTE: there is deliberately NO get_current_tenant_id();
--   multi-tenant users legitimately see every tenant they belong to, so policies
--   join tenant_memberships via is_tenant_member() and the "active tenant" is a
--   UI scoping concept only (see docs/MULTI_TENANCY.md).
--   tenant_id present on students/attendance/fees/announcements/finance_transactions
--   (and the other 8 business tables), RLS enabled on all 13 business tables.
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- Deterministic superuser context for setup (in case the session role differs).
RESET role;

-- ═══════════════════════════════════════════════════════════════════════════════
-- §0  CONTRACT GUARDS — fail fast if migrations 001–010 are not fully applied.
--     These run as superuser (RLS bypassed) and only check the schema shape.
-- ═══════════════════════════════════════════════════════════════════════════════

-- G1: tenants(id, name, slug)
DO $$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='tenants'
        AND column_name IN ('id','name','slug')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G1: public.tenants must have (id, name, slug). Is migration 001 applied?';
  END IF;
  RAISE NOTICE 'PASS: G1 contract — tenants(id, name, slug) present';
END $$;

-- G2: tenant_memberships(tenant_id, user_id, role, is_active)
DO $$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='tenant_memberships'
        AND column_name IN ('tenant_id','user_id','role','is_active')) <> 4 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G2: public.tenant_memberships must have (tenant_id, user_id, role, is_active). Is migration 002 applied?';
  END IF;
  RAISE NOTICE 'PASS: G2 contract — tenant_memberships(tenant_id, user_id, role, is_active) present';
END $$;

-- G3: platform_admins exists
DO $$
BEGIN
  IF to_regclass('public.platform_admins') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT FAIL G3: public.platform_admins missing. Is the platform-admin migration applied?';
  END IF;
  RAISE NOTICE 'PASS: G3 contract — platform_admins present';
END $$;

-- G4: SECURITY DEFINER helpers with the exact contracted signatures
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.prosecdef AND (
        (p.proname = 'is_platform_admin'     AND p.pronargs = 0) OR
        (p.proname = 'is_tenant_member'      AND pg_get_function_identity_arguments(p.oid) = 'uuid') OR
        (p.proname = 'tenant_has_permission' AND pg_get_function_identity_arguments(p.oid) = 'uuid, text')
      )) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G4: expected SECURITY DEFINER helpers is_platform_admin(), is_tenant_member(uuid), tenant_has_permission(uuid, text).';
  END IF;
  RAISE NOTICE 'PASS: G4 contract — SECURITY DEFINER helpers present with exact signatures';
END $$;

-- G5: profiles still carries (id, role, name) — role must exist so the
--     escalation test in S8 is meaningful (a missing column would raise for
--     the wrong reason and give a false PASS).
DO $$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='profiles'
        AND column_name IN ('id','role','name')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G5: public.profiles must keep (id, role, name) with role client-locked, per mission §16.';
  END IF;
  RAISE NOTICE 'PASS: G5 contract — profiles(id, role, name) present';
END $$;

-- G6: tenant_id on the five tables exercised below
DO $$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name IN ('students','attendance','fees','announcements','finance_transactions')
        AND column_name = 'tenant_id') <> 5 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G6: tenant_id missing on a business table. Is migration 004 applied?';
  END IF;
  RAISE NOTICE 'PASS: G6 contract — tenant_id present on students/attendance/fees/announcements/finance_transactions';
END $$;

-- G7: RLS enabled on all 13 business tables
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_tables
      WHERE schemaname='public' AND rowsecurity
        AND tablename IN ('students','staff','darjas','classes','attendance','fees',
                          'exams','results','announcements','darja_sections',
                          'library_books','book_issues','finance_transactions')) <> 13 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G7: RLS is not enabled on all 13 business tables.';
  END IF;
  RAISE NOTICE 'PASS: G7 contract — RLS enabled on all 13 business tables';
END $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- §1  SETUP (superuser — RLS bypassed). Two tenants, four users, one row per
--     tenant in students / attendance / fees / announcements /
--     finance_transactions, plus one storage object per tenant.
--     Fixed UUIDs keep the script readable and re-runnable on a fresh DB.
-- ═══════════════════════════════════════════════════════════════════════════════
--  Tenant A  aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa   slug 'test-a'
--  Tenant B  bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb   slug 'test-b'
--  adminA    11111111-1111-1111-1111-111111111111   tenant_admin of A
--  teacherA  22222222-2222-2222-2222-222222222222   teacher of A
--  adminB    33333333-3333-3333-3333-333333333333   tenant_admin of B
--  teacherB  44444444-4444-4444-4444-444444444444   teacher of B

INSERT INTO public.tenants (id, name, slug) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Test Madrasa A', 'test-a'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Test Madrasa B', 'test-b');

-- auth.users rows. instance_id is NOT NULL in GoTrue — read the live instance.
DO $$
DECLARE
  v_instance_id uuid;
BEGIN
  SELECT id INTO v_instance_id FROM auth.instances LIMIT 1;
  IF v_instance_id IS NULL THEN
    RAISE EXCEPTION 'SETUP FAIL: auth.instances is empty — not a real Supabase project?';
  END IF;

  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
  VALUES
    (v_instance_id, '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated',
     'admin-a@tenant-a.test',   crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb),
    (v_instance_id, '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
     'teacher-a@tenant-a.test', crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb),
    (v_instance_id, '33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated',
     'admin-b@tenant-b.test',   crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb),
    (v_instance_id, '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated',
     'teacher-b@tenant-b.test', crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb);
END $$;

-- profiles rows. The on_auth_user_created trigger may already have created
-- them (with a default role); the upsert covers both cases. role is left
-- untouched — the trigger/default owns it, and S8 proves clients can't change it.
INSERT INTO public.profiles (id, name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Admin A'),
  ('22222222-2222-2222-2222-222222222222', 'Teacher A'),
  ('33333333-3333-3333-3333-333333333333', 'Admin B'),
  ('44444444-4444-4444-4444-444444444444', 'Teacher B')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- Snapshot teacherA's pre-test role so S8 can prove it is unchanged afterwards.
CREATE TEMP TABLE _t_role_before AS
  SELECT role FROM public.profiles WHERE id = '22222222-2222-2222-2222-222222222222';

INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'tenant_admin', true),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'teacher',      true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '33333333-3333-3333-3333-333333333333', 'tenant_admin', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'teacher',      true);

-- One class per tenant (attendance.class_id is NOT NULL).
INSERT INTO public.classes (id, tenant_id, name) VALUES
  ('aa11aa11-aa11-aa11-aa11-aa11aa11aa11', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Test Class A'),
  ('bb22bb22-bb22-bb22-bb22-bb22bb22bb22', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Test Class B');

-- One student per tenant (minimal NOT NULL columns: roll_no, name, father_name).
INSERT INTO public.students (id, tenant_id, roll_no, name, father_name) VALUES
  ('a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'TST-A-001', 'Student A', 'Father A'),
  ('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'TST-B-001', 'Student B', 'Father B');

INSERT INTO public.attendance (id, tenant_id, student_id, class_id, teacher_id, date, status) VALUES
  ('a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'aa11aa11-aa11-aa11-aa11-aa11aa11aa11',
   '11111111-1111-1111-1111-111111111111', CURRENT_DATE, 'present'),
  ('b4b4b4b4-b4b4-b4b4-b4b4-b4b4b4b4b4b4', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'bb22bb22-bb22-bb22-bb22-bb22bb22bb22',
   '33333333-3333-3333-3333-333333333333', CURRENT_DATE, 'present');

INSERT INTO public.fees (id, tenant_id, student_id, month, amount_due, due_date) VALUES
  ('a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', '2026-09', 500, DATE '2026-09-30'),
  ('b6b6b6b6-b6b6-b6b6-b6b6-b6b6b6b6b6b6', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', '2026-09', 500, DATE '2026-09-30');

INSERT INTO public.announcements (id, tenant_id, title, body) VALUES
  ('a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'Announcement A', 'Body for tenant A'),
  ('b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'Announcement B', 'Body for tenant B');

INSERT INTO public.finance_transactions (id, tenant_id, type, amount, description) VALUES
  ('a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'donation', 10000, 'Test donation A'),
  ('b0b0b0b0-b0b0-b0b0-b0b0-b0b0b0b0b0b0', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'donation', 20000, 'Test donation B');

-- Storage: one object per tenant under the {tenant_id}/ prefix convention.
INSERT INTO storage.buckets (id, name, public)
  VALUES ('student-photos', 'student-photos', false)
  ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.objects (bucket_id, name, owner, metadata) VALUES
  ('student-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/photo-a.jpg',
   '11111111-1111-1111-1111-111111111111', '{}'::jsonb),
  ('student-photos', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/photo-b.jpg',
   '33333333-3333-3333-3333-333333333333', '{}'::jsonb);

-- ═══════════════════════════════════════════════════════════════════════════════
-- §2  CROSS-TENANT ISOLATION MATRIX
--     Convention per scenario: SET LOCAL auth context → DO $$ assertion $$.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── S1: Admin A — student SELECT isolation ─────────────────────────────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A1 (canary): Admin A sees exactly her own tenant's student.
-- If this fails, the auth context itself is broken — investigate before
-- trusting any denial below.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.students) <> 1 THEN
    RAISE EXCEPTION 'FAIL: S1-A1 adminA student SELECT — expected 1 row (own tenant), got %',
      (SELECT count(*) FROM public.students);
  ELSE
    RAISE NOTICE 'PASS: S1-A1 adminA SELECT students → sees Student A only (count=1)';
  END IF;
END $$;

-- A2: Admin A must see ZERO rows of Tenant B.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.students
      WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S1-A2 adminA student SELECT — Tenant B rows are visible cross-tenant';
  ELSE
    RAISE NOTICE 'PASS: S1-A2 adminA SELECT students of Tenant B → 0 rows';
  END IF;
END $$;

-- ── S2: Admin A — student UPDATE/DELETE denial on Tenant B's row ────────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A3: UPDATE of Student B must affect 0 rows (RLS hides the row from the
--     WHERE clause, so a broken policy can't silently rewrite B's data).
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.students SET name = 'Tampered by A'
   WHERE id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S2-A3 adminA UPDATE Student B — % row(s) affected (cross-tenant write!)', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S2-A3 adminA UPDATE Student B → 0 rows affected';
  END IF;
END $$;

-- A4: DELETE of Student B must affect 0 rows.
DO $$
DECLARE v_rows int;
BEGIN
  DELETE FROM public.students
   WHERE id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S2-A4 adminA DELETE Student B — % row(s) affected (cross-tenant delete!)', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S2-A4 adminA DELETE Student B → 0 rows affected';
  END IF;
END $$;

-- ── S3: Teacher A — fees SELECT isolation ────────────────────────────────────
-- Kills the old `fees_teacher_read` leak class (DATABASE_AUDIT.md §3a):
-- teachers must never see another tenant's fee records.
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

-- A5: Teacher A must see ZERO fee rows of Tenant B (no assertion is made
--     about her own tenant's rows — that depends on the permission mapping,
--     not on isolation).
DO $$
BEGIN
  IF (SELECT count(*) FROM public.fees
      WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S3-A5 teacherA fees SELECT — Tenant B fee rows visible (fees_teacher_read leak class alive)';
  ELSE
    RAISE NOTICE 'PASS: S3-A5 teacherA SELECT fees of Tenant B → 0 rows';
  END IF;
END $$;

-- ── S4: Admin A — cross-tenant INSERT must raise 42501 ──────────────────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A6: INSERT with tenant_id=B must be rejected by the WITH CHECK clause
--     (SQLSTATE 42501 = insufficient_privilege, the RLS new-row violation).
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO public.students (tenant_id, roll_no, name, father_name)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'X-INTRUDER', 'Intruder', 'Nobody');
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S4-A6 adminA INSERT student with tenant_id=B blocked with 42501 (RLS WITH CHECK)';
  ELSIF v_state IS NULL THEN
    RAISE EXCEPTION 'FAIL: S4-A6 adminA INSERT student with tenant_id=B — cross-tenant INSERT succeeded';
  ELSE
    RAISE EXCEPTION 'FAIL: S4-A6 adminA INSERT student with tenant_id=B — raised % instead of 42501', v_state;
  END IF;
END $$;

-- ── S5: Admin B — cross-tenant announcement INSERT must raise 42501 ─────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

-- A7: symmetric to A6 on announcements (the other direction's tenant).
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO public.announcements (tenant_id, title, body)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Fake', 'Injected into tenant A');
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S5-A7 adminB INSERT announcement with tenant_id=A blocked with 42501 (RLS WITH CHECK)';
  ELSIF v_state IS NULL THEN
    RAISE EXCEPTION 'FAIL: S5-A7 adminB INSERT announcement with tenant_id=A — cross-tenant INSERT succeeded';
  ELSE
    RAISE EXCEPTION 'FAIL: S5-A7 adminB INSERT announcement with tenant_id=A — raised % instead of 42501', v_state;
  END IF;
END $$;

-- ── S6: Attendance cross-tenant SELECT/UPDATE denial, BOTH directions ──────
-- A→B as Admin A:
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A8
DO $$
BEGIN
  IF (SELECT count(*) FROM public.attendance
      WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S6-A8 adminA attendance SELECT — Tenant B rows visible cross-tenant';
  ELSE
    RAISE NOTICE 'PASS: S6-A8 adminA SELECT attendance of Tenant B → 0 rows';
  END IF;
END $$;

-- A9
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.attendance SET note = 'tampered by A'
   WHERE id = 'b4b4b4b4-b4b4-b4b4-b4b4-b4b4b4b4b4b4';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S6-A9 adminA UPDATE Tenant B attendance — % row(s) affected', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S6-A9 adminA UPDATE Tenant B attendance → 0 rows affected';
  END IF;
END $$;

-- B→A as Admin B:
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

-- A10
DO $$
BEGIN
  IF (SELECT count(*) FROM public.attendance
      WHERE tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S6-A10 adminB attendance SELECT — Tenant A rows visible cross-tenant';
  ELSE
    RAISE NOTICE 'PASS: S6-A10 adminB SELECT attendance of Tenant A → 0 rows';
  END IF;
END $$;

-- A11
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.attendance SET note = 'tampered by B'
   WHERE id = 'a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S6-A11 adminB UPDATE Tenant A attendance — % row(s) affected', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S6-A11 adminB UPDATE Tenant A attendance → 0 rows affected';
  END IF;
END $$;

-- ── S7: Teacher A (no finance role) — finance_transactions isolation ────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

-- A12: an accountant-less teacher must see ZERO finance rows of Tenant B
--      (donations/zakat amounts and donor names are the most sensitive rows).
DO $$
BEGIN
  IF (SELECT count(*) FROM public.finance_transactions
      WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S7-A12 teacherA finance SELECT — Tenant B finance rows visible';
  ELSE
    RAISE NOTICE 'PASS: S7-A12 teacherA SELECT finance_transactions of Tenant B → 0 rows';
  END IF;
END $$;

-- ── S8: Role-escalation attempt on profiles (kills DATABASE_AUDIT.md §8#1) ───
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

-- A13: teacherA tries to escalate her own profile to platform_owner.
--      Must raise (role-lock trigger). ANY error counts as blocked here —
--      G5 already proved the `role` column exists, so a raise cannot be a
--      false positive from a missing column.
DO $$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    UPDATE public.profiles SET role = 'platform_owner'
     WHERE id = '22222222-2222-2222-2222-222222222222';
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
    RAISE NOTICE '  (escalation attempt blocked with %: %)', SQLSTATE, SQLERRM;
  END;
  IF v_blocked THEN
    RAISE NOTICE 'PASS: S8-A13 teacherA UPDATE profiles.role → denied (escalation blocked)';
  ELSE
    RAISE EXCEPTION 'FAIL: S8-A13 teacherA UPDATE profiles.role — role escalation SUCCEEDED';
  END IF;
END $$;

-- A14: the role value must be unchanged after the blocked attempt.
--      Checked as superuser so profile-visibility policy can't mask the read.
RESET role;
DO $$
DECLARE v_role text;
BEGIN
  SELECT role INTO v_role FROM public.profiles
   WHERE id = '22222222-2222-2222-2222-222222222222';
  IF v_role IS DISTINCT FROM (SELECT role FROM _t_role_before) THEN
    RAISE EXCEPTION 'FAIL: S8-A14 profiles.role changed despite blocked UPDATE (now %)', v_role;
  ELSE
    RAISE NOTICE 'PASS: S8-A14 profiles.role unchanged after escalation attempt (%)', v_role;
  END IF;
END $$;

-- A15: the legitimate self-update path must still work — teacherA renames
--      her OWN profile (non-role column). Proves the lock is a scalpel,
--      not a blanket deny on profiles.
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.profiles SET name = 'Teacher A (self-edit)'
   WHERE id = '22222222-2222-2222-2222-222222222222';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: S8-A15 teacherA self name-update — expected 1 row, got %', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S8-A15 teacherA UPDATE own profiles.name → 1 row (legit self-update works)';
  END IF;
END $$;

-- ── S9: Tenant-membership tamper — self-join to Tenant B as tenant_admin ─────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

-- A16: teacherA (a teacher of A, stranger to B) must NOT be able to grant
--      herself tenant_admin of B. Any denial counts — the row must not exist.
DO $$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            '22222222-2222-2222-2222-222222222222', 'tenant_admin', true);
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
    RAISE NOTICE '  (tamper attempt blocked with %: %)', SQLSTATE, SQLERRM;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'FAIL: S9-A16 teacherA INSERT tenant_memberships — self-granted tenant_admin of B';
  ELSIF EXISTS (SELECT 1 FROM public.tenant_memberships
                WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                  AND user_id   = '22222222-2222-2222-2222-222222222222') THEN
    -- Defensive: if the INSERT "succeeded" without raising (e.g. swallowed),
    -- the row's presence is itself the failure. (Runs under teacherA; if she
    -- can't see memberships at all, EXISTS is false → still a PASS, which is
    -- the safe direction: nothing was granted that she can observe.)
    RAISE EXCEPTION 'FAIL: S9-A16 teacherA INSERT tenant_memberships — tamper row exists';
  ELSE
    RAISE NOTICE 'PASS: S9-A16 teacherA INSERT tenant_memberships(tenant B, tenant_admin) → denied';
  END IF;
END $$;

-- ── S10: Storage isolation — student-photos bucket (kills §3d leaks) ─────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A17: adminA must NOT be able to write an object under Tenant B's prefix.
DO $$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, metadata)
    VALUES ('student-photos', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/evil.jpg',
            '11111111-1111-1111-1111-111111111111', '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
    RAISE NOTICE '  (cross-tenant object write blocked with %: %)', SQLSTATE, SQLERRM;
  END;
  IF v_blocked THEN
    RAISE NOTICE 'PASS: S10-A17 adminA INSERT storage.objects under Tenant B prefix → denied';
  ELSE
    RAISE EXCEPTION 'FAIL: S10-A17 adminA INSERT storage.objects — cross-tenant object write succeeded';
  END IF;
END $$;

-- A18: adminA must see ZERO objects under Tenant B's prefix
--      (old `student_photos_auth_select` let every authenticated user read
--      every student's photo — photos of minors, cross-tenant).
DO $$
BEGIN
  IF (SELECT count(*) FROM storage.objects
      WHERE bucket_id = 'student-photos'
        AND split_part(name, '/', 1) = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S10-A18 adminA storage SELECT — Tenant B photo objects visible (photo PII leak)';
  ELSE
    RAISE NOTICE 'PASS: S10-A18 adminA SELECT Tenant B photo objects → 0 rows';
  END IF;
END $$;

-- A19: positive storage control — adminA still sees her OWN tenant's object.
DO $$
BEGIN
  IF (SELECT count(*) FROM storage.objects
      WHERE bucket_id = 'student-photos'
        AND split_part(name, '/', 1) = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') <> 1 THEN
    RAISE EXCEPTION 'FAIL: S10-A19 adminA storage SELECT — own-tenant object not visible';
  ELSE
    RAISE NOTICE 'PASS: S10-A19 adminA SELECT own-tenant photo object → 1 row';
  END IF;
END $$;

-- ── S11: Stale-policy regression guard (DATABASE_AUDIT.md §10) ───────────────
-- Runs as superuser (RLS-independent catalog read). Asserts that NONE of the
-- 45 legacy policy names from the 02_rls.sql / 03_storage.sql /
-- 05_new_modules.sql eras still exist — if any survived migration 005's
-- exact-name drops, they would OR-stack with the new tenant-bound policies
-- and silently re-open the old leaks.
RESET role;
DO $$
DECLARE v_found text;
BEGIN
  SELECT string_agg(policyname, ', ' ORDER BY policyname) INTO v_found
  FROM pg_policies
  WHERE policyname IN (
    -- 02_rls.sql era (06_rbac.sql's DROPs targeted wrong names; these are the real ones)
    'profiles_view_own','profiles_update_own','profiles_admin_view_all',
    'profiles_admin_update_all','profiles_insert_own',
    'darjas_read','darjas_admin_write','classes_read','classes_admin_write',
    'students_admin_all','students_teacher_view','students_parent_view_own',
    'staff_admin_all','staff_teacher_view',
    'attendance_admin_all','attendance_teacher_manage','attendance_parent_view_own',
    'fees_admin_all','fees_teacher_read','fees_parent_view_own',
    'exams_read_all_auth','exams_admin_all',
    'results_admin_all','results_teacher_manage','results_parent_view_own',
    'announcements_read','announcements_admin_all',
    -- 03_storage.sql era (all-authenticated / all-teacher photo & document reads)
    'student_photos_admin_insert','student_photos_admin_update',
    'student_photos_auth_select','student_photos_admin_delete',
    'staff_photos_admin_insert','staff_photos_admin_update',
    'staff_photos_auth_select','staff_photos_admin_delete',
    'documents_admin_insert','documents_admin_update',
    'documents_staff_select','documents_parent_select','documents_admin_delete',
    -- 05_new_modules.sql era (never superseded by 06)
    'superAdmin full access on madrasas','admin sees own madrasa',
    'admin manage darja_sections','authenticated users read darja_sections',
    'superAdmin manage announcements'
  );
  IF v_found IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: S11 stale-policy guard — legacy policies still present: %', v_found;
  ELSE
    RAISE NOTICE 'PASS: S11 stale-policy guard — none of the 45 legacy policy names exist';
  END IF;
END $$;

-- ── S12: Positive control — Admin A full CRUD on her OWN tenant ──────────────
-- Proves the new policies are not accidentally deny-all. Uses a dedicated row
-- (c1c1…) so Student A (referenced by attendance/fees) is never touched.
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A20: INSERT own-tenant student succeeds.
DO $$
BEGIN
  INSERT INTO public.students (id, tenant_id, roll_no, name, father_name)
  VALUES ('c1c1c1c1-c1c1-c1c1-c1c1-c1c1c1c1c1c1',
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'TST-A-002', 'Student CRUD', 'Father CRUD');
  RAISE NOTICE 'PASS: S12-A20 adminA INSERT own-tenant student → succeeded';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL: S12-A20 adminA INSERT own-tenant student — raised %: %', SQLSTATE, SQLERRM;
END $$;

-- A21: SELECT sees the new row.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.students
      WHERE id = 'c1c1c1c1-c1c1-c1c1-c1c1-c1c1c1c1c1c1') <> 1 THEN
    RAISE EXCEPTION 'FAIL: S12-A21 adminA SELECT own-tenant student — row not visible';
  ELSE
    RAISE NOTICE 'PASS: S12-A21 adminA SELECT own-tenant student → 1 row';
  END IF;
END $$;

-- A22: UPDATE own-tenant student affects 1 row.
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.students SET name = 'Student CRUD (edited)'
   WHERE id = 'c1c1c1c1-c1c1-c1c1-c1c1-c1c1c1c1c1c1';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: S12-A22 adminA UPDATE own-tenant student — expected 1 row, got %', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S12-A22 adminA UPDATE own-tenant student → 1 row affected';
  END IF;
END $$;

-- A23: DELETE own-tenant student affects 1 row.
DO $$
DECLARE v_rows int;
BEGIN
  DELETE FROM public.students
   WHERE id = 'c1c1c1c1-c1c1-c1c1-c1c1-c1c1c1c1c1c1';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: S12-A23 adminA DELETE own-tenant student — expected 1 row, got %', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S12-A23 adminA DELETE own-tenant student → 1 row affected';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- FINALE — back to superuser, announce, and leave staging untouched.
-- ═══════════════════════════════════════════════════════════════════════════════
RESET role;

DO $$
BEGIN
  RAISE NOTICE 'ALL CROSS-TENANT ISOLATION TESTS PASSED';
END $$;

ROLLBACK;
