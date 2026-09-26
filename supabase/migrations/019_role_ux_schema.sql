-- ═══════════════════════════════════════════════════════════════
-- Migration 019 — Role-aware UX: schema (design doc §3.1)
--   (a) permissions: label_urdu + category_urdu + sort_order columns,
--       backfilled for all 66 codes from the design doc §7 table,
--       then label_urdu SET NOT NULL.
--   (b) New template roles in public.roles (is_system=TRUE,
--       scope='madrasa'): the 15 keys from design doc §5. Legacy 10
--       roles are NOT touched (neither their rows nor their
--       role_permissions sets).
--   (c) tenant_roles — per-tenant editable role catalog
--       (the global roles table stays the immutable template catalog).
--   (d) tenant_role_permissions — per-tenant role→permission grants.
--   (e) Backfill: for EVERY tenant, materialize one tenant_roles row
--       per template key (legacy 10 + 15 new) and copy the template's
--       global role_permissions into tenant_role_permissions.
--       Re-runnable without duplicates (ON CONFLICT DO NOTHING, and the
--       permission copy only seeds roles that have zero permissions —
--       it never re-adds permissions a tenant admin deliberately
--       removed).
--   (f) user_permissions — per-user grant/deny overrides
--       (deny > grant precedence is enforced in 020's helpers).
--   (g) permission_scopes — plain-language data scopes
--       ('all' | 'department' | 'classes' | 'students').
--   (h) permission_delegations — time-boxed delegation grants with a
--       ceiling trigger (delegator must hold roles.assign or be
--       owner/admin AND must effectively hold the delegated code
--       themselves; delegations never chain).
--   (i) tenant_memberships.role: DROP the legacy role CHECK; add a
--       BEFORE trigger validating NEW.role is an active tenant_roles
--       key for that tenant.
--   (j) protect_last_owner() — BEFORE UPDATE/DELETE on
--       tenant_memberships: refuse to remove/deactivate/re-role the
--       last active tenant_owner of a tenant.
--   (k) Auto-audit triggers on all 5 role/permission tables writing
--       structured audit_logs rows.
--   (l) Default data scopes: teachers (teacher/ustad/ustad_hifz keys)
--       get 'classes' scope rows for their mutation codes, seeded from
--       their ACTIVE teacher_class_assignments; everyone else gets no
--       row (= 'all').
--
-- DOCUMENTED CHOICES / DEVIATIONS FROM THE DESIGN DOC:
--   * §5 lists department/student default scopes (nazim_hifz → حفظ,
--     warden → دارالاقامہ, parent/student → own). §3.2.4 (the operative
--     paragraph) says seed only teachers→classes and leave everyone
--     else without a row. Department scopes are not seeded because no
--     department dimension exists on the class/student rows to seed
--     against (see scope_allows() in 020); parent/student "own"
--     visibility is already enforced by the existing 007 select-policy
--     fallbacks via students.parent_user_id.
--   * nazim_aala §5 line reads "students/teachers/staff/attendance/
--     academics/reports/users.view, announcements". Interpreted as:
--     full students.*, teachers.*, staff.*, attendance.*, academics.*,
--     reports.* modules + users.view + notifications.*.
--   * naib_mohtamim "all except roles.assign mgmt? no — all tenant
--     codes" → seeded with ALL tenant codes (incl. roles.assign).
--   * The auto-audit triggers INSERT into public.audit_logs directly
--     as SECURITY DEFINER instead of calling public.log_audit():
--     log_audit() rejects writers who are not tenant owner/admin,
--     but role managers holding roles.assign (non-owners) must still
--     be audited — calling log_audit() would break their writes.
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) permissions: human labels
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.permissions ADD COLUMN IF NOT EXISTS label_urdu    TEXT;
ALTER TABLE public.permissions ADD COLUMN IF NOT EXISTS category_urdu TEXT;
ALTER TABLE public.permissions ADD COLUMN IF NOT EXISTS sort_order    INT;

-- Backfill every permission code (66 dotted from 005 + 56 legacy underscore
-- codes from 06_rbac.sql, which are still live in the catalog)
-- (label_urdu / category_urdu / sort_order-within-category).
UPDATE public.permissions AS p
SET label_urdu    = v.label_urdu,
    category_urdu = v.category_urdu,
    sort_order    = v.sort_order
