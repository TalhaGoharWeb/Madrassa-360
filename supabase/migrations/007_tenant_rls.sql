-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 007: tenant-bound RLS rewrite
-- Phase 2 / Author B — THE critical file.
--
-- Run AFTER 006 (tenant_id columns exist and are NOT NULL).
--
-- What it does:
--   (a) DROPs every legacy policy by exact verified name (02_rls.sql: 27,
--       05_new_modules.sql §9: 11, 06_rbac.sql business tables: 30) on the
--       13 retrofit tables + profiles + madrasas. Names were verified by
--       grep against the source files — never trust a DROP list blindly.
--   (b) Recreates four tenant-bound policies per table:
--         SELECT: is_platform_admin() OR (is_tenant_member(tid) AND
--                   (tenant_has_permission(tid,'<mod>.view') OR <fallback>))
--         INSERT: is_platform_admin() OR (is_tenant_member(tid) AND
--                   tenant_has_permission(tid,'<mod>.create'))
--         UPDATE: USING = SELECT, WITH CHECK = is_platform_admin() OR
--                   (is_tenant_member(tid) AND tenant_has_permission(tid,'<mod>.update'))
--         DELETE: is_platform_admin() OR (is_tenant_member(tid) AND
--                   tenant_has_permission(tid,'<mod>.delete'))
--       Ownership fallbacks preserve the SOUND 02 patterns, now
--       tenant-bound (parents see own children; tenant members read
--       academic structure and active announcements).
--   (c) profiles: least-privilege rewrite + profiles_lock_role() trigger
--       that kills the live privilege escalation (no client role writes).
--   (d) handle_new_user(): single version, role='student' default.
--   (e) madrasas (legacy table): platform admins FOR ALL; tenant members
--       SELECT only.
--   (f) attendance_summary / fee_summary -> security_invoker = true
--       (PostgreSQL 15+ required).
--   (g) FAIL-LOUD verification: raises if any legacy policy survived.
--
-- Permission-code contract (aligned to 005_rbac.sql's 66 seeded codes —
-- verified programmatically: every code used below exists in 005):
--   students.* / staff.* / exams.* / finance.* : view/create/update/delete
--   attendance : view / mark(insert) / edit(update) / delete
--   academics  : view(select) / manage(insert+update+delete)
--   results    : view / enter(insert) / edit(update+delete — 005 has no
--                results.delete; edit is the strongest mutation code)
--   fees       : view / create(insert) / collect(update+delete — 005 has no
--                fees.update/delete; collect covers payment mutation)
--   library    : view(select) / manage(insert+update+delete)
--   notifications : view(select) / send(insert+update+delete)
--   users.view (profiles), documents.manage (008), students.update /
--   staff.update (008 photo buckets)
--
-- Idempotency: legacy drops are DROP POLICY IF EXISTS; new policies are
-- created inside DO blocks guarded by pg_policies existence checks (there
-- is no CREATE POLICY IF NOT EXISTS). No DROP of a new-policy name appears
-- in this file, so the external DROP-name cross-check stays meaningful.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) LEGACY SWEEP — drop every pre-tenant policy by exact name
-- ═══════════════════════════════════════════════════════════════

-- profiles: 5 from 02 + 3 from 06
DROP POLICY IF EXISTS "profiles_view_own"         ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"       ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_view_all"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_update_all" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own"       ON public.profiles;
DROP POLICY IF EXISTS "profiles select authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles update own"       ON public.profiles;
DROP POLICY IF EXISTS "admin manage profiles"     ON public.profiles;

-- darjas / classes (02)
DROP POLICY IF EXISTS "darjas_read"         ON public.darjas;
DROP POLICY IF EXISTS "darjas_admin_write"  ON public.darjas;
DROP POLICY IF EXISTS "classes_read"        ON public.classes;
DROP POLICY IF EXISTS "classes_admin_write" ON public.classes;

-- students: 3 from 02 + 4 from 06
DROP POLICY IF EXISTS "students_admin_all"       ON public.students;
DROP POLICY IF EXISTS "students_teacher_view"    ON public.students;
DROP POLICY IF EXISTS "students_parent_view_own" ON public.students;
DROP POLICY IF EXISTS "view_students permission"   ON public.students;
DROP POLICY IF EXISTS "create_students permission" ON public.students;
DROP POLICY IF EXISTS "edit_students permission"   ON public.students;
DROP POLICY IF EXISTS "delete_students permission" ON public.students;

