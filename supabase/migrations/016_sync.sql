-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 016: offline-first sync engine (server)
-- Phase 5 / Worker 1
--
-- Run AFTER 001–015. Adds the server-side half of the offline-first
-- sync contract to the 13 business tables (006) + the 13 finance
-- tables (014):
--
--   darjas, classes, students, staff, attendance, fees, exams, results,
--   announcements, darja_sections, library_books, book_issues,
--   finance_transactions,
--   accounts, fee_structures, fee_items, invoices, invoice_items,
--   payments, payment_allocations, refunds, discounts, scholarships,
--   expenses, income, transactions
--
-- ── CLIENT ↔ SERVER SYNC CONTRACT ─────────────────────────────────
--
-- Sync columns (added below, all idempotent):
--   revision       INTEGER  NOT NULL DEFAULT 1 — per-row write counter,
--                    bumped by trigger on EVERY update (incl. soft delete).
--   server_version BIGINT   nullable — server-assigned monotonic watermark
--                    from public.sync_server_version_seq. Assigned on every
--                    INSERT (trigger) and every sync_apply write. Clients
--                    pull "everything with server_version > last_pulled".
--                    Pre-016 rows have NULL → treat as 0.
--   updated_by     UUID     nullable — auth.uid() of the writer (some 014
--                    tables already had this column; not re-added).
--   deleted_at     TIMESTAMPTZ nullable — soft delete for sync. Deletes are
--                    NEVER hard deletes through sync_apply.
--
-- RPC: public.sync_apply(p_entity, p_entity_id, p_base_revision,
--                        p_payload, p_op)
--   p_entity        TEXT  — table name, WHITELISTED via CASE inside the
--                           function (never used as a dynamic identifier).
--   p_entity_id     UUID  — row id (client-generated UUID for offline
--                           inserts; COALESCE with payload.id).
--   p_base_revision INT  — the revision the client last synced for this
--                           row. REQUIRED for update/delete; ignored for
--                           insert.
--   p_payload       JSONB — {column: value} using lowercase column names.
--                           Server-managed keys are never trusted from the
--                           client: on UPDATE, id / tenant_id / revision /
--                           server_version / deleted_at / created_at /
--                           updated_at are ignored; tenant_id is stamped
--                           from the EXISTING row. On INSERT, tenant_id is
--                           REQUIRED in the payload, revision starts at 1,
--                           server_version is sequence-assigned.
--   p_op            TEXT  — 'insert' | 'update' | 'delete'.
--
-- base_revision semantics (optimistic concurrency):
--   update/delete succeed only if the server's current revision EQUALS
--   p_base_revision. Anything else → conflict, NOTHING is written.
--
-- Returns (JSONB):
--   success:  {"ok": true, "new_revision": <int>}          (+ "id" on insert)
--   failure:  {"ok": false, "reason": <code>,
--              "server_revision": <int>, "server_row": <jsonb>,
--              "financial": <bool>}
--   reason codes: 'conflict' | 'already_exists' | 'not_found' |
--                 'deleted' | 'already_deleted'
--
-- Conflict policy (mission §§20–23):
--   * NORMAL tables (the 13 business tables): deterministic
--     "latest valid revision wins". A conflict is only raised when
--     server_revision > p_base_revision, i.e. the server row is NEWER —
--     so the server row IS the latest valid state. The client adopts
--     server_row (or field-merges and re-submits with
--     p_base_revision = server_revision).
--   * FINANCIAL tables (all 13 from 014: accounts, fee_structures,
--     fee_items, invoices, invoice_items, payments, payment_allocations,
--     refunds, discounts, scholarships, expenses, income, transactions):
--     NEVER silently overwritten. A revision mismatch returns conflict
--     with the full server_row and the client MUST surface it for
--     MANUAL review (no auto-merge, no last-writer-wins).
--   The "financial" flag in the conflict payload tells the client which
--   path applies.
--
-- Soft-delete contract:
--   * sync_apply(p_op='delete') sets deleted_at = now() (revision bumps).
--   * ALL reads — client queries, RLS policies, pull-sync filters — MUST
--     add `WHERE deleted_at IS NULL`. The server does not hide
--     soft-deleted rows by itself.
--   * update on a soft-deleted row → 'deleted' conflict; delete on an
--     already-deleted row → 'already_deleted'.
--   * 014 immutability still rules: sync_apply CANNOT update/delete a
--     final finance row (paid/posted/void/…) — finance_immutable_guard
--     raises, which is correct (corrections are reversal entries).
--
-- Auth: sync_apply is SECURITY DEFINER; it enforces
--   is_platform_admin() OR is_tenant_member(row.tenant_id) itself and
--   bypasses RLS. Fine-grained permission codes (fees.collect etc.)
--   remain enforced by RLS on direct table access, not by this RPC.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS via information_schema guards,
-- CREATE OR REPLACE functions, pg_trigger existence guards,
-- CREATE SEQUENCE IF NOT EXISTS, schema_migrations ON CONFLICT DO NOTHING.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- (a) server_version sequence (monotonic pull-sync watermark)
-- ─────────────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS public.sync_server_version_seq;


