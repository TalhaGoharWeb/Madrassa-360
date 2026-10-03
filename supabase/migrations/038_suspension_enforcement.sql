-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 038: suspension enforcement, single
-- source of truth
--
-- SEC-H6 (half): suspension was split-brain — manage-tenant writes the
-- tenants.status string, but check_tenant_access() read the `suspended`
-- boolean which nothing ever set, and NO RLS policy checked either
-- flag. A "suspended" tenant kept full access.
--
--   * tenants_sync_suspension_flag(): BEFORE INSERT/UPDATE trigger
--     keeping the `suspended` boolean (and suspended_at) derived from
--     the `status` string — the flag manage-tenant writes is now the
--     single source of truth, readable both ways.
--   * check_tenant_access(): rewritten to read the status string
--     (suspended/expired/cancelled) + expires_at.
--   * is_tenant_member(): now also requires the tenant to be active
--     (not suspended/expired/cancelled, not past expires_at) — RLS
--     enforces suspension, not just the client gate.
--   * "members read own tenants" re-pointed at a raw membership EXISTS
--     so members of a suspended tenant can still READ their tenant row
--     (to see the suspension state); everything else goes dark.
--
-- Backfill: suspended flags recomputed from status on apply.
--
-- Idempotent: CREATE OR REPLACE / DROP IF EXISTS.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) suspension flag derived from status ────────────────────
CREATE OR REPLACE FUNCTION public.tenants_sync_suspension_flag()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.suspended := (NEW.status = 'suspended');
  IF NEW.suspended AND COALESCE(OLD.suspended, false) IS NOT TRUE THEN
    NEW.suspended_at := now();
  ELSIF NOT NEW.suspended THEN
    NEW.suspended_at      := NULL;
    NEW.suspension_reason := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenants_sync_suspension_flag ON public.tenants;
CREATE TRIGGER tenants_sync_suspension_flag
  BEFORE INSERT OR UPDATE OF status ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.tenants_sync_suspension_flag();

-- Backfill existing rows (fires the trigger per row).
UPDATE public.tenants
   SET status = status
 WHERE suspended IS DISTINCT FROM (status = 'suspended');


-- ── (b) is_tenant_member: membership + active tenant ───────────
CREATE OR REPLACE FUNCTION public.is_tenant_member(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tenant_memberships tm
    WHERE tm.tenant_id = p_tenant_id
      AND tm.user_id   = auth.uid()
      AND tm.is_active
  )
  AND COALESCE((
    SELECT t.status NOT IN ('suspended', 'expired', 'cancelled')
       AND (t.expires_at IS NULL OR t.expires_at > now())
      FROM public.tenants t
     WHERE t.id = p_tenant_id
  ), false);
$$;


-- ── (c) check_tenant_access: same source of truth ──────────────
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
      AND COALESCE((
        SELECT t.status NOT IN ('suspended', 'expired', 'cancelled')
           AND (t.expires_at IS NULL OR t.expires_at > now())
          FROM public.tenants t
         WHERE t.id = p_tenant_id
      ), false)
    );
$$;


-- ── (d) suspended members can still read their tenant row ──────
DROP POLICY IF EXISTS "members read own tenants" ON public.tenants;
CREATE POLICY "members read own tenants"
  ON public.tenants FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.tenant_id = tenants.id
        AND tm.user_id   = auth.uid()
        AND tm.is_active
    )
  );


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('038_suspension_enforcement')
ON CONFLICT DO NOTHING;
