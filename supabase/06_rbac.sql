-- ═══════════════════════════════════════════════════════════════
-- Madrasa 360 — Complete RBAC Schema
-- File: 06_rbac.sql
-- Run AFTER 01_schema.sql and 05_new_modules.sql
--
-- Structure:
--   Part 1  — Update profiles.role CHECK for all new roles
--   Part 2  — permissions table
--   Part 3  — roles table
--   Part 4  — role_permissions table
--   Part 5  — user_roles table (user → role, scoped to madrasa)
--   Part 6  — Seed all permissions
--   Part 7  — Seed all roles
--   Part 8  — Seed role→permission mappings
--   Part 9  — Helper SQL functions
--   Part 10 — RLS policies (permission-aware)
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- PART 1: Update profiles.role CHECK
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check CHECK (
    role IN (
      'superAdmin',
      'franchiseManager',
      'madrasaAdmin',
      'editor',
      'academicManager',
      'teacher',
      'attendanceOfficer',
      'accountant',
      'financeManager',
      'libraryManager',
      'hostelManager',
      'announcementManager',
      'admissionOfficer',
      'itManager',
      'parent',
      'student',
      -- legacy aliases kept for backward compatibility
      'admin'
    )
  );

-- Update trigger function to map old 'admin' → 'madrasaAdmin' automatically
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role TEXT;
BEGIN
  v_role := COALESCE(NEW.raw_app_meta_data->>'role', 'teacher');
  -- Normalize legacy 'admin' role
  IF v_role = 'admin' THEN v_role := 'madrasaAdmin'; END IF;

  INSERT INTO public.profiles (id, name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    v_role
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- PART 2: permissions
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.permissions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT        NOT NULL UNIQUE,   -- e.g. 'view_students'
  name        TEXT        NOT NULL,          -- e.g. 'View Students'
  module      TEXT        NOT NULL,          -- e.g. 'students'
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_permissions_code   ON public.permissions (code);
CREATE INDEX IF NOT EXISTS idx_permissions_module ON public.permissions (module);


-- ─────────────────────────────────────────────────────────────
-- PART 3: roles
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.roles (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT        NOT NULL UNIQUE, -- matches UserRole enum value
  display_name TEXT        NOT NULL,
  display_urdu TEXT        NOT NULL DEFAULT '',
  scope        TEXT        NOT NULL DEFAULT 'madrasa'
               CHECK (scope IN ('platform','madrasa','external')),
  is_system    BOOLEAN     NOT NULL DEFAULT TRUE,  -- system roles cannot be deleted
  description  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────────────
-- PART 4: role_permissions
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id       UUID NOT NULL REFERENCES public.roles(id)       ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_rp_role       ON public.role_permissions (role_id);
CREATE INDEX IF NOT EXISTS idx_rp_permission ON public.role_permissions (permission_id);


-- ─────────────────────────────────────────────────────────────
-- PART 5: user_roles  (user ↔ role, optionally scoped to one madrasa)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_roles (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role_id      UUID        NOT NULL REFERENCES public.roles(id)    ON DELETE CASCADE,
  madrasa_id   UUID        REFERENCES public.madrasas(id)          ON DELETE CASCADE,
  assigned_by  UUID        REFERENCES public.profiles(id)          ON DELETE SET NULL,
  assigned_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, role_id, madrasa_id)
);

CREATE INDEX IF NOT EXISTS idx_ur_user    ON public.user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_ur_madrasa ON public.user_roles (madrasa_id);


-- ─────────────────────────────────────────────────────────────
-- PART 6: Seed — All Permissions
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.permissions (code, name, module, description) VALUES

  -- Students
  ('view_students',      'View Students',      'students',    'Read student records'),
  ('create_students',    'Create Students',    'students',    'Add new students'),
  ('edit_students',      'Edit Students',      'students',    'Modify student records'),
  ('delete_students',    'Delete Students',    'students',    'Remove student records'),

  -- Staff
  ('view_staff',         'View Staff',         'staff',       'Read staff records'),
  ('create_staff',       'Create Staff',       'staff',       'Add new staff'),
  ('edit_staff',         'Edit Staff',         'staff',       'Modify staff records'),
  ('delete_staff',       'Delete Staff',       'staff',       'Remove staff records'),

  -- Attendance
  ('view_attendance',    'View Attendance',    'attendance',  'Read attendance records'),
  ('mark_attendance',    'Mark Attendance',    'attendance',  'Record daily attendance'),
  ('edit_attendance',    'Edit Attendance',    'attendance',  'Correct attendance records'),
  ('delete_attendance',  'Delete Attendance',  'attendance',  'Remove attendance records'),

  -- Fees
  ('view_fees',          'View Fees',          'fees',        'Read fee records'),
  ('create_fees',        'Create Fees',        'fees',        'Add fee entries'),
  ('update_fees',        'Update Fees',        'fees',        'Modify fee records'),
  ('delete_fees',        'Delete Fees',        'fees',        'Remove fee records'),

  -- Results / Exams
  ('view_results',       'View Results',       'results',     'Read exam results'),
  ('enter_results',      'Enter Results',      'results',     'Add exam results'),
  ('edit_results',       'Edit Results',       'results',     'Modify exam results'),
  ('delete_results',     'Delete Results',     'results',     'Remove exam results'),
  ('manage_exams',       'Manage Exams',       'results',     'Create and manage exams'),

  -- Finance
  ('view_finance',       'View Finance',       'finance',     'Read financial records'),
  ('create_finance',     'Create Finance',     'finance',     'Add transactions'),
  ('approve_finance',    'Approve Finance',    'finance',     'Approve financial transactions'),
  ('delete_finance',     'Delete Finance',     'finance',     'Remove financial records'),

  -- Library
  ('view_library',       'View Library',       'library',     'Read library records'),
  ('manage_library',     'Manage Library',     'library',     'Full library management'),

  -- Hostel
  ('view_hostel',        'View Hostel',        'hostel',      'Read hostel records'),
  ('manage_hostel',      'Manage Hostel',      'hostel',      'Full hostel management'),

  -- Announcements
  ('view_announcements', 'View Announcements', 'announcements','Read announcements'),
  ('create_announcements','Create Announcements','announcements','Post announcements'),
  ('edit_announcements', 'Edit Announcements', 'announcements','Modify announcements'),
  ('delete_announcements','Delete Announcements','announcements','Remove announcements'),

  -- Admissions
  ('view_admissions',    'View Admissions',    'admissions',  'Read admission requests'),
  ('create_admissions',  'Create Admissions',  'admissions',  'Process new admissions'),
  ('edit_admissions',    'Edit Admissions',    'admissions',  'Modify admission records'),
  ('delete_admissions',  'Delete Admissions',  'admissions',  'Remove admission records'),

  -- Darjas / Classes
  ('view_darjas',        'View Darjas',        'academic',    'Read darja/class records'),
  ('manage_darjas',      'Manage Darjas',      'academic',    'Create and manage darjas'),

  -- Reports
  ('view_reports',       'View Reports',       'reports',     'Access reports and analytics'),
  ('export_reports',     'Export Reports',     'reports',     'Export reports to PDF/Excel'),

  -- User Management
  ('view_users',         'View Users',         'users',       'Read user accounts'),
  ('create_users',       'Create Users',       'users',       'Create new user accounts'),
  ('edit_users',         'Edit Users',         'users',       'Modify user accounts'),
  ('delete_users',       'Delete Users',       'users',       'Remove user accounts (not superAdmin)'),

  -- Roles & Permissions
  ('view_roles',         'View Roles',         'roles',       'See role assignments'),
  ('manage_roles',       'Manage Roles',       'roles',       'Assign and revoke roles'),
  ('manage_permissions', 'Manage Permissions', 'roles',       'Modify role-permission mappings'),

  -- Settings
  ('view_settings',      'View Settings',      'settings',    'Read system settings'),
  ('manage_settings',    'Manage Settings',    'settings',    'Modify system settings'),

  -- Madrasa Management
  ('create_madrasa',     'Create Madrasa',     'madrasa',     'Create new madrasa branches'),
  ('update_madrasa',     'Update Madrasa',     'madrasa',     'Edit madrasa details'),
  ('delete_madrasa',     'Delete Madrasa',     'madrasa',     'Remove madrasa branches'),
  ('assign_madrasa_admin','Assign Madrasa Admin','madrasa',   'Assign admin to a madrasa'),
  ('view_all_madrasas',  'View All Madrasas',  'madrasa',     'See all franchise madrasas'),

  -- System
  ('system_full_access', 'System Full Access', 'system',      'Unrestricted platform access')

ON CONFLICT (code) DO NOTHING;


-- ─────────────────────────────────────────────────────────────
-- PART 7: Seed — All Roles
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.roles (name, display_name, display_urdu, scope, is_system, description) VALUES

  -- Platform level
  ('superAdmin',          'Super Admin',            'سپر ایڈمن',          'platform', TRUE,  'Full unrestricted access to everything'),
  ('franchiseManager',    'Franchise Manager',      'فرنچائز مینیجر',      'platform', TRUE,  'Oversees all madrasas, read+manage across network'),

  -- Madrasa level
  ('madrasaAdmin',        'Madrasa Admin',          'مدرسہ ایڈمن',         'madrasa',  TRUE,  'Manages one madrasa fully (Nazim / Mohtamim)'),
  ('editor',              'Editor / Data Manager',  'ایڈیٹر',              'madrasa',  TRUE,  'Data entry and editing, no user management'),

  -- Academic
  ('academicManager',     'Academic Manager',       'تعلیمی مینیجر',       'madrasa',  TRUE,  'Manages academic structure, exams, results'),
  ('teacher',             'Teacher',                'استاذ',               'madrasa',  TRUE,  'Marks attendance, enters results for own class'),
  ('attendanceOfficer',   'Attendance Officer',     'حاضری افسر',          'madrasa',  TRUE,  'Marks and edits attendance across all classes'),

  -- Finance
  ('accountant',          'Accountant',             'محاسب',               'madrasa',  TRUE,  'Manages fees and daily transactions'),
  ('financeManager',      'Finance Manager',        'مالیاتی مینیجر',      'madrasa',  TRUE,  'Full finance access including approvals'),

  -- Other departments
  ('libraryManager',      'Library Manager',        'لائبریری مینیجر',     'madrasa',  TRUE,  'Manages books and issuances'),
  ('hostelManager',       'Hostel Manager',         'ہاسٹل مینیجر',        'madrasa',  TRUE,  'Manages hostel records'),
  ('announcementManager', 'Announcement Manager',   'اعلان مینیجر',        'madrasa',  TRUE,  'Creates and manages announcements'),
  ('admissionOfficer',    'Admission Officer',      'داخلہ افسر',          'madrasa',  TRUE,  'Handles student admissions'),
  ('itManager',           'IT Manager',             'آئی ٹی مینیجر',       'madrasa',  TRUE,  'System settings and user management'),

  -- External
  ('parent',              'Parent',                 'والدین',              'external', TRUE,  'Read-only access to own child data'),
  ('student',             'Student',                'طالب علم',            'external', TRUE,  'Read-only access to own academic data')

ON CONFLICT (name) DO NOTHING;


-- ─────────────────────────────────────────────────────────────
-- PART 8: Seed — Role → Permission Mappings
-- ─────────────────────────────────────────────────────────────

-- Helper function to assign permissions to a role by code array
CREATE OR REPLACE FUNCTION public.assign_perms(p_role TEXT, p_codes TEXT[])
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v_role_id UUID;
  v_perm_id UUID;
  v_code    TEXT;
BEGIN
  SELECT id INTO v_role_id FROM public.roles WHERE name = p_role;
  IF v_role_id IS NULL THEN RETURN; END IF;

  FOREACH v_code IN ARRAY p_codes LOOP
    SELECT id INTO v_perm_id FROM public.permissions WHERE code = v_code;
    IF v_perm_id IS NOT NULL THEN
      INSERT INTO public.role_permissions (role_id, permission_id)
        VALUES (v_role_id, v_perm_id)
        ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END;
$$;


-- ── superAdmin — full platform access ─────────────────────────
SELECT public.assign_perms('superAdmin', ARRAY[
  'view_students',    'create_students',    'edit_students',    'delete_students',
  'view_staff',       'create_staff',       'edit_staff',       'delete_staff',
  'view_attendance',  'mark_attendance',    'edit_attendance',  'delete_attendance',
  'view_fees',        'create_fees',        'update_fees',      'delete_fees',
  'view_results',     'enter_results',      'edit_results',     'delete_results',  'manage_exams',
  'view_finance',     'create_finance',     'approve_finance',  'delete_finance',
  'view_library',     'manage_library',
  'view_hostel',      'manage_hostel',
  'view_announcements','create_announcements','edit_announcements','delete_announcements',
  'view_admissions',  'create_admissions',  'edit_admissions',  'delete_admissions',
  'view_darjas',      'manage_darjas',
  'view_reports',     'export_reports',
  'view_users',       'create_users',       'edit_users',       'delete_users',
  'view_roles',       'manage_roles',       'manage_permissions',
  'view_settings',    'manage_settings',
  'create_madrasa',   'update_madrasa',     'delete_madrasa',   'assign_madrasa_admin', 'view_all_madrasas',
  'system_full_access'
]);


-- ── franchiseManager ─────────────────────────────────────────
SELECT public.assign_perms('franchiseManager', ARRAY[
  'view_students',    'view_staff',     'view_attendance', 'view_fees',
  'view_results',     'view_finance',   'view_library',    'view_hostel',
  'view_announcements','create_announcements','edit_announcements',
  'view_admissions',  'view_darjas',
  'view_reports',     'export_reports',
  'view_users',       'create_users',   'edit_users',
  'view_roles',
  'view_settings',
  'update_madrasa',   'assign_madrasa_admin', 'view_all_madrasas'
]);


-- ── madrasaAdmin ──────────────────────────────────────────────
SELECT public.assign_perms('madrasaAdmin', ARRAY[
  'view_students',    'create_students',    'edit_students',    'delete_students',
  'view_staff',       'create_staff',       'edit_staff',       'delete_staff',
  'view_attendance',  'mark_attendance',    'edit_attendance',  'delete_attendance',
  'view_fees',        'create_fees',        'update_fees',      'delete_fees',
  'view_results',     'enter_results',      'edit_results',     'delete_results',  'manage_exams',
  'view_finance',     'create_finance',     'approve_finance',  'delete_finance',
  'view_library',     'manage_library',
  'view_hostel',      'manage_hostel',
  'view_announcements','create_announcements','edit_announcements','delete_announcements',
  'view_admissions',  'create_admissions',  'edit_admissions',  'delete_admissions',
  'view_darjas',      'manage_darjas',
  'view_reports',     'export_reports',
  'view_users',       'create_users',       'edit_users',
  'view_roles',       'manage_roles',
  'view_settings',    'manage_settings',
  'update_madrasa'
]);


-- ── editor ────────────────────────────────────────────────────
SELECT public.assign_perms('editor', ARRAY[
  'view_students',    'create_students',    'edit_students',
  'view_staff',
  'view_attendance',  'mark_attendance',    'edit_attendance',
  'view_fees',        'create_fees',        'update_fees',
  'view_results',     'enter_results',      'edit_results',
  'view_finance',     'create_finance',
  'view_library',
  'view_announcements','create_announcements',
  'view_admissions',  'create_admissions',  'edit_admissions',
  'view_darjas',
  'view_reports'
]);


-- ── academicManager ──────────────────────────────────────────
SELECT public.assign_perms('academicManager', ARRAY[
  'view_students',    'edit_students',
  'view_staff',
  'view_attendance',  'mark_attendance',    'edit_attendance',
  'view_results',     'enter_results',      'edit_results',     'delete_results', 'manage_exams',
  'view_darjas',      'manage_darjas',
  'view_announcements','create_announcements',
  'view_reports',     'export_reports'
]);


-- ── teacher ───────────────────────────────────────────────────
SELECT public.assign_perms('teacher', ARRAY[
  'view_students',
  'view_attendance',  'mark_attendance',
  'view_results',     'enter_results',
  'view_darjas',
  'view_announcements',
  'view_fees'
]);


-- ── attendanceOfficer ─────────────────────────────────────────
SELECT public.assign_perms('attendanceOfficer', ARRAY[
  'view_students',
  'view_attendance',  'mark_attendance',    'edit_attendance',
  'view_darjas',
  'view_announcements',
  'view_reports'
]);


-- ── accountant ────────────────────────────────────────────────
SELECT public.assign_perms('accountant', ARRAY[
  'view_students',
  'view_fees',        'create_fees',        'update_fees',
  'view_finance',     'create_finance',
  'view_reports',     'export_reports',
  'view_announcements'
]);


-- ── financeManager ────────────────────────────────────────────
SELECT public.assign_perms('financeManager', ARRAY[
  'view_students',
  'view_fees',        'create_fees',        'update_fees',      'delete_fees',
  'view_finance',     'create_finance',     'approve_finance',  'delete_finance',
  'view_reports',     'export_reports',
  'view_announcements'
]);


-- ── libraryManager ────────────────────────────────────────────
SELECT public.assign_perms('libraryManager', ARRAY[
  'view_students',
  'view_library',     'manage_library',
  'view_announcements',
  'view_reports'
]);


-- ── hostelManager ─────────────────────────────────────────────
SELECT public.assign_perms('hostelManager', ARRAY[
  'view_students',
  'view_hostel',      'manage_hostel',
  'view_announcements',
  'view_reports'
]);


-- ── announcementManager ───────────────────────────────────────
SELECT public.assign_perms('announcementManager', ARRAY[
  'view_students',    'view_staff',
  'view_announcements','create_announcements','edit_announcements','delete_announcements'
]);


-- ── admissionOfficer ─────────────────────────────────────────
SELECT public.assign_perms('admissionOfficer', ARRAY[
  'view_students',    'create_students',    'edit_students',
  'view_admissions',  'create_admissions',  'edit_admissions',  'delete_admissions',
  'view_fees',        'create_fees',
  'view_announcements',
  'view_reports'
]);


-- ── itManager ────────────────────────────────────────────────
SELECT public.assign_perms('itManager', ARRAY[
  'view_users',       'create_users',       'edit_users',       'delete_users',
  'view_roles',       'manage_roles',
  'view_settings',    'manage_settings',
  'view_announcements',
  'view_reports'
]);


-- ── parent ───────────────────────────────────────────────────
SELECT public.assign_perms('parent', ARRAY[
  'view_students',
  'view_attendance',
  'view_fees',
  'view_results',
  'view_announcements'
]);


-- ── student ──────────────────────────────────────────────────
SELECT public.assign_perms('student', ARRAY[
  'view_attendance',
  'view_results',
  'view_fees',
  'view_announcements',
  'view_library'
]);


-- ─────────────────────────────────────────────────────────────
-- PART 9: Helper SQL Functions
-- ─────────────────────────────────────────────────────────────

-- Get the set of permission codes for the current user
-- (unions role-based perms + direct user_roles table, scoped to madrasa or global)
CREATE OR REPLACE FUNCTION public.get_my_permissions(p_madrasa_id UUID DEFAULT NULL)
RETURNS TABLE(code TEXT) LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT DISTINCT p.code
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE ur.user_id = auth.uid()
     AND (ur.madrasa_id = p_madrasa_id OR ur.madrasa_id IS NULL OR p_madrasa_id IS NULL)

  UNION

  -- Also grant perms from the primary role stored in profiles (legacy support)
  SELECT DISTINCT p.code
    FROM public.profiles pr
    JOIN public.roles r              ON r.name = pr.role
    JOIN public.role_permissions rp  ON rp.role_id = r.id
    JOIN public.permissions p        ON p.id = rp.permission_id
   WHERE pr.id = auth.uid();
$$;


-- Check a single permission for the current user
CREATE OR REPLACE FUNCTION public.has_permission(p_code TEXT, p_madrasa_id UUID DEFAULT NULL)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.get_my_permissions(p_madrasa_id)
     WHERE code = p_code
  );
