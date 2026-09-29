-- ═══════════════════════════════════════════════════════════════
-- Migration 023 — super_admins + tenant suspension/expiry/admin-message
--
-- Applied live 2026-09-27; recreated in-branch to close the drift between
-- the branch migration ledger and the live Supabase schema.
--
--   (a) New table public.super_admins — platform super-admins, keyed by
--       auth.users id. Seeded with muhaqqiqcreates@gmail.com (looked up
--       from auth.users; inserts nothing when the auth user is absent).
--   (b) New columns on public.tenants: suspended / suspension_reason /
--       suspended_at (suspension), expires_at (license expiry timer), and
--       admin_message / admin_message_at (platform broadcast message).
--   (c) New helper public.is_super_admin() — SECURITY DEFINER, true when
--       auth.uid() has a row in public.super_admins.
--   (d) is_platform_admin() redefined: platform_admins members AND
--       super_admins both count, so super admins inherit the existing
--       cross-tenant RLS policies at query time (same signature, so
--       CREATE OR REPLACE succeeds and all callers pick it up).
--   (e) New RPC public.check_tenant_access(p_tenant_id) — true for super
--       admins (bypass), otherwise true only for active members of a
--       non-suspended, unexpired tenant. Fail-closed: unknown tenant or
--       any NULL lookup denies.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) super_admins table ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.super_admins (
  user_id    UUID        NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.super_admins ENABLE ROW LEVEL SECURITY;

-- Only super admins can read/manage the super-admin roster. The function
-- is SECURITY DEFINER so policies can call it without recursion. The
-- first row is seeded below as the migration owner (bypasses RLS).
DROP POLICY IF EXISTS "super admins manage super admins" ON public.super_admins;
CREATE POLICY "super admins manage super admins"
  ON public.super_admins FOR ALL
  USING  (public.is_super_admin())
  WITH CHECK (public.is_super_admin());


-- ── (b) tenant suspension / expiry / admin-message columns ─────

ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS suspended         BOOLEAN     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS suspension_reason TEXT,
  ADD COLUMN IF NOT EXISTS suspended_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS expires_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS admin_message     TEXT,
  ADD COLUMN IF NOT EXISTS admin_message_at  TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_tenants_suspended  ON public.tenants (suspended);
CREATE INDEX IF NOT EXISTS idx_tenants_expires_at ON public.tenants (expires_at);


-- ── (c) is_super_admin() helper ────────────────────────────────

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


-- ── (d) is_platform_admin() now includes super admins ──────────
-- Same signature as the 004_memberships.sql version, so CREATE OR REPLACE
-- succeeds and every existing policy/RPC picks up the new semantics.

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


-- ── (e) check_tenant_access() RPC ──────────────────────────────
-- Super admins always pass. Everyone else must be an active member of a
-- tenant that is neither suspended nor expired. Fail-closed on any
-- missing row.

CREATE OR REPLACE FUNCTION public.check_tenant_access(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_super_admin()
    OR (
      public.is_tenant_member(p_tenant_id)
      AND COALESCE(
        (SELECT NOT t.suspended FROM public.tenants t WHERE t.id = p_tenant_id),
        false
      )
      AND COALESCE(
        (SELECT t.expires_at IS NULL OR t.expires_at > now()
           FROM public.tenants t WHERE t.id = p_tenant_id),
        false
      )
    );
$$;


-- ── Grants ─────────────────────────────────────────────────────
-- is_super_admin() / check_tenant_access() are read-only helpers safe for
-- client calls; is_platform_admin() keeps its existing grants.

GRANT EXECUTE ON FUNCTION public.is_super_admin()              TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_tenant_access(UUID)     TO authenticated;


-- ── Seed: platform super admin ─────────────────────────────────
-- Resolves the auth user id by email; no-op when the auth user does not
-- exist yet (the account can be linked later by re-running this insert).

INSERT INTO public.super_admins (user_id, email)
SELECT id, email
FROM auth.users
WHERE email = 'muhaqqiqcreates@gmail.com'
ON CONFLICT (user_id) DO UPDATE SET email = EXCLUDED.email;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('023_super_admin')
ON CONFLICT DO NOTHING;
