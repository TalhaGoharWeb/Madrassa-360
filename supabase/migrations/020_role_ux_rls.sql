-- ═══════════════════════════════════════════════════════════════
-- Migration 020 — Role-aware UX: RLS + permission helpers + RPCs
-- (design doc §3.2)
--   (a) RLS on the five 019 tables (tenant_roles,
--       tenant_role_permissions, user_permissions, permission_scopes,
--       permission_delegations): SELECT for tenant members; writes
--       require tenant_has_permission(tid, 'roles.assign') or
--       owner/admin. The DB never trusts client-sent roles.
--   (b) Rewritten helpers (same signatures/contracts as before):
--         tenant_has_permission(p_tenant_id, p_code)
--         get_my_permissions(p_madrasa_id DEFAULT NULL)
--       now resolving through tenant_roles / tenant_role_permissions
--       (+ user_permissions with deny > grant precedence, + active
--       permission_delegations). Platform-admin short-circuit kept.
--       get_my_permissions keeps RETURNS TABLE(code TEXT) and the
--       p_madrasa_id param name; p_tenant_id/p_madrasa_id is now
--       HONORED (NULL = all tenants, as today); the deprecated
--       profiles.role branch is left untouched.
--       New: get_my_permissions_detailed(p_tenant_id DEFAULT NULL)
--       → (code, tenant_id, source ∈ {role, override, delegation}).
--   (c) scope_allows(p_tenant_id, p_user_id, p_code,
--       p_class_id DEFAULT NULL): TRUE when no scope row exists
--       (default per-role behavior) or scope is 'all'; 'classes'
--       checks teacher_class_assignments-derived class lists;
--       'students' checks scoped students enrolled in the class.
--   (d) attendance + results WRITE policies tightened with
--       scope_allows() so a class-scoped teacher cannot mark/enter
--       outside their classes even via raw API (SELECT policies
--       unchanged).
--   (e) Management RPCs (all SECURITY DEFINER, SET search_path=public;
--       the caller's rights are checked inside via is_tenant_admin /
--       tenant_has_permission — arguments are never trusted):
--         assign_tenant_role, set_role_permissions,
--         set_user_permission, create_tenant_role, delegate_permission.
--
-- DOCUMENTED CHOICES / DEVIATIONS FROM THE DESIGN DOC:
--   * Results scope join: results has NO class_id of its own
--     (verified: 01_schema.sql — exams.class_id ~line 197,
--     students.class_id ~line 94, both nullable). The result's class
--     is resolved as COALESCE(exams.class_id, students.class_id) —
--     the exam's class first (the exam defines the class), falling
--     back to the student's enrolled class. Implemented in the
--     SECURITY DEFINER helper public.result_class_id().
--   * 'department' scope in scope_allows() is fail-closed (returns
--     FALSE when a department scope row exists): the data model has
--     no department dimension on classes/darjas/students (department
--     exists only on staff), so a department scope cannot be
--     evaluated against a class target. No department scopes are
--     seeded by 019, so this path only triggers for rows a tenant
--     admin creates explicitly.
--   * set_role_permissions()'s "last owner-capable role" guard is
--     implemented as: after applying the change, at least one ACTIVE
--     tenant_roles row in the tenant must still hold roles.assign;
--     otherwise the whole change is refused (transaction rollback).
--   * set_user_permission() accepts p_effect NULL to DELETE the
--     override row (remove the exception); 'grant'/'deny' upsert it.
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (b0) User-parameterized helpers used by the rewritten functions,
-- the 019 ceiling trigger, and the RPCs below.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.user_is_tenant_admin(p_tenant_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
           SELECT 1 FROM public.platform_admins pa
            WHERE pa.user_id = p_user_id
         )
      OR EXISTS (
           SELECT 1 FROM public.tenant_memberships tm
            WHERE tm.tenant_id = p_tenant_id
              AND tm.user_id   = p_user_id
              AND tm.is_active
              AND tm.role IN ('tenant_owner', 'tenant_admin')
         );
$$;

