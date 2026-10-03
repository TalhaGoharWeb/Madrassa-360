-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 044: audit retention policy
--
-- SEC-H12 (retention half): audit_logs grew unbounded — no retention
-- policy, no cleanup path. This migration records the policy and
-- ships the cleanup function.
--
-- POLICY (documented here, enforced by audit_retention()):
--   * audit_logs rows are retained for 13 months (one full academic
--     year + one month of overlap for year-end reconciliation).
--   * Cleanup runs monthly via an operator-scheduled job (pg_cron or
--     an Edge Function on a schedule calling the RPC with the
--     service_role key). It is NOT self-scheduling: a migration that
--     silently installs cron jobs is a persistence mechanism, and
--     this task forbids creating scheduled jobs without approval.
--   * Deletes run in bounded batches (default 10k rows) ordered by
--     created_at so a single run never holds a long table lock.
--   * Deletion is FINAL: there is no archive export step here.
--     Operators who need long-term archives must add an export step
--     to the scheduled job BEFORE enabling deletion (see note below).
--
-- PARTITIONING: monthly range partitioning of audit_logs would make
-- retention a cheap DROP PARTITION, but converting a live,
-- FK-referenced table to a partitioned one is a risky, locking,
-- non-idempotent operation (partitioned tables cannot be referenced
-- by the existing FKs without a full rebuild; pg_partman is not
-- guaranteed present). DELIBERATELY DEFERRED: the batched DELETE is
-- safe on any Postgres and sufficient at this table's scale. Revisit
-- partitioning only with a maintenance window and a full backup.
--
-- Idempotent: CREATE OR REPLACE.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.audit_retention(
  p_retention INTERVAL DEFAULT make_interval(months => 13),
  p_batch     INT      DEFAULT 10000
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total BIGINT := 0;
  v_n     BIGINT;
BEGIN
  -- Platform admins only; service_role allowed for the scheduled job.
  IF NOT (public.is_platform_admin()
          OR COALESCE(auth.jwt()->>'role', '') = 'service_role') THEN
    RAISE EXCEPTION 'audit_retention: platform admin only';
  END IF;

  IF p_batch < 1 OR p_batch > 100000 THEN
    RAISE EXCEPTION 'audit_retention: p_batch must be between 1 and 100000';
  END IF;

  LOOP
    DELETE FROM public.audit_logs a
     WHERE a.id IN (
       SELECT id FROM public.audit_logs
        WHERE created_at < now() - p_retention
        ORDER BY created_at
        LIMIT p_batch
     );
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;
    EXIT WHEN v_n < p_batch;
  END LOOP;

  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.audit_retention(INTERVAL, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.audit_retention(INTERVAL, INT) TO authenticated;

COMMENT ON FUNCTION public.audit_retention(INTERVAL, INT) IS
  'Deletes audit_logs older than p_retention (default 13 months) in batches. '
  'Platform-admin-only RPC; schedule monthly via pg_cron or an Edge Function. '
  'Add an archive export before enabling if long-term archives are required.';


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('044_audit_retention')
ON CONFLICT DO NOTHING;