-- staff: 2 from 02 + 4 from 06
DROP POLICY IF EXISTS "staff_admin_all"    ON public.staff;
DROP POLICY IF EXISTS "staff_teacher_view" ON public.staff;
DROP POLICY IF EXISTS "view_staff permission"   ON public.staff;
DROP POLICY IF EXISTS "create_staff permission" ON public.staff;
DROP POLICY IF EXISTS "edit_staff permission"   ON public.staff;
DROP POLICY IF EXISTS "delete_staff permission" ON public.staff;

-- attendance: 3 from 02 + 4 from 06
DROP POLICY IF EXISTS "attendance_admin_all"       ON public.attendance;
DROP POLICY IF EXISTS "attendance_teacher_manage"  ON public.attendance;
DROP POLICY IF EXISTS "attendance_parent_view_own" ON public.attendance;
DROP POLICY IF EXISTS "view_attendance permission"   ON public.attendance;
DROP POLICY IF EXISTS "mark_attendance permission"  ON public.attendance;
DROP POLICY IF EXISTS "edit_attendance permission"  ON public.attendance;
DROP POLICY IF EXISTS "delete_attendance permission" ON public.attendance;

-- fees: 3 from 02 + 4 from 06
DROP POLICY IF EXISTS "fees_admin_all"       ON public.fees;
DROP POLICY IF EXISTS "fees_teacher_read"    ON public.fees;
DROP POLICY IF EXISTS "fees_parent_view_own" ON public.fees;
DROP POLICY IF EXISTS "view_fees permission"   ON public.fees;
DROP POLICY IF EXISTS "create_fees permission" ON public.fees;
DROP POLICY IF EXISTS "update_fees permission" ON public.fees;
DROP POLICY IF EXISTS "delete_fees permission" ON public.fees;

-- exams / results (02; 06 never touched these)
DROP POLICY IF EXISTS "exams_read_all_auth"     ON public.exams;
DROP POLICY IF EXISTS "exams_admin_all"         ON public.exams;
DROP POLICY IF EXISTS "results_admin_all"       ON public.results;
DROP POLICY IF EXISTS "results_teacher_manage"  ON public.results;
DROP POLICY IF EXISTS "results_parent_view_own" ON public.results;

-- announcements: 2 from 02 + 1 from 05 + 4 from 06
DROP POLICY IF EXISTS "announcements_read"      ON public.announcements;
DROP POLICY IF EXISTS "announcements_admin_all" ON public.announcements;
DROP POLICY IF EXISTS "superAdmin manage announcements" ON public.announcements;
DROP POLICY IF EXISTS "view_announcements permission"   ON public.announcements;
DROP POLICY IF EXISTS "create_announcements permission" ON public.announcements;
DROP POLICY IF EXISTS "edit_announcements permission"   ON public.announcements;
DROP POLICY IF EXISTS "delete_announcements permission" ON public.announcements;

-- darja_sections (05; never superseded by 06)
DROP POLICY IF EXISTS "authenticated users read darja_sections" ON public.darja_sections;
DROP POLICY IF EXISTS "admin manage darja_sections"              ON public.darja_sections;

-- library_books: 05 pair (already dropped by 06 — kept for idempotency
-- against DBs where 06 never ran) + 06 pair
DROP POLICY IF EXISTS "authenticated read library_books" ON public.library_books;
DROP POLICY IF EXISTS "admin manage library_books"       ON public.library_books;
DROP POLICY IF EXISTS "view_library permission"          ON public.library_books;
DROP POLICY IF EXISTS "manage_library permission"        ON public.library_books;

-- book_issues: 05 pair (same idempotency note) + 06 pair
DROP POLICY IF EXISTS "authenticated read book_issues"      ON public.book_issues;
DROP POLICY IF EXISTS "admin manage book_issues"            ON public.book_issues;
DROP POLICY IF EXISTS "view_library book_issues permission"   ON public.book_issues;
DROP POLICY IF EXISTS "manage_library book_issues permission" ON public.book_issues;

