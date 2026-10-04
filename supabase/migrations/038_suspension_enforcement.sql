-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 038: suspension enforcement, single
-- source of truth
--
-- SEC-H6 (half): suspension was split-brain — manage-tenant writes the
-- tenants.status string, but check_tenant_access() read a `suspended`
-- boolean which nothing ever set, and NO RLS policy checked either
-- flag. A "suspended" tenant kept full access.
--
--   * tenants_sync_suspension_flag(): BEFORE INSERT/UPDATE trigger
--     keeping the `is_suspended` boolean (and suspended_at /
--     suspension_reason) derived from the `status` string — the flag
--     manage-tenant writes is now the single source of truth,
--     readable both ways. (Live schema names the column
--     `is_suspended`; earlier drafts used `suspended`.)
--   * check_tenant_access(): the live jsonb contract is ADOPTED
--     (back-ported) — it already reads is_suspended + expires_at and
--     returns {allowed, reason, suspension_reason, admin_message,
--     expires_at}. Not regressed to boolean.
--   * is_tenant_member(): now also requires the tenant to be active
--     (not suspended/expired/cancelled, not past expires_at) — RLS
--     enforces suspension, not just the client gate.
--   * "members read own tenants" re-pointed at a raw membership EXISTS
--     so members of a suspended tenant can still READ their tenant row
--     (to see the suspension state); everything else goes dark.
--
-- Backfill: is_suspended flags recomputed from status on apply.
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
  NEW.is_suspended := (NEW.status = 'suspended');
  IF NEW.is_suspended AND COALESCE(OLD.is_suspended, false) IS NOT TRUE THEN
    NEW.suspended_at := now();
  ELSIF NOT NEW.is_suspended THEN
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
 WHERE is_suspended IS DISTINCT FROM (status = 'suspended');


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


-- ── (c) check_tenant_access: keep the live jsonb contract ──────────
-- The live database carries a RICHER check_tenant_access(uuid) RETURNS
-- jsonb than migration 023 ever declared (it returns
-- {allowed, reason, suspension_reason, admin_message, expires_at} and
-- already reads the is_suspended boolean). An earlier draft of this
-- migration replaced it with a boolean version — that would have been
-- a REGRESSION, caught during live apply (42P13 return-type change).
--
-- This migration therefore ADOPTS the live jsonb definition as the
-- canonical one (back-ported verbatim on 2026-10-04 during live apply),
-- so the branch reflects reality. It is already suspension-aware via
-- is_suspended, which part (a) now keeps derived from status.
CREATE OR REPLACE FUNCTION public.check_tenant_access(p_tenant_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
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
$function$;


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
