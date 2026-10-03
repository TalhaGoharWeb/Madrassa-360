-- ═══════════════════════════════════════════════════════════════════
-- 07_redteam_guards.sql — RED-TEAM findings RT-01 / RT-03 / RT-04
--
-- (a) RT-01 / migration 046: sync_force_server_timestamps() trigger —
--     structural: every sync-whitelisted table carrying BOTH created_at
--     and updated_at has trg_<table>_server_timestamps;
--     behavioral: on a scratch table the trigger overwrites a
--     client-supplied 2001 timestamp with server time, and honors the
--     app.preserve_timestamps escape hatch.
-- (b) RT-03 / migration 045: edge_rate_limits table exists with the
--     documented columns + index, RLS enabled with ZERO policies
--     (service-role only), and the fixed-window count query works.
-- (c) RT-04: the 040 storage RLS helper storage_photo_student_id()
--     parses the upload-image deterministic path convention
--     <tenant_id>/students/<student_id>.<ext> (parent SELECT exception).
--
-- RUN: psql "<staging-direct-url>" -v ON_ERROR_STOP=1 -f test/db/07_redteam_guards.sql
--      (postgres superuser / service_role; everything is wrapped in a
--      transaction and ROLLED BACK at the end, so staging is untouched.)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── (a) structural: triggers on all dual-timestamp sync tables ──
DO $$
DECLARE
  t         TEXT;
  v_missing TEXT[] := '{}';
  v_has_both BOOLEAN;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'darjas','classes','darja_sections','students','staff','attendance',
    'fees','exams','results','announcements','library_books','book_issues',
    'finance_transactions','accounts','fee_structures','fee_items',
    'invoices','invoice_items','payments','payment_allocations','refunds',
    'discounts','scholarships','expenses','income','transactions'
  ] LOOP
    SELECT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name=t
                      AND column_name='created_at')
       AND EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name=t
                      AND column_name='updated_at')
      INTO v_has_both;
    IF v_has_both AND NOT EXISTS (
      SELECT 1 FROM pg_trigger tg
      JOIN pg_class c ON c.oid = tg.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname='public' AND c.relname=t
        AND tg.tgname = 'trg_' || t || '_server_timestamps'
        AND NOT tg.tgisinternal
    ) THEN
      v_missing := v_missing || t;
    END IF;
  END LOOP;
  IF array_length(v_missing, 1) > 0 THEN
    RAISE EXCEPTION 'FAIL (a): missing server-timestamp trigger on: %',
      array_to_string(v_missing, ', ');
  END IF;
  RAISE NOTICE 'PASS (a): trg_<table>_server_timestamps present on all dual-timestamp sync tables';
END $$;

-- ── (a2) behavioral: the trigger function forces server time ─────
DO $$
DECLARE
  v_created TIMESTAMPTZ;
  v_updated TIMESTAMPTZ;
BEGIN
  CREATE TEMP TABLE rt_ts_probe (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
  );
  CREATE TRIGGER trg_rt_ts_probe
    BEFORE INSERT ON rt_ts_probe
    FOR EACH ROW EXECUTE FUNCTION public.sync_force_server_timestamps();

  -- hostile insert: backdated timestamps must NOT survive
  INSERT INTO rt_ts_probe (created_at, updated_at)
  VALUES ('2001-01-01 00:00:00+00', '2001-01-01 00:00:00+00')
  RETURNING rt_ts_probe.created_at, rt_ts_probe.updated_at
  INTO v_created, v_updated;
  IF v_created < '2025-01-01 00:00:00+00' OR v_updated < '2025-01-01 00:00:00+00' THEN
    RAISE EXCEPTION 'FAIL (a2): client-supplied 2001 timestamps survived the trigger (got %, %)',
      v_created, v_updated;
  END IF;

  -- escape hatch: intentional backfill is honored
  SET LOCAL app.preserve_timestamps = 'on';
  INSERT INTO rt_ts_probe (created_at, updated_at)
  VALUES ('2001-01-01 00:00:00+00', '2001-01-01 00:00:00+00')
  RETURNING rt_ts_probe.created_at, rt_ts_probe.updated_at
  INTO v_created, v_updated;
  IF v_created <> '2001-01-01 00:00:00+00' THEN
    RAISE EXCEPTION 'FAIL (a2): app.preserve_timestamps=on did not preserve the backfill';
  END IF;
  RAISE NOTICE 'PASS (a2): hostile timestamps overwritten; backfill hatch honored';
