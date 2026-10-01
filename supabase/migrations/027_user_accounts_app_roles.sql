-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 027: user accounts + app roles RLS,
-- tenants member-update policy, madrasas/fees policy fixes,
-- sync_apply writable-column hardening
--
-- Sections:
--   (a) public.user_accounts — matches lib/data/models/user_account.dart
--       (id, name, email, role_name, role_name_urdu, linked_staff_id,
--        linked_parent_id, is_active). created_at / updated_at are
--       migration-added audit columns; the Dart model's fromJson ignores
--       unknown keys, so they are safe to add.
--   (b) public.app_roles — definition for FRESH databases only. Live
--       already has its rows (seeded out-of-band); this migration only
--       CREATEs TABLE IF NOT EXISTS and never drops/recreates it.
--   (c) RLS + fail-closed policies on both tables.
--   (d) tenants_member_update — tenant-member UPDATE gated on
--       settings.update (verified code, 019).
--   (e) Policy fixes: madrasas_member_select own-tenant scoping (legacy
--       madrasas has NO tenant FK column — tenant derived via the
--       tenant_code pattern from 004/006); fees_delete_tenant
--       'fees.collect' → 'fees.delete'.
--   (f) sync_apply: add updated_by to the UPDATE writable-column exclusion
--       list (016's function replicated with a one-line change).
--
-- Flags / known limitations (fail-closed where noted):
--   * Plan §1A named permission code 'users.manage' — it does NOT exist in
--     the 019 permission seed. The user_accounts write policies below use
--     the closest VERIFIED codes instead: users.create (INSERT),
--     users.update (UPDATE), users.deactivate (DELETE). Marked TODO.
--   * public.user_accounts has NO tenant_id column (matches the Dart
--     model), so per-row "own tenant" scoping is impossible; the member
--     write check is "holds the code in >=1 active tenant". Marked TODO.
--   * 'fees.delete' is likewise not in the 019 seed; until it is seeded
--     and granted, fee deletes are platform-admin-only (fail-closed). The
--     rename is applied exactly as plan §1A instructed.
--   * Full per-table permission hardening of sync_apply is DEFERRED
--     (no SECURITY DEFINER change here); see 016 header.
--
-- Idempotent: IF NOT EXISTS / IF EXISTS / DROP POLICY IF EXISTS throughout.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) user_accounts ──────────────────────────────────────────
-- Mirrors lib/data/models/user_account.dart. `password` is transient in the
-- app (used once at creation via the manage-users Edge Function) and is
-- deliberately NOT a column here.

CREATE TABLE IF NOT EXISTS public.user_accounts (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name             TEXT        NOT NULL,
  email            TEXT        NOT NULL UNIQUE,
  role_name        TEXT        NOT NULL DEFAULT 'teacher',
  role_name_urdu   TEXT        NOT NULL DEFAULT 'استاد',
  linked_staff_id  UUID        NULL,
  linked_parent_id UUID        NULL,
  is_active        BOOLEAN     NOT NULL DEFAULT true,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_accounts IS
  '027: admin-managed system users (metadata only; auth lives in auth.users). '
  'Matches lib/data/models/user_account.dart.';


-- ── (b) app_roles (fresh databases only) ───────────────────────
-- Live already has its app_roles rows (created out-of-band); this only
-- ensures fresh databases get the same table. Never dropped/recreated.

CREATE TABLE IF NOT EXISTS public.app_roles (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        UNIQUE NOT NULL,
  name_urdu   TEXT,
  description TEXT,
  permissions TEXT[],
  is_system   BOOLEAN     DEFAULT false,
  created_at  TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE public.app_roles IS
  '027: role definitions for fresh databases. Live rows predate this migration.';


-- ── (c) RLS + policies ─────────────────────────────────────────

ALTER TABLE public.user_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_roles    ENABLE ROW LEVEL SECURITY;

-- user_accounts SELECT: platform/super admins, or active members of any
-- tenant. (Same-tenant scoping is impossible: the table carries no
-- tenant_id — see flags in the header.)
DROP POLICY IF EXISTS "user_accounts_select_member" ON public.user_accounts;
CREATE POLICY "user_accounts_select_member"
  ON public.user_accounts FOR SELECT
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid() AND tm.is_active
    )
  );

-- TODO(users.manage): plan §1A named permission code 'users.manage', which
-- does not exist in the 019 permission seed (verified). Closest verified
-- codes used instead: users.create / users.update / users.deactivate.
-- Also, with no tenant_id on this table the check is "holds the code in
-- >=1 active tenant" rather than per-row tenant scoping.
DROP POLICY IF EXISTS "user_accounts_insert_admin" ON public.user_accounts;
CREATE POLICY "user_accounts_insert_admin"
  ON public.user_accounts FOR INSERT
  WITH CHECK (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.is_active
        AND public.tenant_has_permission(tm.tenant_id, 'users.create')
    )
  );

