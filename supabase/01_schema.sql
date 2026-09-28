-- ═══════════════════════════════════════════════════════════════
-- Madrasa 360 — Database Schema
-- Phase 2: Run this entire file in Supabase → SQL Editor
-- Order: profiles → darjas → classes → students → staff →
--        attendance → fees → exams → results → announcements
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────
-- profiles  (extends auth.users)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  phone      TEXT,
  photo_url  TEXT,
  role       TEXT NOT NULL CHECK (role IN ('admin', 'teacher', 'parent'))
             DEFAULT 'teacher',
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create a profile row whenever a new auth.users row is inserted
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_app_meta_data->>'role', 'teacher')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────
-- darjas  (درجے — class levels / grades)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.darjas (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,          -- Urdu label  e.g. 'درجہ اول'
  name_en    TEXT,                   -- English label e.g. 'Grade 1'
  order_num  INT NOT NULL,           -- for sorted display
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ─────────────────────────────────────────────
-- classes  (جماعتیں — sections within a darja)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.classes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  darja_id   UUID REFERENCES public.darjas(id) ON DELETE SET NULL,
  name       TEXT NOT NULL,          -- e.g. 'جماعت الف'
  teacher_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  capacity   INT NOT NULL DEFAULT 50,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ─────────────────────────────────────────────
-- students  (طلباء)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.students (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  roll_no        TEXT NOT NULL,
  name           TEXT NOT NULL,
  father_name    TEXT NOT NULL,
  darja_id       UUID REFERENCES public.darjas(id) ON DELETE SET NULL,
  class_id       UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  parent_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  date_of_birth  DATE,
  date_of_admit  DATE NOT NULL DEFAULT CURRENT_DATE,
  phone          TEXT,
  address        TEXT,
  photo_url      TEXT,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (roll_no, class_id)
);

CREATE TRIGGER students_set_updated_at
  BEFORE UPDATE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────
-- staff  (عملہ)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.staff (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  name         TEXT NOT NULL,
  father_name  TEXT NOT NULL,
  designation  TEXT NOT NULL,
  department   TEXT,
  phone        TEXT NOT NULL,
  cnic         TEXT,
  salary       NUMERIC(10, 2),
  joining_date DATE NOT NULL,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  photo_url    TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER staff_set_updated_at
  BEFORE UPDATE ON public.staff
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────
-- attendance  (حاضری)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.attendance (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_id   UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id UUID NOT NULL REFERENCES public.profiles(id),
  date       DATE NOT NULL DEFAULT CURRENT_DATE,
  status     TEXT NOT NULL CHECK (status IN ('present', 'absent', 'leave'))
             DEFAULT 'present',
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, date)          -- one record per student per day
);

CREATE INDEX IF NOT EXISTS idx_attendance_date     ON public.attendance (date);
CREATE INDEX IF NOT EXISTS idx_attendance_class    ON public.attendance (class_id, date);
CREATE INDEX IF NOT EXISTS idx_attendance_student  ON public.attendance (student_id);


-- ─────────────────────────────────────────────
-- fees  (فیس)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.fees (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id  UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  month       TEXT NOT NULL,           -- 'YYYY-MM'  e.g. '2026-03'
  amount_due  NUMERIC(10, 2) NOT NULL,
  amount_paid NUMERIC(10, 2) NOT NULL DEFAULT 0,
  due_date    DATE NOT NULL,
  paid_date   DATE,
  status      TEXT NOT NULL
              GENERATED ALWAYS AS (
                CASE
                  WHEN amount_paid >= amount_due   THEN 'paid'
                  WHEN amount_paid  > 0            THEN 'partial'
                  WHEN CURRENT_DATE > due_date     THEN 'past_due'
                  ELSE 'pending'
                END
              ) STORED,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, month)
);

CREATE TRIGGER fees_set_updated_at
  BEFORE UPDATE ON public.fees
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_fees_student ON public.fees (student_id);
CREATE INDEX IF NOT EXISTS idx_fees_month   ON public.fees (month);


-- ─────────────────────────────────────────────
-- exams  (امتحانات)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.exams (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,           -- e.g. 'امتحان نصف سال'
  class_id    UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  exam_date   DATE NOT NULL,
  total_marks INT NOT NULL DEFAULT 100,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ─────────────────────────────────────────────
-- results  (نتائج)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.results (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_id        UUID NOT NULL REFERENCES public.exams(id) ON DELETE CASCADE,
  student_id     UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  subject        TEXT NOT NULL,
  marks_obtained NUMERIC(6, 2) NOT NULL,
  total_marks    NUMERIC(6, 2) NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (exam_id, student_id, subject)
);

CREATE INDEX IF NOT EXISTS idx_results_student ON public.results (student_id);
CREATE INDEX IF NOT EXISTS idx_results_exam    ON public.results (exam_id);


-- ─────────────────────────────────────────────
-- announcements  (اعلانات)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.announcements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  target_role TEXT NOT NULL DEFAULT 'all'
              CHECK (target_role IN ('all', 'admin', 'teacher', 'parent')),
  posted_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ─────────────────────────────────────────────
-- Views
-- ─────────────────────────────────────────────

-- Attendance summary per class per day (Admin dashboard)
CREATE OR REPLACE VIEW public.attendance_summary AS
SELECT
  a.date,
  c.id                                                         AS class_id,
  c.name                                                       AS class_name,
  d.name                                                       AS darja_name,
  COUNT(*)                                                     AS total,
  SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END)       AS present_count,
  SUM(CASE WHEN a.status = 'absent'  THEN 1 ELSE 0 END)       AS absent_count,
  SUM(CASE WHEN a.status = 'leave'   THEN 1 ELSE 0 END)       AS leave_count
FROM public.attendance a
JOIN public.students s ON a.student_id = s.id
JOIN public.classes  c ON a.class_id   = c.id
JOIN public.darjas   d ON s.darja_id   = d.id
GROUP BY a.date, c.id, c.name, d.name;

-- Fee summary per student (Parent + Admin dashboard)
CREATE OR REPLACE VIEW public.fee_summary AS
SELECT
  f.student_id,
  s.name                                        AS student_name,
  s.roll_no,
  c.name                                        AS class_name,
  COUNT(*)                                      AS total_months,
  SUM(f.amount_due)                             AS total_due,
  SUM(f.amount_paid)                            AS total_paid,
  SUM(f.amount_due - f.amount_paid)             AS outstanding,
  SUM(CASE WHEN f.status = 'past_due' THEN 1 ELSE 0 END) AS past_due_count
FROM public.fees f
JOIN public.students s ON f.student_id = s.id
LEFT JOIN public.classes c ON s.class_id = c.id
GROUP BY f.student_id, s.name, s.roll_no, c.name;