FROM (VALUES
  ('students.view',    'طلبہ دیکھنا',                  'طلبہ',       1),
  ('students.create',  'نئے طلبہ شامل کرنا',           'طلبہ',       2),
  ('students.update',  'طلبہ کی معلومات درست کرنا',    'طلبہ',       3),
  ('students.delete',  'طلبہ کا ریکارڈ ختم کرنا',      'طلبہ',       4),
  ('teachers.view',    'اساتذہ کو دیکھنا',             'اساتذہ',     1),
  ('teachers.create',  'نئے اساتذہ شامل کرنا',         'اساتذہ',     2),
  ('teachers.update',  'اساتذہ کی معلومات درست کرنا',  'اساتذہ',     3),
  ('teachers.delete',  'اساتذہ کا ریکارڈ ختم کرنا',    'اساتذہ',     4),
  ('staff.view',       'عملے کو دیکھنا',               'عملہ',       1),
  ('staff.create',     'نیا عملہ شامل کرنا',           'عملہ',       2),
  ('staff.update',     'عملے کی معلومات درست کرنا',    'عملہ',       3),
  ('staff.delete',     'عملے کا ریکارڈ ختم کرنا',      'عملہ',       4),
  ('attendance.view',  'حاضری دیکھنا',                 'حاضری',      1),
  ('attendance.mark',  'حاضری لگانا',                  'حاضری',      2),
  ('attendance.edit',  'حاضری درست کرنا',              'حاضری',      3),
  ('attendance.delete','حاضری کا ریکارڈ ختم کرنا',     'حاضری',      4),
  ('academics.view',   'تعلیمی نظام دیکھنا',           'تعلیم',      1),
  ('academics.manage', 'تعلیمی نظام ترتیب دینا',       'تعلیم',      2),
  ('exams.view',       'امتحانات دیکھنا',              'امتحانات',   1),
  ('exams.create',     'امتحان بنانا',                 'امتحانات',   2),
  ('exams.update',     'امتحان میں تبدیلی کرنا',       'امتحانات',   3),
  ('exams.delete',     'امتحان ختم کرنا',              'امتحانات',   4),
  ('exams.publish',    'امتحان کا اعلان کرنا',         'امتحانات',   5),
  ('results.view',     'نتائج دیکھنا',                 'نتائج',      1),
  ('results.enter',    'نمبر درج کرنا',                'نتائج',      2),
  ('results.edit',     'نمبر درست کرنا',               'نتائج',      3),
  ('results.publish',  'نتائج شائع کرنا',              'نتائج',      4),
  ('fees.view',        'فیس کا حساب دیکھنا',           'فیس',        1),
  ('fees.create',      'فیس مقرر کرنا',                'فیس',        2),
  ('fees.collect',     'فیس وصول کرنا',                'فیس',        3),
  ('fees.refund',      'فیس واپس کرنا',                'فیس',        4),
  ('finance.view',     'مالی حساب دیکھنا',             'مالیات',     1),
  ('finance.create',   'مالی لین دین درج کرنا',        'مالیات',     2),
  ('finance.update',   'مالی ریکارڈ درست کرنا',        'مالیات',     3),
  ('finance.delete',   'مالی ریکارڈ ختم کرنا',         'مالیات',     4),
  ('finance.approve',  'مالی لین دین کی منظوری دینا',  'مالیات',     5),
  ('library.view',     'کتب خانہ دیکھنا',             'کتب خانہ',   1),
  ('library.manage',   'کتب خانے کا انتظام کرنا',      'کتب خانہ',   2),
  ('hostel.view',      'دارالاقامہ دیکھنا',           'دارالاقامہ', 1),
  ('hostel.manage',    'دارالاقامہ کا انتظام کرنا',   'دارالاقامہ', 2),
  ('transport.view',   'ٹرانسپورٹ دیکھنا',            'ٹرانسپورٹ',  1),
  ('transport.manage', 'ٹرانسپورٹ کا انتظام کرنا',     'ٹرانسپورٹ',  2),
  ('parents.view',     'والدین کی معلومات دیکھنا',     'والدین',     1),
  ('notifications.view','اعلانات دیکھنا',              'اعلانات',    1),
  ('notifications.send','اعلان بھیجنا',               'اعلانات',    2),
  ('reports.view',     'رپورٹس دیکھنا',               'رپورٹس',     1),
  ('reports.export',   'رپورٹس محفوظ کرنا',           'رپورٹس',     2),
  ('documents.view',   'دستاویزات دیکھنا',            'دستاویزات',   1),
  ('documents.manage', 'دستاویزات کا انتظام کرنا',     'دستاویزات',   2),
  ('certificates.view', 'اسناد دیکھنا',               'اسناد',       1),
  ('certificates.issue','سند جاری کرنا',              'اسناد',       2),
  ('users.view',       'صارفین دیکھنا',               'صارفین',     1),
  ('users.create',     'نیا صارف بنانا',              'صارفین',     2),
  ('users.update',     'صارف کی معلومات درست کرنا',   'صارفین',     3),
  ('users.deactivate', 'صارف غیر فعال کرنا',          'صارفین',     4),
  ('roles.view',       'ذمہ داریاں دیکھنا',           'ذمہ داریاں', 1),
  ('roles.assign',     'ذمہ داریاں سونپنا',           'ذمہ داریاں', 2),
  ('settings.view',    'ترتیبات دیکھنا',              'ترتیبات',    1),
  ('settings.update',  'ترتیبات تبدیل کرنا',          'ترتیبات',    2),
  ('modules.view',     'شعبے دیکھنا',                 'شعبہ جات',   1),
  ('modules.manage',   'شعبے فعال یا غیر فعال کرنا',  'شعبہ جات',   2),
  ('audit.view',       'سرگرمی کا ریکارڈ دیکھنا',     'سرگرمی',     1),
  ('tenants.view',     'مدارس دیکھنا',                'پلیٹ فارم',  1),
  ('tenants.create',   'نیا مدرسہ بنانا',             'پلیٹ فارم',  2),
  ('tenants.update',   'مدرسے کی معلومات درست کرنا',  'پلیٹ فارم',  3),
  ('tenants.suspend',  'مدرسہ معطل یا بحال کرنا',     'پلیٹ فارم',  4),
  -- Legacy underscore codes from 06_rbac.sql (still live in the catalog;
  -- label them too so no code is ever without a human-readable label).
  ('approve_finance',    'مالی لین دین کی منظوری دینا', 'مالیات',     6),
  ('assign_madrasa_admin','مدرسے کا منتظم مقرر کرنا',   'صارفین',     5),
  ('create_admissions',  'نیا داخلہ کرنا',              'داخلے',      1),
  ('create_announcements','اعلان بنانا',                'اعلانات',    3),
  ('create_fees',        'فیس مقرر کرنا',               'فیس',        5),
  ('create_finance',     'مالی لین دین درج کرنا',       'مالیات',     6),
  ('create_madrasa',     'نیا مدرسہ بنانا',             'پلیٹ فارم',  5),
  ('create_staff',       'نیا عملہ شامل کرنا',          'عملہ',       5),
  ('create_students',    'نئے طلبہ شامل کرنا',          'طلبہ',       5),
  ('create_users',       'نیا صارف بنانا',              'صارفین',     5),
  ('delete_admissions',  'داخلہ ختم کرنا',             'داخلے',      4),
  ('delete_announcements','اعلان ختم کرنا',            'اعلانات',    6),
  ('delete_attendance',  'حاضری کا ریکارڈ ختم کرنا',    'حاضری',      5),
  ('delete_fees',        'فیس کا ریکارڈ ختم کرنا',      'فیس',        6),
  ('delete_finance',     'مالی ریکارڈ ختم کرنا',        'مالیات',     7),
  ('delete_madrasa',     'مدرسہ ختم کرنا',              'پلیٹ فارم',  6),
  ('delete_results',     'نتائج ختم کرنا',              'نتائج',      5),
  ('delete_staff',       'عملے کا ریکارڈ ختم کرنا',     'عملہ',       6),
  ('delete_students',    'طلبہ کا ریکارڈ ختم کرنا',     'طلبہ',       6),
  ('delete_users',       'صارف ختم کرنا',               'صارفین',     6),
  ('edit_admissions',    'داخلے میں تبدیلی کرنا',       'داخلے',      3),
  ('edit_announcements', 'اعلان میں تبدیلی کرنا',       'اعلانات',    5),
  ('edit_attendance',    'حاضری درست کرنا',             'حاضری',      6),
  ('edit_results',       'نمبر درست کرنا',              'نتائج',      6),
  ('edit_staff',         'عملے کی معلومات درست کرنا',   'عملہ',       7),
  ('edit_students',      'طلبہ کی معلومات درست کرنا',  'طلبہ',       7),
  ('edit_users',         'صارف کی معلومات درست کرنا',   'صارفین',     7),
  ('enter_results',      'نمبر درج کرنا',               'نتائج',      7),
  ('export_reports',     'رپورٹس محفوظ کرنا',          'رپورٹس',     3),
  ('manage_darjas',      'درجات کا انتظام کرنا',        'تعلیم',      3),
  ('manage_exams',       'امتحانات کا انتظام کرنا',    'امتحانات',   6),
  ('manage_hostel',      'دارالاقامہ کا انتظام کرنا',  'دارالاقامہ', 3),
  ('manage_library',     'کتب خانے کا انتظام کرنا',    'کتب خانہ',   3),
  ('manage_permissions', 'اختیارات کا انتظام کرنا',    'ذمہ داریاں', 3),
  ('manage_roles',       'ذمہ داریوں کا انتظام کرنا',  'ذمہ داریاں', 4),
  ('manage_settings',    'ترتیبات کا انتظام کرنا',      'ترتیبات',    3),
  ('mark_attendance',    'حاضری لگانا',                'حاضری',      7),
  ('system_full_access', 'مکمل رسائی',                  'پلیٹ فارم',  7),
  ('update_fees',        'فیس میں تبدیلی کرنا',         'فیس',        7),
  ('update_madrasa',     'مدرسے کی معلومات درست کرنا', 'پلیٹ فارم',  8),
  ('view_admissions',    'داخلے دیکھنا',               'داخلے',      2),
  ('view_all_madrasas',  'تمام مدارس دیکھنا',          'پلیٹ فارم',  9),
  ('view_announcements', 'اعلانات دیکھنا',              'اعلانات',    4),
  ('view_attendance',    'حاضری دیکھنا',               'حاضری',      8),
  ('view_darjas',        'درجات دیکھنا',               'تعلیم',      4),
  ('view_fees',          'فیس کا حساب دیکھنا',          'فیس',        8),
  ('view_finance',       'مالی حساب دیکھنا',           'مالیات',     8),
  ('view_hostel',        'دارالاقامہ دیکھنا',          'دارالاقامہ', 4),
  ('view_library',       'کتب خانہ دیکھنا',            'کتب خانہ',   4),
  ('view_reports',       'رپورٹس دیکھنا',              'رپورٹس',     4),
  ('view_results',       'نتائج دیکھنا',               'نتائج',      8),
  ('view_roles',         'ذمہ داریاں دیکھنا',         'ذمہ داریاں', 5),
  ('view_settings',      'ترتیبات دیکھنا',             'ترتیبات',    4),
  ('view_staff',         'عملے کو دیکھنا',             'عملہ',       8),
  ('view_students',      'طلبہ دیکھنا',                'طلبہ',       8),
  ('view_users',         'صارفین دیکھنا',              'صارفین',     8)
) AS v(code, label_urdu, category_urdu, sort_order)
WHERE p.code = v.code;

