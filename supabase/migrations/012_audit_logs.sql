-- ═══════════════════════════════════════════════════════════════
-- Migration 012 — Audit logs (mission §60 item 10, §50)
--   * public.audit_logs — append-only event log for tenant AND
--     platform-level events (tenant_id NULL = platform-level).
--   * NO direct client INSERT/UPDATE/DELETE: no write policies are
--     created, so RLS default-deny applies to clients. Writes go through
--     the SECURITY DEFINER public.log_audit() RPC (below) or the
--     service_role (Edge Functions — service_role bypasses RLS).
--   * SELECT: platform admins see everything; tenant admins/owners see
--     their own tenant's rows only.
--   * Append-only: no UPDATE/DELETE policies exist, deliberately.
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


CREATE TABLE IF NOT EXISTS public.audit_logs (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID        REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  action     TEXT        NOT NULL,
  entity     TEXT,
  entity_id  TEXT,
  old_data   JSONB,
  new_data   JSONB,
  metadata   JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_created
  ON public.audit_logs (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_entity
  ON public.audit_logs (entity, entity_id);


-- ═══════════════════════════════════════════════════════════════
-- RLS — SELECT only (no write policies: default-deny for clients)
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform admins read all audit logs" ON public.audit_logs;
CREATE POLICY "platform admins read all audit logs"
  ON public.audit_logs FOR SELECT
  USING (public.is_platform_admin());

DROP POLICY IF EXISTS "tenant admins read own audit logs" ON public.audit_logs;
CREATE POLICY "tenant admins read own audit logs"
  ON public.audit_logs FOR SELECT
  -- tenant_id NULL = platform-level event: only platform admins pass,
  -- because is_tenant_admin(NULL) cannot match a membership row.
  USING (public.is_tenant_admin(tenant_id));


-- ═══════════════════════════════════════════════════════════════
-- public.log_audit() — the client-safe audit writer.
-- SECURITY DEFINER (SET search_path = public) so the INSERT bypasses
-- RLS; callable by authenticated users. user_id is always auth.uid() —
-- callers cannot impersonate another user. A non-admin cannot write a
-- platform-level entry (tenant_id NULL), and cannot write into another
-- tenant's log.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.log_audit(
  p_tenant_id UUID,
  p_action    TEXT,
  p_entity    TEXT,
  p_entity_id TEXT,
  p_old       JSONB,
  p_new       JSONB,
  p_metadata  JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_action IS NULL OR btrim(p_action) = '' THEN
    RAISE EXCEPTION 'log_audit: action must not be empty';
  END IF;

  IF p_tenant_id IS NULL THEN
    IF NOT public.is_platform_admin() THEN
      RAISE EXCEPTION 'log_audit: platform-level entries require a platform admin';
    END IF;
  ELSIF NOT public.is_tenant_admin(p_tenant_id) THEN
    RAISE EXCEPTION 'log_audit: tenant entries require a tenant admin/owner of %', p_tenant_id;
  END IF;

  INSERT INTO public.audit_logs
    (tenant_id, user_id, action, entity, entity_id, old_data, new_data, metadata)
  VALUES
    (p_tenant_id, auth.uid(), p_action, p_entity, p_entity_id, p_old, p_new, p_metadata)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.log_audit(UUID, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_audit(UUID, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB) TO authenticated;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('012_audit_logs')
ON CONFLICT DO NOTHING;
