-- ═══════════════════════════════════════════════════════════════
-- Madrasa 360 — Storage Buckets & Policies
-- Phase 4: Run AFTER 02_rls.sql in Supabase → SQL Editor
--
-- NOTE: Create buckets first via Supabase Dashboard → Storage,
-- then run this SQL to apply the access policies.
--
-- Buckets to create manually (Dashboard → Storage → New bucket):
--   1. student-photos  | Private
--   2. staff-photos    | Private
--   3. documents       | Private
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────
-- student-photos
-- ─────────────────────────────────────────────

-- Admins can upload student photos
DROP POLICY IF EXISTS "student_photos_admin_insert" ON storage.objects;
CREATE POLICY "student_photos_admin_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'student-photos'
    AND public.get_user_role() = 'admin'
  );

-- Admins can update (replace) student photos
DROP POLICY IF EXISTS "student_photos_admin_update" ON storage.objects;
CREATE POLICY "student_photos_admin_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'student-photos'
    AND public.get_user_role() = 'admin'
  );

-- All authenticated users can view student photos
DROP POLICY IF EXISTS "student_photos_auth_select" ON storage.objects;
CREATE POLICY "student_photos_auth_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'student-photos'
    AND auth.role() = 'authenticated'
  );

-- Admins can delete student photos
DROP POLICY IF EXISTS "student_photos_admin_delete" ON storage.objects;
CREATE POLICY "student_photos_admin_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'student-photos'
    AND public.get_user_role() = 'admin'
  );


-- ─────────────────────────────────────────────
-- staff-photos
-- ─────────────────────────────────────────────

DROP POLICY IF EXISTS "staff_photos_admin_insert" ON storage.objects;
CREATE POLICY "staff_photos_admin_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'staff-photos'
    AND public.get_user_role() = 'admin'
  );

DROP POLICY IF EXISTS "staff_photos_admin_update" ON storage.objects;
CREATE POLICY "staff_photos_admin_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'staff-photos'
    AND public.get_user_role() = 'admin'
  );

DROP POLICY IF EXISTS "staff_photos_auth_select" ON storage.objects;
CREATE POLICY "staff_photos_auth_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'staff-photos'
    AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "staff_photos_admin_delete" ON storage.objects;
CREATE POLICY "staff_photos_admin_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'staff-photos'
    AND public.get_user_role() = 'admin'
  );


-- ─────────────────────────────────────────────
-- documents  (fee receipts, reports, PDFs)
-- ─────────────────────────────────────────────

-- Admins can upload documents
DROP POLICY IF EXISTS "documents_admin_insert" ON storage.objects;
CREATE POLICY "documents_admin_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'documents'
    AND public.get_user_role() = 'admin'
  );

DROP POLICY IF EXISTS "documents_admin_update" ON storage.objects;
CREATE POLICY "documents_admin_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'documents'
    AND public.get_user_role() = 'admin'
  );

-- Admins and teachers can read documents
DROP POLICY IF EXISTS "documents_staff_select" ON storage.objects;
CREATE POLICY "documents_staff_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'documents'
    AND public.get_user_role() IN ('admin', 'teacher')
  );

-- Parents can only read documents under their own student folder
-- Files should be stored as: documents/students/{student_id}/{filename}
DROP POLICY IF EXISTS "documents_parent_select" ON storage.objects;
CREATE POLICY "documents_parent_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'documents'
    AND public.get_user_role() = 'parent'
    AND (storage.foldername(name))[2] IN (
      SELECT id::TEXT FROM public.students
      WHERE parent_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "documents_admin_delete" ON storage.objects;
CREATE POLICY "documents_admin_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'documents'
    AND public.get_user_role() = 'admin'
  );
