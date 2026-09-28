-- ═══════════════════════════════════════════════════════════════
-- Migration 004 — Memberships, platform admins, tenant helpers
--   (a) Migrate legacy madrasas rows → tenants
--   (b) public.platform_admins (platform roles live here, NOT in
--       tenant_memberships)
--   (c) public.tenant_memberships + backfill from user_roles /
--       madrasas.admin_user_id
--   (d) Helper functions: is_platform_admin(), is_tenant_member(),
--       is_tenant_admin(), tenant_has_permission()
--       — all SECURITY DEFINER, SET search_path = public
--   (e) RLS: platform_admins, tenant_memberships, tenants (member read),
--       tenant_settings + tenant_modules (member read / tenant-admin write)
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) Migrate legacy madrasas → tenants
-- tenant_code is derived deterministically from the madrasa id
-- ('M-' + first 8 hex chars, uppercased) so re-runs and the backfill
-- below can always find the migrated row. The 002/003 AFTER INSERT
-- triggers fire here too, so migrated tenants get default settings
-- and the default module set automatically.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.tenants (
  tenant_code, name, name_urdu, logo_url, address, city,
  phone, email, website, status, created_at, updated_at
)
SELECT
  'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8)),
  coalesce(nullif(m.name_english, ''), m.name_urdu),
  nullif(m.name_urdu, ''),
  m.logo_url,
  m.address,
  coalesce(nullif(m.city_english, ''), nullif(m.city_urdu, '')),
  m.phone,
  m.email,
  m.website,
  CASE
    WHEN NOT m.is_active THEN 'suspended'   -- preserves deactivation state
    WHEN m.subscription_plan IN ('basic', 'standard', 'premium') THEN 'active'
    ELSE 'trial'
  END,
  m.created_at,
  m.updated_at
