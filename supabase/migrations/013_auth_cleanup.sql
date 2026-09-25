-- ═══════════════════════════════════════════════════════════════
-- Migration 013 — Auth cleanup: decommission legacy insecure artifacts
-- (mission: "single permission system, tenant-bound"; §60 item 11)
--
-- EVERY drop target below was verified by exact-name grep against the
-- source files BEFORE this file was written (the audit proved silent-miss
-- DROPs are catastrophic):
--
--   DROP TARGET                    VERIFIED AT                  RESULT
--   ──────────────────────────────────────────────────────────────────
--   table public.user_roles        06_rbac.sql:125              DROPPED
--     policies on it:
--       "read own user_roles"      06_rbac.sql:608              DROPPED
--       "platform admin manage     06_rbac.sql:616              DROPPED
--         user_roles"
--   function public.get_user_role()  02_rls.sql:10 (zero-arg). All its
--     callers (02 policies) were dropped by 007's legacy sweep.   DROPPED
--   function public.get_my_role()  05_new_modules.sql:241 AND
--     06_rbac.sql:531 (same zero-arg signature; 06 replaced 05's
--     definition via CREATE OR REPLACE). Callers: 05's policies
--     (dropped by 007), 06's catalog policies (dropped by 005),
--     06's is_platform_admin() (replaced by 004).             DROPPED
--   single-arg public.has_permission()  — NOT FOUND in 01_schema.sql,
--     02_rls.sql, 05_new_modules.sql, 06_rbac.sql, or any migration.
--     The ONLY has_permission() in the codebase is the TWO-arg
--     has_permission(p_code, p_madrasa_id) at 06_rbac.sql:521, and the
--     task explicitly forbids dropping a 2-arg form (like 004's
--     tenant_has_permission).                              SKIPPED (fail-loud
--     NOTICE below — never silently assume).
--
-- CONSEQUENCES HANDLED:
--   * 005's public.get_my_permissions() had a DEPRECATED branch reading
--     public.user_roles. lib/core/services/permission_service.dart:33
--     still RPCs get_my_permissions() and reads row['code'], so the
--     function is REWRITTEN (not dropped): signature
--     (p_madrasa_id UUID DEFAULT NULL) → TABLE(code TEXT) unchanged,
--     user_roles branch REMOVED, tenant-aware primary branch + legacy
--     profiles.role branch kept.
--   * 06's has_permission(p_code, p_madrasa_id) stays live on top of the
--     rewritten function (per 005's contract); its last SQL callers were
--     the dropped user_roles policies.
--   * public.profiles.role COLUMN IS KEPT. Still read by Dart:
--       lib/data/repositories/auth_repository.dart:74-75
--         (profile['role'] — AppUser role resolution)
--       lib/core/services/permission_service.dart:8
--         (comment documenting the legacy profiles.role branch)
--       lib/core/services/auth_service.dart:29,40
--         (mock/demo sign-in only — unrelated to profiles table)
--     (lib/core/services/tenant_context.dart:44's json['role'] is the
--      tenant_memberships row role, NOT profiles.role.)
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) Drop the two user_roles policies by EXACT verified name,
--     then the table itself.
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "read own user_roles"            ON public.user_roles;
DROP POLICY IF EXISTS "platform admin manage user_roles" ON public.user_roles;

-- Fail-loud: no legacy policy on user_roles may survive.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_roles'
  ) THEN
    RAISE EXCEPTION '013 FAIL-LOUD: legacy policy on public.user_roles survived the drop list';
  END IF;
END $$;

DROP TABLE IF EXISTS public.user_roles;


-- ═══════════════════════════════════════════════════════════════
-- (b) Drop the orphaned legacy helpers.
-- ═══════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_user_role();
DROP FUNCTION IF EXISTS public.get_my_role();

-- Fail-loud: the functions must be gone.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('get_user_role', 'get_my_role')
  ) THEN
    RAISE EXCEPTION '013 FAIL-LOUD: legacy helper function survived the drop list';
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- (c) Rewrite get_my_permissions(): same signature, same {code} rows,
--     user_roles branch removed (the table no longer exists).
--     Kept branches: tenant-aware primary (tenant_memberships) +
--     deprecated profiles.role branch (profiles.role column is retained
--     and client-locked by 007's profiles_lock_role trigger).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_my_permissions(p_madrasa_id UUID DEFAULT NULL)
RETURNS TABLE(code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Primary source: UNION of permission codes across all of the caller's
  -- ACTIVE tenant memberships (tenant-aware RBAC).
  SELECT DISTINCT p.code
    FROM public.tenant_memberships tm
    JOIN public.roles r              ON r.name = tm.role
    JOIN public.role_permissions rp  ON rp.role_id = r.id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE tm.user_id = auth.uid()
     AND tm.is_active

  UNION

  -- DEPRECATED: legacy profiles.role branch (kept for backward
  -- compatibility; 004/005 documented the same contract).
  SELECT DISTINCT p.code
    FROM public.profiles pr
    JOIN public.roles r              ON r.name = pr.role
    JOIN public.role_permissions rp  ON rp.role_id = r.id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE pr.id = auth.uid()
$$;


-- ═══════════════════════════════════════════════════════════════
-- (d) Fail-loud NOTICE: single-arg has_permission() does not exist.
-- ═══════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'has_permission'
      AND pg_get_function_arguments(p.oid) = 'p_code text'
  ) THEN
    RAISE NOTICE '013: single-arg public.has_permission() not found anywhere in the legacy SQL (only the 2-arg has_permission(p_code, p_madrasa_id) at 06_rbac.sql:521 exists) — skipping DROP per fail-loud; the 2-arg form is intentionally retained.';
  END IF;
END $$;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('013_auth_cleanup')
ON CONFLICT DO NOTHING;
