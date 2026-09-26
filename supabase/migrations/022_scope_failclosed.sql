-- ═══════════════════════════════════════════════════════════════
-- Migration 022 — permission_scopes: fail-closed hardening
--
-- Closes the known fail-open gap: scope_allows() used to return TRUE
-- when NO permission_scopes row existed for (tenant, user, permission),
-- so "no row" silently meant "whole madrasa". From here on, every
-- effective grant is expected to have an explicit scope row, and a
-- missing row DENIES (fail-closed).
--
--   (a) New columns on permission_scopes: starts_at / expires_at /
--       name_ur / name_en (all nullable; no backfill needed — pre-022
--       rows simply carry NULLs, which mean "always active" / "no
--       label").
--   (b) Backfill FIRST: one 'all' row for every effective grant that
--       lacks a scope row —
--         · role grants + explicit user grants (minus denies), for
--           every ACTIVE tenant member, via the canonical
--           user_effective_permission();
--         · every ACTIVE (unexpired, started) delegation, for the
--           delegatee — unless the delegatee is explicitly denied the
--           code.
--       Pre-022, "no row" behaved exactly as 'all', so this backfill
--       narrows NOTHING for existing users: it only makes the previous
--       implicit default explicit.
--   (c) THEN flip scope_allows(): no row → FALSE (fail-closed). The new
--       starts_at/expires_at columns are honored too: a not-yet-started
--       or expired row denies, mirroring the delegation expiry
--       convention in 020.
--   (d) Provisioning triggers keep the "every effective grant has a
--       scope row" invariant for FUTURE grants, so fail-closed can
--       never lock out a legitimately-granted user going forward:
--         · new/reactivated/re-roled membership → rows for all
--           effective codes;
--         · role gains a permission → rows for active members holding
--           that role key;
--         · explicit user grant → rows for the user;
--         · new delegation → an 'all' row for the delegatee (unless
--           denied).
--       All provisioning is insert-only with ON CONFLICT DO NOTHING —
--       it never narrows or deletes an admin's narrowed scope.
--
-- DOCUMENTED CHOICE: delegation rows are backfilled/provisioned as
-- 'all', NOT as a mirror of the delegation's own scope_type/scope_ref.
-- Pre-022, scope_allows() never consulted the delegation's scope (the
-- no-row fail-open made it 'all' in effect), so mirroring would NARROW
-- existing behavior. The delegation scope columns remain advisory until
-- a follow-up wires them into scope_allows().
--
-- Idempotent: safe to re-run (IF NOT EXISTS / NOT EXISTS guards /
-- ON CONFLICT DO NOTHING / OR REPLACE / DROP IF EXISTS).
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) New columns
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.permission_scopes ADD COLUMN IF NOT EXISTS starts_at  TIMESTAMPTZ;
ALTER TABLE public.permission_scopes ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public.permission_scopes ADD COLUMN IF NOT EXISTS name_ur    TEXT;
ALTER TABLE public.permission_scopes ADD COLUMN IF NOT EXISTS name_en    TEXT;


-- ═══════════════════════════════════════════════════════════════
-- (b) Backfill 'all' rows for every effective grant lacking one.
-- Runs BEFORE the flip in (c), so nothing narrows for existing users.
-- ═══════════════════════════════════════════════════════════════

-- (b1) Role grants + explicit user grants (minus denies), active members.
INSERT INTO public.permission_scopes
  (tenant_id, user_id, permission_id, scope_type, scope_ref)
SELECT tm.tenant_id, tm.user_id, p.id, 'all', '{}'::jsonb
  FROM public.tenant_memberships tm
 CROSS JOIN public.permissions p
 WHERE tm.is_active
   AND public.user_effective_permission(tm.tenant_id, tm.user_id, p.code)
   AND NOT EXISTS (
         SELECT 1
           FROM public.permission_scopes ps
          WHERE ps.tenant_id     = tm.tenant_id
            AND ps.user_id       = tm.user_id
            AND ps.permission_id = p.id
       )
ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;

