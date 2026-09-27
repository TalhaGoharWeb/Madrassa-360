-- 024_tenant_logo.sql
-- Madrassa logo: tenants.logo_url + tenants.use_logo_on_reports
--
-- Lets each madrassa upload its own logo (Supabase Storage `tenant-logos`
-- bucket) and choose whether it appears on generated reports / report
-- cards / receipts / papers.
--
-- Storage bucket setup (run once, via dashboard or API — NOT in this file
-- because storage.buckets lives outside the migration transaction):
--
--   1. Create bucket `tenant-logos` (public: true).
--   2. Storage RLS policies on storage.objects for bucket_id = 'tenant-logos':
--
--      -- Public read (logos appear in app UI + cached for PDFs)
--      CREATE POLICY "Public read tenant logos"
--      ON storage.objects FOR SELECT
--      USING (bucket_id = 'tenant-logos');
--
--      -- Tenant members manage their own tenant's logo only.
--      -- Path convention: tenant-logos/<tenant_id>/logo.png
--      CREATE POLICY "Tenant members upload own logo"
--      ON storage.objects FOR INSERT
--      WITH CHECK (
--        bucket_id = 'tenant-logos'
--        AND (storage.foldername(name))[1] IN (
--          SELECT tenant_id::text FROM tenant_memberships
--          WHERE user_id = auth.uid() AND is_active = true
--        )
--      );
--
--      CREATE POLICY "Tenant members update own logo"
--      ON storage.objects FOR UPDATE
--      USING (
--        bucket_id = 'tenant-logos'
--        AND (storage.foldername(name))[1] IN (
--          SELECT tenant_id::text FROM tenant_memberships
--          WHERE user_id = auth.uid() AND is_active = true
--        )
--      );
--
--      CREATE POLICY "Tenant members delete own logo"
--      ON storage.objects FOR DELETE
--      USING (
--        bucket_id = 'tenant-logos'
--        AND (storage.foldername(name))[1] IN (
--          SELECT tenant_id::text FROM tenant_memberships
--          WHERE user_id = auth.uid() AND is_active = true
--        )
--      );
--
-- Idempotent: safe to re-run.

-- 1. logo_url: public URL of the tenant's logo in the tenant-logos bucket.
--    NULL = no custom logo (app falls back to the neutral emblem).
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- 2. use_logo_on_reports: owner toggle. When FALSE, generated PDFs use the
--    neutral emblem even if a logo is uploaded.
ALTER TABLE public.tenants
  ADD COLUMN IF NOT EXISTS use_logo_on_reports BOOLEAN NOT NULL DEFAULT TRUE;

-- 3. Stamp the migration (repo convention: version column only).
INSERT INTO public.schema_migrations (version)
VALUES ('024_tenant_logo')
ON CONFLICT DO NOTHING;
