-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 032: sync_apply per-entity permissions
--
-- SEC-C1: the SECURITY DEFINER RPC carrying EVERY app write checked only
-- tenant membership and ignored the 66-code permission system — any
-- active member (even `student`) could write any of the 26 whitelisted
-- tables. This migration enforces the permission model INSIDE the write
-- path:
--
--   * public.sync_required_permission(p_entity, p_op) — immutable map
--     (entity, op) → required permission code. NULL = unknown → the
--     caller fails closed with a clear reason (never an exception, so
--     the client marks the op failed instead of retrying forever).
--   * public.sync_scope_ok(...) — for scoped entities (results,
--     attendance) additionally enforces 022's scope_allows() when the
--     caller actually has a narrowed permission_scopes row; callers
--     with no scope row fall back to the permission-code check (so
--     unscoped roles keep working exactly as before).
--   * sync_apply re-declared (same contract as 027) with the checks in
--     the INSERT branch and in the shared UPDATE/DELETE guard section.
--     Platform admins keep the is_platform_admin() short-circuit via
--     tenant_has_permission().
--
-- Permission map uses ONLY verified codes (005/019/021). 'fees.delete'
-- does not exist in the seed (027 note) — deletes on fee/finance rows
-- therefore fail closed to platform admins until it is seeded, matching
-- the RLS policy renamed in 027.
--
-- Idempotent: CREATE OR REPLACE functions.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) immutable (entity, op) → permission code map ──────────
CREATE OR REPLACE FUNCTION public.sync_required_permission(p_entity TEXT, p_op TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE p_entity
    WHEN 'darjas' THEN 'academics.manage'
    WHEN 'classes' THEN 'academics.manage'
    WHEN 'darja_sections' THEN 'academics.manage'
    WHEN 'students' THEN CASE p_op
      WHEN 'insert' THEN 'students.create'
      WHEN 'update' THEN 'students.update'
      WHEN 'delete' THEN 'students.delete' END
    WHEN 'staff' THEN CASE p_op
      WHEN 'insert' THEN 'staff.create'
      WHEN 'update' THEN 'staff.update'
      WHEN 'delete' THEN 'staff.delete' END
    WHEN 'attendance' THEN CASE p_op
      WHEN 'insert' THEN 'attendance.mark'
      WHEN 'update' THEN 'attendance.edit'
      WHEN 'delete' THEN 'attendance.delete' END
    WHEN 'fees' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'exams' THEN CASE p_op
      WHEN 'insert' THEN 'exams.create'
      WHEN 'update' THEN 'exams.update'
      WHEN 'delete' THEN 'exams.delete' END
    WHEN 'results' THEN CASE p_op
      WHEN 'insert' THEN 'results.enter'
      ELSE 'results.edit' END
    WHEN 'announcements' THEN 'announcements.send'
    WHEN 'library_books' THEN 'library.manage'
    WHEN 'book_issues' THEN 'library.manage'
    WHEN 'finance_transactions' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    WHEN 'accounts' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    WHEN 'fee_structures' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.create' END
    WHEN 'fee_items' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.create' END
    WHEN 'invoices' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'invoice_items' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'payments' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.collect' END
    WHEN 'payment_allocations' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.collect' END
    WHEN 'refunds' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.refund' END
    WHEN 'discounts' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'scholarships' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'expenses' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    WHEN 'income' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    WHEN 'transactions' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    ELSE NULL
  END
$$;

COMMENT ON FUNCTION public.sync_required_permission(TEXT, TEXT) IS
  '032: sync write-path permission map. NULL = unknown (entity,op): '
  'sync_apply fails closed with reason forbidden:unknown_entity_or_op.';


-- ── (b) scope narrowing for class-scoped entities ─────────────
-- Respects 022 scope rows when they exist; otherwise the permission-code
-- check (already passed) stands. Never consulted for platform admins
-- (they carry no scope rows).
CREATE OR REPLACE FUNCTION public.sync_scope_ok(
  p_tenant_id UUID,
  p_code      TEXT,
  p_class_id  UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM public.permission_scopes ps
      JOIN public.permissions p ON p.id = ps.permission_id
     WHERE ps.tenant_id = p_tenant_id
       AND ps.user_id   = auth.uid()
       AND p.code       = p_code
  ) THEN
    RETURN TRUE; -- no narrowing configured for this caller+code
  END IF;
  RETURN public.scope_allows(p_tenant_id, auth.uid(), p_code, p_class_id);
END;
$$;


-- ── (c) sync_apply re-declared with permission enforcement ────
-- Body = 027's contract + (1) v_perm lookup & enforcement in INSERT and
-- in the shared UPDATE/DELETE guards, (2) scope narrowing for results /
-- attendance. Denials return a reason object, not an exception.
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
  v_perm         TEXT;   -- required permission code for (entity, op)
  v_class_id     UUID;   -- for scope narrowing on results/attendance
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

    -- 032: permission enforcement on the write path.
    IF NOT public.tenant_has_permission(v_tenant, v_perm) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_permission',
                                'permission', v_perm);
    END IF;

    -- 032: scope narrowing for class-scoped entities.
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

  IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
    RAISE EXCEPTION 'sync: not a member of tenant %', v_tenant;
  END IF;

  -- 032: permission enforcement on the write path.
  IF NOT public.tenant_has_permission(v_tenant, v_perm) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_permission',
                              'permission', v_perm);
  END IF;

  -- 032: scope narrowing for class-scoped entities (class from the row).
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
      '%s WHERE t.id = $2 RETURNING t.revision',
      v_entity, v_cols, v_sel, v_entity, v_stamp)
      INTO v_new_revision
      USING p_payload, p_entity_id, v_uid, v_sv;

    RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision);
  END IF;


  -- ── 4) DELETE (soft) ───────────────────────────────────────
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
  '032: same contract as 027, plus per-entity permission enforcement via '
  'sync_required_permission() (fail closed with a reason, not an exception) '
  'and scope narrowing for results/attendance via sync_scope_ok().';


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('032_sync_apply_permissions')
ON CONFLICT DO NOTHING;