-- (b2) Active delegations: the delegatee needs a row for the delegated
-- code, or the fail-closed flip would break delegated writes that
-- succeed today.
INSERT INTO public.permission_scopes
  (tenant_id, user_id, permission_id, scope_type, scope_ref)
SELECT d.tenant_id, d.delegatee_id, d.permission_id, 'all', '{}'::jsonb
  FROM public.permission_delegations d
  JOIN public.permissions p ON p.id = d.permission_id
 WHERE (d.starts_at  IS NULL OR d.starts_at  <= now())
   AND (d.expires_at IS NULL OR d.expires_at >  now())
   AND NOT public.user_code_denied(d.tenant_id, d.delegatee_id, p.code)
   AND NOT EXISTS (
         SELECT 1
           FROM public.permission_scopes ps
          WHERE ps.tenant_id     = d.tenant_id
            AND ps.user_id       = d.delegatee_id
            AND ps.permission_id = d.permission_id
       )
ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (c) scope_allows(): fail CLOSED when no row exists; honor the new
-- starts_at/expires_at window. Narrower-scope evaluation below is
-- unchanged from 020.
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
  v_scope   TEXT;
  v_ref     JSONB;
  v_starts  TIMESTAMPTZ;
  v_expires TIMESTAMPTZ;
  v_rows    BIGINT;
BEGIN
  SELECT ps.scope_type, ps.scope_ref, ps.starts_at, ps.expires_at
    INTO v_scope, v_ref, v_starts, v_expires
    FROM public.permission_scopes ps
    JOIN public.permissions p ON p.id = ps.permission_id
   WHERE ps.tenant_id = p_tenant_id
     AND ps.user_id   = p_user_id
     AND p.code       = p_code
   LIMIT 1;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RETURN FALSE;  -- 022: no scope row → fail closed (was: fail open)
  END IF;
  IF v_starts IS NOT NULL AND v_starts > now() THEN
    RETURN FALSE;  -- scope window has not started yet
  END IF;
  IF v_expires IS NOT NULL AND v_expires <= now() THEN
    RETURN FALSE;  -- scope window has expired
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


-- ═══════════════════════════════════════════════════════════════
-- (d) Provisioning: keep "every effective grant has a scope row" true
-- for future grants. Insert-only; never narrows, never deletes.
-- ═══════════════════════════════════════════════════════════════