-- finance_transactions: 05 pair (same idempotency note) + 06 triple
DROP POLICY IF EXISTS "authenticated read finance" ON public.finance_transactions;
DROP POLICY IF EXISTS "admin manage finance"       ON public.finance_transactions;
DROP POLICY IF EXISTS "view_finance permission"   ON public.finance_transactions;
DROP POLICY IF EXISTS "create_finance permission" ON public.finance_transactions;
DROP POLICY IF EXISTS "delete_finance permission" ON public.finance_transactions;

-- madrasas (05)
DROP POLICY IF EXISTS "superAdmin full access on madrasas" ON public.madrasas;
DROP POLICY IF EXISTS "admin sees own madrasa"             ON public.madrasas;


-- ═══════════════════════════════════════════════════════════════
-- (b) TENANT-BOUND POLICIES — four per table
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.darjas               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exams                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.results              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.darja_sections       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.library_books        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_issues          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.madrasas             ENABLE ROW LEVEL SECURITY;


-- ── darjas (academics.*) — any tenant member may read structure ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darjas' AND policyname='darjas_select_tenant') THEN
    CREATE POLICY "darjas_select_tenant" ON public.darjas FOR SELECT USING (
      public.is_platform_admin() OR public.is_tenant_member(darjas.tenant_id)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darjas' AND policyname='darjas_insert_tenant') THEN
    CREATE POLICY "darjas_insert_tenant" ON public.darjas FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(darjas.tenant_id)
          AND public.tenant_has_permission(darjas.tenant_id, 'academics.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darjas' AND policyname='darjas_update_tenant') THEN
    CREATE POLICY "darjas_update_tenant" ON public.darjas FOR UPDATE USING (
      public.is_platform_admin() OR public.is_tenant_member(darjas.tenant_id)
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(darjas.tenant_id)
          AND public.tenant_has_permission(darjas.tenant_id, 'academics.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darjas' AND policyname='darjas_delete_tenant') THEN
    CREATE POLICY "darjas_delete_tenant" ON public.darjas FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(darjas.tenant_id)
          AND public.tenant_has_permission(darjas.tenant_id, 'academics.manage'))
    );
  END IF;
END $$;


-- ── classes (academics.*) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='classes' AND policyname='classes_select_tenant') THEN
    CREATE POLICY "classes_select_tenant" ON public.classes FOR SELECT USING (
      public.is_platform_admin() OR public.is_tenant_member(classes.tenant_id)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='classes' AND policyname='classes_insert_tenant') THEN
    CREATE POLICY "classes_insert_tenant" ON public.classes FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(classes.tenant_id)
          AND public.tenant_has_permission(classes.tenant_id, 'academics.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='classes' AND policyname='classes_update_tenant') THEN
    CREATE POLICY "classes_update_tenant" ON public.classes FOR UPDATE USING (
      public.is_platform_admin() OR public.is_tenant_member(classes.tenant_id)
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(classes.tenant_id)
          AND public.tenant_has_permission(classes.tenant_id, 'academics.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='classes' AND policyname='classes_delete_tenant') THEN
    CREATE POLICY "classes_delete_tenant" ON public.classes FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(classes.tenant_id)
          AND public.tenant_has_permission(classes.tenant_id, 'academics.manage'))
    );
  END IF;
END $$;


-- ── darja_sections (academics.*) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darja_sections' AND policyname='darja_sections_select_tenant') THEN
    CREATE POLICY "darja_sections_select_tenant" ON public.darja_sections FOR SELECT USING (
      public.is_platform_admin() OR public.is_tenant_member(darja_sections.tenant_id)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darja_sections' AND policyname='darja_sections_insert_tenant') THEN
    CREATE POLICY "darja_sections_insert_tenant" ON public.darja_sections FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(darja_sections.tenant_id)
          AND public.tenant_has_permission(darja_sections.tenant_id, 'academics.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darja_sections' AND policyname='darja_sections_update_tenant') THEN
    CREATE POLICY "darja_sections_update_tenant" ON public.darja_sections FOR UPDATE USING (
      public.is_platform_admin() OR public.is_tenant_member(darja_sections.tenant_id)
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(darja_sections.tenant_id)
          AND public.tenant_has_permission(darja_sections.tenant_id, 'academics.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='darja_sections' AND policyname='darja_sections_delete_tenant') THEN
    CREATE POLICY "darja_sections_delete_tenant" ON public.darja_sections FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(darja_sections.tenant_id)
          AND public.tenant_has_permission(darja_sections.tenant_id, 'academics.manage'))
    );
  END IF;
END $$;


-- ── students (students.*) — parents keep own-children visibility ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='students' AND policyname='students_select_tenant') THEN
    CREATE POLICY "students_select_tenant" ON public.students FOR SELECT USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(students.tenant_id)
        AND (
          public.tenant_has_permission(students.tenant_id, 'students.view')
          OR students.parent_user_id = auth.uid()
        )
      )
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='students' AND policyname='students_insert_tenant') THEN
    CREATE POLICY "students_insert_tenant" ON public.students FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(students.tenant_id)
          AND public.tenant_has_permission(students.tenant_id, 'students.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='students' AND policyname='students_update_tenant') THEN
    CREATE POLICY "students_update_tenant" ON public.students FOR UPDATE USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(students.tenant_id)
        AND (
          public.tenant_has_permission(students.tenant_id, 'students.view')
          OR students.parent_user_id = auth.uid()
        )
      )
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(students.tenant_id)
          AND public.tenant_has_permission(students.tenant_id, 'students.update'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='students' AND policyname='students_delete_tenant') THEN
    CREATE POLICY "students_delete_tenant" ON public.students FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(students.tenant_id)
          AND public.tenant_has_permission(students.tenant_id, 'students.delete'))
    );
  END IF;