$$;


-- Get current user's primary role name
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;


-- Check if current user is platform-level (superAdmin or franchiseManager)
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT public.get_my_role() IN ('superAdmin', 'franchiseManager');
$$;


-- Check if current user is admin of a specific madrasa
CREATE OR REPLACE FUNCTION public.is_madrasa_admin(p_madrasa_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT public.is_platform_admin()
      OR EXISTS (
           SELECT 1 FROM public.user_roles ur
            JOIN public.roles r ON r.id = ur.role_id
           WHERE ur.user_id = auth.uid()
             AND ur.madrasa_id = p_madrasa_id
             AND r.name IN ('madrasaAdmin','editor','itManager')
         );
$$;


-- ─────────────────────────────────────────────────────────────
-- PART 10: RLS — Permission-aware Policies
-- ─────────────────────────────────────────────────────────────

-- Enable RLS
ALTER TABLE public.permissions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles          ENABLE ROW LEVEL SECURITY;


-- ── permissions table ─────────────────────────────────────────
-- Everyone authenticated can read; only superAdmin can modify

CREATE POLICY "authenticated read permissions"
  ON public.permissions FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "superAdmin manage permissions"
  ON public.permissions FOR ALL
  USING  (public.get_my_role() = 'superAdmin')
  WITH CHECK (public.get_my_role() = 'superAdmin');


-- ── roles table ───────────────────────────────────────────────

CREATE POLICY "authenticated read roles"
  ON public.roles FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "superAdmin manage roles"
  ON public.roles FOR ALL
  USING  (public.get_my_role() = 'superAdmin')
  WITH CHECK (public.get_my_role() = 'superAdmin');


-- ── role_permissions ──────────────────────────────────────────

CREATE POLICY "authenticated read role_permissions"
  ON public.role_permissions FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "superAdmin manage role_permissions"
  ON public.role_permissions FOR ALL
  USING  (public.get_my_role() = 'superAdmin')
  WITH CHECK (public.get_my_role() = 'superAdmin');


-- ── user_roles ────────────────────────────────────────────────

CREATE POLICY "read own user_roles"
  ON public.user_roles FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.is_platform_admin()
    OR public.has_permission('manage_roles', madrasa_id)
  );