-- Per-user provisioner used by the membership / user-grant triggers.
-- Deliberately NOT granted to authenticated (least privilege): only
-- triggers and migrations call it. Inserting 'all' rows cannot
-- escalate — rows are only created for codes
-- user_effective_permission() already grants.
CREATE OR REPLACE FUNCTION public.ensure_member_scope_rows(
  p_tenant_id UUID,
  p_user_id   UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.permission_scopes
    (tenant_id, user_id, permission_id, scope_type, scope_ref)
  SELECT p_tenant_id, p_user_id, p.id, 'all', '{}'::jsonb
    FROM public.permissions p
   WHERE public.user_effective_permission(p_tenant_id, p_user_id, p.code)
     AND NOT EXISTS (
           SELECT 1
             FROM public.permission_scopes ps
            WHERE ps.tenant_id     = p_tenant_id
              AND ps.user_id       = p_user_id
              AND ps.permission_id = p.id
         )
  ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;
END;
$$;

-- New / reactivated / re-roled active membership → provision rows.
CREATE OR REPLACE FUNCTION public.trg_provision_scope_rows_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_active THEN
    PERFORM public.ensure_member_scope_rows(NEW.tenant_id, NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS provision_scope_rows_membership ON public.tenant_memberships;
CREATE TRIGGER provision_scope_rows_membership
  AFTER INSERT OR UPDATE OF role, is_active ON public.tenant_memberships
  FOR EACH ROW
  WHEN (NEW.is_active)
  EXECUTE FUNCTION public.trg_provision_scope_rows_membership();

-- A role gains a permission → provision rows for active members
-- holding that role key (skipping explicitly-denied users).
CREATE OR REPLACE FUNCTION public.trg_provision_scope_rows_role_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_key    TEXT;
  v_code   TEXT;
BEGIN
  SELECT tr.tenant_id, tr.key INTO v_tenant, v_key
    FROM public.tenant_roles tr
   WHERE tr.id = NEW.tenant_role_id;
  IF v_tenant IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT p.code INTO v_code
    FROM public.permissions p
   WHERE p.id = NEW.permission_id;

  INSERT INTO public.permission_scopes
    (tenant_id, user_id, permission_id, scope_type, scope_ref)
  SELECT v_tenant, tm.user_id, NEW.permission_id, 'all', '{}'::jsonb
    FROM public.tenant_memberships tm
   WHERE tm.tenant_id = v_tenant
     AND tm.is_active
     AND tm.role = v_key
     AND (v_code IS NULL
          OR NOT public.user_code_denied(v_tenant, tm.user_id, v_code))
     AND NOT EXISTS (
           SELECT 1
             FROM public.permission_scopes ps
            WHERE ps.tenant_id     = v_tenant
              AND ps.user_id       = tm.user_id
              AND ps.permission_id = NEW.permission_id
         )
  ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS provision_scope_rows_role_grant ON public.tenant_role_permissions;
CREATE TRIGGER provision_scope_rows_role_grant
  AFTER INSERT ON public.tenant_role_permissions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_provision_scope_rows_role_grant();

-- Explicit per-user grant → provision rows for the user.
CREATE OR REPLACE FUNCTION public.trg_provision_scope_rows_user_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.ensure_member_scope_rows(NEW.tenant_id, NEW.user_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS provision_scope_rows_user_grant ON public.user_permissions;
CREATE TRIGGER provision_scope_rows_user_grant
  AFTER INSERT OR UPDATE OF effect ON public.user_permissions
  FOR EACH ROW
  WHEN (NEW.effect = 'grant')
  EXECUTE FUNCTION public.trg_provision_scope_rows_user_grant();

-- New delegation → an 'all' row for the delegatee (unless denied),
-- so the fail-closed flip cannot break delegated writes.
CREATE OR REPLACE FUNCTION public.trg_provision_scope_rows_delegation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
BEGIN
  SELECT p.code INTO v_code
    FROM public.permissions p
   WHERE p.id = NEW.permission_id;
  IF v_code IS NOT NULL
     AND public.user_code_denied(NEW.tenant_id, NEW.delegatee_id, v_code) THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.permission_scopes
    (tenant_id, user_id, permission_id, scope_type, scope_ref)
  VALUES (NEW.tenant_id, NEW.delegatee_id, NEW.permission_id, 'all', '{}'::jsonb)
  ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS provision_scope_rows_delegation ON public.permission_delegations;
CREATE TRIGGER provision_scope_rows_delegation
  AFTER INSERT ON public.permission_delegations
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_provision_scope_rows_delegation();


-- ═══════════════════════════════════════════════════════════════
-- Grants: helpers + triggers run as owner; nothing here is granted
-- to authenticated (the provisioning functions must not be directly
-- callable — they only ever ADD 'all' rows for already-held codes).
-- scope_allows() keeps its 020 grant (authenticated may execute).
-- ═══════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.ensure_member_scope_rows(UUID, UUID)          FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_provision_scope_rows_membership()         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_provision_scope_rows_role_grant()        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_provision_scope_rows_user_grant()        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_provision_scope_rows_delegation()         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.scope_allows(UUID, UUID, TEXT, UUID)         FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scope_allows(UUID, UUID, TEXT, UUID)       TO authenticated;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('022_scope_failclosed')
ON CONFLICT DO NOTHING;
