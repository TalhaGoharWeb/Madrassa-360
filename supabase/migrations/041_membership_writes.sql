-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 041: tenant_memberships writes via the
-- privileged path only
--
-- SEC-H3: the "tenant admins manage memberships" FOR ALL policy let a
-- tenant_admin INSERT/UPDATE/DELETE tenant_memberships directly —
-- self-promotion to tenant_owner, arbitrary role grants, no audit row,
-- no rank gates. The Edge Function's ceilings and the audit trail were
-- optional; the database offered a parallel weaker path.
--
-- Fix: tenant callers get SELECT only (own row + tenant-admin read of
-- their tenants' rows); all WRITES are platform-admin-only at the RLS
-- layer. Mutations go through manage-users (service_role) or the
-- hardened RPCs (assign_tenant_role / set_user_permission /
-- set_role_permissions — SECURITY DEFINER, with 036 ceilings, 019
-- last-owner backstop, and audit triggers). The Flutter app performs
-- no direct membership writes (verified 2026-10-03: reads only).
--
-- Idempotent: DROP POLICY IF EXISTS.
-- ═══════════════════════════════════════════════════════════════

-- Drop the permissive FOR ALL tenant-admin policy.
DROP POLICY IF EXISTS "tenant admins manage memberships" ON public.tenant_memberships;

-- SELECT: own rows (kept) + tenant admins may read their tenants' rows.
DROP POLICY IF EXISTS "users read own memberships" ON public.tenant_memberships;
CREATE POLICY "users read own memberships"
  ON public.tenant_memberships FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "tenant admins read memberships" ON public.tenant_memberships;
CREATE POLICY "tenant admins read memberships"
  ON public.tenant_memberships FOR SELECT
  USING (public.is_tenant_admin(tenant_memberships.tenant_id));

-- Writes: platform admins only at the RLS layer. (SECURITY DEFINER RPCs
-- and the service_role Edge Function bypass RLS by design.)
DROP POLICY IF EXISTS "platform admins manage memberships" ON public.tenant_memberships;
CREATE POLICY "platform admins manage memberships"
  ON public.tenant_memberships FOR ALL
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('041_membership_writes')
ON CONFLICT DO NOTHING;
