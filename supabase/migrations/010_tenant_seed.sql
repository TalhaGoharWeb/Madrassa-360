-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 010: demo tenant seed
-- Phase 2 / Author B
--
-- ═══════════════════════════════════════════════════════════════
--  DEV / STAGING ONLY — NEVER RUN IN PRODUCTION.
--  Running this in production would create a demo tenant (and demo
--  membership) inside a production database.
-- ═══════════════════════════════════════════════════════════════
--
-- Run AFTER 009. Relies on the 002/003 triggers to auto-provision
-- tenant_settings and tenant_modules for the new tenant.
--
-- Idempotent: INSERT ... ON CONFLICT DO NOTHING throughout; the DO block
-- is a safe no-op when the demo auth user does not exist yet.
-- ═══════════════════════════════════════════════════════════════


INSERT INTO public.tenants (name, name_urdu, slug, status)
VALUES ('Demo Madrasa', 'ڈیمو مدرسہ', 'demo', 'trial')
ON CONFLICT (slug) DO NOTHING;


DO $$
DECLARE
  v_demo_tenant_id UUID;
  v_demo_user_id   UUID;
BEGIN
  SELECT id INTO v_demo_tenant_id FROM public.tenants WHERE slug = 'demo';

  IF v_demo_tenant_id IS NULL THEN
    RAISE EXCEPTION '010: demo tenant was not created — aborting seed';
  END IF;

  SELECT id INTO v_demo_user_id
    FROM auth.users
   WHERE email = 'demo.admin@madrasa360.local';

  IF v_demo_user_id IS NULL THEN
    RAISE NOTICE '010: demo user not found — create it in Auth dashboard first, then re-run';
    RETURN;
  END IF;

  -- Least-privilege profile row (the signup trigger would have created
  -- this with role='student' already; this is a backstop).
  -- profiles_lock_role() permits role='student' on insert.
  INSERT INTO public.profiles (id, name, role)
  VALUES (v_demo_user_id, 'Demo Admin', 'student')
  ON CONFLICT (id) DO NOTHING;

  -- Real authority lives here: tenant_owner of the demo tenant.
  INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active)
  VALUES (v_demo_tenant_id, v_demo_user_id, 'tenant_owner', TRUE)
  ON CONFLICT DO NOTHING;

  RAISE NOTICE '010: demo tenant (%) provisioned for %', v_demo_tenant_id, 'demo.admin@madrasa360.local';
END $$;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('010_tenant_seed') ON CONFLICT DO NOTHING;