END $$;


-- ── staff (staff.*) — no ownership fallback: salary/CNIC stay gated ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff' AND policyname='staff_select_tenant') THEN
    CREATE POLICY "staff_select_tenant" ON public.staff FOR SELECT USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(staff.tenant_id)
          AND public.tenant_has_permission(staff.tenant_id, 'staff.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff' AND policyname='staff_insert_tenant') THEN
    CREATE POLICY "staff_insert_tenant" ON public.staff FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(staff.tenant_id)
          AND public.tenant_has_permission(staff.tenant_id, 'staff.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff' AND policyname='staff_update_tenant') THEN
    CREATE POLICY "staff_update_tenant" ON public.staff FOR UPDATE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(staff.tenant_id)
          AND public.tenant_has_permission(staff.tenant_id, 'staff.view'))
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(staff.tenant_id)
          AND public.tenant_has_permission(staff.tenant_id, 'staff.update'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff' AND policyname='staff_delete_tenant') THEN
    CREATE POLICY "staff_delete_tenant" ON public.staff FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(staff.tenant_id)
          AND public.tenant_has_permission(staff.tenant_id, 'staff.delete'))
    );
  END IF;
END $$;


-- ── attendance (attendance.*) — parents see own children's records ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='attendance' AND policyname='attendance_select_tenant') THEN
    CREATE POLICY "attendance_select_tenant" ON public.attendance FOR SELECT USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(attendance.tenant_id)
        AND (
          public.tenant_has_permission(attendance.tenant_id, 'attendance.view')
          OR attendance.student_id IN (
            SELECT s.id FROM public.students s
            WHERE s.parent_user_id = auth.uid()
              AND s.tenant_id = attendance.tenant_id
          )
        )
      )
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='attendance' AND policyname='attendance_insert_tenant') THEN
    CREATE POLICY "attendance_insert_tenant" ON public.attendance FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(attendance.tenant_id)
          AND public.tenant_has_permission(attendance.tenant_id, 'attendance.mark'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='attendance' AND policyname='attendance_update_tenant') THEN
    CREATE POLICY "attendance_update_tenant" ON public.attendance FOR UPDATE USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(attendance.tenant_id)
        AND (
          public.tenant_has_permission(attendance.tenant_id, 'attendance.view')
          OR attendance.student_id IN (
            SELECT s.id FROM public.students s
            WHERE s.parent_user_id = auth.uid()
              AND s.tenant_id = attendance.tenant_id
          )
        )
      )
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(attendance.tenant_id)
          AND public.tenant_has_permission(attendance.tenant_id, 'attendance.edit'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='attendance' AND policyname='attendance_delete_tenant') THEN
    CREATE POLICY "attendance_delete_tenant" ON public.attendance FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(attendance.tenant_id)
          AND public.tenant_has_permission(attendance.tenant_id, 'attendance.delete'))
    );
  END IF;
