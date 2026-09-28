-- ═══════════════════════════════════════════════════════════════
-- Migration 001 — Tenant core
--   * public.schema_migrations version ledger
--   * public.slugify(text) helper
--   * public.tenants (canonical multi-tenant root)
--   * BEFORE INSERT slug trigger + updated_at trigger
--   * RLS enabled; platform-admin-only policy here.
--     (Member read access is added in 004_memberships.sql, after the
--      is_tenant_member() helper exists.)
--
-- Idempotent: safe to re-run (IF NOT EXISTS / OR REPLACE / DROP IF EXISTS).
-- ═══════════════════════════════════════════════════════════════


-- ── Version ledger ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.schema_migrations (
  version    TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ── slugify helper ─────────────────────────────────────────────
-- Lowercases, collapses non [a-z0-9] runs to a single dash, trims dashes.
-- Pure-non-Latin input (e.g. Urdu-only names) yields '' — the trigger then
-- falls back to 'tenant'.
CREATE OR REPLACE FUNCTION public.slugify(p_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v TEXT;
BEGIN
  v := lower(trim(coalesce(p_text, '')));
  v := regexp_replace(v, '[^a-z0-9]+', '-', 'g');
  v := regexp_replace(v, '^-+|-+$', '', 'g');
  RETURN nullif(v, '');
END;
$$;


-- ── tenants ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tenants (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_code         TEXT        NOT NULL UNIQUE
                        DEFAULT ('T-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  name                TEXT        NOT NULL,
  name_urdu           TEXT,
  slug                TEXT        NOT NULL UNIQUE,
  logo_url            TEXT,
  favicon_url         TEXT,
  address             TEXT,
  city                TEXT,
  district            TEXT,
  province            TEXT,
  country             TEXT        NOT NULL DEFAULT 'Pakistan',
  phone               TEXT,
  email               TEXT,
  website             TEXT,
  principal_name      TEXT,
  registration_number TEXT,
  status              TEXT        NOT NULL DEFAULT 'trial'
                        CHECK (status IN ('trial','active','suspended','expired','cancelled','archived')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tenants_status ON public.tenants (status);
CREATE INDEX IF NOT EXISTS idx_tenants_city   ON public.tenants (city);


-- BEFORE INSERT: fill slug from name, guaranteeing uniqueness (-2, -3, …).
-- An explicitly provided slug is respected as-is.
CREATE OR REPLACE FUNCTION public.trg_tenants_fill_slug()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_base      TEXT;
  v_candidate TEXT;
  v_n         INT := 1;
BEGIN
  IF NEW.slug IS NULL OR btrim(NEW.slug) = '' THEN
    v_base := public.slugify(NEW.name);
    IF v_base IS NULL OR v_base = '' THEN
      v_base := 'tenant';
    END IF;
    v_candidate := v_base;
    WHILE EXISTS (SELECT 1 FROM public.tenants t WHERE t.slug = v_candidate AND t.id <> NEW.id) LOOP
      v_n := v_n + 1;
      v_candidate := v_base || '-' || v_n;
    END LOOP;
    NEW.slug := v_candidate;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenants_fill_slug ON public.tenants;
CREATE TRIGGER tenants_fill_slug
  BEFORE INSERT ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.trg_tenants_fill_slug();

-- updated_at maintenance. (The old 01_schema.sql:45 this comment once pointed
-- at is not part of this migration set, so the function is defined here —
-- idempotent, safe to re-run.)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenants_set_updated_at ON public.tenants;
CREATE TRIGGER tenants_set_updated_at
  BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ── RLS ────────────────────────────────────────────────────────
-- NOTE: public.is_platform_admin() at this point is the legacy 06_rbac.sql
-- version (profiles.role IN ('superAdmin','franchiseManager')). It is
-- redefined against public.platform_admins in 004_memberships.sql; policies
-- are evaluated at query time, so they pick up the new definition.
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform admins manage tenants" ON public.tenants;
CREATE POLICY "platform admins manage tenants"
  ON public.tenants FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- Member read policy ("members read own tenants") is added in
-- 004_memberships.sql after is_tenant_member() is defined.


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('001_tenant_core')
ON CONFLICT DO NOTHING;