CREATE POLICY "platform admin manage user_roles"
  ON public.user_roles FOR ALL
  USING  (public.is_platform_admin() OR public.has_permission('manage_roles', madrasa_id))
  WITH CHECK (public.is_platform_admin() OR public.has_permission('manage_roles', madrasa_id));


-- ── students — permission-aware ──────────────────────────────

DROP POLICY IF EXISTS "admin full access on students" ON public.students;
DROP POLICY IF EXISTS "teacher read students"         ON public.students;
DROP POLICY IF EXISTS "parent read own child"         ON public.students;

CREATE POLICY "view_students permission"
  ON public.students FOR SELECT
  USING (
    public.has_permission('view_students')
    OR parent_user_id = auth.uid()
  );

CREATE POLICY "create_students permission"
  ON public.students FOR INSERT
  WITH CHECK (public.has_permission('create_students'));

CREATE POLICY "edit_students permission"
  ON public.students FOR UPDATE
  USING  (public.has_permission('edit_students'))
  WITH CHECK (public.has_permission('edit_students'));

CREATE POLICY "delete_students permission"
  ON public.students FOR DELETE
  USING (public.has_permission('delete_students'));


-- ── staff — permission-aware ──────────────────────────────────

DROP POLICY IF EXISTS "admin full access on staff" ON public.staff;
DROP POLICY IF EXISTS "teacher read staff"         ON public.staff;

