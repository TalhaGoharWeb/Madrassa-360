-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 046: server-authoritative insert timestamps
--
-- RED-TEAM RT-01: sync_apply's INSERT branch builds its column list from
-- the client payload and excludes only
-- ('id','revision','server_version','updated_by','deleted_at') — a
-- malicious client could supply arbitrary created_at / updated_at values
-- on insert (backdated fee receipts, far-future updated_at to win
-- client-side last-write-wins conflict resolution). The UPDATE branch
-- already stamps updated_at = now() server-side; INSERT was inconsistent.
--
-- Fix at the DATABASE layer (covers sync_apply AND any direct
-- PostgREST insert path, present or future): a BEFORE INSERT trigger on
-- every sync-whitelisted table forces created_at / updated_at to
-- statement time. Client-supplied values are overwritten, never trusted.
--
-- Escape hatch: seeds / backfills that intentionally set historical
-- timestamps may run with
--     SET LOCAL app.preserve_timestamps = 'on';
-- (transaction-scoped). Default is off → server time is forced.
--
-- Idempotent: CREATE OR REPLACE function; triggers dropped/recreated
-- per table inside the DO block (only for tables that actually carry
-- both columns).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sync_force_server_timestamps()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_setting('app.preserve_timestamps', true) = 'on' THEN
    RETURN NEW; -- intentional historical backfill (seeds/migrations)
  END IF;
  NEW.created_at := now();
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_force_server_timestamps() IS
  '046: BEFORE INSERT trigger function — overwrites client-supplied '
  'created_at/updated_at with server time. Bypass with '
  'SET LOCAL app.preserve_timestamps = ''on'' for intentional backfills.';

DO $$
DECLARE
  t            TEXT;
  v_has_both   BOOLEAN;
  v_trg        TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'darjas','classes','darja_sections','students','staff','attendance',
    'fees','exams','results','announcements','library_books','book_issues',
    'finance_transactions','accounts','fee_structures','fee_items',
    'invoices','invoice_items','payments','payment_allocations','refunds',
    'discounts','scholarships','expenses','income','transactions'
  ] LOOP
    SELECT EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = t
                AND column_name = 'created_at')
       AND EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = t
                AND column_name = 'updated_at')
      INTO v_has_both;
    IF v_has_both THEN
      v_trg := 'trg_' || t || '_server_timestamps';
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_trg, t);
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE INSERT ON public.%I '
        'FOR EACH ROW EXECUTE FUNCTION public.sync_force_server_timestamps()',
        v_trg, t);
    END IF;
  END LOOP;
END $$;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('046_sync_insert_timestamps')
ON CONFLICT DO NOTHING;
