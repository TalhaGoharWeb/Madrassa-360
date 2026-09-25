-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 015: parent/teacher link tables
-- Phase 4 — parent & teacher portal scoping.
--
-- What it does:
--   (a) Creates public.student_guardians — the ENFORCED parent↔child
--       link. The legacy students.parent_user_id single-column link is
--       retained for compatibility (007 RLS fallbacks still reference
--       it), but it is not a link table: one parent per student, no
--       relationship tracking, no integrity enforcement. New code MUST
--       join through student_guardians.
--       Backfill: one 'father'/'other'-labelled primary guardian row per
--       legacy parent_user_id that resolves to a real auth.users row.
--   (b) Creates public.teacher_class_assignments — the ENFORCED
--       teacher↔class link. Previously there was NO assignment table at
--       all; teacher screens loaded all classes/students client-side.
--   (c) RLS on both tables (DB is the single enforcement point):
--       guardians/teachers can SELECT only their own rows within tenants
--       they belong to; only tenant admins (+ platform admins) manage.
--   (d) tenant_id immutability trigger (same as the 13 business tables).
--   (e) Version stamp in public.schema_migrations.
--
-- Run AFTER 013. Does not depend on 014 (whatever it ends up being).
--
-- Idempotent: IF NOT EXISTS / OR REPLACE / DROP ... IF EXISTS /
--             ON CONFLICT DO NOTHING / policy blocks guarded by
--             pg_policies existence checks.
-- ═══════════════════════════════════════════════════════════════


-- ── student_guardians ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.student_guardians (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID        NOT NULL
                                REFERENCES public.tenants(id)
                                ON DELETE RESTRICT,
  student_id       UUID        NOT NULL
                                REFERENCES public.students(id)
                                ON DELETE CASCADE,
  guardian_user_id UUID        NOT NULL
                                REFERENCES auth.users(id)
                                ON DELETE CASCADE,
  relationship     TEXT        NOT NULL DEFAULT 'guardian'
                                CHECK (relationship IN
                                  ('father','mother','guardian','sponsor','other')),
  is_primary       BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT student_guardians_unique
    UNIQUE (tenant_id, student_id, guardian_user_id)
);


-- ── teacher_class_assignments ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.teacher_class_assignments (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID        NOT NULL
                               REFERENCES public.tenants(id)
                               ON DELETE RESTRICT,
  teacher_user_id UUID        NOT NULL
                               REFERENCES auth.users(id)
                               ON DELETE CASCADE,
  class_id        UUID        NOT NULL
                               REFERENCES public.classes(id)
                               ON DELETE CASCADE,
  subject         TEXT        NOT NULL DEFAULT '',
  academic_year   TEXT,
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT teacher_class_assignments_unique
    UNIQUE (tenant_id, teacher_user_id, class_id, subject)
);


-- ── indexes (009 naming: idx_<table>_<key>) ─────────────────────
CREATE INDEX IF NOT EXISTS idx_student_guardians_tenant
  ON public.student_guardians (tenant_id);
CREATE INDEX IF NOT EXISTS idx_student_guardians_user
  ON public.student_guardians (guardian_user_id);
CREATE INDEX IF NOT EXISTS idx_student_guardians_tenant_student
  ON public.student_guardians (tenant_id, student_id);
CREATE INDEX IF NOT EXISTS idx_teacher_class_assignments_tenant
  ON public.teacher_class_assignments (tenant_id);
CREATE INDEX IF NOT EXISTS idx_teacher_class_assignments_user
  ON public.teacher_class_assignments (teacher_user_id);
CREATE INDEX IF NOT EXISTS idx_teacher_class_assignments_tenant_class
  ON public.teacher_class_assignments (tenant_id, class_id);


-- ── tenant_id immutability (006 helper) ────────────────────────
DO $$
BEGIN
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change
    ON public.student_guardians;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.student_guardians
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change
    ON public.teacher_class_assignments;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.teacher_class_assignments
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();
END $$;


-- ── backfill from legacy students.parent_user_id ───────────────
-- One primary guardian row per non-null parent_user_id that resolves to
-- a real auth.users row. Idempotent (UNIQUE + ON CONFLICT DO NOTHING).
INSERT INTO public.student_guardians
  (tenant_id, student_id, guardian_user_id, relationship, is_primary)
SELECT s.tenant_id, s.id, s.parent_user_id, 'other', TRUE
FROM public.students s
WHERE s.parent_user_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.parent_user_id)
  AND s.tenant_id IS NOT NULL
ON CONFLICT ON CONSTRAINT student_guardians_unique DO NOTHING;