FROM public.madrasas m
ON CONFLICT (tenant_code) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (b) platform_admins — platform-level roles live ONLY here
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.platform_admins (
  user_id    UUID NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role       TEXT NOT NULL CHECK (role IN ('platform_owner', 'platform_support')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed from the legacy profiles.role column (superAdmin → platform_owner,
-- franchiseManager → platform_support). Runs as the migration owner, which
-- bypasses RLS — this is also the supported way to bootstrap the FIRST
-- platform owner if no legacy superAdmin exists: a superuser/service_role
-- INSERT (RLS is bypassed for table owners and service_role).
INSERT INTO public.platform_admins (user_id, role)
SELECT p.id,
       CASE WHEN p.role = 'superAdmin' THEN 'platform_owner' ELSE 'platform_support' END
FROM public.profiles p
WHERE p.role IN ('superAdmin', 'franchiseManager')
ON CONFLICT (user_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (c) tenant_memberships — the single user↔tenant↔role source of truth
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.tenant_memberships (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       TEXT        NOT NULL CHECK (role IN (
               'tenant_owner','tenant_admin','principal','accountant','teacher',
               'librarian','hostel_manager','parent','student','staff')),
  is_active  BOOLEAN     NOT NULL DEFAULT true,
  joined_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, tenant_id)
);

CREATE INDEX IF NOT EXISTS idx_tm_user   ON public.tenant_memberships (user_id);
CREATE INDEX IF NOT EXISTS idx_tm_tenant ON public.tenant_memberships (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tm_tenant_role ON public.tenant_memberships (tenant_id, role);

DROP TRIGGER IF EXISTS tenant_memberships_set_updated_at ON public.tenant_memberships;
CREATE TRIGGER tenant_memberships_set_updated_at
  BEFORE UPDATE ON public.tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- Backfill 1/2: madrasas.admin_user_id → tenant_owner (inserted FIRST so the
-- owner wins the UNIQUE(user_id, tenant_id) conflict against any legacy
-- user_roles row for the same user).
INSERT INTO public.tenant_memberships (tenant_id, user_id, role)
SELECT t.id, m.admin_user_id, 'tenant_owner'
FROM public.madrasas m
JOIN public.tenants t
  ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
WHERE m.admin_user_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM auth.users au WHERE au.id = m.admin_user_id)
ON CONFLICT (user_id, tenant_id) DO NOTHING;


-- Backfill 2/2: legacy user_roles → tenant_memberships.
--  * Only madrasa-scoped rows (madrasa_id NOT NULL); global legacy roles
--    are platform concerns and are NOT migrated here.
--  * Legacy role name → tenant role via the CASE map below; rows whose
--    role does not resolve (incl. superAdmin/franchiseManager, which live
--    in platform_admins) are skipped.
--  * A user holding several legacy roles in one madrasa keeps only the
--    highest-privilege one (DISTINCT ON … ORDER BY prio).
WITH mapped AS (
  SELECT ur.user_id,
         ur.madrasa_id,
         ur.assigned_at,
         CASE r.name
           WHEN 'madrasaAdmin'       THEN 'tenant_admin'
           WHEN 'admin'              THEN 'tenant_admin'
           WHEN 'itManager'          THEN 'tenant_admin'
           WHEN 'academicManager'    THEN 'principal'
           WHEN 'accountant'         THEN 'accountant'
           WHEN 'financeManager'     THEN 'accountant'
           WHEN 'teacher'            THEN 'teacher'
           WHEN 'libraryManager'     THEN 'librarian'
           WHEN 'hostelManager'      THEN 'hostel_manager'
           WHEN 'attendanceOfficer'  THEN 'staff'
           WHEN 'announcementManager' THEN 'staff'
           WHEN 'admissionOfficer'   THEN 'staff'
           WHEN 'editor'             THEN 'staff'
           WHEN 'parent'             THEN 'parent'
           WHEN 'student'            THEN 'student'
         END AS tenant_role,
         CASE r.name
           WHEN 'madrasaAdmin' THEN 1
           WHEN 'admin'        THEN 1
           WHEN 'itManager'    THEN 1
           WHEN 'academicManager' THEN 2
           WHEN 'accountant'   THEN 3
           WHEN 'financeManager' THEN 3
           WHEN 'teacher'      THEN 4
           WHEN 'libraryManager' THEN 5
           WHEN 'hostelManager'  THEN 6
           WHEN 'attendanceOfficer'   THEN 7
           WHEN 'announcementManager' THEN 7
           WHEN 'admissionOfficer'    THEN 7
           WHEN 'editor'              THEN 7
           WHEN 'parent'  THEN 8
           WHEN 'student' THEN 9
           ELSE 99
         END AS prio
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.madrasa_id IS NOT NULL
)
INSERT INTO public.tenant_memberships (tenant_id, user_id, role, joined_at)
SELECT DISTINCT ON (t.id, m2.user_id)
       t.id,
       m2.user_id,
       m2.tenant_role,
       coalesce(m2.assigned_at, now())
FROM mapped m2
JOIN public.madrasas m ON m.id = m2.madrasa_id
JOIN public.tenants t
  ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
WHERE m2.tenant_role IS NOT NULL
  AND EXISTS (SELECT 1 FROM auth.users au WHERE au.id = m2.user_id)
ORDER BY t.id, m2.user_id, m2.prio, m2.assigned_at
ON CONFLICT (user_id, tenant_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (d) Helper functions — all SECURITY DEFINER, SET search_path = public
-- (SECURITY DEFINER lets them bypass RLS so policies can safely call them
-- without self-reference recursion.)
-- ═══════════════════════════════════════════════════════════════

-- Replaces the 06_rbac.sql version (profiles.role based). Same signature,
-- so CREATE OR REPLACE succeeds and all existing callers pick up the new
-- platform_admins-table semantics at query time.
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_admins pa
    WHERE pa.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_tenant_member(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tenant_memberships tm
    WHERE tm.tenant_id = p_tenant_id
      AND tm.user_id   = auth.uid()
      AND tm.is_active
  );
$$;

-- Tenant admin check (owner or admin). Used by write policies so they do
-- not have to query tenant_memberships directly (which would recurse
-- through RLS).
CREATE OR REPLACE FUNCTION public.is_tenant_admin(p_tenant_id UUID)
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
             AND tm.role IN ('tenant_owner', 'tenant_admin')
         );
$$;

-- Tenant-scoped permission check: platform admins pass everything;
-- otherwise the caller's ACTIVE membership role in THIS tenant must grant
-- the code via roles → role_permissions → permissions.
CREATE OR REPLACE FUNCTION public.tenant_has_permission(p_tenant_id UUID, p_code TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_platform_admin()
      OR EXISTS (
           SELECT 1
           FROM public.tenant_memberships tm
           JOIN public.roles r              ON r.name = tm.role
           JOIN public.role_permissions rp  ON rp.role_id = r.id
           JOIN public.permissions p        ON p.id = rp.permission_id
           WHERE tm.tenant_id = p_tenant_id
             AND tm.user_id   = auth.uid()
             AND tm.is_active
             AND p.code       = p_code
         );
$$;


-- ═══════════════════════════════════════════════════════════════
-- (e) RLS
-- ═══════════════════════════════════════════════════════════════

-- ── platform_admins: platform admins only ───────────────────────
ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform admins only" ON public.platform_admins;
CREATE POLICY "platform admins only"
  ON public.platform_admins FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());
-- NOTE: bootstrapping an empty platform_admins requires a superuser /
-- service_role INSERT (bypasses RLS); see the seed above.


-- ── tenant_memberships ──────────────────────────────────────────
ALTER TABLE public.tenant_memberships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users read own memberships" ON public.tenant_memberships;
CREATE POLICY "users read own memberships"
  ON public.tenant_memberships FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "tenant admins manage memberships" ON public.tenant_memberships;
CREATE POLICY "tenant admins manage memberships"
  ON public.tenant_memberships FOR ALL
  USING  (public.is_tenant_admin(tenant_id))
  WITH CHECK (public.is_tenant_admin(tenant_id));

DROP POLICY IF EXISTS "platform admins manage memberships" ON public.tenant_memberships;
CREATE POLICY "platform admins manage memberships"
  ON public.tenant_memberships FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());


-- ── tenants: member read (complements 001's platform-admin policy) ─
DROP POLICY IF EXISTS "members read own tenants" ON public.tenants;
CREATE POLICY "members read own tenants"
  ON public.tenants FOR SELECT
  USING (public.is_tenant_member(id));


-- ── tenant_settings: member read / tenant-admin write ───────────
DROP POLICY IF EXISTS "members read tenant settings" ON public.tenant_settings;
CREATE POLICY "members read tenant settings"
  ON public.tenant_settings FOR SELECT
  USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "tenant admins manage tenant settings" ON public.tenant_settings;
CREATE POLICY "tenant admins manage tenant settings"
  ON public.tenant_settings FOR ALL
  USING  (public.is_tenant_admin(tenant_id))
  WITH CHECK (public.is_tenant_admin(tenant_id));


-- ── tenant_modules: member read / tenant-admin write ────────────
DROP POLICY IF EXISTS "members read tenant modules" ON public.tenant_modules;
CREATE POLICY "members read tenant modules"
  ON public.tenant_modules FOR SELECT
  USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS "tenant admins manage tenant modules" ON public.tenant_modules;
CREATE POLICY "tenant admins manage tenant modules"
  ON public.tenant_modules FOR ALL
  USING  (public.is_tenant_admin(tenant_id))
  WITH CHECK (public.is_tenant_admin(tenant_id));


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('004_memberships')
ON CONFLICT DO NOTHING;