END $$;


-- ── fees (fees.*) — parents see own children's fee records ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fees' AND policyname='fees_select_tenant') THEN
    CREATE POLICY "fees_select_tenant" ON public.fees FOR SELECT USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(fees.tenant_id)
        AND (
          public.tenant_has_permission(fees.tenant_id, 'fees.view')
          OR fees.student_id IN (
            SELECT s.id FROM public.students s
            WHERE s.parent_user_id = auth.uid()
              AND s.tenant_id = fees.tenant_id
          )
        )
      )
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fees' AND policyname='fees_insert_tenant') THEN
    CREATE POLICY "fees_insert_tenant" ON public.fees FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(fees.tenant_id)
          AND public.tenant_has_permission(fees.tenant_id, 'fees.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fees' AND policyname='fees_update_tenant') THEN
    CREATE POLICY "fees_update_tenant" ON public.fees FOR UPDATE USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(fees.tenant_id)
        AND (
          public.tenant_has_permission(fees.tenant_id, 'fees.view')
          OR fees.student_id IN (
            SELECT s.id FROM public.students s
            WHERE s.parent_user_id = auth.uid()
              AND s.tenant_id = fees.tenant_id
          )
        )
      )
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(fees.tenant_id)
          AND public.tenant_has_permission(fees.tenant_id, 'fees.collect'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fees' AND policyname='fees_delete_tenant') THEN
    CREATE POLICY "fees_delete_tenant" ON public.fees FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(fees.tenant_id)
          AND public.tenant_has_permission(fees.tenant_id, 'fees.collect'))
    );
  END IF;
END $$;


-- ── exams (exams.*) — any tenant member may read exam schedule ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='exams' AND policyname='exams_select_tenant') THEN
    CREATE POLICY "exams_select_tenant" ON public.exams FOR SELECT USING (
      public.is_platform_admin() OR public.is_tenant_member(exams.tenant_id)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='exams' AND policyname='exams_insert_tenant') THEN
    CREATE POLICY "exams_insert_tenant" ON public.exams FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(exams.tenant_id)
          AND public.tenant_has_permission(exams.tenant_id, 'exams.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='exams' AND policyname='exams_update_tenant') THEN
    CREATE POLICY "exams_update_tenant" ON public.exams FOR UPDATE USING (
      public.is_platform_admin() OR public.is_tenant_member(exams.tenant_id)
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(exams.tenant_id)
          AND public.tenant_has_permission(exams.tenant_id, 'exams.update'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='exams' AND policyname='exams_delete_tenant') THEN
    CREATE POLICY "exams_delete_tenant" ON public.exams FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(exams.tenant_id)
          AND public.tenant_has_permission(exams.tenant_id, 'exams.delete'))
    );
  END IF;
END $$;


-- ── results (results.*) — parents see own children's results ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='results' AND policyname='results_select_tenant') THEN
    CREATE POLICY "results_select_tenant" ON public.results FOR SELECT USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(results.tenant_id)
        AND (
          public.tenant_has_permission(results.tenant_id, 'results.view')
          OR results.student_id IN (
            SELECT s.id FROM public.students s
            WHERE s.parent_user_id = auth.uid()
              AND s.tenant_id = results.tenant_id
          )
        )
      )
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='results' AND policyname='results_insert_tenant') THEN
    CREATE POLICY "results_insert_tenant" ON public.results FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(results.tenant_id)
          AND public.tenant_has_permission(results.tenant_id, 'results.enter'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='results' AND policyname='results_update_tenant') THEN
    CREATE POLICY "results_update_tenant" ON public.results FOR UPDATE USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(results.tenant_id)
        AND (
          public.tenant_has_permission(results.tenant_id, 'results.view')
          OR results.student_id IN (
            SELECT s.id FROM public.students s
            WHERE s.parent_user_id = auth.uid()
              AND s.tenant_id = results.tenant_id
          )
        )
      )
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(results.tenant_id)
          AND public.tenant_has_permission(results.tenant_id, 'results.edit'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='results' AND policyname='results_delete_tenant') THEN
    CREATE POLICY "results_delete_tenant" ON public.results FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(results.tenant_id)
          AND public.tenant_has_permission(results.tenant_id, 'results.edit'))
    );
  END IF;