CREATE POLICY "view_staff permission"
  ON public.staff FOR SELECT
  USING (public.has_permission('view_staff'));

CREATE POLICY "create_staff permission"
  ON public.staff FOR INSERT
  WITH CHECK (public.has_permission('create_staff'));

CREATE POLICY "edit_staff permission"
  ON public.staff FOR UPDATE
  USING  (public.has_permission('edit_staff'))
  WITH CHECK (public.has_permission('edit_staff'));

CREATE POLICY "delete_staff permission"
  ON public.staff FOR DELETE
  USING (public.has_permission('delete_staff'));


-- ── attendance — permission-aware ────────────────────────────

DROP POLICY IF EXISTS "teacher manage own attendance" ON public.attendance;

CREATE POLICY "view_attendance permission"
  ON public.attendance FOR SELECT
  USING (public.has_permission('view_attendance'));

CREATE POLICY "mark_attendance permission"
  ON public.attendance FOR INSERT
  WITH CHECK (public.has_permission('mark_attendance'));

CREATE POLICY "edit_attendance permission"
  ON public.attendance FOR UPDATE
  USING  (public.has_permission('edit_attendance'))
  WITH CHECK (public.has_permission('edit_attendance'));

CREATE POLICY "delete_attendance permission"
  ON public.attendance FOR DELETE
  USING (public.has_permission('delete_attendance'));


