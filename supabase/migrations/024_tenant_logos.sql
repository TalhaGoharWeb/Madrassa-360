-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 024: tenant logo storage + reports toggle
--
-- Run AFTER 023.
--
-- What it does:
--   1. Adds `tenants.use_logo_on_reports` (BOOLEAN NOT NULL DEFAULT TRUE):
--      per-madrassa toggle for drawing the uploaded logo on generated
--      reports, certificates, papers and other documents. Default TRUE so
--      an uploaded logo appears on documents immediately.
--   2. Ensures the `tenant-logos` bucket exists (PUBLIC read — a madrassa
--      logo is public-facing identity printed on documents; the app loads
--      it with a plain URL via cached_network_image, and the offline
--      report cache stores a local copy per tenant).
--   3. Storage RLS policies, tenant-bound like 008_tenant_storage.sql:
--        SELECT: public read (bucket is public).
--        INSERT/UPDATE/DELETE: path tenant's first segment must be a
--          valid UUID AND (platform admin OR tenant member holding
--          `settings.update`).
--      Object layout: `{tenant_id}/logo.png` (single logo per tenant).
--
-- Deployment note: run this file in the Supabase SQL editor (or via the
-- migration runner) AND confirm the bucket is public afterwards. The app
-- also needs `tenants` UPDATE/SELECT RLS to cover the two columns; the
-- existing tenant-member policies already allow members to read their
-- tenant row and `settings.update` holders to update it.
--
-- Idempotency: ADD COLUMN IF NOT EXISTS; bucket INSERT ... ON CONFLICT
-- DO NOTHING; policies created inside DO blocks guarded by pg_policies
-- existence checks (same pattern as 008).
-- ═══════════════════════════════════════════════════════════════


-- ── 1) reports toggle on the tenant row ────────────────────────
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS use_logo_on_reports BOOLEAN NOT NULL DEFAULT TRUE;


-- ── 2) bucket (public read) ────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('tenant-logos', 'tenant-logos', TRUE)
ON CONFLICT (id) DO NOTHING;

-- If the bucket already existed as private (e.g. created by hand),
-- promote it to public so document logos resolve without signed URLs.
UPDATE storage.buckets SET public = TRUE WHERE id = 'tenant-logos';


-- ── 3) storage policies ────────────────────────────────────────
-- Reuses public.storage_path_tenant() from 008 (first path segment →
-- UUID, NULL on malformed paths so bad paths DENY instead of raising).

-- Public read: anyone can fetch a madrassa logo (printed on documents).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'tenant_logos_select_public'
  ) THEN
    CREATE POLICY "tenant_logos_select_public"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'tenant-logos');
  END IF;
END $$;

-- Writes: platform admin, or a member of the path tenant holding
-- `settings.update` (the same permission that gates the in-app
-- "مدرسے کا لوگو" screen).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'tenant_logos_insert_tenant'
  ) THEN
    CREATE POLICY "tenant_logos_insert_tenant"
      ON storage.objects FOR INSERT
      WITH CHECK (
        bucket_id = 'tenant-logos'
        AND public.storage_path_tenant(name) IS NOT NULL
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(
              public.storage_path_tenant(name), 'settings.update')
          )
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'tenant_logos_update_tenant'
  ) THEN
    CREATE POLICY "tenant_logos_update_tenant"
      ON storage.objects FOR UPDATE
      USING (
        bucket_id = 'tenant-logos'
        AND public.storage_path_tenant(name) IS NOT NULL
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(
              public.storage_path_tenant(name), 'settings.update')
          )
        )
      )
      WITH CHECK (
        bucket_id = 'tenant-logos'
        AND public.storage_path_tenant(name) IS NOT NULL
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(
              public.storage_path_tenant(name), 'settings.update')
          )
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'tenant_logos_delete_tenant'
  ) THEN
    CREATE POLICY "tenant_logos_delete_tenant"
      ON storage.objects FOR DELETE
      USING (
        bucket_id = 'tenant-logos'
        AND public.storage_path_tenant(name) IS NOT NULL
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(
              public.storage_path_tenant(name), 'settings.update')
          )
        )
      );
  END IF;
END $$;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('024_tenant_logos')
ON CONFLICT DO NOTHING;
