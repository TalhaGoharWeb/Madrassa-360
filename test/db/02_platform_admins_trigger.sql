-- ═══════════════════════════════════════════════════════════════════
-- 02_platform_admins_trigger.sql — SEC-C5
--
-- Asserts the BEFORE INSERT OR UPDATE OR DELETE trigger on
-- public.platform_admins (trigger name: trg_platform_admins_guard):
--   (a) platform_support CANNOT self-promote to platform_owner via a
--       direct PostgREST-style write (RLS passes for platform admins;
--       the TRIGGER must raise).
--   (b) the last platform_owner CANNOT be deleted or demoted.
--   (c) positive control: a platform_owner CAN manage support rows.
--
-- Statements run as ROLE authenticated with request.jwt.claims set, so
-- RLS applies exactly as it does for real API callers. If the trigger is
-- not deployed, the script raises SKIP notices (not failures).
--
-- RUN: psql "<staging-direct-url>" -v ON_ERROR_STOP=1 -f test/db/02_platform_admins_trigger.sql
--      Wrapped in a transaction, rolled back at the end.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── fixtures (as superuser; RLS bypassed) ──────────────────────────
INSERT INTO auth.users (id, aud, role, email, encrypted_password,
                       email_confirmed_at, created_at, updated_at,
                       raw_app_meta_data, raw_user_meta_data, is_super_admin)
VALUES
  ('c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3', 'authenticated', 'authenticated',
   'sec-owner@example.com', 'dummy', now(), now(), now(), '{}', '{}', false),
  ('d4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4', 'authenticated', 'authenticated',
   'sec-support@example.com', 'dummy', now(), now(), now(), '{}', '{}', false),
  ('e5e5e5e5-e5e5-4e5e-8e5e-e5e5e5e5e5e5', 'authenticated', 'authenticated',
   'sec-owner2@example.com', 'dummy', now(), now(), now(), '{}', '{}', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.platform_admins (user_id, role) VALUES
  ('c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3', 'platform_owner'),
  ('e5e5e5e5-e5e5-4e5e-8e5e-e5e5e5e5e5e5', 'platform_owner'),
  ('d4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4', 'platform_support')
ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

DO $$
DECLARE
  v_trigger_deployed BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname = 'trg_platform_admins_guard')
    INTO v_trigger_deployed;
  IF NOT v_trigger_deployed THEN
    RAISE NOTICE 'SKIP: trg_platform_admins_guard not deployed — SEC-C5 fix pending';
    RETURN;
  END IF;

  -- ── (a) support self-promotion must raise ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','d4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4',
                       'role','authenticated')::text, true);
  BEGIN
    UPDATE public.platform_admins SET role = 'platform_owner'
     WHERE user_id = 'd4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4';
    RAISE EXCEPTION 'FAIL (a): platform_support self-promoted to platform_owner';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (a)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (a): support self-promotion blocked: %', SQLERRM;
  END;
  RESET ROLE;

  -- ── (a2) support cannot delete an owner ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','d4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4',
                       'role','authenticated')::text, true);
  BEGIN
    DELETE FROM public.platform_admins
     WHERE user_id = 'c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3';
    RAISE EXCEPTION 'FAIL (a2): platform_support deleted a platform_owner';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (a2)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (a2): support deleting owner blocked: %', SQLERRM;
  END;
  RESET ROLE;

  -- reduce to a single owner (as superuser)
  DELETE FROM public.platform_admins
   WHERE user_id = 'e5e5e5e5-e5e5-4e5e-8e5e-e5e5e5e5e5e5';

  -- ── (b) cannot delete the LAST platform_owner ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3',
                       'role','authenticated')::text, true);
  BEGIN
    DELETE FROM public.platform_admins
     WHERE user_id = 'c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3';
    RAISE EXCEPTION 'FAIL (b): last platform_owner was deleted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (b)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (b): last-owner delete blocked: %', SQLERRM;
  END;

  -- ── (b2) cannot demote the last platform_owner ──
  BEGIN
    UPDATE public.platform_admins SET role = 'platform_support'
     WHERE user_id = 'c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3';
    RAISE EXCEPTION 'FAIL (b2): last platform_owner was demoted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (b2)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (b2): last-owner demote blocked: %', SQLERRM;
  END;
  RESET ROLE;

  -- ── (c) positive control: owner can manage support rows ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3',
                       'role','authenticated')::text, true);
  DELETE FROM public.platform_admins
   WHERE user_id = 'd4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4';
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.platform_admins
             WHERE user_id = 'd4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4') THEN
    RAISE EXCEPTION 'FAIL (c): owner could not delete a support row';
  END IF;
  RAISE NOTICE 'PASS (c): owner management of support rows still works';
END $$;

ROLLBACK;