-- is_tenant_admin() keeps its 004 contract; now delegates to the
-- user-parameterized helper so triggers/RPCs can check ANY user.
CREATE OR REPLACE FUNCTION public.is_tenant_admin(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.user_is_tenant_admin(p_tenant_id, auth.uid());
$$;

-- Explicit deny lookup (deny > everything).
CREATE OR REPLACE FUNCTION public.user_code_denied(p_tenant_id UUID, p_user_id UUID, p_code TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.user_permissions up
      JOIN public.permissions p ON p.id = up.permission_id
     WHERE up.tenant_id = p_tenant_id
       AND up.user_id   = p_user_id
       AND p.code       = p_code
       AND up.effect     = 'deny'
  );
$$;

-- Effective permission WITHOUT delegations (role grant OR explicit
-- user grant, minus denies). Delegations deliberately do NOT chain:
-- a delegated code can never itself be re-delegated.
CREATE OR REPLACE FUNCTION public.user_effective_permission(p_tenant_id UUID, p_user_id UUID, p_code TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT public.user_code_denied(p_tenant_id, p_user_id, p_code)
     AND (
           EXISTS ( -- role grant via the tenant's editable role catalog
             SELECT 1
               FROM public.tenant_memberships tm
               JOIN public.tenant_roles tr
                 ON tr.tenant_id = tm.tenant_id
                AND tr.key       = tm.role
                AND tr.is_active
               JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = tr.id
               JOIN public.permissions p             ON p.id = trp.permission_id
              WHERE tm.tenant_id = p_tenant_id
                AND tm.user_id   = p_user_id
                AND tm.is_active
                AND p.code       = p_code
           )
        OR EXISTS ( -- explicit per-user grant override
             SELECT 1
               FROM public.user_permissions up
               JOIN public.permissions p ON p.id = up.permission_id
              WHERE up.tenant_id = p_tenant_id
                AND up.user_id   = p_user_id
                AND p.code       = p_code
                AND up.effect     = 'grant'
           )
         );
$$;


-- ═══════════════════════════════════════════════════════════════
-- (b1) Rewrite tenant_has_permission(): same signature
-- (p_tenant_id UUID, p_code TEXT); resolves through tenant_roles /
-- tenant_role_permissions + user_permissions (deny > grant) +
-- ACTIVE permission_delegations (expires_at IS NULL OR > now()).
-- Platform-admin short-circuit retained.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tenant_has_permission(p_tenant_id UUID, p_code TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_platform_admin()
      OR public.user_effective_permission(p_tenant_id, auth.uid(), p_code)
      OR (
           NOT public.user_code_denied(p_tenant_id, auth.uid(), p_code)
           AND EXISTS (
                 SELECT 1
                   FROM public.permission_delegations d
                   JOIN public.permissions p ON p.id = d.permission_id
                  WHERE d.tenant_id    = p_tenant_id
                    AND d.delegatee_id = auth.uid()
                    AND p.code         = p_code
                    AND (d.starts_at  IS NULL OR d.starts_at  <= now())
                    AND (d.expires_at IS NULL OR d.expires_at >  now())
               )
         );
$$;


-- ═══════════════════════════════════════════════════════════════
-- (b2) Rewrite get_my_permissions(): same signature
-- (p_madrasa_id UUID DEFAULT NULL) → TABLE(code TEXT). The tenant
-- filter is now HONORED (NULL = all tenants, as today). Sources:
-- role grants + explicit grant overrides + active delegations,
-- minus explicit denies. The DEPRECATED profiles.role branch is
-- kept byte-for-byte (still read by legacy clients).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_my_permissions(p_madrasa_id UUID DEFAULT NULL)
RETURNS TABLE(code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Role grants through the tenant's editable role catalog
  SELECT DISTINCT p.code
    FROM public.tenant_memberships tm
    JOIN public.tenant_roles tr
      ON tr.tenant_id = tm.tenant_id
     AND tr.key       = tm.role
     AND tr.is_active
    JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = tr.id
    JOIN public.permissions p               ON p.id = trp.permission_id
   WHERE tm.user_id = auth.uid()
     AND tm.is_active
     AND (p_madrasa_id IS NULL OR tm.tenant_id = p_madrasa_id)
     AND NOT public.user_code_denied(tm.tenant_id, auth.uid(), p.code)

  UNION

  -- Explicit per-user grant overrides
  SELECT DISTINCT p.code
    FROM public.user_permissions up
    JOIN public.permissions p ON p.id = up.permission_id
   WHERE up.user_id = auth.uid()
     AND up.effect   = 'grant'
     AND (p_madrasa_id IS NULL OR up.tenant_id = p_madrasa_id)

  UNION

  -- Active delegation grants (expiry honored)
  SELECT DISTINCT p.code
    FROM public.permission_delegations d
    JOIN public.permissions p ON p.id = d.permission_id
   WHERE d.delegatee_id = auth.uid()
     AND (d.starts_at  IS NULL OR d.starts_at  <= now())
     AND (d.expires_at IS NULL OR d.expires_at >  now())
     AND (p_madrasa_id IS NULL OR d.tenant_id = p_madrasa_id)
     AND NOT public.user_code_denied(d.tenant_id, auth.uid(), p.code)

  UNION

  -- DEPRECATED: legacy profiles.role branch (kept for backward
  -- compatibility; 004/005/013 documented the same contract).
  SELECT DISTINCT p.code
    FROM public.profiles pr
    JOIN public.roles r              ON r.name = pr.role
    JOIN public.role_permissions rp  ON rp.role_id = r.id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE pr.id = auth.uid()
$$;

-- public.has_permission(p_code, p_madrasa_id) (06_rbac.sql) keeps
-- working unchanged on top of the replaced function.


-- ═══════════════════════════════════════════════════════════════
-- (b3) get_my_permissions_detailed(): per-tenant grant provenance
-- for the new client. source ∈ {role, override, delegation}.
-- Denied codes are excluded entirely (deny > grant > delegation).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_my_permissions_detailed(p_tenant_id UUID DEFAULT NULL)
RETURNS TABLE(code TEXT, tenant_id UUID, source TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.code, tm.tenant_id, 'role'::TEXT
    FROM public.tenant_memberships tm
    JOIN public.tenant_roles tr
      ON tr.tenant_id = tm.tenant_id
     AND tr.key       = tm.role
     AND tr.is_active
    JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = tr.id
    JOIN public.permissions p               ON p.id = trp.permission_id
   WHERE tm.user_id = auth.uid()
     AND tm.is_active
     AND (p_tenant_id IS NULL OR tm.tenant_id = p_tenant_id)
     AND NOT public.user_code_denied(tm.tenant_id, auth.uid(), p.code)

  UNION

  SELECT p.code, up.tenant_id, 'override'::TEXT
    FROM public.user_permissions up
    JOIN public.permissions p ON p.id = up.permission_id
   WHERE up.user_id = auth.uid()
     AND up.effect   = 'grant'
     AND (p_tenant_id IS NULL OR up.tenant_id = p_tenant_id)

  UNION

  SELECT p.code, d.tenant_id, 'delegation'::TEXT
    FROM public.permission_delegations d
    JOIN public.permissions p ON p.id = d.permission_id
   WHERE d.delegatee_id = auth.uid()
     AND (d.starts_at  IS NULL OR d.starts_at  <= now())
     AND (d.expires_at IS NULL OR d.expires_at >  now())
     AND (p_tenant_id IS NULL OR d.tenant_id = p_tenant_id)
     AND NOT public.user_code_denied(d.tenant_id, auth.uid(), p.code)
$$;


-- ═══════════════════════════════════════════════════════════════
-- (c) scope_allows(): data-scope enforcement helper.
-- TRUE when no scope row exists (default per-role behavior) or the
-- scope is 'all'. Narrower scopes are fail-closed: with a 'classes'
-- or 'students' row but no verifiable class target → FALSE.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.scope_allows(
  p_tenant_id UUID,
  p_user_id   UUID,
  p_code      TEXT,
  p_class_id  UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope TEXT;
  v_ref   JSONB;
  v_rows  BIGINT;
BEGIN
  SELECT ps.scope_type, ps.scope_ref
    INTO v_scope, v_ref
    FROM public.permission_scopes ps
    JOIN public.permissions p ON p.id = ps.permission_id
   WHERE ps.tenant_id = p_tenant_id
     AND ps.user_id   = p_user_id
     AND p.code       = p_code
   LIMIT 1;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN TRUE;   -- no scope row: default per-role behavior
  END IF;
  IF v_scope = 'all' THEN
    RETURN TRUE;
  END IF;
  IF p_class_id IS NULL THEN
    RETURN FALSE;  -- narrower scope, unverifiable target: fail closed
  END IF;

  IF v_scope = 'classes' THEN
    -- class_ids stored as JSONB text array; compare as text to avoid
    -- uuid-cast failures on malformed entries
    RETURN p_class_id::TEXT = ANY (
             ARRAY(SELECT jsonb_array_elements_text(v_ref -> 'class_ids'))
           );
  ELSIF v_scope = 'students' THEN
    -- allow when at least one of the scoped students is enrolled in
    -- the target class
    RETURN EXISTS (
      SELECT 1
        FROM public.students s
       WHERE s.tenant_id = p_tenant_id
         AND s.class_id  = p_class_id
         AND s.id::TEXT = ANY (
               ARRAY(SELECT jsonb_array_elements_text(v_ref -> 'student_ids'))
             )
    );
  ELSIF v_scope = 'department' THEN
    -- The data model has no department dimension on classes/darjas/
    -- students (department exists only on staff), so a department
    -- scope cannot be evaluated against a class target: fail closed.
    RETURN FALSE;
  ELSE
    RETURN FALSE;  -- unknown scope_type: fail closed
  END IF;
END;
$$;

-- Resolve a result row's class: the exam's class first (the exam
-- defines the class), falling back to the student's enrolled class.
-- (results itself carries no class_id; both source columns are
-- nullable — verified against 01_schema.sql.)
CREATE OR REPLACE FUNCTION public.result_class_id(p_exam_id UUID, p_student_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT e.class_id FROM public.exams    e WHERE e.id = p_exam_id),
    (SELECT s.class_id FROM public.students s WHERE s.id = p_student_id)
  );
$$;


-- ═══════════════════════════════════════════════════════════════
-- (a) RLS on the five 019 tables.
-- SELECT: platform admins + tenant members. Writes: tenant owner/
-- admin or a holder of roles.assign in that tenant (the DB never
-- trusts client-sent roles).
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.tenant_roles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_permissions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_scopes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_delegations  ENABLE ROW LEVEL SECURITY;

-- ── tenant_roles ──
DROP POLICY IF EXISTS "tenant members read tenant roles" ON public.tenant_roles;
CREATE POLICY "tenant members read tenant roles"
  ON public.tenant_roles FOR SELECT
  USING (public.is_platform_admin() OR public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "role managers write tenant roles" ON public.tenant_roles;
CREATE POLICY "role managers write tenant roles"
  ON public.tenant_roles FOR ALL
  USING  (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'))
  WITH CHECK (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'));

-- ── tenant_role_permissions (tenant via the parent tenant_roles row) ──
DROP POLICY IF EXISTS "tenant members read tenant role permissions" ON public.tenant_role_permissions;
CREATE POLICY "tenant members read tenant role permissions"
  ON public.tenant_role_permissions FOR SELECT
  USING (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.tenant_roles tr
       WHERE tr.id = tenant_role_permissions.tenant_role_id
         AND public.is_tenant_member(tr.tenant_id)
    )
  );

DROP POLICY IF EXISTS "role managers write tenant role permissions" ON public.tenant_role_permissions;
CREATE POLICY "role managers write tenant role permissions"
  ON public.tenant_role_permissions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.tenant_roles tr
       WHERE tr.id = tenant_role_permissions.tenant_role_id
         AND (public.is_tenant_admin(tr.tenant_id)
              OR public.tenant_has_permission(tr.tenant_id, 'roles.assign'))
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tenant_roles tr
       WHERE tr.id = tenant_role_permissions.tenant_role_id
         AND (public.is_tenant_admin(tr.tenant_id)
              OR public.tenant_has_permission(tr.tenant_id, 'roles.assign'))
    )
  );

-- ── user_permissions ──
DROP POLICY IF EXISTS "tenant members read user permissions" ON public.user_permissions;
CREATE POLICY "tenant members read user permissions"
  ON public.user_permissions FOR SELECT
  USING (public.is_platform_admin() OR public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "role managers write user permissions" ON public.user_permissions;
CREATE POLICY "role managers write user permissions"
  ON public.user_permissions FOR ALL
  USING  (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'))
  WITH CHECK (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'));

-- ── permission_scopes ──
DROP POLICY IF EXISTS "tenant members read permission scopes" ON public.permission_scopes;
CREATE POLICY "tenant members read permission scopes"
  ON public.permission_scopes FOR SELECT
  USING (public.is_platform_admin() OR public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "role managers write permission scopes" ON public.permission_scopes;
CREATE POLICY "role managers write permission scopes"
  ON public.permission_scopes FOR ALL
  USING  (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'))
  WITH CHECK (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'));

-- ── permission_delegations ──
DROP POLICY IF EXISTS "tenant members read permission delegations" ON public.permission_delegations;
CREATE POLICY "tenant members read permission delegations"
  ON public.permission_delegations FOR SELECT
  USING (public.is_platform_admin() OR public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "role managers write permission delegations" ON public.permission_delegations;
CREATE POLICY "role managers write permission delegations"
  ON public.permission_delegations FOR ALL
  USING  (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'))
  WITH CHECK (public.is_tenant_admin(tenant_id)
          OR public.tenant_has_permission(tenant_id, 'roles.assign'));


-- ═══════════════════════════════════════════════════════════════
-- (d) Tighten the attendance + results WRITE policies (007 names
-- kept) with scope_allows(), so a class-scoped teacher cannot
-- mark/enter outside their classes even via raw API. SELECT
-- policies are unchanged.
-- ═══════════════════════════════════════════════════════════════

-- ── attendance writes ──
DROP POLICY IF EXISTS "attendance_insert_tenant" ON public.attendance;
CREATE POLICY "attendance_insert_tenant" ON public.attendance FOR INSERT WITH CHECK (
  public.is_platform_admin()
  OR (public.is_tenant_member(attendance.tenant_id)
      AND public.tenant_has_permission(attendance.tenant_id, 'attendance.mark')
      AND public.scope_allows(attendance.tenant_id, auth.uid(), 'attendance.mark', attendance.class_id))
);

DROP POLICY IF EXISTS "attendance_update_tenant" ON public.attendance;
CREATE POLICY "attendance_update_tenant" ON public.attendance FOR UPDATE USING (
  public.is_platform_admin()
  OR (public.is_tenant_member(attendance.tenant_id)
      AND public.tenant_has_permission(attendance.tenant_id, 'attendance.edit')
      AND public.scope_allows(attendance.tenant_id, auth.uid(), 'attendance.edit', attendance.class_id))
) WITH CHECK (
  public.is_platform_admin()
  OR (public.is_tenant_member(attendance.tenant_id)
      AND public.tenant_has_permission(attendance.tenant_id, 'attendance.edit')
      AND public.scope_allows(attendance.tenant_id, auth.uid(), 'attendance.edit', attendance.class_id))
);

DROP POLICY IF EXISTS "attendance_delete_tenant" ON public.attendance;
CREATE POLICY "attendance_delete_tenant" ON public.attendance FOR DELETE USING (
  public.is_platform_admin()
  OR (public.is_tenant_member(attendance.tenant_id)
      AND public.tenant_has_permission(attendance.tenant_id, 'attendance.delete')
      AND public.scope_allows(attendance.tenant_id, auth.uid(), 'attendance.delete', attendance.class_id))
);

-- ── results writes ──
DROP POLICY IF EXISTS "results_insert_tenant" ON public.results;
CREATE POLICY "results_insert_tenant" ON public.results FOR INSERT WITH CHECK (
  public.is_platform_admin()
  OR (public.is_tenant_member(results.tenant_id)
      AND public.tenant_has_permission(results.tenant_id, 'results.enter')
      AND public.scope_allows(results.tenant_id, auth.uid(), 'results.enter',
            public.result_class_id(results.exam_id, results.student_id)))
);

DROP POLICY IF EXISTS "results_update_tenant" ON public.results;
CREATE POLICY "results_update_tenant" ON public.results FOR UPDATE USING (
  public.is_platform_admin()
  OR (public.is_tenant_member(results.tenant_id)
      AND public.tenant_has_permission(results.tenant_id, 'results.edit')
      AND public.scope_allows(results.tenant_id, auth.uid(), 'results.edit',
            public.result_class_id(results.exam_id, results.student_id)))
) WITH CHECK (
  public.is_platform_admin()
  OR (public.is_tenant_member(results.tenant_id)
      AND public.tenant_has_permission(results.tenant_id, 'results.edit')
      AND public.scope_allows(results.tenant_id, auth.uid(), 'results.edit',
            public.result_class_id(results.exam_id, results.student_id)))
);

DROP POLICY IF EXISTS "results_delete_tenant" ON public.results;
CREATE POLICY "results_delete_tenant" ON public.results FOR DELETE USING (
  public.is_platform_admin()
  OR (public.is_tenant_member(results.tenant_id)
      AND public.tenant_has_permission(results.tenant_id, 'results.edit')
      AND public.scope_allows(results.tenant_id, auth.uid(), 'results.edit',
            public.result_class_id(results.exam_id, results.student_id)))
);


-- ═══════════════════════════════════════════════════════════════
-- (e) Management RPCs. All SECURITY DEFINER, SET search_path=public.
-- The CALLER's rights (auth.uid()) are checked inside — arguments
-- are never trusted. Audit rows are written by the 019 triggers,
-- which fire under the definer.
-- ═══════════════════════════════════════════════════════════════

-- assign_tenant_role: requires roles.assign (or owner/admin).
CREATE OR REPLACE FUNCTION public.assign_tenant_role(
  p_tenant_id UUID,
  p_user_id   UUID,
  p_role_key  TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT (public.is_tenant_admin(p_tenant_id)
          OR public.tenant_has_permission(p_tenant_id, 'roles.assign')) THEN
    RAISE EXCEPTION 'assign_tenant_role: requires roles.assign in tenant %', p_tenant_id;
  END IF;

  -- The role key itself is validated by the 019
  -- tenant_memberships_validate_role trigger; the last-owner
  -- backstop (protect_last_owner) also fires on re-role.
  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
  VALUES (p_tenant_id, p_user_id, p_role_key, TRUE)
  ON CONFLICT (user_id, tenant_id)
  DO UPDATE SET role = EXCLUDED.role, is_active = TRUE, updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- set_role_permissions: requires roles.assign (or owner/admin).
-- Refuses to strip the LAST roles.assign grant in the tenant.
-- p_codes = NULL/empty clears the role's permissions.
CREATE OR REPLACE FUNCTION public.set_role_permissions(
  p_tenant_role_id UUID,
  p_codes          TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant    UUID;
  v_bad       TEXT;
  v_remaining INT;
BEGIN
  SELECT tr.tenant_id INTO v_tenant
    FROM public.tenant_roles tr
   WHERE tr.id = p_tenant_role_id;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'set_role_permissions: unknown tenant role %', p_tenant_role_id;
  END IF;
  IF NOT (public.is_tenant_admin(v_tenant)
          OR public.tenant_has_permission(v_tenant, 'roles.assign')) THEN
    RAISE EXCEPTION 'set_role_permissions: requires roles.assign in tenant %', v_tenant;
  END IF;

  SELECT c INTO v_bad
    FROM unnest(COALESCE(p_codes, '{}')) AS c
   WHERE NOT EXISTS (SELECT 1 FROM public.permissions p WHERE p.code = c)
   LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'set_role_permissions: unknown permission code "%"', v_bad;
  END IF;

  DELETE FROM public.tenant_role_permissions trp
   WHERE trp.tenant_role_id = p_tenant_role_id
     AND trp.permission_id NOT IN (
           SELECT p.id FROM public.permissions p WHERE p.code = ANY(COALESCE(p_codes, '{}'))
         );

  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
  SELECT p_tenant_role_id, p.id
    FROM public.permissions p
   WHERE p.code = ANY(COALESCE(p_codes, '{}'))
  ON CONFLICT (tenant_role_id, permission_id) DO NOTHING;

  -- Safety backstop: at least one ACTIVE tenant role must retain
  -- roles.assign, or nobody could ever manage roles again.
  SELECT COUNT(*) INTO v_remaining
    FROM public.tenant_roles tr
    JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = tr.id
    JOIN public.permissions p               ON p.id = trp.permission_id
   WHERE tr.tenant_id = v_tenant
     AND tr.is_active
     AND p.code = 'roles.assign';
  IF v_remaining = 0 THEN
    RAISE EXCEPTION 'set_role_permissions: refusing to remove the last roles.assign grant in tenant %',
      v_tenant;
  END IF;
END;
$$;

-- set_user_permission: requires roles.assign (or owner/admin).
-- p_effect 'grant'/'deny' upserts the override; NULL deletes it.
CREATE OR REPLACE FUNCTION public.set_user_permission(
  p_tenant_id UUID,
  p_user_id   UUID,
  p_code      TEXT,
  p_effect    TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_perm_id UUID;
BEGIN
  IF NOT (public.is_tenant_admin(p_tenant_id)
          OR public.tenant_has_permission(p_tenant_id, 'roles.assign')) THEN
    RAISE EXCEPTION 'set_user_permission: requires roles.assign in tenant %', p_tenant_id;
  END IF;
  IF p_effect IS NOT NULL AND p_effect NOT IN ('grant', 'deny') THEN
    RAISE EXCEPTION 'set_user_permission: p_effect must be ''grant'', ''deny'', or NULL (got "%")', p_effect;
  END IF;

  SELECT p.id INTO v_perm_id
    FROM public.permissions p
   WHERE p.code = p_code;
  IF v_perm_id IS NULL THEN
    RAISE EXCEPTION 'set_user_permission: unknown permission code "%"', p_code;
  END IF;

  IF p_effect IS NULL THEN
    DELETE FROM public.user_permissions up
     WHERE up.tenant_id = p_tenant_id
       AND up.user_id   = p_user_id
       AND up.permission_id = v_perm_id;
  ELSE
    INSERT INTO public.user_permissions
      (tenant_id, user_id, permission_id, effect, created_by)
    VALUES
      (p_tenant_id, p_user_id, v_perm_id, p_effect, auth.uid())
    ON CONFLICT (tenant_id, user_id, permission_id)
    DO UPDATE SET effect = EXCLUDED.effect, created_by = EXCLUDED.created_by;
  END IF;
END;
$$;

-- create_tenant_role: requires roles.assign (or owner/admin).
-- Clones a template's permission set when p_template_key is given.
CREATE OR REPLACE FUNCTION public.create_tenant_role(
  p_tenant_id    UUID,
  p_key          TEXT,
  p_urdu         TEXT,
  p_template_key TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id           UUID;
  v_display_name TEXT;
  v_template_id  UUID;
BEGIN
  IF NOT (public.is_tenant_admin(p_tenant_id)
          OR public.tenant_has_permission(p_tenant_id, 'roles.assign')) THEN
    RAISE EXCEPTION 'create_tenant_role: requires roles.assign in tenant %', p_tenant_id;
  END IF;
  IF p_key IS NULL OR p_key !~ '^[a-z0-9_]+$' THEN
    RAISE EXCEPTION 'create_tenant_role: p_key must be lowercase alphanumeric/underscore (got "%")', p_key;
  END IF;
  IF p_urdu IS NULL OR btrim(p_urdu) = '' THEN
    RAISE EXCEPTION 'create_tenant_role: p_urdu (Urdu display name) is required';
  END IF;

  IF p_template_key IS NOT NULL THEN
    SELECT r.id, r.display_name INTO v_template_id, v_display_name
      FROM public.roles r
     WHERE r.name = p_template_key;
    IF v_template_id IS NULL THEN
      RAISE EXCEPTION 'create_tenant_role: unknown template key "%"', p_template_key;
    END IF;
  ELSE
    v_display_name := p_key;
  END IF;

  INSERT INTO public.tenant_roles
    (tenant_id, key, display_name, display_urdu, template_key, created_by)
  VALUES
    (p_tenant_id, p_key, v_display_name, p_urdu, p_template_key, auth.uid())
  ON CONFLICT (tenant_id, key) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'create_tenant_role: role key "%" already exists in tenant %', p_key, p_tenant_id;
  END IF;

  IF v_template_id IS NOT NULL THEN
    INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
    SELECT v_id, rp.permission_id
      FROM public.role_permissions rp
     WHERE rp.role_id = v_template_id
    ON CONFLICT (tenant_role_id, permission_id) DO NOTHING;
  END IF;

  RETURN v_id;
END;
$$;

-- delegate_permission: the CALLER (auth.uid()) is the delegator —
-- never trusted from arguments. Requires roles.assign (or
-- owner/admin) AND that the caller effectively holds p_code
-- themselves (delegations do not chain). The 019 ceiling trigger
-- re-enforces all of this on the row.
CREATE OR REPLACE FUNCTION public.delegate_permission(
  p_tenant_id   UUID,
  p_delegatee   UUID,
  p_code        TEXT,
  p_scope_type  TEXT DEFAULT 'all',
  p_scope_ref   JSONB DEFAULT '{}',
  p_expires_at  TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id      UUID;
  v_perm_id UUID;
  v_caller  UUID := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'delegate_permission: requires an authenticated caller';
  END IF;
  IF NOT (public.is_tenant_admin(p_tenant_id)
          OR public.tenant_has_permission(p_tenant_id, 'roles.assign')) THEN
    RAISE EXCEPTION 'delegate_permission: requires roles.assign in tenant %', p_tenant_id;
  END IF;
  IF p_delegatee = v_caller THEN
    RAISE EXCEPTION 'delegate_permission: cannot delegate to yourself';
  END IF;
  IF p_expires_at IS NOT NULL AND p_expires_at <= now() THEN
    RAISE EXCEPTION 'delegate_permission: p_expires_at must be in the future';
  END IF;

  SELECT p.id INTO v_perm_id
    FROM public.permissions p
   WHERE p.code = p_code;
  IF v_perm_id IS NULL THEN
    RAISE EXCEPTION 'delegate_permission: unknown permission code "%"', p_code;
  END IF;

  -- The caller's own grant (delegations never chain).
  IF NOT public.user_effective_permission(p_tenant_id, v_caller, p_code) THEN
    RAISE EXCEPTION 'delegate_permission: you do not effectively hold permission "%" in tenant %',
      p_code, p_tenant_id;
  END IF;

  INSERT INTO public.permission_delegations
    (tenant_id, delegator_id, delegatee_id, permission_id,
     scope_type, scope_ref, starts_at, expires_at, created_by)
  VALUES
    (p_tenant_id, v_caller, p_delegatee, v_perm_id,
     COALESCE(p_scope_type, 'all'), COALESCE(p_scope_ref, '{}'),
     now(), p_expires_at, v_caller)
  ON CONFLICT (tenant_id, delegatee_id, permission_id)
  DO UPDATE SET scope_type  = EXCLUDED.scope_type,
                scope_ref   = EXCLUDED.scope_ref,
                starts_at   = EXCLUDED.starts_at,
                expires_at  = EXCLUDED.expires_at,
                delegator_id = EXCLUDED.delegator_id
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;


-- ═══════════════════════════════════════════════════════════════
-- Grants: helpers + RPCs are callable by authenticated users
-- (policies and triggers run them as SECURITY DEFINER regardless).
-- ═══════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.user_is_tenant_admin(UUID, UUID)                    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.user_code_denied(UUID, UUID, TEXT)                  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.user_effective_permission(UUID, UUID, TEXT)        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tenant_has_permission(UUID, TEXT)                  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_permissions(UUID)                           FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_permissions_detailed(UUID)                  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scope_allows(UUID, UUID, TEXT, UUID)               FROM PUBLIC;
REVOKE ALL ON FUNCTION public.result_class_id(UUID, UUID)                        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assign_tenant_role(UUID, UUID, TEXT)                FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_role_permissions(UUID, TEXT[])                 FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_user_permission(UUID, UUID, TEXT, TEXT)        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_tenant_role(UUID, TEXT, TEXT, TEXT)          FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delegate_permission(UUID, UUID, TEXT, TEXT, JSONB, TIMESTAMPTZ) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.user_is_tenant_admin(UUID, UUID)                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_code_denied(UUID, UUID, TEXT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_effective_permission(UUID, UUID, TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.tenant_has_permission(UUID, TEXT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_permissions(UUID)                           TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_permissions_detailed(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.scope_allows(UUID, UUID, TEXT, UUID)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.result_class_id(UUID, UUID)                        TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_tenant_role(UUID, UUID, TEXT)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_role_permissions(UUID, TEXT[])                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_user_permission(UUID, UUID, TEXT, TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_tenant_role(UUID, TEXT, TEXT, TEXT)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.delegate_permission(UUID, UUID, TEXT, TEXT, JSONB, TIMESTAMPTZ) TO authenticated;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('020_role_ux_rls')
ON CONFLICT DO NOTHING;