END $$;


-- ── announcements (notifications.*) — active ones visible to members ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='announcements' AND policyname='announcements_select_tenant') THEN
    CREATE POLICY "announcements_select_tenant" ON public.announcements FOR SELECT USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(announcements.tenant_id)
        AND (
          public.tenant_has_permission(announcements.tenant_id, 'notifications.view')
          OR announcements.is_active = TRUE
        )
      )
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='announcements' AND policyname='announcements_insert_tenant') THEN
    CREATE POLICY "announcements_insert_tenant" ON public.announcements FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(announcements.tenant_id)
          AND public.tenant_has_permission(announcements.tenant_id, 'notifications.send'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='announcements' AND policyname='announcements_update_tenant') THEN
    CREATE POLICY "announcements_update_tenant" ON public.announcements FOR UPDATE USING (
      public.is_platform_admin()
      OR (
        public.is_tenant_member(announcements.tenant_id)
        AND (
          public.tenant_has_permission(announcements.tenant_id, 'notifications.view')
          OR announcements.is_active = TRUE
        )
      )
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(announcements.tenant_id)
          AND public.tenant_has_permission(announcements.tenant_id, 'notifications.send'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='announcements' AND policyname='announcements_delete_tenant') THEN
    CREATE POLICY "announcements_delete_tenant" ON public.announcements FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(announcements.tenant_id)
          AND public.tenant_has_permission(announcements.tenant_id, 'notifications.send'))
    );
  END IF;
END $$;


-- ── library_books (library.*) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='library_books' AND policyname='library_books_select_tenant') THEN
    CREATE POLICY "library_books_select_tenant" ON public.library_books FOR SELECT USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(library_books.tenant_id)
          AND public.tenant_has_permission(library_books.tenant_id, 'library.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='library_books' AND policyname='library_books_insert_tenant') THEN
    CREATE POLICY "library_books_insert_tenant" ON public.library_books FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(library_books.tenant_id)
          AND public.tenant_has_permission(library_books.tenant_id, 'library.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='library_books' AND policyname='library_books_update_tenant') THEN
    CREATE POLICY "library_books_update_tenant" ON public.library_books FOR UPDATE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(library_books.tenant_id)
          AND public.tenant_has_permission(library_books.tenant_id, 'library.view'))
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(library_books.tenant_id)
          AND public.tenant_has_permission(library_books.tenant_id, 'library.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='library_books' AND policyname='library_books_delete_tenant') THEN
    CREATE POLICY "library_books_delete_tenant" ON public.library_books FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(library_books.tenant_id)
          AND public.tenant_has_permission(library_books.tenant_id, 'library.manage'))
    );
  END IF;
END $$;


-- ── book_issues (library.*) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='book_issues' AND policyname='book_issues_select_tenant') THEN
    CREATE POLICY "book_issues_select_tenant" ON public.book_issues FOR SELECT USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(book_issues.tenant_id)
          AND public.tenant_has_permission(book_issues.tenant_id, 'library.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='book_issues' AND policyname='book_issues_insert_tenant') THEN
    CREATE POLICY "book_issues_insert_tenant" ON public.book_issues FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(book_issues.tenant_id)
          AND public.tenant_has_permission(book_issues.tenant_id, 'library.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='book_issues' AND policyname='book_issues_update_tenant') THEN
    CREATE POLICY "book_issues_update_tenant" ON public.book_issues FOR UPDATE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(book_issues.tenant_id)
          AND public.tenant_has_permission(book_issues.tenant_id, 'library.view'))
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(book_issues.tenant_id)
          AND public.tenant_has_permission(book_issues.tenant_id, 'library.manage'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='book_issues' AND policyname='book_issues_delete_tenant') THEN
    CREATE POLICY "book_issues_delete_tenant" ON public.book_issues FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(book_issues.tenant_id)
          AND public.tenant_has_permission(book_issues.tenant_id, 'library.manage'))
    );
  END IF;
