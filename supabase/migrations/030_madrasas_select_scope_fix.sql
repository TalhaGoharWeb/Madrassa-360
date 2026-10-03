-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 030: fix madrasas_member_select scoping bug
--
-- SEC-H7: the 027 policy intended per-row scoping via madrasas.id, but the
-- EXISTS subquery is FROM public.tenants t, so the bare `id` in
--   replace(id::text, '-', '')
-- resolves to t.id (innermost scope wins) — the predicate became a
-- property of the tenant, not the row. For legacy M-code tenants any
-- active member could SELECT every row of public.madrasas (cross-tenant
-- read); for new T-code tenants it failed closed.
--
-- Fix: qualify the reference as madrasas.id.
--
-- Idempotent: DROP POLICY IF EXISTS.
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "madrasas_member_select" ON public.madrasas;
CREATE POLICY "madrasas_member_select"
  ON public.madrasas FOR SELECT
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1
      FROM public.tenants t
      WHERE t.tenant_code = 'M-' || upper(substr(replace(madrasas.id::text, '-', ''), 1, 8))
        AND public.is_tenant_member(t.id)
    )
  );


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('030_madrasas_select_scope_fix')
ON CONFLICT DO NOTHING;
