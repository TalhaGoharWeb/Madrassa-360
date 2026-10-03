-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 035: platform_admins guard trigger
--
-- SEC-C5: the only server-side guard on public.platform_admins was the
-- RLS policy "caller is any platform admin" — a platform_support user
-- could PATCH their own row to platform_owner (or delete all owners)
-- with a raw HTTP call. The Flutter screen's last-owner checks are
-- client-side and bypassable; manage-users:set_platform_role is
-- correctly owner-gated, but the table was directly writable in
-- parallel.
--
-- platform_admins_guard() BEFORE INSERT OR UPDATE OR DELETE:
--   * only a current platform_owner may change role to/from
--     'platform_owner' or delete an owner row;
--   * refuse to delete or demote the LAST platform_owner;
--   * every change writes an audit_logs row (platform-level).
-- Server-side flows without a JWT (seeds, service_role Edge Functions —
-- manage-users is already owner-gated in code) bypass the trigger;
-- service_role bypasses RLS entirely anyway.
--
-- Idempotent: DROP TRIGGER IF EXISTS / CREATE OR REPLACE.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.platform_admins_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_is_owner BOOLEAN;
  v_owner_count     INT;
  v_involves_owner  BOOLEAN;
BEGIN
  -- Seeds / service_role automations run without a JWT; they bypass
  -- (service_role bypasses RLS regardless; manage-users enforces the
  -- owner gate in code before reaching the table).
  IF auth.uid() IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.platform_admins pa
    WHERE pa.user_id = auth.uid() AND pa.role = 'platform_owner'
  ) INTO v_caller_is_owner;

  IF TG_OP = 'INSERT' THEN
    v_involves_owner := (NEW.role = 'platform_owner');
  ELSIF TG_OP = 'UPDATE' THEN
    v_involves_owner := (OLD.role = 'platform_owner' OR NEW.role = 'platform_owner');
  ELSE -- DELETE
    v_involves_owner := (OLD.role = 'platform_owner');
  END IF;

  IF v_involves_owner AND NOT v_caller_is_owner THEN
    RAISE EXCEPTION 'platform_admins: only a platform_owner may grant, revoke, or remove platform_owner';
  END IF;

  -- Last-owner backstop: never delete or demote the final owner.
  IF (TG_OP = 'DELETE' AND OLD.role = 'platform_owner')
     OR (TG_OP = 'UPDATE' AND OLD.role = 'platform_owner' AND NEW.role <> 'platform_owner') THEN
    SELECT COUNT(*) INTO v_owner_count
      FROM public.platform_admins
     WHERE role = 'platform_owner' AND user_id <> OLD.user_id;
    IF v_owner_count = 0 THEN
      RAISE EXCEPTION 'platform_admins: refusing to remove the last platform_owner';
    END IF;
  END IF;

  -- Audit every change (platform-level entry).
  INSERT INTO public.audit_logs (tenant_id, user_id, action, entity, entity_id, old_data, new_data)
  VALUES (
    NULL,
    auth.uid(),
    'platform_admin.' || lower(TG_OP),
    'platform_admins',
    COALESCE(NEW.user_id::text, OLD.user_id::text),
    CASE WHEN TG_OP IN ('UPDATE','DELETE')
         THEN jsonb_build_object('role', OLD.role) END,
    CASE WHEN TG_OP IN ('INSERT','UPDATE')
         THEN jsonb_build_object('role', NEW.role) END
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS platform_admins_guard ON public.platform_admins;
CREATE TRIGGER platform_admins_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.platform_admins
  FOR EACH ROW EXECUTE FUNCTION public.platform_admins_guard();


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('035_platform_admins_guard')
ON CONFLICT DO NOTHING;