-- ── RLS ────────────────────────────────────────────────────────
ALTER TABLE public.student_guardians ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_class_assignments ENABLE ROW LEVEL SECURITY;

-- student_guardians: guardians see only their own rows in tenants they
-- belong to; tenant admins (and platform admins) manage everything.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='student_guardians'
                   AND policyname='student_guardians_select_tenant') THEN
    CREATE POLICY "student_guardians_select_tenant"
      ON public.student_guardians FOR SELECT USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(student_guardians.tenant_id)
        OR (
          student_guardians.guardian_user_id = auth.uid()
          AND public.is_tenant_member(student_guardians.tenant_id)
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='student_guardians'
                   AND policyname='student_guardians_insert_tenant') THEN
    CREATE POLICY "student_guardians_insert_tenant"
      ON public.student_guardians FOR INSERT WITH CHECK (
        public.is_platform_admin()
        OR public.is_tenant_admin(student_guardians.tenant_id)
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='student_guardians'
                   AND policyname='student_guardians_update_tenant') THEN
    CREATE POLICY "student_guardians_update_tenant"
      ON public.student_guardians FOR UPDATE
      USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(student_guardians.tenant_id)
      )
      WITH CHECK (
        public.is_platform_admin()
        OR public.is_tenant_admin(student_guardians.tenant_id)
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='student_guardians'
                   AND policyname='student_guardians_delete_tenant') THEN
    CREATE POLICY "student_guardians_delete_tenant"
      ON public.student_guardians FOR DELETE USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(student_guardians.tenant_id)
      );
  END IF;
END $$;

-- teacher_class_assignments: teachers see only their own assignments in
-- tenants they belong to; tenant admins (and platform admins) manage.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public'
                   AND tablename='teacher_class_assignments'
                   AND policyname='teacher_class_assignments_select_tenant') THEN
    CREATE POLICY "teacher_class_assignments_select_tenant"
      ON public.teacher_class_assignments FOR SELECT USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(teacher_class_assignments.tenant_id)
        OR (
          teacher_class_assignments.teacher_user_id = auth.uid()
          AND public.is_tenant_member(teacher_class_assignments.tenant_id)
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public'
                   AND tablename='teacher_class_assignments'
                   AND policyname='teacher_class_assignments_insert_tenant') THEN
    CREATE POLICY "teacher_class_assignments_insert_tenant"
      ON public.teacher_class_assignments FOR INSERT WITH CHECK (
        public.is_platform_admin()
        OR public.is_tenant_admin(teacher_class_assignments.tenant_id)
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public'
                   AND tablename='teacher_class_assignments'
                   AND policyname='teacher_class_assignments_update_tenant') THEN
    CREATE POLICY "teacher_class_assignments_update_tenant"
      ON public.teacher_class_assignments FOR UPDATE
      USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(teacher_class_assignments.tenant_id)
      )
      WITH CHECK (
        public.is_platform_admin()
        OR public.is_tenant_admin(teacher_class_assignments.tenant_id)
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public'
                   AND tablename='teacher_class_assignments'
                   AND policyname='teacher_class_assignments_delete_tenant') THEN
    CREATE POLICY "teacher_class_assignments_delete_tenant"
      ON public.teacher_class_assignments FOR DELETE USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(teacher_class_assignments.tenant_id)
      );
  END IF;
END $$;


-- ── fail-loud verification (007 convention) ────────────────────
DO $$
DECLARE
  v_missing TEXT[];
BEGIN
  SELECT array_agg(p)
  INTO v_missing
  FROM unnest(ARRAY[
    'public.student_guardians.student_guardians_select_tenant',
    'public.student_guardians.student_guardians_insert_tenant',
    'public.student_guardians.student_guardians_update_tenant',
    'public.student_guardians.student_guardians_delete_tenant',
    'public.teacher_class_assignments.teacher_class_assignments_select_tenant',
    'public.teacher_class_assignments.teacher_class_assignments_insert_tenant',
    'public.teacher_class_assignments.teacher_class_assignments_update_tenant',
    'public.teacher_class_assignments.teacher_class_assignments_delete_tenant'
  ]) AS p
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_policies pol
    WHERE pol.schemaname = split_part(p, '.', 1)
      AND pol.tablename  = split_part(p, '.', 2)
      AND pol.policyname = split_part(p, '.', 3)
  );
  IF v_missing IS NOT NULL AND array_length(v_missing, 1) > 0 THEN
    RAISE EXCEPTION '015: missing policies: %', array_to_string(v_missing, ', ');
  END IF;
END $$;


-- ── version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('015_parent_links')
ON CONFLICT DO NOTHING;