END $$;

-- ── (b) edge_rate_limits table ──────────────────────────────────
DO $$
DECLARE
  v_rls     BOOLEAN;
  v_policies INT;
  v_idx     BOOLEAN;
  v_n       BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                  WHERE table_schema='public' AND table_name='edge_rate_limits') THEN
    RAISE EXCEPTION 'FAIL (b): public.edge_rate_limits does not exist (rate limiting fails open)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='edge_rate_limits'
                    AND column_name='bucket_key')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='edge_rate_limits'
                    AND column_name='created_at') THEN
    RAISE EXCEPTION 'FAIL (b): edge_rate_limits missing bucket_key/created_at columns';
  END IF;
  SELECT EXISTS (SELECT 1 FROM pg_indexes
                  WHERE schemaname='public' AND tablename='edge_rate_limits'
                    AND indexname='ix_edge_rate_limits_key_time')
    INTO v_idx;
  IF NOT v_idx THEN
    RAISE EXCEPTION 'FAIL (b): ix_edge_rate_limits_key_time index missing';
  END IF;
  SELECT c.relrowsecurity INTO v_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='edge_rate_limits';
  IF NOT COALESCE(v_rls, false) THEN
    RAISE EXCEPTION 'FAIL (b): RLS not enabled on edge_rate_limits';
  END IF;
  SELECT count(*) INTO v_policies FROM pg_policies
   WHERE schemaname='public' AND tablename='edge_rate_limits';
  IF v_policies <> 0 THEN
    RAISE EXCEPTION 'FAIL (b): edge_rate_limits must be service-role-only (found % policies)', v_policies;
  END IF;

  -- behavioral: the guard.ts fixed-window pattern works end to end
  INSERT INTO public.edge_rate_limits (bucket_key) VALUES ('rt-test-bucket');
  SELECT count(*) INTO v_n FROM public.edge_rate_limits
   WHERE bucket_key='rt-test-bucket'
     AND created_at > now() - interval '1 hour';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'FAIL (b): fixed-window count query returned % (expected 1)', v_n;
  END IF;
  RAISE NOTICE 'PASS (b): edge_rate_limits present, indexed, RLS-on with no policies, window query works';
END $$;

-- ── (c) RT-04: 040 policy helper parses the deterministic path ───
DO $$
DECLARE
  v_sid UUID := 'c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3';
  v_tid TEXT := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_got UUID;
  v_tenant UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='storage_photo_student_id') THEN
    RAISE NOTICE 'SKIP (c): storage_photo_student_id() not deployed';
    RETURN;
  END IF;
  -- new upload-image convention: <tenant_id>/students/<student_id>.png
  v_got := public.storage_photo_student_id(v_tid || '/students/' || v_sid::text || '.png');
  IF v_got IS DISTINCT FROM v_sid THEN
    RAISE EXCEPTION 'FAIL (c): storage_photo_student_id did not parse the deterministic photo path';
  END IF;
  v_tenant := public.storage_path_tenant(v_tid || '/students/' || v_sid::text || '.png');
  IF v_tenant IS DISTINCT FROM v_tid::uuid THEN
    RAISE EXCEPTION 'FAIL (c): storage_path_tenant did not parse the deterministic photo path';
  END IF;
  -- logo path: tenant parses, student-id helper stays NULL
  v_tenant := public.storage_path_tenant(v_tid || '/logo.png');
  IF v_tenant IS DISTINCT FROM v_tid::uuid THEN
    RAISE EXCEPTION 'FAIL (c): storage_path_tenant did not parse the deterministic logo path';
  END IF;
  RAISE NOTICE 'PASS (c): 040 helpers parse the upload-image deterministic path convention';
END $$;

ROLLBACK;
