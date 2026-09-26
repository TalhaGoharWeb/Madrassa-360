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
--   (mission §§17, 56), extended in Phase 8 (Worker 3) to cover migrations
--   011–018. Proves, as real authenticated users, that:
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
--     5. The 011–018 surfaces hold:
--          - storage isolation on ALL THREE buckets (student-photos,
--            staff-photos, documents) under the {tenant_id}/ prefix rule;
--          - permission-code boundaries: a teacher WITHOUT fees.collect /
--            fees.create / documents.manage cannot INSERT payments /
--            invoices / documents;
--          - parent↔child links via student_guardians: a parent sees only
--            their own family's rows (same-tenant other-family AND
--            cross-tenant denial);
--          - platform_config: tenant admins can read (public) but never
--            write — writes are platform-admin only;
--          - finance immutability: UPDATE/DELETE of a posted transaction
--            fails even for a tenant admin (RLS default-deny), and the
--            finance_immutable_guard() trigger raises as the backstop.
--
--   44 assertions (A1–A44) + 9 contract guards (G1–G9) = 53 checks.
--
-- PREREQUISITES
--   1. Migrations 001–018 applied on a FRESH staging Supabase project
--      (tenants, tenant_settings, tenant_modules, tenant_memberships,
--      platform_admins, SECURITY DEFINER helpers, tenant_id on all 13 business
--      tables, tenant-bound RLS rewrite, tenant storage prefixes, licensing,
--      audit logs, finance ledger with posted-row immutability, parent links,
--      sync columns, notifications, platform_config/devices).
--   2. pgcrypto extension available (used for test-user password hashing).
--   3. Run as the `postgres` superuser (or any BYPASSRLS role). Setup inserts
--      bypass RLS deliberately; scenario blocks then impersonate test users via
--      SET LOCAL (see AUTH-CONTEXT HELPER below).
--   4. No pre-existing rows with the test UUIDs / slugs below (use a fresh DB).
--   5. The three storage buckets are created by migration 008; this script
--      re-asserts them idempotently.
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
-- CONTRACT ASSUMED (must hold after migrations 001–018 — verified in §0):
--   tenants(id, name, slug) · tenant_memberships(tenant_id, user_id, role, is_active)
--   platform_admins exists · profiles(id, role, name) with role locked for clients
--   is_platform_admin(), is_tenant_member(uuid), tenant_has_permission(uuid, text)
--   — all SECURITY DEFINER. NOTE: there is deliberately NO get_current_tenant_id();
--   multi-tenant users legitimately see every tenant they belong to, so policies
--   join tenant_memberships via is_tenant_member() and the "active tenant" is a
--   UI scoping concept only (see docs/MULTI_TENANCY.md).
--   tenant_id present on students/attendance/fees/announcements/finance_transactions
--   (and the other 8 business tables), RLS enabled on all 13 business tables.
--   011–018 additions exercised below: platform_config(key, latest_version),
--   student_guardians(tenant_id, student_id, guardian_user_id),
--   transactions(tenant_id, status, kind, category, amount),
--   payments/invoices(tenant_id, status); storage buckets student-photos /
--   staff-photos / documents with {tenant_id}/-prefixed policies from 008.
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- Deterministic superuser context for setup (in case the session role differs).
RESET role;

-- ═══════════════════════════════════════════════════════════════════════════════
-- §0  CONTRACT GUARDS — fail fast if migrations 001–018 are not fully applied.
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
-- DRIFT FIX (2026-09-25 re-verification, Worker 3): the original guard
-- compared pg_get_function_identity_arguments(p.oid) to 'uuid' / 'uuid, text'.
-- That can NEVER match: the function returns 'p_tenant_id uuid' — it includes
-- parameter NAMES and excludes OUT (TABLE) params (verified empirically on
-- PG16). G4 would have failed on staging with count=1. The guard now compares
-- pronargs + proargtypes element-wise (input arg types only): rename-proof,
-- default-proof, OUT-param-proof.
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.prosecdef AND (
        (p.proname = 'is_platform_admin'     AND p.pronargs = 0) OR
        (p.proname = 'is_tenant_member'      AND p.pronargs = 1
           AND p.proargtypes[0] = 'uuid'::regtype) OR
        (p.proname = 'tenant_has_permission' AND p.pronargs = 2
           AND p.proargtypes[0] = 'uuid'::regtype
           AND p.proargtypes[1] = 'text'::regtype)
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

-- G6: tenant_id on the five tables exercised below (006 retrofit; 007 depends on it).
--     (Comment corrected 2026-09-25: tenant MEMBERSHIPS are migration 004;
--      the tenant_id column retrofit itself is migration 006, not 004.)
DO $$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name IN ('students','attendance','fees','announcements','finance_transactions')
        AND column_name = 'tenant_id') <> 5 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G6: tenant_id missing on a business table. Is migration 006 applied?';
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