-- ── fees — permission-aware ───────────────────────────────────

CREATE POLICY "view_fees permission"
  ON public.fees FOR SELECT
  USING (
    public.has_permission('view_fees')
    OR EXISTS (
      SELECT 1 FROM public.students s
       WHERE s.id = fees.student_id AND s.parent_user_id = auth.uid()
    )
  );

CREATE POLICY "create_fees permission"
  ON public.fees FOR INSERT
  WITH CHECK (public.has_permission('create_fees'));

CREATE POLICY "update_fees permission"
  ON public.fees FOR UPDATE
  USING  (public.has_permission('update_fees'))
  WITH CHECK (public.has_permission('update_fees'));

CREATE POLICY "delete_fees permission"
  ON public.fees FOR DELETE
  USING (public.has_permission('delete_fees'));


-- ── finance_transactions — permission-aware ───────────────────

DROP POLICY IF EXISTS "admin manage finance"         ON public.finance_transactions;
DROP POLICY IF EXISTS "authenticated read finance"   ON public.finance_transactions;

CREATE POLICY "view_finance permission"
  ON public.finance_transactions FOR SELECT
  USING (public.has_permission('view_finance'));

CREATE POLICY "create_finance permission"
  ON public.finance_transactions FOR INSERT
  WITH CHECK (public.has_permission('create_finance'));

