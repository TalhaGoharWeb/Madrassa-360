-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 008: tenant-scoped storage
-- Phase 2 / Author B
--
-- Run AFTER 007.
--
-- What it does:
--   1. Ensures the three buckets exist (all private):
--        student-photos, staff-photos, documents
--   2. DROPs all 13 legacy storage policies by exact verified name
--      (03_storage.sql — verified by grep).
--   3. New object layout: {tenant_id}/{...} as the first path segment.
--   4. Recreates per-bucket policies keyed on the tenant extracted from
--      the object path:
--        SELECT: bucket matches AND caller is a member of the path tenant.
--        INSERT/UPDATE/DELETE: same path check AND
--          (is_platform_admin() OR tenant_has_permission(path_tenant,
--           '<mod>.update')) with <mod> = students (student-photos),
--           staff (staff-photos), documents (documents.* -> 'documents.manage').
--
-- The text->uuid cast is guarded by a UUID regex so malformed paths DENY
-- instead of raising.
--
-- Idempotency: bucket INSERT ... ON CONFLICT DO NOTHING; legacy drops are
-- DROP POLICY IF EXISTS; new policies are created inside DO blocks guarded
-- by pg_policies existence checks.
-- ═══════════════════════════════════════════════════════════════


-- ── 1) buckets (all private) ─────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('student-photos', 'student-photos', FALSE),
  ('staff-photos',   'staff-photos',   FALSE),
  ('documents',      'documents',      FALSE)
ON CONFLICT (id) DO NOTHING;


-- ── 2) legacy sweep — exact verified names from 03_storage.sql ─
DROP POLICY IF EXISTS "student_photos_admin_insert" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_admin_update" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_auth_select"  ON storage.objects;
DROP POLICY IF EXISTS "student_photos_admin_delete" ON storage.objects;

DROP POLICY IF EXISTS "staff_photos_admin_insert" ON storage.objects;
DROP POLICY IF EXISTS "staff_photos_admin_update" ON storage.objects;
DROP POLICY IF EXISTS "staff_photos_auth_select"  ON storage.objects;
DROP POLICY IF EXISTS "staff_photos_admin_delete" ON storage.objects;

DROP POLICY IF EXISTS "documents_admin_insert"  ON storage.objects;
DROP POLICY IF EXISTS "documents_admin_update"  ON storage.objects;
DROP POLICY IF EXISTS "documents_staff_select"  ON storage.objects;
DROP POLICY IF EXISTS "documents_parent_select" ON storage.objects;
DROP POLICY IF EXISTS "documents_admin_delete"  ON storage.objects;


-- ── 3) helper: tenant uuid from the first path segment ────────
-- Returns NULL for malformed paths (deny, don't error).
CREATE OR REPLACE FUNCTION public.storage_path_tenant(p_object_name TEXT)
RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN (storage.foldername(p_object_name))[1]
         ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    THEN ((storage.foldername(p_object_name))[1])::uuid
    ELSE NULL
  END;
$$;


ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;


-- ── 4) new tenant-bound storage policies ──────────────────────

-- student-photos: read = tenant members; write = students.update ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='student_photos_select_tenant') THEN
    CREATE POLICY "student_photos_select_tenant"
      ON storage.objects FOR SELECT
      USING (
        bucket_id = 'student-photos'
        AND public.is_tenant_member(public.storage_path_tenant(name))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='student_photos_insert_tenant') THEN
    CREATE POLICY "student_photos_insert_tenant"
      ON storage.objects FOR INSERT
      WITH CHECK (
        bucket_id = 'student-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'students.update')
          )
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='student_photos_update_tenant') THEN
    CREATE POLICY "student_photos_update_tenant"
      ON storage.objects FOR UPDATE
      USING (
        bucket_id = 'student-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'students.update')
          )
        )
      )
      WITH CHECK (
        bucket_id = 'student-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'students.update')
          )
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='student_photos_delete_tenant') THEN
    CREATE POLICY "student_photos_delete_tenant"
      ON storage.objects FOR DELETE
      USING (
        bucket_id = 'student-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'students.update')
          )
        )
      );
  END IF;
END $$;


-- staff-photos: read = tenant members; write = staff.update ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='staff_photos_select_tenant') THEN
    CREATE POLICY "staff_photos_select_tenant"
      ON storage.objects FOR SELECT
      USING (
        bucket_id = 'staff-photos'
        AND public.is_tenant_member(public.storage_path_tenant(name))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='staff_photos_insert_tenant') THEN
    CREATE POLICY "staff_photos_insert_tenant"
      ON storage.objects FOR INSERT
      WITH CHECK (
        bucket_id = 'staff-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'staff.update')
          )
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='staff_photos_update_tenant') THEN
    CREATE POLICY "staff_photos_update_tenant"
      ON storage.objects FOR UPDATE
      USING (
        bucket_id = 'staff-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'staff.update')
          )
        )
      )
      WITH CHECK (
        bucket_id = 'staff-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'staff.update')
          )
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='staff_photos_delete_tenant') THEN
    CREATE POLICY "staff_photos_delete_tenant"
      ON storage.objects FOR DELETE
      USING (
        bucket_id = 'staff-photos'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'staff.update')
          )
        )
      );
  END IF;
END $$;


-- documents: read = tenant members; write = documents.manage ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='documents_select_tenant') THEN
    CREATE POLICY "documents_select_tenant"
      ON storage.objects FOR SELECT
      USING (
        bucket_id = 'documents'
        AND public.is_tenant_member(public.storage_path_tenant(name))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='documents_insert_tenant') THEN
    CREATE POLICY "documents_insert_tenant"
      ON storage.objects FOR INSERT
      WITH CHECK (
        bucket_id = 'documents'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'documents.manage')
          )
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='documents_update_tenant') THEN
    CREATE POLICY "documents_update_tenant"
      ON storage.objects FOR UPDATE
      USING (
        bucket_id = 'documents'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'documents.manage')
          )
        )
      )
      WITH CHECK (
        bucket_id = 'documents'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'documents.manage')
          )
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='documents_delete_tenant') THEN
    CREATE POLICY "documents_delete_tenant"
      ON storage.objects FOR DELETE
      USING (
        bucket_id = 'documents'
        AND (
          public.is_platform_admin()
          OR (
            public.is_tenant_member(public.storage_path_tenant(name))
            AND public.tenant_has_permission(public.storage_path_tenant(name), 'documents.manage')
          )
        )
      );
  END IF;
END $$;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('008_tenant_storage') ON CONFLICT DO NOTHING;
