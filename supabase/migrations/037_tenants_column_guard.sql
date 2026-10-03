-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 037: tenants column guard
--
-- SEC-H6 (half): the 027 tenants_member_update RLS policy gates on
-- settings.update but restricts NO columns — RLS cannot do column
-- grants. Any settings.update holder could PATCH status/suspended/
-- expires_at/tenant_code/slug/logo_url and un-suspend their own
-- tenant or poison the tenant row (logo_url → arbitrary URL fetched
-- unboundedly by every device: OOM/SSRF).
--
-- tenants_column_guard() BEFORE UPDATE: strict allow-list for tenant
-- callers (name, name_urdu, contact fields, use_logo_on_reports);
-- logo_url only to the tenant's own storage logo prefix; everything
-- else (status, suspended, expires_at, tenant_code, slug,
-- registration_number, admin_message*, suspension_* , favicon_url)
-- is platform-admin-only. Defense in depth: also requires
-- settings.update for any tenant-caller write (behind the RLS policy).
-- Seeds / service_role (no JWT) bypass — service_role bypasses RLS
-- regardless, and the upload Edge Function will own logo_url writes.
--
-- Trigger name sorts before tenants_set_updated_at, so the updated_at
-- maintenance trigger is unaffected (updated_at is exempted anyway).
--
-- Idempotent: DROP TRIGGER IF EXISTS / CREATE OR REPLACE.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tenants_column_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Seeds / service_role automations run without a JWT.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- Platform admins: no column restrictions (001's policy already
  -- gates the row).
  IF public.is_platform_admin() THEN
    RETURN NEW;
  END IF;

  -- Any other tenant-caller write needs settings.update (the RLS
  -- policy checks this too; the trigger is the backstop).
  IF NOT public.tenant_has_permission(OLD.id, 'settings.update') THEN
    RAISE EXCEPTION 'tenants: requires settings.update in tenant %', OLD.id;
  END IF;

  -- logo_url: only the tenant's own storage logo prefix.
  IF NEW.logo_url IS DISTINCT FROM OLD.logo_url THEN
    IF NEW.logo_url IS NOT NULL AND btrim(NEW.logo_url) <> ''
       AND NEW.logo_url NOT LIKE '%tenant-logos/' || OLD.id::text || '/%' THEN
      RAISE EXCEPTION 'tenants: logo_url must point at this tenant''s own logo storage prefix';
    END IF;
  END IF;

  -- Strict allow-list: anything not listed here is platform-only.
  IF (NEW.name              IS DISTINCT FROM OLD.name)
     OR (NEW.name_urdu      IS DISTINCT FROM OLD.name_urdu)
     OR (NEW.address        IS DISTINCT FROM OLD.address)
     OR (NEW.city           IS DISTINCT FROM OLD.city)
     OR (NEW.district       IS DISTINCT FROM OLD.district)
     OR (NEW.province       IS DISTINCT FROM OLD.province)
     OR (NEW.country        IS DISTINCT FROM OLD.country)
     OR (NEW.phone          IS DISTINCT FROM OLD.phone)
     OR (NEW.email          IS DISTINCT FROM OLD.email)
     OR (NEW.website        IS DISTINCT FROM OLD.website)
     OR (NEW.principal_name IS DISTINCT FROM OLD.principal_name)
     OR (NEW.use_logo_on_reports IS DISTINCT FROM OLD.use_logo_on_reports)
     OR (NEW.updated_at     IS DISTINCT FROM OLD.updated_at) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'tenants: only a platform admin may change status, suspension, license, code, slug, registration, broadcast, or favicon fields';
END;
$$;

DROP TRIGGER IF EXISTS tenants_column_guard ON public.tenants;
CREATE TRIGGER tenants_column_guard
  BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.tenants_column_guard();


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('037_tenants_column_guard')
ON CONFLICT DO NOTHING;