END $$;


-- ── finance_transactions (finance.*) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='finance_transactions' AND policyname='finance_transactions_select_tenant') THEN
    CREATE POLICY "finance_transactions_select_tenant" ON public.finance_transactions FOR SELECT USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(finance_transactions.tenant_id)
          AND public.tenant_has_permission(finance_transactions.tenant_id, 'finance.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='finance_transactions' AND policyname='finance_transactions_insert_tenant') THEN
    CREATE POLICY "finance_transactions_insert_tenant" ON public.finance_transactions FOR INSERT WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(finance_transactions.tenant_id)
          AND public.tenant_has_permission(finance_transactions.tenant_id, 'finance.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='finance_transactions' AND policyname='finance_transactions_update_tenant') THEN
    CREATE POLICY "finance_transactions_update_tenant" ON public.finance_transactions FOR UPDATE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(finance_transactions.tenant_id)
          AND public.tenant_has_permission(finance_transactions.tenant_id, 'finance.view'))
    ) WITH CHECK (
      public.is_platform_admin()
      OR (public.is_tenant_member(finance_transactions.tenant_id)
          AND public.tenant_has_permission(finance_transactions.tenant_id, 'finance.update'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='finance_transactions' AND policyname='finance_transactions_delete_tenant') THEN
    CREATE POLICY "finance_transactions_delete_tenant" ON public.finance_transactions FOR DELETE USING (
      public.is_platform_admin()
      OR (public.is_tenant_member(finance_transactions.tenant_id)
          AND public.tenant_has_permission(finance_transactions.tenant_id, 'finance.delete'))
    );
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- (c) profiles — least-privilege rewrite + anti-escalation lock
-- ═══════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='profiles_select_tenant') THEN
    CREATE POLICY "profiles_select_tenant"
      ON public.profiles FOR SELECT
      USING (
        profiles.id = auth.uid()
        OR public.is_platform_admin()
        OR EXISTS (
          SELECT 1
            FROM public.tenant_memberships m1
            JOIN public.tenant_memberships m2
              ON m2.tenant_id = m1.tenant_id
           WHERE m1.user_id = auth.uid()
             AND m1.is_active = TRUE
             AND m2.user_id = profiles.id
             AND m2.is_active = TRUE
             AND public.tenant_has_permission(m1.tenant_id, 'users.view')
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='profiles_update_tenant') THEN
    -- No INSERT policy for the authenticated role: only the
    -- SECURITY DEFINER handle_new_user() trigger inserts profiles
    -- (SECURITY DEFINER bypasses RLS). This closes the live
    -- profiles_insert_own escalation for good.
    CREATE POLICY "profiles_update_tenant"
      ON public.profiles FOR UPDATE
      USING (profiles.id = auth.uid() OR public.is_platform_admin())
      WITH CHECK (profiles.id = auth.uid() OR public.is_platform_admin());
  END IF;
END $$;


-- Role column is no longer client-writable. Any non-platform-admin
-- attempt to change role on UPDATE, or to insert a non-default role,
-- is rejected. Real roles live in tenant_memberships (provisioning),
-- never in profiles.
CREATE OR REPLACE FUNCTION public.profiles_lock_role()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.role IS DISTINCT FROM OLD.role AND NOT public.is_platform_admin() THEN
      RAISE EXCEPTION 'profiles.role is not client-writable; assign roles via tenant_memberships';
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'INSERT' THEN
    IF NEW.role IS DISTINCT FROM 'student' AND NOT public.is_platform_admin() THEN
      RAISE EXCEPTION 'new profiles must use the least-privilege role ''student''; assign real roles via tenant_memberships';
    END IF;
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_lock_role ON public.profiles;
CREATE TRIGGER trg_profiles_lock_role
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_lock_role();


-- ═══════════════════════════════════════════════════════════════
-- (d) handle_new_user() — single version, least-privilege default
-- (Replaces the three divergent definitions in 01/05/06.)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    'student'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
-- The existing on_auth_user_created trigger (01) keeps pointing at this
-- function; only the body is replaced. Real roles are provisioned into
-- tenant_memberships, never trusted from client-controlled metadata.


-- ═══════════════════════════════════════════════════════════════
-- (e) madrasas (legacy table) — platform admins manage, members read
-- ═══════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='madrasas' AND policyname='madrasas_platform_admin_all') THEN
    CREATE POLICY "madrasas_platform_admin_all"
      ON public.madrasas FOR ALL
      USING (public.is_platform_admin())
      WITH CHECK (public.is_platform_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='madrasas' AND policyname='madrasas_member_select') THEN
    CREATE POLICY "madrasas_member_select"
      ON public.madrasas FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.tenant_memberships m
          WHERE m.user_id = auth.uid() AND m.is_active = TRUE
        )
      );
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- (f) Views — run as the caller so underlying RLS applies
-- Requires PostgreSQL 15+ (security_invoker on views).
-- ═══════════════════════════════════════════════════════════════
ALTER VIEW IF EXISTS public.attendance_summary SET (security_invoker = true);
ALTER VIEW IF EXISTS public.fee_summary         SET (security_invoker = true);


