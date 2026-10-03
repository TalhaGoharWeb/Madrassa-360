-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 039: user_accounts gets tenant_id
--
-- SEC-H5 (full): public.user_accounts had no tenant_id, so per-row
-- tenant scoping was impossible — any users.view holder in any tenant
-- could read/update rows belonging to other tenants.
--
--   1. ADD COLUMN tenant_id UUID REFERENCES tenants(id) ON DELETE
--      CASCADE (nullable at first).
--   2. Backfill: linked_staff_id → staff.tenant_id; then
--      email → auth.users → active tenant_memberships (deterministic:
--      earliest membership wins).
--   3. BEFORE INSERT trigger fills tenant_id from the caller's
--      memberships when exactly one active tenant exists (keeps the
--      app's user_management_provider insert working); otherwise a
--      clear error (multi-tenant callers must send tenant_id —
--      client follow-up noted in MIGRATION_NOTES_029_044.md).
--   4. SET NOT NULL (fails loudly if backfill left gaps — fix data,
--      re-run).
--   5. All four RLS policies re-scoped per-row on tenant_id.
--   6. role_name is platform-admin-only: non-platform writes get the
--      default on INSERT and are ignored on UPDATE (the column is
--      display metadata today, but must not become a trust anchor).
--
-- Idempotent: ADD COLUMN IF NOT EXISTS / DROP POLICY IF EXISTS /
-- DROP TRIGGER IF EXISTS.
-- ═══════════════════════════════════════════════════════════════


-- ── 1) column ──────────────────────────────────────────────────
ALTER TABLE public.user_accounts
  ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_user_accounts_tenant ON public.user_accounts (tenant_id);


-- ── 2) backfill ────────────────────────────────────────────────
-- 2a) via linked staff row (most reliable).
UPDATE public.user_accounts ua
   SET tenant_id = s.tenant_id
  FROM public.staff s
 WHERE ua.tenant_id IS NULL
   AND ua.linked_staff_id IS NOT NULL
   AND s.id = ua.linked_staff_id
   AND s.tenant_id IS NOT NULL;

-- 2b) via auth email → earliest active membership (deterministic).
UPDATE public.user_accounts ua
   SET tenant_id = m.tenant_id
  FROM (
    SELECT DISTINCT ON (au.email) au.email AS email, tm.tenant_id
      FROM auth.users au
      JOIN public.tenant_memberships tm
        ON tm.user_id = au.id AND tm.is_active
     ORDER BY au.email, tm.created_at NULLS LAST, tm.tenant_id
  ) m
 WHERE ua.tenant_id IS NULL
   AND lower(ua.email) = lower(m.email);


-- ── 3) server-side tenant fill for app inserts ─────────────────
CREATE OR REPLACE FUNCTION public.user_accounts_fill_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n      INT;
  v_tenant UUID;
BEGIN
  IF NEW.tenant_id IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'user_accounts: tenant_id is required';
  END IF;
  SELECT COUNT(*), MIN(tm.tenant_id)
    INTO v_n, v_tenant
    FROM public.tenant_memberships tm
   WHERE tm.user_id = auth.uid() AND tm.is_active;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'user_accounts: caller is not a member of any tenant';
  ELSIF v_n > 1 THEN
    RAISE EXCEPTION 'user_accounts: tenant_id is required (member of multiple tenants)';
  END IF;
  NEW.tenant_id := v_tenant;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_accounts_fill_tenant ON public.user_accounts;
CREATE TRIGGER user_accounts_fill_tenant
  BEFORE INSERT ON public.user_accounts
  FOR EACH ROW EXECUTE FUNCTION public.user_accounts_fill_tenant();


-- ── 4) not null (loud if backfill left gaps) ───────────────────
-- Diagnostic for the applier (run before applying):
--   SELECT id, email FROM public.user_accounts WHERE tenant_id IS NULL;
ALTER TABLE public.user_accounts ALTER COLUMN tenant_id SET NOT NULL;


-- ── 5) per-row RLS ─────────────────────────────────────────────
DROP POLICY IF EXISTS "user_accounts_select_scoped"  ON public.user_accounts;
DROP POLICY IF EXISTS "user_accounts_select_member"  ON public.user_accounts;
DROP POLICY IF EXISTS "user_accounts_insert_admin"   ON public.user_accounts;
DROP POLICY IF EXISTS "user_accounts_update_admin"   ON public.user_accounts;
DROP POLICY IF EXISTS "user_accounts_delete_admin"   ON public.user_accounts;

DROP POLICY IF EXISTS "user_accounts_select_tenant" ON public.user_accounts;
CREATE POLICY "user_accounts_select_tenant"
  ON public.user_accounts FOR SELECT
  USING (
    public.is_platform_admin()
    OR (
      public.is_tenant_member(user_accounts.tenant_id)
      AND public.tenant_has_permission(user_accounts.tenant_id, 'users.view')
    )
  );

DROP POLICY IF EXISTS "user_accounts_insert_tenant" ON public.user_accounts;
CREATE POLICY "user_accounts_insert_tenant"
  ON public.user_accounts FOR INSERT
  WITH CHECK (
    public.is_platform_admin()
    OR (
      public.is_tenant_member(user_accounts.tenant_id)
      AND public.tenant_has_permission(user_accounts.tenant_id, 'users.create')
    )
  );

DROP POLICY IF EXISTS "user_accounts_update_tenant" ON public.user_accounts;
CREATE POLICY "user_accounts_update_tenant"
  ON public.user_accounts FOR UPDATE
  USING (
    public.is_platform_admin()
    OR (
      public.is_tenant_member(user_accounts.tenant_id)
      AND public.tenant_has_permission(user_accounts.tenant_id, 'users.update')
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR (
      public.is_tenant_member(user_accounts.tenant_id)
      AND public.tenant_has_permission(user_accounts.tenant_id, 'users.update')
    )
  );

DROP POLICY IF EXISTS "user_accounts_delete_tenant" ON public.user_accounts;
CREATE POLICY "user_accounts_delete_tenant"
  ON public.user_accounts FOR DELETE
  USING (
    public.is_platform_admin()
    OR (
      public.is_tenant_member(user_accounts.tenant_id)
      AND public.tenant_has_permission(user_accounts.tenant_id, 'users.deactivate')
    )
  );


-- ── 6) role_name: platform-admin-only writes ───────────────────
CREATE OR REPLACE FUNCTION public.user_accounts_role_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service BOOLEAN;
BEGIN
  v_service := (auth.uid() IS NULL)
            OR (COALESCE(auth.jwt()->>'role', '') = 'service_role');
  IF public.is_platform_admin() OR v_service THEN
    RETURN NEW;
  END IF;
  -- Non-platform callers: role_name is display metadata, never a trust
  -- anchor. Force the default on insert; ignore changes on update.
  IF TG_OP = 'INSERT' THEN
    NEW.role_name := 'teacher';
  ELSE
    NEW.role_name := OLD.role_name;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_accounts_role_guard ON public.user_accounts;
CREATE TRIGGER user_accounts_role_guard
  BEFORE INSERT OR UPDATE OF role_name ON public.user_accounts
  FOR EACH ROW EXECUTE FUNCTION public.user_accounts_role_guard();


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('039_user_accounts_tenant')
ON CONFLICT DO NOTHING;