-- ─────────────────────────────────────────────────────────────
-- (b) Sync columns on all 26 tables
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- 13 business tables (006)
    'darjas','classes','students','staff','attendance','fees','exams','results',
    'announcements','darja_sections','library_books','book_issues','finance_transactions',
    -- 13 finance tables (014)
    'accounts','fee_structures','fee_items','invoices','invoice_items','payments',
    'payment_allocations','refunds','discounts','scholarships','expenses','income','transactions'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name=t AND column_name='revision') THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN revision INTEGER NOT NULL DEFAULT 1', t);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name=t AND column_name='server_version') THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN server_version BIGINT', t);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name=t AND column_name='updated_by') THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN updated_by UUID', t);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name=t AND column_name='deleted_at') THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN deleted_at TIMESTAMPTZ', t);
    END IF;
  END LOOP;
END $$;


-- ─────────────────────────────────────────────────────────────
-- (c) Trigger functions
-- ─────────────────────────────────────────────────────────────

-- Every UPDATE bumps the per-row revision (drives optimistic concurrency).
CREATE OR REPLACE FUNCTION public.bump_revision()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.revision := OLD.revision + 1;
  RETURN NEW;
END;
$$;

-- Every INSERT gets a server-assigned watermark, even rows created by
-- server-side triggers (e.g. 014 posting flows creating ledger rows).
CREATE OR REPLACE FUNCTION public.sync_stamp_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.server_version IS NULL THEN
    NEW.server_version := nextval('public.sync_server_version_seq');
  END IF;
  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- (d) Trigger attachments (pg_trigger existence guards)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'darjas','classes','students','staff','attendance','fees','exams','results',
    'announcements','darja_sections','library_books','book_issues','finance_transactions',
    'accounts','fee_structures','fee_items','invoices','invoice_items','payments',
    'payment_allocations','refunds','discounts','scholarships','expenses','income','transactions'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname = 'trg_sync_bump_revision'
                      AND tgrelid = ('public.' || t)::regclass) THEN
      EXECUTE format(
        'CREATE TRIGGER trg_sync_bump_revision
           BEFORE UPDATE ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.bump_revision()', t);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname = 'trg_sync_stamp_insert'
                      AND tgrelid = ('public.' || t)::regclass) THEN
      EXECUTE format(
        'CREATE TRIGGER trg_sync_stamp_insert
           BEFORE INSERT ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.sync_stamp_insert()', t);
    END IF;
  END LOOP;
END $$;


-- ─────────────────────────────────────────────────────────────
-- (e) sync_apply RPC
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_apply(
  p_entity        TEXT,
  p_entity_id     UUID,
  p_base_revision INT,
  p_payload       JSONB,
  p_op            TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entity       TEXT;   -- whitelisted table name; NEVER raw input
  v_financial    BOOLEAN;
  v_id           UUID;
  v_tenant       UUID;
  v_cur_revision INT;
  v_deleted_at   TIMESTAMPTZ;
  v_row          JSONB;
  v_new_revision INT;
  v_sv           BIGINT;
  v_uid          UUID;
  v_found        BOOLEAN;
  v_rows         INT;
  v_cols         TEXT;   -- settable payload columns (update)
  v_sel          TEXT;   -- their select list from the populated record
  v_ins_cols     TEXT;   -- insertable payload columns (insert)
  v_ins_sel      TEXT;
  v_stamp        TEXT;   -- audit stamp clause (update/delete)
  v_has_updated_by BOOLEAN;
  v_has_updated_at BOOLEAN;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sync: unauthenticated';
  END IF;

  IF p_op NOT IN ('insert', 'update', 'delete') THEN
    RAISE EXCEPTION 'sync: unknown op %', p_op;
  END IF;

  -- ── 1) whitelist p_entity via CASE — no dynamic table names ──
  CASE p_entity
    WHEN 'darjas'               THEN v_entity := 'darjas';
    WHEN 'classes'              THEN v_entity := 'classes';
    WHEN 'students'             THEN v_entity := 'students';
    WHEN 'staff'                THEN v_entity := 'staff';
    WHEN 'attendance'           THEN v_entity := 'attendance';
    WHEN 'fees'                 THEN v_entity := 'fees';
    WHEN 'exams'                THEN v_entity := 'exams';
    WHEN 'results'              THEN v_entity := 'results';
    WHEN 'announcements'        THEN v_entity := 'announcements';
    WHEN 'darja_sections'       THEN v_entity := 'darja_sections';
    WHEN 'library_books'        THEN v_entity := 'library_books';
    WHEN 'book_issues'          THEN v_entity := 'book_issues';
    WHEN 'finance_transactions' THEN v_entity := 'finance_transactions';
    WHEN 'accounts'             THEN v_entity := 'accounts';
    WHEN 'fee_structures'       THEN v_entity := 'fee_structures';
    WHEN 'fee_items'            THEN v_entity := 'fee_items';
    WHEN 'invoices'             THEN v_entity := 'invoices';
    WHEN 'invoice_items'        THEN v_entity := 'invoice_items';
    WHEN 'payments'             THEN v_entity := 'payments';
    WHEN 'payment_allocations'  THEN v_entity := 'payment_allocations';
    WHEN 'refunds'              THEN v_entity := 'refunds';
    WHEN 'discounts'            THEN v_entity := 'discounts';
    WHEN 'scholarships'         THEN v_entity := 'scholarships';
    WHEN 'expenses'             THEN v_entity := 'expenses';
    WHEN 'income'               THEN v_entity := 'income';
    WHEN 'transactions'         THEN v_entity := 'transactions';
    ELSE RAISE EXCEPTION 'sync: unknown entity %', p_entity;
  END CASE;

  -- All 13 tables created by 014 are financial: never silently overwrite.
  v_financial := v_entity IN (
    'accounts','fee_structures','fee_items','invoices','invoice_items',
    'payments','payment_allocations','refunds','discounts','scholarships',
    'expenses','income','transactions'
  );

  -- Per-table audit-stamp availability (not every table has both columns:
  -- e.g. payment_allocations / invoice_items have no updated_by).
  SELECT
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name=v_entity AND column_name='updated_by'),
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name=v_entity AND column_name='updated_at')
    INTO v_has_updated_by, v_has_updated_at;


  -- ── 2) INSERT ──────────────────────────────────────────────
  IF p_op = 'insert' THEN
    v_id := COALESCE(p_entity_id, NULLIF(p_payload->>'id','')::UUID, gen_random_uuid());

    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1)', v_entity)
      INTO v_found USING v_id;
    IF v_found THEN
      EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.id = $1', v_entity)
        INTO v_row USING v_id;
      RETURN jsonb_build_object('ok', false, 'reason', 'already_exists',
                                'server_revision', (v_row->>'revision')::INT,
                                'server_row', v_row,
                                'financial', v_financial);
    END IF;

    v_tenant := NULLIF(p_payload->>'tenant_id','')::UUID;
    IF v_tenant IS NULL THEN
      RAISE EXCEPTION 'sync: insert payload missing tenant_id';
    END IF;
    IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
      RAISE EXCEPTION 'sync: not a member of tenant %', v_tenant;
    END IF;

    -- Insertable = payload keys ∩ real, non-generated columns,
    -- minus server-managed ones (id explicit, revision/server_version/
    -- updated_by/deleted_at assigned or forbidden here).
    SELECT
      string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position),
      string_agg('p.' || quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
      INTO v_ins_cols, v_ins_sel
      FROM information_schema.columns c
     WHERE c.table_schema = 'public'
       AND c.table_name   = v_entity
       AND c.is_generated = 'NEVER'
       AND c.column_name NOT IN
             ('id','revision','server_version','updated_by','deleted_at')
       AND p_payload ? c.column_name;

    IF v_ins_cols IS NULL THEN
      RAISE EXCEPTION 'sync: insert payload carries no writable columns';
    END IF;

    EXECUTE format(
      'INSERT INTO public.%I (id, %s, revision, updated_by) ' ||
      'SELECT $2, %s, 1, $3 ' ||
      'FROM jsonb_populate_record(NULL::public.%I, $1) AS p ' ||
      'RETURNING revision',
      v_entity, v_ins_cols, v_ins_sel, v_entity)
      INTO v_new_revision
      USING p_payload, v_id, v_uid;
    -- server_version is stamped by trg_sync_stamp_insert (nextval).

    RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision, 'id', v_id);
  END IF;


  -- ── update / delete share the fetch + guards ────────────────
  IF p_base_revision IS NULL THEN
    RAISE EXCEPTION 'sync: base_revision is required for %', p_op;
  END IF;

  EXECUTE format(
    'SELECT t.revision, t.tenant_id, t.deleted_at, to_jsonb(t) ' ||
    'FROM public.%I t WHERE t.id = $1', v_entity)
    INTO v_cur_revision, v_tenant, v_deleted_at, v_row
    USING p_entity_id;
  -- NOTE: do NOT use IF NOT FOUND here — EXECUTE..INTO does not reset
  -- FOUND when zero rows are returned (it keeps the previous value).
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- tenant_id comes from the EXISTING row; client tenant_id never trusted.
  IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
    RAISE EXCEPTION 'sync: not a member of tenant %', v_tenant;
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    IF p_op = 'delete' THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'already_deleted',
                                'server_revision', v_cur_revision,
                                'server_row', v_row,
                                'financial', v_financial);
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'deleted',
                              'server_revision', v_cur_revision,
                              'server_row', v_row,
                              'financial', v_financial);
  END IF;

  -- Optimistic-concurrency check. On mismatch NOTHING is written —
