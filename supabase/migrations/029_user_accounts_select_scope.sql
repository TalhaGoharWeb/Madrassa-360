-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 029: user_accounts SELECT scope +
-- schema_migrations backfill for 025–028
--
-- (a) SEC-H5 (read half): the 027 policy "user_accounts_select_member"
--     let ANY active member of ANY tenant SELECT every row of
--     public.user_accounts (names, emails, phones, role names —
--     cross-tenant PII). Restrict SELECT to platform admins OR callers
--     holding the verified 'users.view' code in at least one of their
--     active tenants. Full per-row tenant_id scoping lands in 039.
-- (b) Ledger backfill: 025–028 never stamped public.schema_migrations
--     themselves (the live ledger was reconciled by hand). Stamp them
--     here idempotently so fresh databases carry the full chain.
--
-- Idempotent: DROP POLICY IF EXISTS / INSERT ... ON CONFLICT DO NOTHING.
-- ═══════════════════════════════════════════════════════════════

-- ── (a) user_accounts SELECT: user-management audience only ──
DROP POLICY IF EXISTS "user_accounts_select_member" ON public.user_accounts;

DROP POLICY IF EXISTS "user_accounts_select_scoped" ON public.user_accounts;
CREATE POLICY "user_accounts_select_scoped"
  ON public.user_accounts FOR SELECT
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.is_active
        AND public.tenant_has_permission(tm.tenant_id, 'users.view')
    )
  );


-- ── (b) backfill missing ledger stamps (025–028) ──
INSERT INTO public.schema_migrations(version) VALUES
  ('025_repair_finance_doc_columns'),
  ('026_repair_profiles_columns'),
  ('027_user_accounts_app_roles'),
  ('028_finance_per_table_doc_triggers')
ON CONFLICT DO NOTHING;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('029_user_accounts_select_scope')
ON CONFLICT DO NOTHING;