CREATE POLICY "delete_finance permission"
  ON public.finance_transactions FOR DELETE
  USING (public.has_permission('delete_finance'));


-- ── library_books — permission-aware ─────────────────────────

DROP POLICY IF EXISTS "admin manage library_books"      ON public.library_books;
DROP POLICY IF EXISTS "authenticated read library_books" ON public.library_books;

CREATE POLICY "view_library permission"
  ON public.library_books FOR SELECT
  USING (public.has_permission('view_library'));

CREATE POLICY "manage_library permission"
  ON public.library_books FOR ALL
  USING  (public.has_permission('manage_library'))
  WITH CHECK (public.has_permission('manage_library'));


-- ── book_issues — permission-aware ────────────────────────────

DROP POLICY IF EXISTS "admin manage book_issues"      ON public.book_issues;
DROP POLICY IF EXISTS "authenticated read book_issues" ON public.book_issues;

CREATE POLICY "view_library book_issues permission"
  ON public.book_issues FOR SELECT
  USING (public.has_permission('view_library'));

CREATE POLICY "manage_library book_issues permission"
  ON public.book_issues FOR ALL
  USING  (public.has_permission('manage_library'))
  WITH CHECK (public.has_permission('manage_library'));


-- ── announcements — permission-aware ─────────────────────────

