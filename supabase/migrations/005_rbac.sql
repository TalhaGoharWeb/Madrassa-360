-- ═══════════════════════════════════════════════════════════════
-- Migration 005 — RBAC reconciliation with legacy 06_rbac.sql
--   (a) Drop 06's catalog-table policies BY EXACT NAME (verified against
--       06_rbac.sql via grep before writing this file)
--   (b) Seed canonical dotted permission codes
--   (c) Ensure the 12 tenant/platform roles exist in public.roles
--       (legacy 06 roles untouched)
--   (d) Seed role_permissions: tenant_owner/tenant_admin = all
--       tenant-scoped codes; platform_owner = everything; curated rest
--   (e) Replace get_my_permissions() with a tenant-aware version
--       (same signature; p_madrasa_id deprecated/ignored)
--   (f) RLS on permissions/roles/role_permissions: authenticated SELECT,
--       platform-admin writes. user_roles left exactly as legacy
--       (deprecated, documented).
--
-- Uses CREATE TABLE IF NOT EXISTS for the catalog tables — never drops
-- them or their data.
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- Catalog tables must exist (06_rbac.sql creates them; tolerate absence).
CREATE TABLE IF NOT EXISTS public.permissions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT        NOT NULL UNIQUE,
  name        TEXT        NOT NULL,
  module      TEXT        NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.roles (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT        NOT NULL UNIQUE,
  display_name TEXT        NOT NULL,
  display_urdu TEXT        NOT NULL DEFAULT '',
  scope        TEXT        NOT NULL DEFAULT 'madrasa'
               CHECK (scope IN ('platform','madrasa','external')),
  is_system    BOOLEAN     NOT NULL DEFAULT TRUE,
  description  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id       UUID NOT NULL REFERENCES public.roles(id)       ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_permissions_code   ON public.permissions (code);
CREATE INDEX IF NOT EXISTS idx_permissions_module ON public.permissions (module);
CREATE INDEX IF NOT EXISTS idx_rp_role       ON public.role_permissions (role_id);
CREATE INDEX IF NOT EXISTS idx_rp_permission ON public.role_permissions (permission_id);


-- ═══════════════════════════════════════════════════════════════
-- (a) Drop 06's catalog-table policies by EXACT name.
-- Each name below was verified to exist as a CREATE POLICY in
-- supabase/06_rbac.sql (lines 572–600). user_roles policies are
-- intentionally NOT dropped (left as legacy, deprecated).
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "authenticated read permissions"       ON public.permissions;
DROP POLICY IF EXISTS "superAdmin manage permissions"        ON public.permissions;
DROP POLICY IF EXISTS "authenticated read roles"             ON public.roles;
DROP POLICY IF EXISTS "superAdmin manage roles"              ON public.roles;
DROP POLICY IF EXISTS "authenticated read role_permissions"  ON public.role_permissions;
DROP POLICY IF EXISTS "superAdmin manage role_permissions"  ON public.role_permissions;


-- ═══════════════════════════════════════════════════════════════
-- (b) Seed canonical dotted permission codes (66 codes)
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.permissions (code, name, module, description) VALUES
  -- Students
  ('students.view',   'View Students',   'students', 'Read student records'),
  ('students.create', 'Create Students', 'students', 'Add new students'),
  ('students.update', 'Update Students', 'students', 'Modify student records'),
  ('students.delete', 'Delete Students', 'students', 'Remove student records'),
  -- Teachers
  ('teachers.view',   'View Teachers',   'teachers', 'Read teacher records'),
  ('teachers.create', 'Create Teachers', 'teachers', 'Add new teachers'),
  ('teachers.update', 'Update Teachers', 'teachers', 'Modify teacher records'),
  ('teachers.delete', 'Delete Teachers', 'teachers', 'Remove teacher records'),
  -- Staff
  ('staff.view',   'View Staff',   'staff', 'Read staff records'),
  ('staff.create', 'Create Staff', 'staff', 'Add new staff'),
  ('staff.update', 'Update Staff', 'staff', 'Modify staff records'),
  ('staff.delete', 'Delete Staff', 'staff', 'Remove staff records'),
  -- Attendance
  ('attendance.view', 'View Attendance', 'attendance', 'Read attendance records'),
  ('attendance.mark', 'Mark Attendance', 'attendance', 'Record daily attendance'),
  ('attendance.edit', 'Edit Attendance', 'attendance', 'Correct attendance records'),
  ('attendance.delete', 'Delete Attendance', 'attendance', 'Remove attendance records'),
  -- Academics
  ('academics.view',   'View Academics',   'academics', 'Read academic structure'),
  ('academics.manage', 'Manage Academics', 'academics', 'Manage classes, darjas and structure'),
  -- Exams
  ('exams.view',    'View Exams',    'exams', 'Read exam schedules'),
  ('exams.create',  'Create Exams',  'exams', 'Schedule new exams'),
  ('exams.update',  'Update Exams',  'exams', 'Modify exam schedules'),
  ('exams.delete',  'Delete Exams',  'exams', 'Remove exams'),
  ('exams.publish', 'Publish Exams', 'exams', 'Publish exam schedules'),
  -- Results
  ('results.view',    'View Results',    'results', 'Read exam results'),
  ('results.enter',   'Enter Results',   'results', 'Add exam results'),
  ('results.edit',    'Edit Results',    'results', 'Modify exam results'),
  ('results.publish', 'Publish Results', 'results', 'Publish results to parents/students'),
  -- Fees
  ('fees.view',    'View Fees',    'fees', 'Read fee records'),
  ('fees.create',  'Create Fees',  'fees', 'Add fee entries'),
  ('fees.collect', 'Collect Fees', 'fees', 'Record fee payments'),
  ('fees.refund',  'Refund Fees',  'fees', 'Issue fee refunds'),
  -- Finance
  ('finance.view',    'View Finance',    'finance', 'Read financial records'),
  ('finance.create',  'Create Finance',  'finance', 'Add transactions'),
  ('finance.update',  'Update Finance',  'finance', 'Modify transactions'),
  ('finance.delete',  'Delete Finance',  'finance', 'Remove transactions'),
  ('finance.approve', 'Approve Finance', 'finance', 'Approve financial transactions'),
  -- Library
  ('library.view',   'View Library',   'library', 'Read library records'),
  ('library.manage', 'Manage Library', 'library', 'Full library management'),
  -- Hostel
  ('hostel.view',   'View Hostel',   'hostel', 'Read hostel records'),
  ('hostel.manage', 'Manage Hostel', 'hostel', 'Full hostel management'),
  -- Transport
  ('transport.view',   'View Transport',   'transport', 'Read transport records'),
  ('transport.manage', 'Manage Transport', 'transport', 'Full transport management'),
  -- Parents
  ('parents.view', 'View Parents', 'parents', 'Read parent/guardian records'),
  -- Notifications
  ('notifications.view', 'View Notifications', 'notifications', 'Read announcements'),
  ('notifications.send', 'Send Notifications', 'notifications', 'Send announcements and alerts'),
  -- Reports
  ('reports.view',   'View Reports',   'reports', 'Read analytics and reports'),
  ('reports.export', 'Export Reports', 'reports', 'Export reports to file'),
  -- Documents
  ('documents.view',   'View Documents',   'documents', 'Read stored documents'),
  ('documents.manage', 'Manage Documents', 'documents', 'Upload and manage documents'),
  -- Certificates
  ('certificates.view',  'View Certificates',  'certificates', 'Read certificates'),
  ('certificates.issue', 'Issue Certificates', 'certificates', 'Generate and issue certificates'),
  -- Users
  ('users.view',       'View Users',       'users', 'Read user accounts'),
  ('users.create',     'Create Users',     'users', 'Create user accounts'),
  ('users.update',     'Update Users',     'users', 'Modify user accounts'),
  ('users.deactivate', 'Deactivate Users', 'users', 'Deactivate user accounts'),
  -- Roles
  ('roles.view',   'View Roles',   'roles', 'Read roles'),
  ('roles.assign', 'Assign Roles', 'roles', 'Assign roles to users'),
  -- Settings
  ('settings.view',   'View Settings',   'settings', 'Read tenant settings'),
  ('settings.update', 'Update Settings', 'settings', 'Modify tenant settings'),
  -- Modules
  ('modules.view',   'View Modules',   'modules', 'Read module switches'),
  ('modules.manage', 'Manage Modules', 'modules', 'Enable/disable modules'),
  -- Audit
  ('audit.view', 'View Audit Log', 'audit', 'Read the audit log'),
  -- Tenants (platform-level)
  ('tenants.view',    'View Tenants',    'tenants', 'Read tenant records'),
  ('tenants.create',  'Create Tenants',  'tenants', 'Provision new tenants'),
  ('tenants.update',  'Update Tenants',  'tenants', 'Modify tenant records'),
  ('tenants.suspend', 'Suspend Tenants', 'tenants', 'Suspend/unsuspend tenants')
ON CONFLICT (code) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (c) Ensure the 12 tenant/platform roles exist.
-- Upsert by name; pre-existing rows (legacy 06 roles like 'teacher',
-- 'accountant', 'parent', 'student') are left completely untouched.
-- NOTE: scope reuses the existing CHECK values — tenant-level roles use
-- 'madrasa' (the institution scope), platform roles use 'platform'.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.roles (name, display_name, display_urdu, scope, is_system, description) VALUES
  ('tenant_owner',   'Tenant Owner',   'مالک',              'madrasa',  TRUE, 'Owns the tenant; full control within the tenant'),
  ('tenant_admin',   'Tenant Admin',   'ایڈمن',             'madrasa',  TRUE, 'Administers the tenant day-to-day'),
  ('principal',      'Principal',      'پرنسپل',            'madrasa',  TRUE, 'Academic head of the institution'),
  ('accountant',     'Accountant',     'محاسب',             'madrasa',  TRUE, 'Manages fees and daily transactions'),
  ('teacher',        'Teacher',        'استاذ',             'madrasa',  TRUE, 'Marks attendance, enters results for own class'),
  ('librarian',      'Librarian',      'لائبریرین',          'madrasa',  TRUE, 'Manages books and issuances'),
  ('hostel_manager', 'Hostel Manager', 'ہاسٹل مینیجر',       'madrasa',  TRUE, 'Manages hostel rooms and boarders'),
  ('parent',         'Parent',         'والدین',            'external', TRUE, 'Read-only access to own child data'),
  ('student',        'Student',        'طالب علم',          'external', TRUE, 'Read-only access to own academic data'),
  ('staff',          'Staff',          'عملہ',              'madrasa',  TRUE, 'General staff member'),
  ('platform_owner',   'Platform Owner',   'پلیٹ فارم مالک',   'platform', TRUE, 'Full control over the whole SaaS platform'),
  ('platform_support', 'Platform Support', 'پلیٹ فارم سپورٹ', 'platform', TRUE, 'Platform support with limited read visibility')
ON CONFLICT (name) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (d) Seed role_permissions
-- Tenant-scoped = every code EXCEPT the platform-level tenants.* codes
-- and audit.view. (users.*/roles.*/settings.*/modules.* ARE tenant-scoped:
-- they govern managing users/settings WITHIN a tenant.)
-- ═══════════════════════════════════════════════════════════════

-- tenant_owner + tenant_admin: every tenant-scoped code
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name IN ('tenant_owner', 'tenant_admin')
  AND p.code NOT LIKE 'tenants.%'
  AND p.code <> 'audit.view'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- platform_owner: everything, including platform-level codes
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name = 'platform_owner'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Curated mappings for the remaining roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
  -- accountant: fees + finance + reporting
  ('accountant','fees.view'), ('accountant','fees.create'),
  ('accountant','fees.collect'), ('accountant','fees.refund'),
  ('accountant','finance.view'), ('accountant','finance.create'),
  ('accountant','finance.update'), ('accountant','finance.delete'),
  ('accountant','finance.approve'),
  ('accountant','reports.view'), ('accountant','reports.export'),
  -- teacher: students read, attendance, exams read, results entry, announcements read
  ('teacher','students.view'),
  ('teacher','attendance.view'), ('teacher','attendance.mark'), ('teacher','attendance.edit'),
  ('teacher','exams.view'),
  ('teacher','results.view'), ('teacher','results.enter'), ('teacher','results.edit'),
  ('teacher','notifications.view'),
  -- librarian
  ('librarian','library.view'), ('librarian','library.manage'),
  -- hostel_manager
  ('hostel_manager','hostel.view'), ('hostel_manager','hostel.manage'),
  -- principal: academics, exams, results, reports, plus read-only ops visibility
  ('principal','academics.view'), ('principal','academics.manage'),
  ('principal','exams.view'), ('principal','exams.create'), ('principal','exams.update'),
  ('principal','exams.delete'), ('principal','exams.publish'),
  ('principal','results.view'), ('principal','results.enter'), ('principal','results.edit'),
  ('principal','results.publish'),
  ('principal','reports.view'), ('principal','reports.export'),
  ('principal','attendance.view'),
  ('principal','staff.view'),
  ('principal','fees.view'),
  -- parent / student: announcements read-only
  ('parent','notifications.view'),
  ('student','notifications.view'),
  -- staff: attendance view + mark
  ('staff','attendance.view'), ('staff','attendance.mark'),
  -- platform_support: limited platform visibility
  ('platform_support','tenants.view'),
  ('platform_support','users.view'),
  ('platform_support','audit.view'),
  ('platform_support','reports.view')
) AS m(role_name, perm_code)
JOIN public.roles r       ON r.name = m.role_name
JOIN public.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (e) Replace get_my_permissions() with a tenant-aware version.
-- Same signature (app compat). p_madrasa_id is DEPRECATED and ignored:
-- permissions now resolve per tenant through tenant_memberships.
-- The legacy user_roles / profiles.role UNION branches are retained
-- (deprecated) so the existing 02/06 business-table policies keep working
-- until they are rewritten tenant-aware in a later phase.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_my_permissions(p_madrasa_id UUID DEFAULT NULL)
RETURNS TABLE(code TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Primary source: UNION of permission codes across all of the caller's
  -- ACTIVE tenant memberships (tenant-aware RBAC).
  SELECT DISTINCT p.code
    FROM public.tenant_memberships tm
    JOIN public.roles r              ON r.name = tm.role
    JOIN public.role_permissions rp  ON rp.role_id = r.id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE tm.user_id = auth.uid()
     AND tm.is_active

  UNION

  -- DEPRECATED: legacy user_roles branch (kept for backward compatibility)
  SELECT DISTINCT p.code
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE ur.user_id = auth.uid()
     AND (ur.madrasa_id = p_madrasa_id OR ur.madrasa_id IS NULL OR p_madrasa_id IS NULL)

  UNION

  -- DEPRECATED: legacy profiles.role branch (kept for backward compatibility)
  SELECT DISTINCT p.code
    FROM public.profiles pr
    JOIN public.roles r              ON r.name = pr.role
    JOIN public.role_permissions rp  ON rp.role_id = r.id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE pr.id = auth.uid()
$$;

-- public.has_permission(p_code, p_madrasa_id) (06_rbac.sql) keeps working
-- unchanged on top of the replaced function.


-- ═══════════════════════════════════════════════════════════════
-- (f) RLS on the catalog tables.
-- Authenticated users may SELECT (low-sensitivity catalog);
-- only platform admins may write.
-- public.user_roles and its policies are left EXACTLY as legacy
-- (deprecated; superseded by tenant_memberships).
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.permissions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

-- ── permissions ──
DROP POLICY IF EXISTS "authenticated read permissions catalog" ON public.permissions;
CREATE POLICY "authenticated read permissions catalog"
  ON public.permissions FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "platform admins manage permissions" ON public.permissions;
CREATE POLICY "platform admins manage permissions"
  ON public.permissions FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- ── roles ──
DROP POLICY IF EXISTS "authenticated read roles catalog" ON public.roles;
CREATE POLICY "authenticated read roles catalog"
  ON public.roles FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "platform admins manage roles" ON public.roles;
CREATE POLICY "platform admins manage roles"
  ON public.roles FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- ── role_permissions ──
DROP POLICY IF EXISTS "authenticated read role_permissions catalog" ON public.role_permissions;
CREATE POLICY "authenticated read role_permissions catalog"
  ON public.role_permissions FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "platform admins manage role_permissions" ON public.role_permissions;
CREATE POLICY "platform admins manage role_permissions"
  ON public.role_permissions FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- user_roles: intentionally untouched (legacy, deprecated).


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('005_rbac')
ON CONFLICT DO NOTHING;