-- Fail-loud: every seeded permission code must have a label now.
DO $$
DECLARE
  v_missing INT;
BEGIN
  SELECT COUNT(*) INTO v_missing
    FROM public.permissions
   WHERE label_urdu IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION '019 FAIL-LOUD: % permission code(s) missing label_urdu after backfill', v_missing;
  END IF;
END $$;

ALTER TABLE public.permissions ALTER COLUMN label_urdu SET NOT NULL;


-- ═══════════════════════════════════════════════════════════════
-- (b) New template roles in public.roles (is_system=TRUE,
--     scope='madrasa'). Legacy 10 roles untouched.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.roles (name, display_name, display_urdu, scope, is_system, description) VALUES
  ('mohtamim',           'Mohtamim',           'مہتمم',            'madrasa', TRUE, 'Head of the institution; full tenant control'),
  ('naib_mohtamim',      'Naib Mohtamim',      'نائب مہتمم',        'madrasa', TRUE, 'Deputy head; full tenant control'),
  ('nazim_aala',         'Nazim Aala',         'ناظم اعلیٰ',        'madrasa', TRUE, 'Senior administrator across departments'),
  ('nazim_taleem',       'Nazim Taleem',       'ناظم تعلیم',        'madrasa', TRUE, 'Head of academics and examinations'),
  ('nazim_intizamia',    'Nazim Intizamia',    'ناظم انتظامیہ',     'madrasa', TRUE, 'Head of administration and staff affairs'),
  ('nazim_maliyat',      'Nazim Maliyat',      'ناظم مالیات',       'madrasa', TRUE, 'Head of fees and finance'),
  ('daftar_dar',         'Daftar Dar',         'دفتر دار',          'madrasa', TRUE, 'Front-office clerk: admissions, fees, documents'),
  ('ustad',              'Ustad',              'استاد',             'madrasa', TRUE, 'Teacher (madrassa vocabulary)'),
  ('ustad_hifz',         'Ustad Hifz',         'مدرس حفظ',          'madrasa', TRUE, 'Quran memorization teacher'),
  ('nazim_hifz',         'Nazim Hifz',         'ناظم حفظ',          'madrasa', TRUE, 'Head of the hifz department'),
  ('nazim_darul_iqama',  'Nazim Darul Iqama',  'ناظم دارالاقامہ',    'madrasa', TRUE, 'Head of the boarding house'),
  ('warden',             'Warden',             'وارڈن',             'madrasa', TRUE, 'Boarding-house warden'),
  ('mumtahin',           'Mumtahin',           'ممتحن',             'madrasa', TRUE, 'Examiner: exams and results entry'),
  ('store_incharge',     'Store Incharge',     'اسٹور انچارج',      'madrasa', TRUE, 'Manages documents and store records'),
  ('hr_incharge',        'HR Incharge',        'عملہ انچارج',       'madrasa', TRUE, 'Manages staff records and attendance')
