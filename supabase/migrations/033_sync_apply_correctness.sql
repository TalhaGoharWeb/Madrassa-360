-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 033: sync_apply correctness hardening
--
-- SEC-C2: the INSERT branch probed existence and returned the FULL row
-- (server_row) BEFORE checking tenant membership — any authenticated
-- user could exfiltrate other tenants' rows by UUID probing.
-- SEC-C3: the UPDATE/soft-DELETE revision check was a plain SELECT
-- followed by a separate write with no revision predicate (TOCTOU) —
-- concurrent writers silently lost updates.
--
-- Changes vs 032 (same permission map / scope logic):
--   1. INSERT: tenant_id is required and the membership check runs
--      BEFORE the existence probe. Denials return a reason object.
--   2. INSERT already_exists: server_row is included ONLY when the
--      existing row belongs to the caller's tenant (or caller is a
--      platform admin); cross-tenant hits return a bare reason.
--   3. UPDATE/DELETE: a row the caller may not access returns
--      'not_found' (no membership exception) — closing the
--      exists-vs-forbidden oracle.
--   4. UPDATE and soft-DELETE are predicated on the revision
--      (WHERE id = $n AND revision = $m) with a ROW_COUNT check; a
--      concurrent write between the check and the write now yields a
--      'conflict' payload with freshly re-read server state instead of
--      a silent lost update.
--
-- Idempotent: CREATE OR REPLACE.
-- ═══════════════════════════════════════════════════════════════

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
  v_entity       TEXT;
  v_financial    BOOLEAN;
  v_id           UUID;
  v_tenant       UUID;
  v_row_tenant   UUID;
  v_cur_revision INT;
  v_deleted_at   TIMESTAMPTZ;
  v_row          JSONB;
  v_new_revision INT;
  v_sv           BIGINT;
  v_uid          UUID;
  v_found        BOOLEAN;
  v_rows         INT;
  v_cols         TEXT;
  v_sel          TEXT;
  v_ins_cols     TEXT;
  v_ins_sel      TEXT;
  v_stamp        TEXT;
  v_has_updated_by BOOLEAN;
  v_has_updated_at BOOLEAN;
  v_perm         TEXT;
  v_class_id     UUID;
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

  -- ── 1b) permission map — fail closed on unknown (entity, op) ──
  v_perm := public.sync_required_permission(p_entity, p_op);
  IF v_perm IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:unknown_entity_or_op');
  END IF;

  v_financial := v_entity IN (
    'accounts','fee_structures','fee_items','invoices','invoice_items',
    'payments','payment_allocations','refunds','discounts','scholarships',
    'expenses','income','transactions'
  );

  SELECT
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name=v_entity AND column_name='updated_by'),
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name=v_entity AND column_name='updated_at')
    INTO v_has_updated_by, v_has_updated_at;


  -- ── 2) INSERT ──────────────────────────────────────────────
  IF p_op = 'insert' THEN
    v_id := COALESCE(p_entity_id, NULLIF(p_payload->>'id','')::UUID, gen_random_uuid());

    -- 033: tenant + membership FIRST, before any existence probe.
    v_tenant := NULLIF(p_payload->>'tenant_id','')::UUID;
    IF v_tenant IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_tenant');
    END IF;
    IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:not_member');
    END IF;
    IF NOT public.tenant_has_permission(v_tenant, v_perm) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_permission',
                                'permission', v_perm);
    END IF;

    IF v_entity IN ('results', 'attendance') THEN
      BEGIN
        v_class_id := NULLIF(p_payload->>'class_id','')::UUID;
      EXCEPTION WHEN OTHERS THEN
        v_class_id := NULL;
      END;
      IF NOT public.sync_scope_ok(v_tenant, v_perm, v_class_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:scope');
      END IF;
    END IF;

    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1)', v_entity)
      INTO v_found USING v_id;
    IF v_found THEN
      -- 033: only reveal the row when it belongs to the caller's tenant
      -- (or the caller is a platform admin). Cross-tenant UUID probes
      -- get a bare reason — no data.
      EXECUTE format(
        'SELECT t.tenant_id, t.revision, ' ||
        'CASE WHEN $2 OR t.tenant_id = $3 THEN to_jsonb(t) END ' ||
        'FROM public.%I t WHERE t.id = $1', v_entity)
        INTO v_row_tenant, v_cur_revision, v_row
        USING v_id, public.is_platform_admin(), v_tenant;
      RETURN jsonb_build_object('ok', false, 'reason', 'already_exists',
                                'server_revision', v_cur_revision,
                                'server_row', v_row,
                                'financial', v_financial);
    END IF;

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
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- 033: tenant_id comes from the EXISTING row; rows outside the
  -- caller's access return 'not_found' (closes the exists-vs-forbidden
  -- oracle; previously this raised a distinguishing exception).
  IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT public.tenant_has_permission(v_tenant, v_perm) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_permission',
                              'permission', v_perm);
  END IF;

  IF v_entity IN ('results', 'attendance') THEN
    BEGIN
      v_class_id := NULLIF(v_row->>'class_id','')::UUID;
    EXCEPTION WHEN OTHERS THEN
      v_class_id := NULL;
    END;
    IF v_class_id IS NULL THEN
      BEGIN
        v_class_id := NULLIF(p_payload->>'class_id','')::UUID;
      EXCEPTION WHEN OTHERS THEN
        v_class_id := NULL;
      END;
    END IF;
    IF NOT public.sync_scope_ok(v_tenant, v_perm, v_class_id) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:scope');
    END IF;
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

  -- Pre-check (fast path); the write itself is predicated on the
  -- revision below, which is the atomic guarantee.
  IF v_cur_revision IS DISTINCT FROM p_base_revision THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'conflict',
                              'server_revision', v_cur_revision,
                              'server_row', v_row,
                              'financial', v_financial);
  END IF;

  v_stamp := '';
  IF v_has_updated_by THEN v_stamp := v_stamp || ', updated_by = $3'; END IF;
  IF v_has_updated_at THEN v_stamp := v_stamp || ', updated_at = now()'; END IF;
  v_stamp := v_stamp || ', server_version = $4';


  -- ── 3) UPDATE ──────────────────────────────────────────────
  -- 033: atomic — the revision predicate is part of the UPDATE.
  IF p_op = 'update' THEN
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
              'updated_by','deleted_at','created_at','updated_at')
       AND p_payload ? c.column_name;

    IF v_cols IS NULL THEN
      RETURN jsonb_build_object('ok', true, 'new_revision', v_cur_revision);
    END IF;

    v_sv := nextval('public.sync_server_version_seq');
    EXECUTE format(
      'UPDATE public.%I t SET (%s) = ' ||
      '(SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) AS p)' ||
      '%s WHERE t.id = $2 AND t.revision = $5 RETURNING t.revision',
      v_entity, v_cols, v_sel, v_entity, v_stamp)
      INTO v_new_revision
      USING p_payload, p_entity_id, v_uid, v_sv, p_base_revision;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
      -- Lost the race between the pre-check and the write: re-read and
      -- report a conflict with fresh server state.
      EXECUTE format(
        'SELECT t.revision, to_jsonb(t) FROM public.%I t WHERE t.id = $1', v_entity)
        INTO v_cur_revision, v_row
        USING p_entity_id;
      RETURN jsonb_build_object('ok', false, 'reason', 'conflict',
                                'server_revision', v_cur_revision,
                                'server_row', v_row,
                                'financial', v_financial);
    END IF;

    RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision);
  END IF;


  -- ── 4) DELETE (soft) ───────────────────────────────────────
  -- 033: atomic — predicated on the revision like UPDATE.
  v_stamp := '';
  IF v_has_updated_by THEN v_stamp := v_stamp || ', updated_by = $2'; END IF;
  IF v_has_updated_at THEN v_stamp := v_stamp || ', updated_at = now()'; END IF;
  v_stamp := v_stamp || ', server_version = $3';

  v_sv := nextval('public.sync_server_version_seq');
  EXECUTE format(
    'UPDATE public.%I t SET deleted_at = now()%s ' ||
    'WHERE t.id = $1 AND t.revision = $4 RETURNING t.revision',
    v_entity, v_stamp)
    INTO v_new_revision
    USING p_entity_id, v_uid, v_sv, p_base_revision;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    EXECUTE format(
      'SELECT t.revision, to_jsonb(t) FROM public.%I t WHERE t.id = $1', v_entity)
      INTO v_cur_revision, v_row
      USING p_entity_id;
    RETURN jsonb_build_object('ok', false, 'reason', 'conflict',
                              'server_revision', v_cur_revision,
                              'server_row', v_row,
                              'financial', v_financial);
  END IF;

  RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision);
END;
$$;

COMMENT ON FUNCTION public.sync_apply(TEXT, UUID, INT, JSONB, TEXT) IS
  '033: 032 + correctness: membership check before the existence probe, '
  'server_row scoped to the caller''s tenant, not_found instead of a '
  'membership exception (oracle closed), and atomic revision-predicated '
  'writes for UPDATE/soft-DELETE.';


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('033_sync_apply_correctness')
ON CONFLICT DO NOTHING;
