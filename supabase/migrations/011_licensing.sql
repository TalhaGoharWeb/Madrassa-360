-- ═══════════════════════════════════════════════════════════════
-- Migration 011 — Licensing (mission §§42–43)
--   * public.license_plans       — platform catalog of sellable plans
--   * public.licenses            — per-tenant license grants (limits snapshot)
--   * public.tenant_subscriptions — per-tenant subscription lifecycle
--   * RLS: platform admins manage everything; tenant admins/owners may
--     SELECT their own tenant's rows (plans catalog is authenticated-read,
--     mirroring 005's catalog-table pattern).
--   * Seed: 3 editable plans (Basic / Professional / Enterprise).
--   * Adds the platform_admins self-read policy Worker 3's Master Admin
--     guard needs ("platform_admins_self_read", guarded DO block in the
--     style of 007) — 004 only had the FOR ALL platform-admin policy, so
--     there was no way for a client to check "am I / what is my role".
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- license_plans — platform-wide sellable plans (Master-Admin editable)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.license_plans (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT        NOT NULL UNIQUE,
  description    TEXT,
  max_students   INTEGER,
  max_users      INTEGER,
  max_teachers   INTEGER,
  enabled_modules TEXT[]     NOT NULL DEFAULT '{}',
  price_monthly  NUMERIC(12,2),
  is_active      BOOLEAN     NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ═══════════════════════════════════════════════════════════════
-- licenses — per-tenant license grants (the enforced limits snapshot)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.licenses (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  plan_id         UUID        REFERENCES public.license_plans(id) ON DELETE SET NULL,
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ,
  status          TEXT        NOT NULL DEFAULT 'trial'
                  CHECK (status IN ('trial','active','grace_period','expired','suspended','cancelled')),
  max_users       INTEGER,
  max_students    INTEGER,
  enabled_modules TEXT[]     NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_licenses_tenant  ON public.licenses (tenant_id);
CREATE INDEX IF NOT EXISTS idx_licenses_status  ON public.licenses (status);


-- ═══════════════════════════════════════════════════════════════
-- tenant_subscriptions — per-tenant subscription lifecycle
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.tenant_subscriptions (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  plan_id    UUID        REFERENCES public.license_plans(id) ON DELETE SET NULL,
  status     TEXT        NOT NULL DEFAULT 'trial',
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tenant_subscriptions_tenant ON public.tenant_subscriptions (tenant_id);


-- ═══════════════════════════════════════════════════════════════
-- RLS
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.license_plans       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.licenses            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;

-- ── license_plans (platform catalog: authenticated SELECT, platform writes) ──
DROP POLICY IF EXISTS "authenticated read license plans" ON public.license_plans;
CREATE POLICY "authenticated read license plans"
  ON public.license_plans FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "platform admins manage license plans" ON public.license_plans;
CREATE POLICY "platform admins manage license plans"
  ON public.license_plans FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

-- ── licenses ──
DROP POLICY IF EXISTS "platform admins manage licenses" ON public.licenses;
CREATE POLICY "platform admins manage licenses"
  ON public.licenses FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "tenant admins read own licenses" ON public.licenses;
CREATE POLICY "tenant admins read own licenses"
  ON public.licenses FOR SELECT
  USING (public.is_tenant_admin(tenant_id));

-- ── tenant_subscriptions ──
DROP POLICY IF EXISTS "platform admins manage subscriptions" ON public.tenant_subscriptions;
CREATE POLICY "platform admins manage subscriptions"
  ON public.tenant_subscriptions FOR ALL
  USING  (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

DROP POLICY IF EXISTS "tenant admins read own subscriptions" ON public.tenant_subscriptions;
CREATE POLICY "tenant admins read own subscriptions"
  ON public.tenant_subscriptions FOR SELECT
  USING (public.is_tenant_admin(tenant_id));


-- ═══════════════════════════════════════════════════════════════
-- platform_admins self-read (Worker 3's Master Admin guard contract).
-- 004 only shipped the FOR ALL "platform admins only" policy, so a client
-- had no way to read its own row (role: platform_owner vs platform_support).
-- Guarded DO block (007 pattern): creates only if absent.
-- ═══════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'platform_admins'
      AND policyname = 'platform_admins_self_read'
  ) THEN
    CREATE POLICY "platform_admins_self_read"
      ON public.platform_admins FOR SELECT
      USING (user_id = auth.uid());
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- Seed plans — EDITABLE SEED DATA (Master Admin may change names, limits,
-- module sets and prices in the UI; rows are the defaults only).
-- Module codes come from the 17-module catalog in 003_tenant_modules.sql.
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.license_plans
  (name, description, max_students, max_users, max_teachers, enabled_modules, price_monthly)
VALUES
  ('Basic',
   'Entry plan for small madrasas — core academic + finance + parent portal modules.',
   200, 10, 25,
   ARRAY['students','teachers','attendance','academics','exams','results','fees','parents','notifications','reports'],
   1499.00),
  ('Professional',
   'Full operational plan — adds staff, library, documents and certificates.',
   1000, 50, 100,
   ARRAY['students','staff','teachers','attendance','academics','exams','results','fees','parents','notifications','reports','documents','certificates','library'],
   4999.00),
  ('Enterprise',
   'Everything — all 17 modules for large institutions and networks.',
   5000, 200, 300,
   ARRAY['students','staff','teachers','attendance','academics','exams','results','fees','finance','library','hostel','transport','parents','notifications','reports','documents','certificates'],
   9999.00)
ON CONFLICT (name) DO NOTHING;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('011_licensing')
ON CONFLICT DO NOTHING;