CREATE POLICY "view_announcements permission"
  ON public.announcements FOR SELECT
  USING (public.has_permission('view_announcements'));

CREATE POLICY "create_announcements permission"
  ON public.announcements FOR INSERT
  WITH CHECK (public.has_permission('create_announcements'));

CREATE POLICY "edit_announcements permission"
  ON public.announcements FOR UPDATE
  USING  (public.has_permission('edit_announcements'))
  WITH CHECK (public.has_permission('edit_announcements'));

CREATE POLICY "delete_announcements permission"
  ON public.announcements FOR DELETE
  USING (public.has_permission('delete_announcements'));


-- ── profiles — prevent non-admins from elevating roles ────────

DROP POLICY IF EXISTS "users read own profile"   ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;

-- Everyone can read profiles (needed for display names)
CREATE POLICY "profiles select authenticated"
  ON public.profiles FOR SELECT
  USING (auth.role() = 'authenticated');

-- Users can update their own non-sensitive fields
CREATE POLICY "profiles update own"
  ON public.profiles FOR UPDATE
  USING  (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    -- Prevent role escalation by non-admins
    AND (
      role = (SELECT role FROM public.profiles WHERE id = auth.uid())
      OR public.has_permission('manage_roles')
    )
  );

-- Only admins can insert/delete profiles
CREATE POLICY "admin manage profiles"
  ON public.profiles FOR ALL
  USING  (public.has_permission('create_users') OR public.is_platform_admin())
  WITH CHECK (public.has_permission('create_users') OR public.is_platform_admin());


-- ─────────────────────────────────────────────────────────────
-- PART 11: Convenience View — user permissions summary
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.my_permissions AS
  SELECT code FROM public.get_my_permissions();

-- A flat JSON aggregate useful for the Flutter app to load in one query:
-- SELECT array_agg(code) FROM public.get_my_permissions();