-- ═══════════════════════════════════════════════════════════════
-- (g) FAIL-LOUD VERIFICATION — no legacy policy may survive
-- Queries pg_policies for the 13 retrofit tables + profiles and raises
-- if any policy name from the legacy-drop list is still present.
-- The migration FAILS rather than silently stacking policies.
-- ═══════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_legacy TEXT[] := ARRAY[
    -- profiles (02 + 06)
    'profiles_view_own','profiles_update_own','profiles_admin_view_all',
    'profiles_admin_update_all','profiles_insert_own',
    'profiles select authenticated','profiles update own','admin manage profiles',
    -- darjas / classes (02)
    'darjas_read','darjas_admin_write','classes_read','classes_admin_write',
    -- students (02 + 06)
    'students_admin_all','students_teacher_view','students_parent_view_own',
    'view_students permission','create_students permission',
    'edit_students permission','delete_students permission',
    -- staff (02 + 06)
    'staff_admin_all','staff_teacher_view',
    'view_staff permission','create_staff permission',
    'edit_staff permission','delete_staff permission',
    -- attendance (02 + 06)
    'attendance_admin_all','attendance_teacher_manage','attendance_parent_view_own',
    'view_attendance permission','mark_attendance permission',
    'edit_attendance permission','delete_attendance permission',
    -- fees (02 + 06)
    'fees_admin_all','fees_teacher_read','fees_parent_view_own',
    'view_fees permission','create_fees permission',
    'update_fees permission','delete_fees permission',
    -- exams / results (02)
    'exams_read_all_auth','exams_admin_all',
    'results_admin_all','results_teacher_manage','results_parent_view_own',
    -- announcements (02 + 05 + 06)
    'announcements_read','announcements_admin_all','superAdmin manage announcements',
    'view_announcements permission','create_announcements permission',
    'edit_announcements permission','delete_announcements permission',
    -- darja_sections (05)
    'authenticated users read darja_sections','admin manage darja_sections',
    -- library_books (05 + 06)
    'authenticated read library_books','admin manage library_books',
    'view_library permission','manage_library permission',
    -- book_issues (05 + 06)
    'authenticated read book_issues','admin manage book_issues',
    'view_library book_issues permission','manage_library book_issues permission',
    -- finance_transactions (05 + 06)
    'authenticated read finance','admin manage finance',
    'view_finance permission','create_finance permission','delete_finance permission'
  ];
  v_found TEXT;
BEGIN
  SELECT string_agg(policyname, ', ' ORDER BY policyname)
    INTO v_found
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename IN (
       'profiles','darjas','classes','students','staff','attendance','fees',
       'exams','results','announcements','darja_sections','library_books',
       'book_issues','finance_transactions'
     )
     AND policyname = ANY (v_legacy);

  IF v_found IS NOT NULL THEN
    RAISE EXCEPTION '007 FAILED: stale legacy policies survived the sweep: %', v_found;
  END IF;

  RAISE NOTICE '007 legacy-policy sweep clean: 0 stale policies on the 13 retrofit tables + profiles.';
END $$;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('007_tenant_rls') ON CONFLICT DO NOTHING;