-- G8: 011–018 tables exist with the columns the extended scenarios touch.
--     Fails fast (before any scenario) if migrations 011–018 are missing.
DO $$
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='platform_config'
        AND column_name IN ('key','latest_version')) <> 2
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='student_guardians'
        AND column_name IN ('tenant_id','student_id','guardian_user_id')) <> 3
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='transactions'
        AND column_name IN ('tenant_id','status','kind','category','amount')) <> 5
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='payments'
        AND column_name IN ('tenant_id','status')) <> 2
     OR (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='invoices'
        AND column_name IN ('tenant_id','status','due_date')) <> 3
  THEN
    RAISE EXCEPTION 'CONTRACT FAIL G8: 011–018 tables/columns missing (platform_config, student_guardians, transactions, payments, invoices). Are migrations 011–018 applied?';
  END IF;
  RAISE NOTICE 'PASS: G8 contract — 011–018 tables present with expected columns';
END $$;

-- G9: RLS enabled on the 011–018 tables the extended scenarios touch.
DO $$
BEGIN
  IF (SELECT count(*) FROM pg_tables
      WHERE schemaname='public' AND rowsecurity
        AND tablename IN ('platform_config','devices','device_sessions',
                          'student_guardians','teacher_class_assignments',
                          'transactions','payments','invoices',
                          'notifications','audit_logs','licenses')) <> 10 THEN
    RAISE EXCEPTION 'CONTRACT FAIL G9: RLS is not enabled on all 011–018 scenario tables.';
  END IF;
  RAISE NOTICE 'PASS: G9 contract — RLS enabled on 011–018 scenario tables';
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
--  parentA1  55555555-5555-5555-5555-555555555555   parent of Student A (tenant A)
--  parentA2  66666666-6666-6666-6666-666666666666   parent of Student A2 (tenant A, other family)
--  parentB   77777777-7777-7777-7777-777777777777   parent of Student B (tenant B)

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
     'teacher-b@tenant-b.test', crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb),
    (v_instance_id, '55555555-5555-5555-5555-555555555555', 'authenticated', 'authenticated',
     'parent-a1@tenant-a.test', crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb),
    (v_instance_id, '66666666-6666-6666-6666-666666666666', 'authenticated', 'authenticated',
     'parent-a2@tenant-a.test', crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb),
    (v_instance_id, '77777777-7777-7777-7777-777777777777', 'authenticated', 'authenticated',
     'parent-b@tenant-b.test',  crypt('Test1234!', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb);
END $$;

-- profiles rows. The on_auth_user_created trigger may already have created
-- them (with a default role); the upsert covers both cases. role is left
-- untouched — the trigger/default owns it, and S8 proves clients can't change it.
INSERT INTO public.profiles (id, name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Admin A'),
  ('22222222-2222-2222-2222-222222222222', 'Teacher A'),
  ('33333333-3333-3333-3333-333333333333', 'Admin B'),
  ('44444444-4444-4444-4444-444444444444', 'Teacher B'),
  ('55555555-5555-5555-5555-555555555555', 'Parent A1'),
  ('66666666-6666-6666-6666-666666666666', 'Parent A2'),
  ('77777777-7777-7777-7777-777777777777', 'Parent B')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- Snapshot teacherA's pre-test role so S8 can prove it is unchanged afterwards.
CREATE TEMP TABLE _t_role_before AS
  SELECT role FROM public.profiles WHERE id = '22222222-2222-2222-2222-222222222222';

INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'tenant_admin', true),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'teacher',      true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '33333333-3333-3333-3333-333333333333', 'tenant_admin', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '44444444-4444-4444-4444-444444444444', 'teacher',      true),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', 'parent',       true),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '66666666-6666-6666-6666-666666666666', 'parent',       true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '77777777-7777-7777-7777-777777777777', 'parent',       true);

