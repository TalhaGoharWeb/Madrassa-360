-- ═══════════════════════════════════════════════════════════════
-- Migration 003 — Tenant modules
--   * public.modules_catalog (platform-wide module registry)
--   * public.tenant_modules (per-tenant enable/disable)
--   * AFTER INSERT trigger on tenants → enable the default module set
--   * RLS enabled; platform-admin-only policy here.
--     Member read + tenant-admin write policies are added in
--     004_memberships.sql (needs is_tenant_member()/is_tenant_admin()).
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ── Module catalog (platform-wide, tenant-agnostic) ─────────────
CREATE TABLE IF NOT EXISTS public.modules_catalog (
  module      TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  name_urdu   TEXT,
  description TEXT
);

INSERT INTO public.modules_catalog (module, name, name_urdu, description) VALUES
  ('students',      'Students',      'طلبہ',        'Student records and admissions data'),
  ('staff',         'Staff',         'عملہ',         'Non-teaching staff records'),
  ('teachers',      'Teachers',      'اساتذہ',       'Teaching staff records'),
  ('attendance',    'Attendance',    'حاضری',        'Daily attendance marking'),
  ('academics',     'Academics',     'تعلیمیات',      'Classes, darjas and academic structure'),
  ('exams',         'Exams',         'امتحانات',     'Exam scheduling and management'),
  ('results',       'Results',       'نتائج',        'Exam results and report cards'),
  ('fees',          'Fees',          'فیس',          'Fee collection and dues'),
  ('finance',       'Finance',       'مالیات',       'Income, expenses and donations'),
  ('library',       'Library',       'لائبریری',     'Books catalogue and issuance'),
  ('hostel',        'Hostel',        'ہاسٹل',        'Hostel rooms and boarders'),
  ('transport',     'Transport',     'ٹرانسپورٹ',    'Routes, vehicles and drivers'),
  ('parents',       'Parents',       'والدین',       'Parent portal and linked guardians'),
  ('notifications', 'Notifications', 'اطلاعات',      'Announcements and push notifications'),
  ('reports',       'Reports',       'رپورٹس',       'Analytics and printable reports'),
  ('documents',     'Documents',     'دستاویزات',    'File storage and document management'),
  ('certificates',  'Certificates',  'اسناد',        'Generated certificates')
ON CONFLICT (module) DO NOTHING;


-- ── Per-tenant module switches ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tenant_modules (
  tenant_id UUID    NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  module    TEXT    NOT NULL REFERENCES public.modules_catalog(module),
  enabled   BOOLEAN NOT NULL DEFAULT true,
  PRIMARY KEY (tenant_id, module)
);

CREATE INDEX IF NOT EXISTS idx_tenant_modules_tenant ON public.tenant_modules (tenant_id);


-- Enable the default module set for every new tenant.
CREATE OR REPLACE FUNCTION public.trg_tenants_enable_default_modules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.tenant_modules (tenant_id, module, enabled)
  SELECT NEW.id, m.module, true
    FROM (VALUES
      ('students'), ('teachers'), ('attendance'), ('academics'),
      ('exams'), ('results'), ('fees'), ('parents'),
      ('notifications'), ('reports')
    ) AS m(module)
  ON CONFLICT (tenant_id, module) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenants_enable_default_modules ON public.tenants;
CREATE TRIGGER tenants_enable_default_modules
  AFTER INSERT ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.trg_tenants_enable_default_modules();


-- ── RLS ────────────────────────────────────────────────────────
ALTER TABLE public.tenant_modules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform admins manage tenant modules" ON public.tenant_modules;
CREATE POLICY "platform admins manage tenant modules"
  ON public.tenant_modules FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- modules_catalog is a low-sensitivity read-mostly registry:
ALTER TABLE public.modules_catalog ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated read modules catalog" ON public.modules_catalog;
CREATE POLICY "authenticated read modules catalog"
  ON public.modules_catalog FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "platform admins manage modules catalog" ON public.modules_catalog;
CREATE POLICY "platform admins manage modules catalog"
  ON public.modules_catalog FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- 004_memberships.sql adds:
--   "members read tenant modules"      FOR SELECT (is_tenant_member)
--   "tenant admins manage tenant modules" FOR ALL (is_tenant_admin)


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('003_tenant_modules')
ON CONFLICT DO NOTHING;
