-- ═══════════════════════════════════════════════════════════════
-- Migration 002 — Tenant settings
--   * public.tenant_settings (one row per tenant)
--   * AFTER INSERT trigger on tenants → auto-create default settings row
--   * RLS enabled; platform-admin-only policy here.
--     Member read + tenant-admin write policies are added in
--     004_memberships.sql (needs is_tenant_member()/is_tenant_admin()).
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


CREATE TABLE IF NOT EXISTS public.tenant_settings (
  tenant_id          UUID        PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
  language           TEXT        NOT NULL DEFAULT 'ur',
  timezone           TEXT        NOT NULL DEFAULT 'Asia/Karachi',
  currency           TEXT        NOT NULL DEFAULT 'PKR',
  date_format        TEXT        NOT NULL DEFAULT 'dd-MM-yyyy',
  academic_year      TEXT,
  theme              TEXT        NOT NULL DEFAULT 'light',
  primary_color      TEXT        NOT NULL DEFAULT '#0E7C5B',
  secondary_color    TEXT,
  accent_color       TEXT,
  font               TEXT        NOT NULL DEFAULT 'JameelNooriNastaleeq',
  dark_mode_enabled  BOOLEAN     NOT NULL DEFAULT false,
  receipt_header     TEXT,
  receipt_footer     TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- Auto-create a default settings row for every new tenant.
CREATE OR REPLACE FUNCTION public.trg_tenants_create_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.tenant_settings (tenant_id)
  VALUES (NEW.id)
  ON CONFLICT (tenant_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenants_create_settings ON public.tenants;
CREATE TRIGGER tenants_create_settings
  AFTER INSERT ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.trg_tenants_create_settings();

DROP TRIGGER IF EXISTS tenant_settings_set_updated_at ON public.tenant_settings;
CREATE TRIGGER tenant_settings_set_updated_at
  BEFORE UPDATE ON public.tenant_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ── RLS ────────────────────────────────────────────────────────
ALTER TABLE public.tenant_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform admins manage tenant settings" ON public.tenant_settings;
CREATE POLICY "platform admins manage tenant settings"
  ON public.tenant_settings FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- 004_memberships.sql adds:
--   "members read tenant settings"      FOR SELECT (is_tenant_member)
--   "tenant admins manage tenant settings" FOR ALL (is_tenant_admin)


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('002_tenant_settings')
ON CONFLICT DO NOTHING;
