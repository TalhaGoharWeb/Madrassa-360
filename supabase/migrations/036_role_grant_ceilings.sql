-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 036: role-RPC grant ceilings
--
-- SEC-H1: assign_tenant_role / set_role_permissions / set_user_permission
-- (020) required only roles.assign (or legacy owner/admin) and could
-- then grant ANYTHING — including tenant_owner or permission codes the
-- caller does not hold. A custom role with roles.assign was a
-- de-facto owner-mint.
--
-- Ceilings added (mirroring the 019 delegation ceiling):
--   * public.is_tenant_owner(p_tenant_id) helper (legacy rank root).
--   * public.tenant_role_rank(p_key) — the Edge Function's
--     TENANT_ROLE_RANK table in SQL, so the RPC layer and the Edge
--     Function share one source of truth.
--   * assign_tenant_role: may not assign 'tenant_owner' unless the
--     caller is tenant_owner (or platform admin); may not assign a role
--     whose effective permission set exceeds the caller's (each code the
--     role grants must be effectively held by the caller, unless the
--     caller is platform admin / tenant_owner).
--   * set_role_permissions: may not leave the role granting codes the
--     caller does not effectively hold (same bypass for platform admin
--     / tenant_owner). The existing last-roles.assign backstop is kept.
--   * set_user_permission: a 'grant' effect may not grant a code the
--     caller does not effectively hold (same bypass).
--
-- Idempotent: CREATE OR REPLACE.
-- ═══════════════════════════════════════════════════════════════


-- ── is_tenant_owner helper ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_tenant_owner(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_platform_admin()
      OR EXISTS (
           SELECT 1 FROM public.tenant_memberships tm
           WHERE tm.tenant_id = p_tenant_id
             AND tm.user_id   = auth.uid()
             AND tm.is_active
             AND tm.role = 'tenant_owner'
         );
$$;


-- ── rank table in SQL (mirrors manage-users TENANT_ROLE_RANK) ──
CREATE OR REPLACE FUNCTION public.tenant_role_rank(p_key TEXT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE p_key
    WHEN 'tenant_owner'   THEN 100
    WHEN 'tenant_admin'   THEN 90
    WHEN 'principal'      THEN 80
    WHEN 'accountant'     THEN 70
    WHEN 'teacher'        THEN 50
    WHEN 'librarian'      THEN 50
    WHEN 'hostel_manager' THEN 50
    WHEN 'staff'          THEN 50
    WHEN 'parent'         THEN 10
    WHEN 'student'        THEN 10
    ELSE NULL
  END
$$;

COMMENT ON FUNCTION public.tenant_role_rank(TEXT) IS
  '036: legacy role rank table in SQL — the single source of truth shared '
  'with the manage-users Edge Function TENANT_ROLE_RANK. Custom tenant_roles '
  'keys return NULL (their authority is measured by permission set, not rank).';


-- ── assign_tenant_role with ceilings ──────────────────────────
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
  v_id       UUID;
  v_role_id  UUID;
  v_unheld   TEXT;
BEGIN
  IF NOT (public.is_tenant_admin(p_tenant_id)
          OR public.tenant_has_permission(p_tenant_id, 'roles.assign')) THEN
    RAISE EXCEPTION 'assign_tenant_role: requires roles.assign in tenant %', p_tenant_id;
  END IF;

  -- Ceiling 1: tenant_owner is granted only by a tenant_owner
  -- (platform admins bypass via is_tenant_owner's short-circuit).
  IF p_role_key = 'tenant_owner'
     AND NOT public.is_tenant_owner(p_tenant_id) THEN
    RAISE EXCEPTION 'assign_tenant_role: only a tenant_owner may assign tenant_owner in tenant %',
      p_tenant_id;
  END IF;

  -- Ceiling 2: the role's effective permission set must not exceed the
  -- caller's. Platform admins and tenant_owners bypass (they may
  -- legitimately structure any role).
  IF NOT (public.is_platform_admin()
          OR EXISTS (SELECT 1 FROM public.tenant_memberships tm
                      WHERE tm.tenant_id = p_tenant_id AND tm.user_id = auth.uid()
                        AND tm.is_active AND tm.role = 'tenant_owner')) THEN
    SELECT tr.id INTO v_role_id
      FROM public.tenant_roles tr
     WHERE tr.tenant_id = p_tenant_id
       AND tr.key       = p_role_key
       AND tr.is_active;
    IF v_role_id IS NULL THEN
      RAISE EXCEPTION 'assign_tenant_role: unknown or inactive role key "%" for tenant %',
        p_role_key, p_tenant_id;
    END IF;
    SELECT p.code INTO v_unheld
      FROM public.tenant_role_permissions trp
      JOIN public.permissions p ON p.id = trp.permission_id
     WHERE trp.tenant_role_id = v_role_id
       AND NOT public.tenant_has_permission(p_tenant_id, p.code)
     LIMIT 1;
    IF v_unheld IS NOT NULL THEN
      RAISE EXCEPTION 'assign_tenant_role: role "%" grants "%", which you do not hold in tenant %',
        p_role_key, v_unheld, p_tenant_id;
    END IF;
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


-- ── set_role_permissions with ceilings ───────────────────────
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
  v_unheld    TEXT;
  v_remaining INT;
  v_is_owner  BOOLEAN;
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

  -- Ceiling: the resulting grant set must not exceed the caller's own
  -- effective holdings (platform admins and tenant_owners bypass).
  SELECT EXISTS (
    SELECT 1 FROM public.tenant_memberships tm
     WHERE tm.tenant_id = v_tenant AND tm.user_id = auth.uid()
       AND tm.is_active AND tm.role = 'tenant_owner'
  ) INTO v_is_owner;
  IF NOT (public.is_platform_admin() OR v_is_owner) THEN
    SELECT c INTO v_unheld
      FROM unnest(COALESCE(p_codes, '{}')) AS c
     WHERE NOT public.tenant_has_permission(v_tenant, c)
     LIMIT 1;
    IF v_unheld IS NOT NULL THEN
      RAISE EXCEPTION 'set_role_permissions: you do not hold permission "%" in tenant %',
        v_unheld, v_tenant;
    END IF;
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


-- ── set_user_permission with ceilings ────────────────────────
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

  -- Ceiling: a grant must not exceed the caller's own effective holdings
  -- (platform admins and tenant_owners bypass). Deny/remove always allowed
  -- for authorized callers (shrinking privilege is safe).
  IF p_effect = 'grant'
     AND NOT public.is_platform_admin()
     AND NOT EXISTS (
           SELECT 1 FROM public.tenant_memberships tm
            WHERE tm.tenant_id = p_tenant_id AND tm.user_id = auth.uid()
              AND tm.is_active AND tm.role = 'tenant_owner')
     AND NOT public.tenant_has_permission(p_tenant_id, p_code) THEN
    RAISE EXCEPTION 'set_user_permission: you do not hold permission "%" in tenant %',
      p_code, p_tenant_id;
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


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('036_role_grant_ceilings')
ON CONFLICT DO NOTHING;