DROP POLICY IF EXISTS "user_accounts_update_admin" ON public.user_accounts;
CREATE POLICY "user_accounts_update_admin"
  ON public.user_accounts FOR UPDATE
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.is_active
        AND public.tenant_has_permission(tm.tenant_id, 'users.update')
    )
  )
  WITH CHECK (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.is_active
        AND public.tenant_has_permission(tm.tenant_id, 'users.update')
    )
  );

DROP POLICY IF EXISTS "user_accounts_delete_admin" ON public.user_accounts;
CREATE POLICY "user_accounts_delete_admin"
  ON public.user_accounts FOR DELETE
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.tenant_memberships tm
      WHERE tm.user_id = auth.uid()
        AND tm.is_active
        AND public.tenant_has_permission(tm.tenant_id, 'users.deactivate')
    )
  );

-- app_roles SELECT: any authenticated user (roles are read by the user
-- management screen's role picker).
DROP POLICY IF EXISTS "app_roles_select_auth" ON public.app_roles;
CREATE POLICY "app_roles_select_auth"
  ON public.app_roles FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- app_roles writes: platform/super admins only.
DROP POLICY IF EXISTS "app_roles_insert_platform" ON public.app_roles;
CREATE POLICY "app_roles_insert_platform"
  ON public.app_roles FOR INSERT
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "app_roles_update_platform" ON public.app_roles;
CREATE POLICY "app_roles_update_platform"
  ON public.app_roles FOR UPDATE
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "app_roles_delete_platform" ON public.app_roles;
CREATE POLICY "app_roles_delete_platform"
  ON public.app_roles FOR DELETE
  USING (public.is_platform_admin());


-- ── (d) tenants: member UPDATE ─────────────────────────────────
-- Members with the settings.update permission (verified code, 019) may
-- update their own tenant row. Platform admins are covered by 001's
-- "platform admins manage tenants" FOR ALL policy.

DROP POLICY IF EXISTS "tenants_member_update" ON public.tenants;
CREATE POLICY "tenants_member_update"
  ON public.tenants FOR UPDATE
  USING (
    public.is_tenant_member(id)
    AND public.tenant_has_permission(id, 'settings.update')
  )
  WITH CHECK (
    public.is_tenant_member(id)
    AND public.tenant_has_permission(id, 'settings.update')
  );


-- ── (e1) madrasas_member_select: own-tenant scoping ─────────────
-- public.madrasas is a legacy out-of-band table with NO tenant FK column
-- (verified via 004_memberships.sql / 006_tenant_retrofit.sql, which derive
-- the tenant as tenants.tenant_code =
-- 'M-' || upper(substr(replace(madrasas.id::text, '-', ''), 1, 8))).
-- The old USING granted SELECT to any active member of ANY tenant; the new
-- one scopes to the row's own derived tenant (+ platform admins).

DROP POLICY IF EXISTS "madrasas_member_select" ON public.madrasas;
CREATE POLICY "madrasas_member_select"
  ON public.madrasas FOR SELECT
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1
      FROM public.tenants t
      WHERE t.tenant_code = 'M-' || upper(substr(replace(id::text, '-', ''), 1, 8))
        AND public.is_tenant_member(t.id)
    )
  );


-- ── (e2) fees_delete_tenant: 'fees.collect' → 'fees.delete' ──────
-- NOTE: 'fees.delete' is not in the 019 permission seed; until it is seeded
-- and granted to a role, fee deletes are platform-admin-only (fail-closed).

DROP POLICY IF EXISTS "fees_delete_tenant" ON public.fees;
CREATE POLICY "fees_delete_tenant" ON public.fees FOR DELETE USING (
  public.is_platform_admin()
  OR (public.is_tenant_member(fees.tenant_id)
      AND public.tenant_has_permission(fees.tenant_id, 'fees.delete'))
);


-- ── (f) sync_apply: exclude updated_by from client-writable columns ──
-- Replicates 016_sync.sql's sync_apply() with a ONE-LINE change: 'updated_by'
-- added to the UPDATE branch's NOT IN exclusion list (the INSERT branch
-- already excluded it). Rationale: updated_by is stamped server-side via
-- v_stamp ('updated_by = $3'), so a client-supplied value would either forge
-- the audit trail or break the UPDATE with a duplicate column assignment.
-- Full per-table permission hardening of sync_apply is DEFERRED (see 016).

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
              'updated_by','deleted_at','created_at','updated_at')
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
  '027: same contract as 016, plus updated_by excluded from the '
  'client-writable UPDATE column list (server stamps it from auth.uid()).';