ON CONFLICT (name) DO NOTHING;

-- Template permission sets (design doc §5). "All tenant codes" =
-- everything except the platform-level tenants.* codes and audit.view
-- (same definition as 005's tenant_owner/tenant_admin seed).
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name IN ('mohtamim', 'naib_mohtamim')
  AND p.code NOT LIKE 'tenants.%'
  AND p.code <> 'audit.view'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name = 'nazim_aala'
  AND (p.code LIKE 'students.%'
    OR p.code LIKE 'teachers.%'
    OR p.code LIKE 'staff.%'
    OR p.code LIKE 'attendance.%'
    OR p.code LIKE 'academics.%'
    OR p.code LIKE 'reports.%'
    OR p.code = 'users.view'
    OR p.code LIKE 'notifications.%')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name = 'nazim_taleem'
  AND (p.code LIKE 'academics.%'
    OR p.code LIKE 'exams.%'
    OR p.code LIKE 'results.%'
    OR p.code = 'attendance.view'
    OR p.code = 'teachers.view'
    OR p.code LIKE 'reports.%')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name = 'nazim_intizamia'
  AND (p.code LIKE 'staff.%'
    OR p.code LIKE 'documents.%'
    OR p.code = 'notifications.send'
    OR p.code = 'users.view')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name = 'nazim_maliyat'
  AND (p.code LIKE 'fees.%' OR p.code LIKE 'finance.%')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name = 'daftar_dar'
  AND (p.code IN ('students.view','students.create','students.update',
                  'fees.view','fees.collect',
                  'certificates.issue','notifications.view')
    OR p.code LIKE 'documents.%')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ustad = teacher set; ustad_hifz = teacher set + hostel.view
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code IN
  ('students.view',
   'attendance.view','attendance.mark','attendance.edit',
   'exams.view',
   'results.view','results.enter','results.edit',
   'notifications.view')
WHERE r.name IN ('ustad', 'ustad_hifz')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code = 'hostel.view'
WHERE r.name = 'ustad_hifz'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code IN
  ('academics.view',
   'exams.view','exams.create',
   'results.view','results.enter','results.edit',
   'attendance.view')
WHERE r.name = 'nazim_hifz'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code IN
  ('hostel.view','hostel.manage','students.view','attendance.view')
WHERE r.name = 'nazim_darul_iqama'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code IN
  ('hostel.view','attendance.view','attendance.mark','students.view')
WHERE r.name = 'warden'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code IN
  ('exams.view','exams.create','exams.update',
   'results.view','results.enter','results.edit',
   'students.view')
WHERE r.name = 'mumtahin'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code IN
  ('documents.view','documents.manage','reports.view')
WHERE r.name = 'store_incharge'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code IN
  ('staff.view','staff.create','staff.update','staff.delete',
   'users.view','attendance.view','reports.view')
WHERE r.name = 'hr_incharge'
ON CONFLICT (role_id, permission_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (c)+(d) tenant_roles + tenant_role_permissions
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.tenant_roles (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  key          TEXT        NOT NULL,
  display_name TEXT        NOT NULL,
  display_urdu TEXT        NOT NULL,
  template_key TEXT,
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  created_by   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, key)
);

CREATE TABLE IF NOT EXISTS public.tenant_role_permissions (
  tenant_role_id UUID NOT NULL REFERENCES public.tenant_roles(id) ON DELETE CASCADE,
  permission_id  UUID NOT NULL REFERENCES public.permissions(id)  ON DELETE CASCADE,
  PRIMARY KEY (tenant_role_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_tenant_roles_tenant ON public.tenant_roles (tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_roles_key    ON public.tenant_roles (tenant_id, key);
CREATE INDEX IF NOT EXISTS idx_trp_role       ON public.tenant_role_permissions (tenant_role_id);
CREATE INDEX IF NOT EXISTS idx_trp_permission ON public.tenant_role_permissions (permission_id);

DROP TRIGGER IF EXISTS tenant_roles_set_updated_at ON public.tenant_roles;
CREATE TRIGGER tenant_roles_set_updated_at
  BEFORE UPDATE ON public.tenant_roles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ═══════════════════════════════════════════════════════════════
-- (f) user_permissions — per-user grant/deny overrides
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.user_permissions (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission_id UUID        NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  effect        TEXT        NOT NULL CHECK (effect IN ('grant', 'deny')),
  reason        TEXT,
  created_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_user_permissions_tenant_user
  ON public.user_permissions (tenant_id, user_id);


-- ═══════════════════════════════════════════════════════════════
-- (g) permission_scopes — plain-language data scopes
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.permission_scopes (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission_id UUID        NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  scope_type    TEXT        NOT NULL CHECK (scope_type IN ('all', 'department', 'classes', 'students')),
  scope_ref     JSONB       NOT NULL DEFAULT '{}',
  created_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id, permission_id)
);

CREATE INDEX IF NOT EXISTS idx_permission_scopes_tenant_user
  ON public.permission_scopes (tenant_id, user_id);


-- ═══════════════════════════════════════════════════════════════
-- (h) permission_delegations — delegation with ceilings
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.permission_delegations (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  delegator_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  delegatee_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission_id UUID        NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  scope_type    TEXT        NOT NULL DEFAULT 'all'
                            CHECK (scope_type IN ('all', 'department', 'classes', 'students')),
  scope_ref     JSONB       NOT NULL DEFAULT '{}',
  starts_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ,
  created_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, delegatee_id, permission_id),
  CHECK (delegator_id <> delegatee_id),
  CHECK (expires_at IS NULL OR expires_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_permission_delegations_tenant_delegatee
  ON public.permission_delegations (tenant_id, delegatee_id);
CREATE INDEX IF NOT EXISTS idx_permission_delegations_expiry
  ON public.permission_delegations (expires_at);


-- ═══════════════════════════════════════════════════════════════
-- (e) Backfill: materialize tenant_roles for every tenant × every
-- template key (global roles with is_system=TRUE and a non-platform
-- scope), then copy each template's global role_permissions.
-- Re-runnable: ON CONFLICT DO NOTHING; the permission copy only
-- seeds roles that currently hold ZERO permissions, so it never
-- re-adds a permission a tenant admin deliberately removed.
-- ═══════════════════════════════════════════════════════════════

WITH new_roles AS (
  INSERT INTO public.tenant_roles (tenant_id, key, display_name, display_urdu, template_key)
  SELECT t.id, r.name, r.display_name, r.display_urdu, r.name
    FROM public.tenants t
   CROSS JOIN public.roles r
   WHERE r.is_system
     AND r.scope IN ('madrasa', 'external')
  ON CONFLICT (tenant_id, key) DO NOTHING
  RETURNING id, template_key
)
INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
SELECT nr.id, rp.permission_id
  FROM new_roles nr
  JOIN public.roles r              ON r.name = nr.template_key
  JOIN public.role_permissions rp ON rp.role_id = r.id
ON CONFLICT (tenant_role_id, permission_id) DO NOTHING;

-- Repair pass: roles that exist but somehow hold zero permissions
-- (e.g. a previous partial run) get their template set now.
INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
SELECT tr.id, rp.permission_id
  FROM public.tenant_roles tr
  JOIN public.roles r              ON r.name = tr.template_key
  JOIN public.role_permissions rp ON rp.role_id = r.id
 WHERE tr.template_key IS NOT NULL
   AND NOT EXISTS (
         SELECT 1 FROM public.tenant_role_permissions x
          WHERE x.tenant_role_id = tr.id
       )
ON CONFLICT (tenant_role_id, permission_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (l) Default data scopes: teacher-class roles (teacher, ustad,
-- ustad_hifz) → 'classes' scope on their mutation codes, seeded
-- from ACTIVE teacher_class_assignments. Users with no active
-- assignments are SKIPPED (no row = 'all', so nobody is locked out
-- by the migration); a tenant admin can tighten them later.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.permission_scopes
  (tenant_id, user_id, permission_id, scope_type, scope_ref)
SELECT DISTINCT
  tm.tenant_id,
  tm.user_id,
  p.id,
  'classes',
  jsonb_build_object('class_ids',
    (SELECT jsonb_agg(DISTINCT tca.class_id)
       FROM public.teacher_class_assignments tca
      WHERE tca.tenant_id       = tm.tenant_id
        AND tca.teacher_user_id = tm.user_id
        AND tca.is_active))
FROM public.tenant_memberships tm
JOIN public.tenant_roles tr              ON tr.tenant_id = tm.tenant_id
                                         AND tr.key      = tm.role
                                         AND tr.is_active
JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = tr.id
JOIN public.permissions p               ON p.id = trp.permission_id
WHERE tm.is_active
  AND tm.role IN ('teacher', 'ustad', 'ustad_hifz')
  AND p.code IN ('attendance.mark', 'attendance.edit', 'results.enter', 'results.edit')
  AND EXISTS ( -- at least one active class assignment
        SELECT 1 FROM public.teacher_class_assignments tca
         WHERE tca.tenant_id       = tm.tenant_id
           AND tca.teacher_user_id = tm.user_id
           AND tca.is_active
      )
ON CONFLICT (tenant_id, user_id, permission_id) DO NOTHING;


-- ═══════════════════════════════════════════════════════════════
-- (i) tenant_memberships.role: DROP the legacy role CHECK (constraint
-- name is looked up dynamically — it was created inline in 004), then
-- validate NEW.role against the tenant's active tenant_roles keys.
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_conname TEXT;
BEGIN
  SELECT conname INTO v_conname
    FROM pg_constraint
   WHERE conrelid = 'public.tenant_memberships'::regclass
     AND contype = 'c'
     AND pg_get_constraintdef(oid) ILIKE '%role%IN%';
  IF v_conname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.tenant_memberships DROP CONSTRAINT %I', v_conname);
    RAISE NOTICE '019: dropped legacy role CHECK constraint % on tenant_memberships', v_conname;
  ELSE
    RAISE NOTICE '019: no legacy role CHECK constraint found on tenant_memberships (already dropped?)';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.tenant_memberships_validate_role()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM public.tenant_roles tr
   WHERE tr.tenant_id = NEW.tenant_id
     AND tr.key       = NEW.role
     AND tr.is_active;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'tenant_memberships: role "%" is not an active role key for tenant %',
      NEW.role, NEW.tenant_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenant_memberships_validate_role ON public.tenant_memberships;
CREATE TRIGGER tenant_memberships_validate_role
  BEFORE INSERT OR UPDATE OF tenant_id, role ON public.tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION public.tenant_memberships_validate_role();


-- ═══════════════════════════════════════════════════════════════
-- (h) Delegation ceiling trigger: the delegator must (a) hold
-- roles.assign or be tenant_owner/tenant_admin in that tenant, AND
-- (b) effectively hold the delegated permission code themselves
-- (role grant OR explicit user grant, minus denies; delegations do
-- NOT chain). The delegatee must be a member of the tenant.
-- (user_effective_permission / user_is_tenant_admin are defined in
-- 020; the trigger body resolves them at execution time, so the
-- trigger is created here and validated on first use.)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.delegation_ceiling_check()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
BEGIN
  IF NEW.delegator_id = NEW.delegatee_id THEN
    RAISE EXCEPTION 'permission_delegations: delegator and delegatee must differ';
  END IF;
  IF NEW.expires_at IS NOT NULL AND NEW.expires_at <= NEW.starts_at THEN
    RAISE EXCEPTION 'permission_delegations: expires_at must be after starts_at';
  END IF;

  SELECT p.code INTO v_code
    FROM public.permissions p
   WHERE p.id = NEW.permission_id;
  IF v_code IS NULL THEN
    RAISE EXCEPTION 'permission_delegations: unknown permission_id %', NEW.permission_id;
  END IF;

  -- (a) delegator authority
  IF NOT (
    public.user_is_tenant_admin(NEW.tenant_id, NEW.delegator_id)
    OR public.user_effective_permission(NEW.tenant_id, NEW.delegator_id, 'roles.assign')
  ) THEN
    RAISE EXCEPTION 'permission_delegations: delegator % lacks roles.assign (or owner/admin) in tenant %',
      NEW.delegator_id, NEW.tenant_id;
  END IF;

  -- (b) delegator must effectively hold the delegated code (no chaining)
  IF NOT public.user_effective_permission(NEW.tenant_id, NEW.delegator_id, v_code) THEN
    RAISE EXCEPTION 'permission_delegations: delegator % does not effectively hold permission "%" in tenant %',
      NEW.delegator_id, v_code, NEW.tenant_id;
  END IF;

  -- delegatee must belong to the tenant
  IF NOT EXISTS (
    SELECT 1 FROM public.tenant_memberships tm
     WHERE tm.tenant_id = NEW.tenant_id
       AND tm.user_id   = NEW.delegatee_id
  ) THEN
    RAISE EXCEPTION 'permission_delegations: delegatee % is not a member of tenant %',
      NEW.delegatee_id, NEW.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS permission_delegations_ceiling ON public.permission_delegations;
CREATE TRIGGER permission_delegations_ceiling
  BEFORE INSERT OR UPDATE ON public.permission_delegations
  FOR EACH ROW EXECUTE FUNCTION public.delegation_ceiling_check();


-- ═══════════════════════════════════════════════════════════════
-- (j) protect_last_owner(): refuse to remove, deactivate, or
-- re-role the last ACTIVE tenant_owner of a tenant. This is the
-- DB backstop; the Flutter danger-zone confirmation sits in front.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.protect_last_owner()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_tenant     UUID;
  v_remaining  INT;
  v_old_is_owner BOOLEAN;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_tenant       := OLD.tenant_id;
    v_old_is_owner := OLD.is_active AND OLD.role = 'tenant_owner';
    IF NOT v_old_is_owner THEN
      RETURN OLD;
    END IF;
  ELSE -- UPDATE
    v_tenant       := OLD.tenant_id;
    v_old_is_owner := OLD.is_active AND OLD.role = 'tenant_owner';
    IF NOT v_old_is_owner THEN
      RETURN NEW;
    END IF;
    -- still an active owner after the change? then nothing is lost
    IF NEW.is_active AND NEW.role = 'tenant_owner' THEN
      RETURN NEW;
    END IF;
  END IF;

  SELECT COUNT(*) INTO v_remaining
    FROM public.tenant_memberships tm
   WHERE tm.tenant_id = v_tenant
     AND tm.is_active
     AND tm.role = 'tenant_owner'
     AND tm.id <> OLD.id;

  IF v_remaining = 0 THEN
    RAISE EXCEPTION 'tenant_memberships: cannot remove, deactivate, or re-role the last active tenant_owner of tenant %',
      v_tenant;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS tenant_memberships_protect_last_owner ON public.tenant_memberships;
CREATE TRIGGER tenant_memberships_protect_last_owner
  BEFORE UPDATE OR DELETE ON public.tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION public.protect_last_owner();


-- ═══════════════════════════════════════════════════════════════
-- (k) Auto-audit triggers: AFTER INSERT/UPDATE/DELETE on the five
-- role/permission tables → structured audit_logs rows. The trigger
-- inserts directly as SECURITY DEFINER (it deliberately does NOT
-- call public.log_audit(), whose tenant-owner/admin writer check
-- would reject legitimate writes by roles.assign holders).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.audit_role_ux_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec    RECORD;
  v_tenant UUID;
  v_eid    TEXT;
  v_action TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_rec := OLD;
  ELSE
    v_rec := NEW;
  END IF;

  v_tenant := (to_jsonb(v_rec) ->> 'tenant_id')::UUID;
  v_eid    := to_jsonb(v_rec) ->> 'id';
  IF v_eid IS NULL AND TG_TABLE_NAME = 'tenant_role_permissions' THEN
    v_eid := (to_jsonb(v_rec) ->> 'tenant_role_id') || '/'
          || (to_jsonb(v_rec) ->> 'permission_id');
  END IF;
  v_action := TG_TABLE_NAME || '.' ||
              CASE TG_OP WHEN 'INSERT' THEN 'created'
                         WHEN 'UPDATE' THEN 'updated'
                         ELSE 'deleted' END;

  INSERT INTO public.audit_logs
    (tenant_id, user_id, action, entity, entity_id, old_data, new_data)
  VALUES
    (v_tenant,
     auth.uid(),
     v_action,
     TG_TABLE_NAME,
     v_eid,
     CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
     CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS tenant_memberships_audit_ux ON public.tenant_memberships;
CREATE TRIGGER tenant_memberships_audit_ux
  AFTER INSERT OR UPDATE OR DELETE ON public.tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION public.audit_role_ux_changes();

DROP TRIGGER IF EXISTS tenant_roles_audit_ux ON public.tenant_roles;
CREATE TRIGGER tenant_roles_audit_ux
  AFTER INSERT OR UPDATE OR DELETE ON public.tenant_roles
  FOR EACH ROW EXECUTE FUNCTION public.audit_role_ux_changes();

DROP TRIGGER IF EXISTS tenant_role_permissions_audit_ux ON public.tenant_role_permissions;
CREATE TRIGGER tenant_role_permissions_audit_ux
  AFTER INSERT OR UPDATE OR DELETE ON public.tenant_role_permissions
  FOR EACH ROW EXECUTE FUNCTION public.audit_role_ux_changes();

DROP TRIGGER IF EXISTS user_permissions_audit_ux ON public.user_permissions;
CREATE TRIGGER user_permissions_audit_ux
  AFTER INSERT OR UPDATE OR DELETE ON public.user_permissions
  FOR EACH ROW EXECUTE FUNCTION public.audit_role_ux_changes();

DROP TRIGGER IF EXISTS permission_delegations_audit_ux ON public.permission_delegations;
CREATE TRIGGER permission_delegations_audit_ux
  AFTER INSERT OR UPDATE OR DELETE ON public.permission_delegations
  FOR EACH ROW EXECUTE FUNCTION public.audit_role_ux_changes();

DROP TRIGGER IF EXISTS permission_scopes_audit_ux ON public.permission_scopes;
CREATE TRIGGER permission_scopes_audit_ux
  AFTER INSERT OR UPDATE OR DELETE ON public.permission_scopes
  FOR EACH ROW EXECUTE FUNCTION public.audit_role_ux_changes();


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('019_role_ux_schema')
ON CONFLICT DO NOTHING;