-- One class per tenant (attendance.class_id is NOT NULL).
INSERT INTO public.classes (id, tenant_id, name) VALUES
  ('aa11aa11-aa11-aa11-aa11-aa11aa11aa11', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Test Class A'),
  ('bb22bb22-bb22-bb22-bb22-bb22bb22bb22', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Test Class B');

-- One student per tenant (minimal NOT NULL columns: roll_no, name, father_name),
-- plus a second student in Tenant A so parent isolation has two families.
-- 'TST-A-002' is reserved for S12's transient CRUD row.
INSERT INTO public.students (id, tenant_id, roll_no, name, father_name) VALUES
  ('a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'TST-A-001', 'Student A', 'Father A'),
  ('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'TST-B-001', 'Student B', 'Father B'),
  ('d2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'TST-A-003', 'Student A2', 'Father A2');

-- Parent↔child links: one guardian row per family, per tenant.
INSERT INTO public.student_guardians
  (id, tenant_id, student_id, guardian_user_id, relationship, is_primary) VALUES
  ('e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', '55555555-5555-5555-5555-555555555555', 'father', true),
  ('e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'd2d2d2d2-d2d2-d2d2-d2d2-d2d2d2d2d2d2', '66666666-6666-6666-6666-666666666666', 'mother', true),
  ('e3e3e3e3-e3e3-e3e3-e3e3-e3e3e3e3e3e3', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', '77777777-7777-7777-7777-777777777777', 'father', true);

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

-- Storage: one object per tenant under the {tenant_id}/ prefix convention,
-- for ALL THREE buckets (008 creates them; ON CONFLICT keeps this re-runnable).
INSERT INTO storage.buckets (id, name, public)
  VALUES ('student-photos', 'student-photos', false),
         ('staff-photos',   'staff-photos',   false),
         ('documents',      'documents',      false)
  ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.objects (bucket_id, name, owner, metadata) VALUES
  ('student-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/photo-a.jpg',
   '11111111-1111-1111-1111-111111111111', '{}'::jsonb),
  ('student-photos', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/photo-b.jpg',
   '33333333-3333-3333-3333-333333333333', '{}'::jsonb),
  ('staff-photos', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/staff-a.jpg',
   '11111111-1111-1111-1111-111111111111', '{}'::jsonb),
  ('staff-photos', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/staff-b.jpg',
   '33333333-3333-3333-3333-333333333333', '{}'::jsonb),
  ('documents', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/doc-a.pdf',
   '11111111-1111-1111-1111-111111111111', '{}'::jsonb),
  ('documents', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/doc-b.pdf',
   '33333333-3333-3333-3333-333333333333', '{}'::jsonb);

-- Finance ledger (014): one POSTED (finalized) and one DRAFT transaction in
-- Tenant A. Posted rows must be untouchable even for tenant admins (S18).
INSERT INTO public.transactions
  (id, tenant_id, kind, category, amount, status) VALUES
  ('f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'expense', 'test', 100, 'posted'),
  ('f2f2f2f2-f2f2-f2f2-f2f2-f2f2f2f2f2f2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'expense', 'test', 50, 'draft');

-- ═══════════════════════════════════════════════════════════════════════════════
-- §2  CROSS-TENANT ISOLATION MATRIX
--     Convention per scenario: SET LOCAL auth context → DO $$ assertion $$.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── S1: Admin A — student SELECT isolation ─────────────────────────────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A1 (canary): Admin A sees exactly her own tenant's students.
-- If this fails, the auth context itself is broken — investigate before
-- trusting any denial below.
-- (Count is 2 since 2026-09-25: Student A + Student A2 for parent isolation.)
DO $$
BEGIN
  IF (SELECT count(*) FROM public.students) <> 2 THEN
    RAISE EXCEPTION 'FAIL: S1-A1 adminA student SELECT — expected 2 rows (own tenant), got %',
      (SELECT count(*) FROM public.students);
  ELSE
    RAISE NOTICE 'PASS: S1-A1 adminA SELECT students → sees own tenant only (count=2)';
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
--      herself tenant_admin of B. The expected denial is SQLSTATE 42501 —
--      an RLS WITH CHECK violation (neither the tenant-admin nor the
--      platform-admin branch of the INSERT policy holds for her).
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            '22222222-2222-2222-2222-222222222222', 'tenant_admin', true);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
    RAISE NOTICE '  (tamper attempt blocked with %: %)', SQLSTATE, SQLERRM;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S9-A16 teacherA INSERT tenant_memberships(tenant B, tenant_admin) → denied with 42501 (RLS WITH CHECK)';
  ELSIF v_state IS NULL THEN
    -- Defensive: if the INSERT "succeeded" without raising (e.g. swallowed),
    -- the row's presence is itself the failure. (Runs under teacherA; if she
    -- can't see memberships at all, EXISTS is false → still a PASS, which is
    -- the safe direction: nothing was granted that she can observe.)
    IF EXISTS (SELECT 1 FROM public.tenant_memberships
               WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
                 AND user_id   = '22222222-2222-2222-2222-222222222222') THEN
      RAISE EXCEPTION 'FAIL: S9-A16 teacherA INSERT tenant_memberships — tamper row exists';
    ELSE
      RAISE EXCEPTION 'FAIL: S9-A16 teacherA INSERT tenant_memberships — succeeded without raising';
    END IF;
  ELSE
    RAISE EXCEPTION 'FAIL: S9-A16 teacherA INSERT tenant_memberships — raised % instead of 42501', v_state;
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
-- S13–S18: Phase-8 extensions — 011–018 surfaces (Worker 3).
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── S13: Storage isolation — staff-photos bucket ─────────────────────────────
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A24: adminA must see ZERO staff-photos objects under Tenant B's prefix.
DO $$
BEGIN
  IF (SELECT count(*) FROM storage.objects
      WHERE bucket_id = 'staff-photos'
        AND split_part(name, '/', 1) = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S13-A24 adminA staff-photos SELECT — Tenant B objects visible cross-tenant';
  ELSE
    RAISE NOTICE 'PASS: S13-A24 adminA SELECT staff-photos of Tenant B → 0 rows';
  END IF;
END $$;

-- A25: adminA must NOT write under Tenant B's prefix → 42501
-- (staff_photos_insert_tenant needs is_tenant_member(B) AND
-- tenant_has_permission(B, 'staff.update'); adminA is a stranger to B).
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, metadata)
    VALUES ('staff-photos', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/evil.jpg',
            '11111111-1111-1111-1111-111111111111', '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S13-A25 adminA INSERT staff-photos under Tenant B prefix → denied with 42501';
  ELSE
    RAISE EXCEPTION 'FAIL: S13-A25 adminA INSERT staff-photos under Tenant B prefix — state=% (expected 42501)', v_state;
  END IF;
END $$;

-- A26 (canary): adminA sees her own tenant's staff photo.
DO $$
BEGIN
  IF (SELECT count(*) FROM storage.objects
      WHERE bucket_id = 'staff-photos'
        AND split_part(name, '/', 1) = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') <> 1 THEN
    RAISE EXCEPTION 'FAIL: S13-A26 adminA staff-photos SELECT — own tenant object not visible';
  ELSE
    RAISE NOTICE 'PASS: S13-A26 adminA SELECT own staff-photos object → 1 row';
  END IF;
END $$;

-- ── S14: Storage isolation — documents bucket ───────────────────────────────
-- A27: adminA must see ZERO documents under Tenant B's prefix.
DO $$
BEGIN
  IF (SELECT count(*) FROM storage.objects
      WHERE bucket_id = 'documents'
        AND split_part(name, '/', 1) = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S14-A27 adminA documents SELECT — Tenant B objects visible cross-tenant';
  ELSE
    RAISE NOTICE 'PASS: S14-A27 adminA SELECT documents of Tenant B → 0 rows';
  END IF;
END $$;

-- A28: adminA must NOT write under Tenant B's prefix → 42501.
-- (documents_insert_tenant needs is_tenant_member(B) AND
-- tenant_has_permission(B, 'documents.manage'); adminA is a stranger to B.)
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, metadata)
    VALUES ('documents', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/evil.pdf',
            '11111111-1111-1111-1111-111111111111', '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S14-A28 adminA INSERT documents under Tenant B prefix → denied with 42501';
  ELSE
    RAISE EXCEPTION 'FAIL: S14-A28 adminA INSERT documents under Tenant B prefix — state=% (expected 42501)', v_state;
  END IF;
END $$;

-- A29: teacherA must NOT write documents even in her OWN tenant — she lacks
--      the documents.manage permission (008 "teachers manage own objects").
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, metadata)
    VALUES ('documents', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/teacher-doc.pdf',
            '22222222-2222-2222-2222-222222222222', '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S14-A29 teacherA INSERT documents (own tenant) → denied with 42501 (no documents.manage)';
  ELSE
    RAISE EXCEPTION 'FAIL: S14-A29 teacherA INSERT documents (own tenant) — state=% (expected 42501)', v_state;
  END IF;
END $$;

-- A30 (canary): adminA CAN write documents in her own tenant — proves the
--      denial in A29 is the permission boundary, not a broken bucket policy.
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
DO $$
BEGIN
  INSERT INTO storage.objects (bucket_id, name, owner, metadata)
  VALUES ('documents', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/admin-doc.pdf',
          '11111111-1111-1111-1111-111111111111', '{}'::jsonb);
  RAISE NOTICE 'PASS: S14-A30 adminA INSERT documents (own tenant) → succeeded';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'FAIL: S14-A30 adminA INSERT documents (own tenant) — raised %: %', SQLSTATE, SQLERRM;
END $$;

-- ── S15: Permission boundaries — teacher without fees.collect / fees.create ──
-- teacherA's role (005 seed) has NO fees.* permission codes, so the 014
-- WITH CHECK clauses must block her payments/invoices inserts even in Tenant A.
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

-- A31: teacherA must NOT insert a payment (payments_insert_tenant needs
--      tenant_has_permission(tid, 'fees.collect')).
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO public.payments (tenant_id, student_id, amount)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', 500);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S15-A31 teacherA INSERT payments (own tenant) → denied with 42501 (no fees.collect)';
  ELSE
    RAISE EXCEPTION 'FAIL: S15-A31 teacherA INSERT payments (own tenant) — state=% (expected 42501)', v_state;
  END IF;
END $$;

-- A32: teacherA must NOT insert an invoice (invoices_insert_tenant needs
--      tenant_has_permission(tid, 'fees.create')).
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO public.invoices (tenant_id, student_id, due_date, subtotal)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1', DATE '2026-10-31', 500);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S15-A32 teacherA INSERT invoices (own tenant) → denied with 42501 (no fees.create)';
  ELSE
    RAISE EXCEPTION 'FAIL: S15-A32 teacherA INSERT invoices (own tenant) — state=% (expected 42501)', v_state;
  END IF;
END $$;

-- ── S16: Parent isolation — student_guardians (015) ──────────────────────────
-- parentA1 (guardian of Student A) must see exactly her own link: nothing of
-- Tenant B, and nothing of the OTHER family in her own tenant.
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

-- A33 (canary): parentA1 sees exactly 1 guardian row — her own child's link.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.student_guardians) <> 1 THEN
    RAISE EXCEPTION 'FAIL: S16-A33 parentA1 student_guardians SELECT — expected 1 row (own link), got %',
      (SELECT count(*) FROM public.student_guardians);
  ELSE
    RAISE NOTICE 'PASS: S16-A33 parentA1 SELECT student_guardians → sees own link only (count=1)';
  END IF;
END $$;

-- A34: parentA1 must see ZERO rows of Tenant B.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.student_guardians
      WHERE tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S16-A34 parentA1 student_guardians SELECT — Tenant B rows visible cross-tenant';
  ELSE
    RAISE NOTICE 'PASS: S16-A34 parentA1 SELECT student_guardians of Tenant B → 0 rows';
  END IF;
END $$;

-- A35: parentA1 must see ZERO rows of parentA2's family (same tenant).
DO $$
BEGIN
  IF (SELECT count(*) FROM public.student_guardians
      WHERE guardian_user_id = '66666666-6666-6666-6666-666666666666') <> 0 THEN
    RAISE EXCEPTION 'FAIL: S16-A35 parentA1 student_guardians SELECT — other family rows visible';
  ELSE
    RAISE NOTICE 'PASS: S16-A35 parentA1 SELECT student_guardians of other family → 0 rows';
  END IF;
END $$;

-- ── S17: platform_config — read-public, write platform-only (018) ───────────
-- The seed row is intentionally readable by any authenticated user
-- (platform_config_public_read: clients check it pre-login), but INSERT /
-- UPDATE / DELETE require is_platform_admin().
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A36: adminA UPDATE of platform_config must affect 0 rows.
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.platform_config SET latest_version = '99.99.99-tampered'
   WHERE key = 'default';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S17-A36 adminA UPDATE platform_config — affected % rows (expected 0)', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S17-A36 adminA UPDATE platform_config → 0 rows affected';
  END IF;
END $$;

-- A37: adminA DELETE of platform_config must affect 0 rows.
DO $$
DECLARE v_rows int;
BEGIN
  DELETE FROM public.platform_config WHERE key = 'default';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S17-A37 adminA DELETE platform_config — affected % rows (expected 0)', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S17-A37 adminA DELETE platform_config → 0 rows affected';
  END IF;
END $$;

-- A38: adminA INSERT into platform_config must be denied with 42501.
DO $$
DECLARE v_state text := NULL;
BEGIN
  BEGIN
    INSERT INTO public.platform_config (key) VALUES ('evil-cfg');
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  IF v_state = '42501' THEN
    RAISE NOTICE 'PASS: S17-A38 adminA INSERT platform_config → denied with 42501';
  ELSE
    RAISE EXCEPTION 'FAIL: S17-A38 adminA INSERT platform_config — state=% (expected 42501)', v_state;
  END IF;
END $$;

-- A39 (canary): adminA CAN read platform_config — the denial above is the
--      write boundary, not a broken table.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.platform_config) <> 1 THEN
    RAISE EXCEPTION 'FAIL: S17-A39 adminA platform_config SELECT — expected 1 row, got %',
      (SELECT count(*) FROM public.platform_config);
  ELSE
    RAISE NOTICE 'PASS: S17-A39 adminA SELECT platform_config → 1 row (public read intact)';
  END IF;
END $$;

-- ── S18: Finance immutability — posted transactions (014) ───────────────────
-- transactions_update_tenant / transactions_delete_tenant require status='draft'
-- in the USING clause, so a posted (finalized) row must be untouchable even
-- for a tenant admin: RLS denies it (0 rows) BEFORE the immutability trigger
-- would fire (verified: PG16 evaluates policy quals before BEFORE triggers).
SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- A40: adminA UPDATE of a POSTED transaction must affect 0 rows.
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.transactions SET description = 'tampered'
   WHERE id = 'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S18-A40 adminA UPDATE posted transaction — affected % rows (expected 0)', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S18-A40 adminA UPDATE posted transaction → 0 rows affected';
  END IF;
END $$;

-- A41: adminA DELETE of a POSTED transaction must affect 0 rows.
DO $$
DECLARE v_rows int;
BEGIN
  DELETE FROM public.transactions
   WHERE id = 'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: S18-A41 adminA DELETE posted transaction — affected % rows (expected 0)', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S18-A41 adminA DELETE posted transaction → 0 rows affected';
  END IF;
END $$;

-- A42 (canary): adminA CAN update a DRAFT transaction — immutability is
--      status-scoped, not a blanket lockout of the finance ledger.
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.transactions SET description = 'draft edited'
   WHERE id = 'f2f2f2f2-f2f2-f2f2-f2f2-f2f2f2f2f2f2';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: S18-A42 adminA UPDATE draft transaction — expected 1 row, got %', v_rows;
  ELSE
    RAISE NOTICE 'PASS: S18-A42 adminA UPDATE draft transaction → 1 row affected';
  END IF;
END $$;

-- A43: superuser (bypassing RLS) UPDATE of the posted row must RAISE —
--      the finance_immutable_guard() trigger is the defense-in-depth backstop.
RESET role;
DO $$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    UPDATE public.transactions SET description = 'tampered by superuser'
     WHERE id = 'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1';
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
    RAISE NOTICE '  (superuser UPDATE of posted transaction raised %: %)', SQLSTATE, SQLERRM;
  END;
  IF v_blocked THEN
    RAISE NOTICE 'PASS: S18-A43 superuser UPDATE posted transaction → trigger raised (immutability backstop holds)';
  ELSE
    RAISE EXCEPTION 'FAIL: S18-A43 superuser UPDATE posted transaction — succeeded without raising';
  END IF;
END $$;

-- A44: superuser DELETE of the posted row must RAISE as well.
DO $$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    DELETE FROM public.transactions
     WHERE id = 'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1';
  EXCEPTION WHEN OTHERS THEN
    v_blocked := true;
    RAISE NOTICE '  (superuser DELETE of posted transaction raised %: %)', SQLSTATE, SQLERRM;
  END;
  IF v_blocked THEN
    RAISE NOTICE 'PASS: S18-A44 superuser DELETE posted transaction → trigger raised (immutability backstop holds)';
  ELSE
    RAISE EXCEPTION 'FAIL: S18-A44 superuser DELETE posted transaction — succeeded without raising';
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
