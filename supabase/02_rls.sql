-- ═══════════════════════════════════════════════════════════════
-- Madrasa 360 — Row Level Security Policies
-- Phase 3: Run AFTER 01_schema.sql in Supabase → SQL Editor
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────
-- Helper function: extract role from JWT
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    auth.jwt() -> 'app_metadata' ->> 'role',
    'teacher'
  );
$$;


-- ─────────────────────────────────────────────
-- Enable RLS on all tables
-- ─────────────────────────────────────────────
ALTER TABLE public.profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.darjas        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exams         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.results       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;


-- ═══════════════════════════════════════════════════════════════
-- profiles
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "profiles_view_own"         ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_view_all"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"       ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_update_all" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own"       ON public.profiles;

-- Every user can view & update their own profile
CREATE POLICY "profiles_view_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- Admins can view and update all profiles
CREATE POLICY "profiles_admin_view_all"
  ON public.profiles FOR SELECT
  USING (public.get_user_role() = 'admin');

CREATE POLICY "profiles_admin_update_all"
  ON public.profiles FOR UPDATE
  USING (public.get_user_role() = 'admin');

-- The trigger inserts a profile on signup; allow it (SECURITY DEFINER handles this)
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);


-- ═══════════════════════════════════════════════════════════════
-- darjas & classes  (lookup / read-only for non-admins)
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "darjas_read"         ON public.darjas;
DROP POLICY IF EXISTS "darjas_admin_write"  ON public.darjas;
DROP POLICY IF EXISTS "classes_read"        ON public.classes;
DROP POLICY IF EXISTS "classes_admin_write" ON public.classes;

CREATE POLICY "darjas_read"
  ON public.darjas FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "darjas_admin_write"
  ON public.darjas FOR ALL
  USING (public.get_user_role() = 'admin');

CREATE POLICY "classes_read"
  ON public.classes FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "classes_admin_write"
  ON public.classes FOR ALL
  USING (public.get_user_role() = 'admin');


-- ═══════════════════════════════════════════════════════════════
-- students
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "students_admin_all"          ON public.students;
DROP POLICY IF EXISTS "students_teacher_view"       ON public.students;
DROP POLICY IF EXISTS "students_parent_view_own"    ON public.students;

-- Admins: full CRUD
CREATE POLICY "students_admin_all"
  ON public.students FOR ALL
  USING (public.get_user_role() = 'admin');

-- Teachers: view students in classes they teach
CREATE POLICY "students_teacher_view"
  ON public.students FOR SELECT
  USING (
    public.get_user_role() = 'teacher'
    AND class_id IN (
      SELECT id FROM public.classes WHERE teacher_id = auth.uid()
    )
  );

-- Parents: view only their own children
CREATE POLICY "students_parent_view_own"
  ON public.students FOR SELECT
  USING (
    public.get_user_role() = 'parent'
    AND parent_user_id = auth.uid()
  );


-- ═══════════════════════════════════════════════════════════════
-- staff
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "staff_admin_all"        ON public.staff;
DROP POLICY IF EXISTS "staff_teacher_view"     ON public.staff;

-- Admins: full CRUD
CREATE POLICY "staff_admin_all"
  ON public.staff FOR ALL
  USING (public.get_user_role() = 'admin');

-- Teachers: read-only (to see colleagues)
CREATE POLICY "staff_teacher_view"
  ON public.staff FOR SELECT
  USING (
    public.get_user_role() IN ('teacher', 'parent')
    AND is_active = TRUE
  );


-- ═══════════════════════════════════════════════════════════════
-- attendance
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "attendance_admin_all"         ON public.attendance;
DROP POLICY IF EXISTS "attendance_teacher_manage"    ON public.attendance;
DROP POLICY IF EXISTS "attendance_parent_view_own"   ON public.attendance;

-- Admins: full access
CREATE POLICY "attendance_admin_all"
  ON public.attendance FOR ALL
  USING (public.get_user_role() = 'admin');

-- Teachers: full access to records they created
CREATE POLICY "attendance_teacher_manage"
  ON public.attendance FOR ALL
  USING (
    public.get_user_role() = 'teacher'
    AND teacher_id = auth.uid()
  );

-- Parents: view their children's attendance only
CREATE POLICY "attendance_parent_view_own"
  ON public.attendance FOR SELECT
  USING (
    public.get_user_role() = 'parent'
    AND student_id IN (
      SELECT id FROM public.students WHERE parent_user_id = auth.uid()
    )
  );


-- ═══════════════════════════════════════════════════════════════
-- fees
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "fees_admin_all"          ON public.fees;
DROP POLICY IF EXISTS "fees_teacher_read"       ON public.fees;
DROP POLICY IF EXISTS "fees_parent_view_own"    ON public.fees;

-- Admins: full access
CREATE POLICY "fees_admin_all"
  ON public.fees FOR ALL
  USING (public.get_user_role() = 'admin');

-- Teachers: read-only
CREATE POLICY "fees_teacher_read"
  ON public.fees FOR SELECT
  USING (public.get_user_role() = 'teacher');

-- Parents: view fees for their own children
CREATE POLICY "fees_parent_view_own"
  ON public.fees FOR SELECT
  USING (
    public.get_user_role() = 'parent'
    AND student_id IN (
      SELECT id FROM public.students WHERE parent_user_id = auth.uid()
    )
  );


-- ═══════════════════════════════════════════════════════════════
-- exams & results
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "exams_admin_all"          ON public.exams;
DROP POLICY IF EXISTS "exams_read_all_auth"      ON public.exams;
DROP POLICY IF EXISTS "results_admin_all"        ON public.results;
DROP POLICY IF EXISTS "results_teacher_manage"   ON public.results;
DROP POLICY IF EXISTS "results_parent_view_own"  ON public.results;

CREATE POLICY "exams_read_all_auth"
  ON public.exams FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "exams_admin_all"
  ON public.exams FOR ALL
  USING (public.get_user_role() = 'admin');

-- Admins: full access
CREATE POLICY "results_admin_all"
  ON public.results FOR ALL
  USING (public.get_user_role() = 'admin');

-- Teachers: manage results for exams in their classes
CREATE POLICY "results_teacher_manage"
  ON public.results FOR ALL
  USING (
    public.get_user_role() = 'teacher'
    AND exam_id IN (
      SELECT e.id FROM public.exams e
      JOIN  public.classes c ON e.class_id = c.id
      WHERE c.teacher_id = auth.uid()
    )
  );

-- Parents: view their children's results only
CREATE POLICY "results_parent_view_own"
  ON public.results FOR SELECT
  USING (
    public.get_user_role() = 'parent'
    AND student_id IN (
      SELECT id FROM public.students WHERE parent_user_id = auth.uid()
    )
  );


-- ═══════════════════════════════════════════════════════════════
-- announcements
-- ═══════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "announcements_read"        ON public.announcements;
DROP POLICY IF EXISTS "announcements_admin_all"   ON public.announcements;

-- All authenticated users can read announcements intended for them
CREATE POLICY "announcements_read"
  ON public.announcements FOR SELECT
  USING (
    is_active = TRUE
    AND auth.role() = 'authenticated'
    AND (
      target_role = 'all'
      OR target_role = public.get_user_role()
    )
  );

-- Only admins can create / edit / delete
CREATE POLICY "announcements_admin_all"
  ON public.announcements FOR ALL
  USING (public.get_user_role() = 'admin');
