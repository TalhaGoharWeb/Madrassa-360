-- ═══════════════════════════════════════════════════════════════
-- Migration 023 — Super Admin backend (SaaS control plane)
--
-- Gives the SaaS owner full cross-tenant control:
--
--   (a) New table public.super_admins — the single source of truth for
--       SaaS super admins. user_id UUID PRIMARY KEY → auth.users,
--       created_at, notes.
--   (b) New columns on public.tenants:
--         is_suspended     BOOLEAN NOT NULL DEFAULT FALSE
--         suspended_at     TIMESTAMPTZ      (when suspension started)
--         suspension_reason TEXT           (why; shown to tenant admins)
--         expires_at       TIMESTAMPTZ      (NULL = no expiry; past = blocked)
--         admin_message    TEXT             (NULL = no broadcast message)
--         admin_message_at TIMESTAMPTZ      (when the message was set)
--   (c) New helper public.is_super_admin() — TRUE when auth.uid() is in
--       super_admins. SECURITY DEFINER, STABLE.
--   (d) public.is_platform_admin() is REDEFINED to also return TRUE for
--       super admins. Every existing RLS policy in the codebase is of the
--       form `is_platform_admin() OR …`, so super admins automatically
--       bypass ALL tenant RLS (read/write everything, every tenant)
--       without touching a single existing policy.
--   (e) RLS on super_admins itself: platform admins / super admins only
--       (FOR ALL). Bootstrapping the FIRST super admin is done by the
--       seed in (g) below, which runs as the migration owner (bypasses
--       RLS) — the same pattern 004 used for platform_admins.
--   (f) New RPC public.check_tenant_access(p_tenant_id) — SECURITY
--       DEFINER, callable by authenticated. Returns JSONB:
--         { allowed: bool,
--           reason:  'ok' | 'suspended' | 'expired' | 'not_found',
--           suspension_reason: TEXT|null,
--           admin_message: TEXT|null,
--           expires_at: TIMESTAMPTZ|null }
--       Suspension and expiry are enforced in the app layer (the Dart
--       SuperAdminService calls this on startup and on tenant switch
--       and blocks access with an Urdu message); RLS is deliberately
--       NOT changed for suspension so a suspended tenant's data stays
--       intact and the super admin can still manage it.
--   (g) Seed: muhaqqiqcreates@gmail.com → super_admins (email lookup,
--       plus the verified UUID as a safety net).
--   (h) Grants: helpers callable by authenticated; nothing else exposed.
--
-- Idempotent: safe to re-run (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS /
-- ON CONFLICT DO NOTHING / OR REPLACE / DROP IF EXISTS).
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) super_admins table
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.super_admins (
  user_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes      TEXT
);

COMMENT ON TABLE public.super_admins IS
  'SaaS super admins: full cross-tenant control (suspend, expiry, broadcast). '
  'Membership here also grants is_platform_admin() = TRUE, bypassing all tenant RLS.';


-- ═══════════════════════════════════════════════════════════════
-- (b) tenants: suspension / expiry / broadcast columns
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS is_suspended      BOOLEAN     NOT NULL DEFAULT FALSE;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS suspended_at      TIMESTAMPTZ;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS suspension_reason TEXT;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS expires_at        TIMESTAMPTZ;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS admin_message     TEXT;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS admin_message_at  TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_tenants_is_suspended ON public.tenants (is_suspended) WHERE is_suspended;
CREATE INDEX IF NOT EXISTS idx_tenants_expires_at   ON public.tenants (expires_at)   WHERE expires_at IS NOT NULL;

COMMENT ON COLUMN public.tenants.is_suspended IS
  'SaaS-level suspension: when TRUE the tenant is blocked from the app (Urdu message shown). Data is retained.';
COMMENT ON COLUMN public.tenants.expires_at IS
  'SaaS subscription expiry: NULL = no expiry. When expires_at <= now() the tenant is blocked (Urdu message shown).';
COMMENT ON COLUMN public.tenants.admin_message IS
  'Broadcast message from the SaaS super admin, shown on the tenant''s screens (e.g. payment reminder). NULL = none.';


-- ═══════════════════════════════════════════════════════════════
-- (c) is_super_admin() helper
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.user_id = auth.uid()
  );
$$;

COMMENT ON FUNCTION public.is_super_admin() IS
  'TRUE when the calling user is a SaaS super admin (row in public.super_admins).';


-- ═══════════════════════════════════════════════════════════════
-- (d) is_platform_admin() now includes super admins
-- Same signature — CREATE OR REPLACE succeeds and every existing
-- caller (all RLS policies use `is_platform_admin() OR …`) picks up
-- the new semantics at query time. Super admins therefore bypass
-- ALL tenant RLS with zero policy edits.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_admins pa
    WHERE pa.user_id = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.user_id = auth.uid()
  );
$$;