-- financial rows are NEVER overwritten; the caller resolves
  -- (manual review for financial, latest-valid-revision for normal).
  IF v_cur_revision IS DISTINCT FROM p_base_revision THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'conflict',
                              'server_revision', v_cur_revision,
                              'server_row', v_row,
                              'financial', v_financial);
  END IF;

  -- Audit stamp, adapted to the table's actual columns.
  v_stamp := '';
  IF v_has_updated_by THEN v_stamp := v_stamp || ', updated_by = $3'; END IF;
  IF v_has_updated_at THEN v_stamp := v_stamp || ', updated_at = now()'; END IF;
  v_stamp := v_stamp || ', server_version = $4';


  -- ── 3) UPDATE ──────────────────────────────────────────────
  IF p_op = 'update' THEN
    -- Only payload keys that are real, non-generated, non-server-managed
    -- columns are written; everything else in the payload is ignored.
    SELECT
      string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position),
      string_agg('p.' || quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
      INTO v_cols, v_sel
      FROM information_schema.columns c
     WHERE c.table_schema = 'public'
       AND c.table_name   = v_entity
       AND c.is_generated = 'NEVER'
       AND c.column_name NOT IN
             ('id','tenant_id','revision','server_version',
              'deleted_at','created_at','updated_at')
       AND p_payload ? c.column_name;

    IF v_cols IS NULL THEN
      -- Payload carried nothing writable; revision already matches.
      RETURN jsonb_build_object('ok', true, 'new_revision', v_cur_revision);
    END IF;

    v_sv := nextval('public.sync_server_version_seq');
    EXECUTE format(
      'UPDATE public.%I t SET (%s) = ' ||
      '(SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) AS p)' ||
      '%s WHERE t.id = $2 RETURNING t.revision',
      v_entity, v_cols, v_sel, v_entity, v_stamp)
      INTO v_new_revision
      USING p_payload, p_entity_id, v_uid, v_sv;
    -- revision bumped by trg_sync_bump_revision.

    RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision);
  END IF;


  -- ── 4) DELETE (soft) ───────────────────────────────────────
  -- Rebuild the stamp for this branch's parameter layout ($1=id, $2=uid, $3=sv).
  v_stamp := '';
  IF v_has_updated_by THEN v_stamp := v_stamp || ', updated_by = $2'; END IF;
  IF v_has_updated_at THEN v_stamp := v_stamp || ', updated_at = now()'; END IF;
  v_stamp := v_stamp || ', server_version = $3';

  v_sv := nextval('public.sync_server_version_seq');
  EXECUTE format(
    'UPDATE public.%I t SET deleted_at = now()%s ' ||
    'WHERE t.id = $1 RETURNING t.revision',
    v_entity, v_stamp)
    INTO v_new_revision
    USING p_entity_id, v_uid, v_sv;

  RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision);
END;
$$;

COMMENT ON FUNCTION public.sync_apply(TEXT, UUID, INT, JSONB, TEXT) IS
  '016: offline-sync apply RPC. Optimistic concurrency on revision; '
  'soft deletes; financial tables never overwritten on conflict. '
  'See migration header for the full client contract.';


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('016_sync') ON CONFLICT DO NOTHING;
