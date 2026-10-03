-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 040: storage policy tightening
--
-- SEC-H9: the export-tenant Edge Function writes full-tenant PII dumps
-- to a `tenant-exports` bucket that exists NOWHERE in version control —
-- either broken or manually created with unknown policies. Create it
-- PRIVATE with platform-admin-only policies here.
-- Photo SELECT alignment: student-photos / staff-photos SELECT allowed
-- any tenant member; align with the row policies (students.view, or the
-- parent of the photographed student; staff.view).
-- The `documents` bucket is unwired (no app or function code references
-- it; verified 2026-10-03) — drop it to remove unused attack surface.
--
-- Idempotent: ON CONFLICT DO NOTHING / DROP POLICY IF EXISTS.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) tenant-exports: private, platform-admin-only ───────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('tenant-exports', 'tenant-exports', FALSE)
ON CONFLICT (id) DO NOTHING;

-- If it was created manually as public, force it private.
UPDATE storage.buckets SET public = FALSE WHERE id = 'tenant-exports';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
                 AND policyname='tenant_exports_platform_all') THEN
    CREATE POLICY "tenant_exports_platform_all"
      ON storage.objects FOR ALL
      USING (bucket_id = 'tenant-exports' AND public.is_platform_admin())
      WITH CHECK (bucket_id = 'tenant-exports' AND public.is_platform_admin());
  END IF;
END $$;


-- ── (b) photo SELECT aligned with row policies ─────────────────
-- Path convention (app): <tenant_id>/students/<student_id>.<ext>
--                        <tenant_id>/staff/<staff_id>.<ext>
CREATE OR REPLACE FUNCTION public.storage_photo_student_id(p_name TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN split_part((storage.foldername(p_name))[3], '.', 1)
         ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    THEN (split_part((storage.foldername(p_name))[3], '.', 1))::uuid
    ELSE NULL
  END;
$$;

DROP POLICY IF EXISTS "student_photos_select_tenant" ON storage.objects;
CREATE POLICY "student_photos_select_tenant"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'student-photos'
    AND (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(public.storage_path_tenant(name))
        AND (
          public.tenant_has_permission(public.storage_path_tenant(name), 'students.view')
          OR EXISTS (
            SELECT 1 FROM public.students s
            WHERE s.id = public.storage_photo_student_id(name)
              AND s.tenant_id = public.storage_path_tenant(name)
              AND s.parent_user_id = auth.uid()
          )
        )
      )
    )
  );

DROP POLICY IF EXISTS "staff_photos_select_tenant" ON storage.objects;
CREATE POLICY "staff_photos_select_tenant"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'staff-photos'
    AND (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(public.storage_path_tenant(name))
        AND public.tenant_has_permission(public.storage_path_tenant(name), 'staff.view')
      )
    )
  );


-- ── (c) drop the unwired `documents` bucket ────────────────────
-- Verified 2026-10-03: no Flutter or Edge Function code references this
-- bucket. Its tenant-bound policies were sound, but unused storage
-- surface is still surface.
DO $$
BEGIN
  DELETE FROM storage.objects WHERE bucket_id = 'documents';
  DELETE FROM storage.buckets WHERE id = 'documents';
EXCEPTION WHEN OTHERS THEN
  -- Best-effort: never fail the migration over bucket cleanup.
  RAISE NOTICE '040: documents bucket cleanup skipped: %', SQLERRM;
END $$;

DROP POLICY IF EXISTS "documents_select_tenant" ON storage.objects;
DROP POLICY IF EXISTS "documents_insert_tenant" ON storage.objects;
DROP POLICY IF EXISTS "documents_update_tenant" ON storage.objects;
DROP POLICY IF EXISTS "documents_delete_tenant" ON storage.objects;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('040_storage_policies')
ON CONFLICT DO NOTHING;
