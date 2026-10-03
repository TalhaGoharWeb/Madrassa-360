-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 043: audit triggers + log_audit
-- hardening
--
-- SEC-H12: privileged operations (role grants, invoice voids, tenant
-- suspension) had inconsistent audit coverage; log_audit() accepted
-- arbitrary action strings and unbounded payloads.
--
--   * public.audit_all_writes(): generic AFTER INSERT/UPDATE/DELETE
--     trigger that appends an audit_logs row for any write. Tenant is
--     derived from the row's tenant_id (JSONB-safe: tables without the
--     column get NULL, not an error). Payloads are capped at 64KB —
--     oversized payloads are replaced with a {_truncated:true,_bytes:N}
--     marker so the audit ROW always survives. A trigger exception
--     logs a WARNING and never blocks the write it observes (an audit
--     outage must not become a school-operations outage).
--   * Attached to students, staff, attendance, results, classes —
--     the tables the offline sync engine writes.
--   * log_audit(): hardened — action must match a namespaced format
--     allow-list (^[a-z0-9][a-z0-9._-]{1,63}$); entity/entity_id
--     length-capped; new_data/old_data/metadata truncated at 64KB
--     with a marker instead of rejected (the audit row must exist).
--     A strict enumerated action list would break legitimate
--     app-supplied actions (e.g. license.revoked); the format gate is
--     the safer choice — see MIGRATION_NOTES_029_044.md.
--
-- Idempotent: CREATE OR REPLACE / DROP TRIGGER IF EXISTS.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) generic audit trigger ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.audit_all_writes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant  UUID;
  v_rec_id  TEXT;
  v_new     JSONB;
  v_old     JSONB;
  v_new_txt TEXT;
  v_old_txt TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_new := to_jsonb(NEW); v_old := NULL;
  ELSIF TG_OP = 'DELETE' THEN
    v_new := NULL;           v_old := to_jsonb(OLD);
  ELSE
    v_new := to_jsonb(NEW);  v_old := to_jsonb(OLD);
  END IF;

  -- 64KB cap per payload: truncate with a marker, never drop the row.
  IF v_new IS NOT NULL THEN
    v_new_txt := v_new::text;
    IF octet_length(v_new_txt) > 65536 THEN
      v_new := jsonb_build_object('_truncated', TRUE, '_bytes', octet_length(v_new_txt));
    END IF;
  END IF;
  IF v_old IS NOT NULL THEN
    v_old_txt := v_old::text;
    IF octet_length(v_old_txt) > 65536 THEN
      v_old := jsonb_build_object('_truncated', TRUE, '_bytes', octet_length(v_old_txt));
    END IF;
  END IF;

  -- JSONB-safe: tables without these columns yield NULL, not an error.
  v_tenant := NULLIF(COALESCE(v_new, v_old) ->> 'tenant_id', '')::uuid;
  v_rec_id := COALESCE(v_new, v_old) ->> 'id';

  INSERT INTO public.audit_logs
    (tenant_id, user_id, action, entity, entity_id, old_data, new_data, metadata)
  VALUES
    (v_tenant, auth.uid(), lower(TG_OP), TG_TABLE_NAME, v_rec_id,
     v_old, v_new,
     jsonb_build_object('trigger', 'audit_all_writes'));

  RETURN COALESCE(NEW, OLD);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'audit_all_writes failed for %.% (%): %',
    TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, SQLERRM;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS audit_writes ON public.students;
CREATE TRIGGER audit_writes
  AFTER INSERT OR UPDATE OR DELETE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.audit_all_writes();

DROP TRIGGER IF EXISTS audit_writes ON public.staff;
CREATE TRIGGER audit_writes
  AFTER INSERT OR UPDATE OR DELETE ON public.staff
  FOR EACH ROW EXECUTE FUNCTION public.audit_all_writes();

DROP TRIGGER IF EXISTS audit_writes ON public.attendance;
CREATE TRIGGER audit_writes
  AFTER INSERT OR UPDATE OR DELETE ON public.attendance
  FOR EACH ROW EXECUTE FUNCTION public.audit_all_writes();

DROP TRIGGER IF EXISTS audit_writes ON public.results;
CREATE TRIGGER audit_writes
  AFTER INSERT OR UPDATE OR DELETE ON public.results
  FOR EACH ROW EXECUTE FUNCTION public.audit_all_writes();

DROP TRIGGER IF EXISTS audit_writes ON public.classes;
CREATE TRIGGER audit_writes
  AFTER INSERT OR UPDATE OR DELETE ON public.classes
  FOR EACH ROW EXECUTE FUNCTION public.audit_all_writes();


-- ── (b) log_audit() hardening ────────────────────────────────────
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
  -- Action format allow-list: namespaced, lowercase, bounded.
  IF p_action IS NULL
     OR p_action !~ '^[a-z0-9][a-z0-9._-]{1,63}$' THEN
    RAISE EXCEPTION 'log_audit: action must match ^[a-z0-9][a-z0-9._-]{1,63}$';
  END IF;

  IF p_entity IS NOT NULL AND char_length(p_entity) > 128 THEN
    RAISE EXCEPTION 'log_audit: entity too long (max 128)';
  END IF;
  IF p_entity_id IS NOT NULL AND char_length(p_entity_id) > 256 THEN
    RAISE EXCEPTION 'log_audit: entity_id too long (max 256)';
  END IF;

  -- 64KB caps: truncate with a marker so the audit row survives.
  IF p_new IS NOT NULL AND octet_length(p_new::text) > 65536 THEN
    p_new := jsonb_build_object('_truncated', TRUE,
                               '_bytes', octet_length(p_new::text));
  END IF;
  IF p_old IS NOT NULL AND octet_length(p_old::text) > 65536 THEN
    p_old := jsonb_build_object('_truncated', TRUE,
                               '_bytes', octet_length(p_old::text));
  END IF;
  IF p_metadata IS NOT NULL AND octet_length(p_metadata::text) > 65536 THEN
    p_metadata := jsonb_build_object('_truncated', TRUE,
                                    '_bytes', octet_length(p_metadata::text));
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


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('043_audit_triggers')
ON CONFLICT DO NOTHING;