COMMENT ON FUNCTION public.is_platform_admin() IS
  '023: TRUE for platform_admins rows AND super_admins rows. '
  'Super admins bypass every tenant RLS policy via the existing `is_platform_admin() OR …` pattern.';


-- ═══════════════════════════════════════════════════════════════
-- (e) RLS on super_admins — platform/super admins only
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.super_admins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform admins manage super_admins" ON public.super_admins;
CREATE POLICY "platform admins manage super_admins"
  ON public.super_admins FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());
-- NOTE: is_platform_admin() is TRUE for super admins themselves, so the
-- SaaS owner can manage this table; bootstrapping the first row happens
-- in (g) below as the migration owner (RLS bypassed), same as 004.


-- ═══════════════════════════════════════════════════════════════
-- (f) check_tenant_access(p_tenant_id) — suspension/expiry gate
-- SECURITY DEFINER so any authenticated user can check THEIR tenant's
-- status even if their own row-level read would be limited; it reveals
-- only suspension/expiry/message metadata, never tenant data.
-- The app calls this on startup and on tenant switch and blocks
-- access with an Urdu message when allowed = FALSE.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_tenant_access(p_tenant_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_suspended   BOOLEAN;
  v_expires_at  TIMESTAMPTZ;
  v_susp_reason TEXT;
  v_message     TEXT;
  v_found       BOOLEAN;
BEGIN
  SELECT TRUE, t.is_suspended, t.expires_at, t.suspension_reason, t.admin_message
    INTO v_found, v_suspended, v_expires_at, v_susp_reason, v_message
    FROM public.tenants t
   WHERE t.id = p_tenant_id;

  IF NOT COALESCE(v_found, FALSE) THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'not_found',
      'suspension_reason', NULL::TEXT,
      'admin_message', NULL::TEXT,
      'expires_at', NULL::TIMESTAMPTZ
    );
  END IF;

  IF COALESCE(v_suspended, FALSE) THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'suspended',
      'suspension_reason', v_susp_reason,
      'admin_message', v_message,
      'expires_at', v_expires_at
    );
  END IF;

  IF v_expires_at IS NOT NULL AND v_expires_at <= now() THEN
    RETURN jsonb_build_object(
      'allowed', FALSE,
      'reason', 'expired',
      'suspension_reason', NULL::TEXT,
      'admin_message', v_message,
      'expires_at', v_expires_at
    );
  END IF;

  RETURN jsonb_build_object(
    'allowed', TRUE,
    'reason', 'ok',
    'suspension_reason', NULL::TEXT,
    'admin_message', v_message,
    'expires_at', v_expires_at
  );
END;
$$;

COMMENT ON FUNCTION public.check_tenant_access(UUID) IS
  'SaaS access gate: returns {allowed, reason, suspension_reason, admin_message, expires_at} '
  'for a tenant. reason ∈ ok | suspended | expired | not_found. Enforced app-side with Urdu messaging.';


-- ═══════════════════════════════════════════════════════════════
-- (g) Seed: muhaqqiqcreates@gmail.com → super_admins
-- Runs as the migration owner (bypasses RLS) — the supported
-- bootstrap path, same pattern 004 used for platform_admins.
-- Email lookup first (portable across environments); the verified
-- UUID second as a safety net. Both are ON CONFLICT DO NOTHING.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.super_admins (user_id, notes)
SELECT u.id,
       'SaaS super admin (bootstrap 023): full cross-tenant control — suspend/unsuspend tenants, '
       'set subscription expiry, broadcast admin messages.'
FROM auth.users u
WHERE u.email = 'muhaqqiqcreates@gmail.com'
ON CONFLICT (user_id) DO NOTHING;

-- Safety net: verified auth.users id for muhaqqiqcreates@gmail.com
-- (2026-09-27). No-op if the email lookup above already inserted it.
INSERT INTO public.super_admins (user_id, notes)
VALUES ('9c338cfe-162a-4000-ae45-885fe6a35463',
        'SaaS super admin (bootstrap 023): full cross-tenant control — suspend/unsuspend tenants, '
        'set subscription expiry, broadcast admin messages.')
ON CONFLICT (user_id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.super_admins sa
    JOIN auth.users u ON u.id = sa.user_id
    WHERE u.email = 'muhaqqiqcreates@gmail.com'
       OR sa.user_id = '9c338cfe-162a-4000-ae45-885fe6a35463'
  ) THEN
    RAISE WARNING '023: super_admin seed did not match any auth.users row for muhaqqiqcreates@gmail.com — '
                  'insert the super admin manually once the user exists.';
  ELSE
    RAISE NOTICE '023: muhaqqiqcreates@gmail.com is seeded as SaaS super admin.';
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- (h) Grants — helpers callable by authenticated; nothing else exposed
-- ═══════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

REVOKE ALL ON FUNCTION public.check_tenant_access(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_tenant_access(UUID) TO authenticated;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('023_super_admin')
ON CONFLICT DO NOTHING;
