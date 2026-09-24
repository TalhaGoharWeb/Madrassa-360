-- ═══════════════════════════════════════════════════════════════
-- Madrasa 360 — New Modules Migration
-- File: 05_new_modules.sql
-- Run this AFTER 01_schema.sql, 02_rls.sql, 03_storage.sql, 04_seed.sql
--
-- Changes:
--   1.  profiles   → add 'superAdmin' to role CHECK
--   2.  madrasas   → new multi-tenant franchise table
--   3.  darjas     → rebuild with multi-tenant columns
--   4.  darja_sections → sections within a darja
--   5.  announcements → rebuild with new columns
--   6.  library_books  → new
--   7.  book_issues    → new
--   8.  finance_transactions → new
--   9.  RLS policies for all new tables
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────
-- 1.  profiles — allow superAdmin role
-- ─────────────────────────────────────────────
-- Drop the old CHECK constraint and add an updated one
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('superAdmin', 'admin', 'teacher', 'parent'));

-- Update the trigger function to accept superAdmin
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


-- ─────────────────────────────────────────────
-- 2.  madrasas  (مدارس — franchise branches)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.madrasas (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name_urdu         TEXT        NOT NULL,
  name_english      TEXT        NOT NULL DEFAULT '',
  city_urdu         TEXT        NOT NULL DEFAULT '',
  city_english      TEXT        NOT NULL DEFAULT '',
  address           TEXT,
  phone             TEXT,
  email             TEXT,
  website           TEXT,
  logo_url          TEXT,
  branch_code       TEXT        UNIQUE,
  admin_user_id     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  subscription_plan TEXT        NOT NULL DEFAULT 'basic'
                                CHECK (subscription_plan IN ('basic','standard','premium')),
  is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER madrasas_set_updated_at
  BEFORE UPDATE ON public.madrasas
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_madrasas_active ON public.madrasas (is_active);


-- ─────────────────────────────────────────────
-- 3.  darjas (rebuild for multi-tenant)
--     NOTE: If existing darjas data exists, back it up first!
--     The old columns (name, name_en, order_num) are replaced.
-- ─────────────────────────────────────────────

-- Add new columns to existing darjas table (non-destructive)
ALTER TABLE public.darjas
  ADD COLUMN IF NOT EXISTS madrasa_id   UUID        REFERENCES public.madrasas(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS name_urdu    TEXT,
  ADD COLUMN IF NOT EXISTS name_english TEXT        DEFAULT '',
  ADD COLUMN IF NOT EXISTS level        TEXT        DEFAULT 'dars_e_nizami'
                                        CHECK (level IN ('nazra','hifz','dars_e_nizami','takhassus')),
  ADD COLUMN IF NOT EXISTS order_index  INT         DEFAULT 0,
  ADD COLUMN IF NOT EXISTS description  TEXT,
  ADD COLUMN IF NOT EXISTS capacity     INT         DEFAULT 30,
  ADD COLUMN IF NOT EXISTS updated_at   TIMESTAMPTZ DEFAULT NOW();

-- Migrate old data if name column exists
UPDATE public.darjas SET name_urdu = name WHERE name_urdu IS NULL AND name IS NOT NULL;
UPDATE public.darjas SET order_index = order_num WHERE order_index = 0 AND order_num IS NOT NULL;

-- Make name_urdu non-null with fallback
UPDATE public.darjas SET name_urdu = 'درجہ' WHERE name_urdu IS NULL;
ALTER TABLE public.darjas ALTER COLUMN name_urdu SET NOT NULL;


-- ─────────────────────────────────────────────
-- 4.  darja_sections  (سیکشن — الف/ب/ج within darja)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.darja_sections (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  darja_id   UUID        NOT NULL REFERENCES public.darjas(id) ON DELETE CASCADE,
  madrasa_id UUID        REFERENCES public.madrasas(id) ON DELETE CASCADE,
  name_urdu  TEXT        NOT NULL,   -- الف / ب / ج
  teacher_id UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  capacity   INT         DEFAULT 30,
  is_active  BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_darja_sections_darja ON public.darja_sections (darja_id);


-- ─────────────────────────────────────────────
-- 5.  announcements (rebuild with new schema)
--     Old columns: title, body, target_role, posted_by, is_active
--     New columns: madrasa_id, target (enum), posted_by_user_id,
--                  posted_by_name, is_pinned, scheduled_at
-- ─────────────────────────────────────────────
ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS madrasa_id       UUID        REFERENCES public.madrasas(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS target           TEXT        DEFAULT 'all'
                                            CHECK (target IN ('all','teachers','parents','students','specific')),
  ADD COLUMN IF NOT EXISTS posted_by_user_id UUID       REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS posted_by_name   TEXT        DEFAULT '',
  ADD COLUMN IF NOT EXISTS is_pinned        BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS scheduled_at     TIMESTAMPTZ;

-- Migrate old target_role to new target column
UPDATE public.announcements
  SET target = target_role
  WHERE target IS NULL AND target_role IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_announcements_madrasa ON public.announcements (madrasa_id);
CREATE INDEX IF NOT EXISTS idx_announcements_pinned  ON public.announcements (is_pinned);


-- ─────────────────────────────────────────────
-- 6.  library_books  (کتب خانہ)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.library_books (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  madrasa_id       UUID        REFERENCES public.madrasas(id) ON DELETE CASCADE,
  title            TEXT        NOT NULL,
  author           TEXT,
  subject          TEXT,
  isbn             TEXT,
  total_copies     INT         NOT NULL DEFAULT 1,
  available_copies INT         NOT NULL DEFAULT 1,
  status           TEXT        NOT NULL DEFAULT 'available'
                               CHECK (status IN ('available','issued','lost')),
  added_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER library_books_set_updated_at
  BEFORE UPDATE ON public.library_books
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_library_books_madrasa ON public.library_books (madrasa_id);
CREATE INDEX IF NOT EXISTS idx_library_books_status  ON public.library_books (status);


-- ─────────────────────────────────────────────
-- 7.  book_issues  (کتاب اجراء / واپسی)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.book_issues (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  madrasa_id     UUID        REFERENCES public.madrasas(id) ON DELETE CASCADE,
  book_id        UUID        NOT NULL REFERENCES public.library_books(id) ON DELETE CASCADE,
  book_title     TEXT        NOT NULL,
  borrower_id    TEXT        NOT NULL,   -- student roll_no or staff id
  borrower_name  TEXT        NOT NULL,
  borrower_type  TEXT        NOT NULL DEFAULT 'student'
                             CHECK (borrower_type IN ('student','teacher','staff')),
  issued_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  due_at         TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '14 days'),
  returned_at    TIMESTAMPTZ,
  fine           NUMERIC(8,2),
  is_returned    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update available_copies when a book is returned
CREATE OR REPLACE FUNCTION public.handle_book_return()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_returned = TRUE AND OLD.is_returned = FALSE THEN
    UPDATE public.library_books
      SET available_copies = available_copies + 1
      WHERE id = NEW.book_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_book_returned ON public.book_issues;
CREATE TRIGGER on_book_returned
  AFTER UPDATE ON public.book_issues
  FOR EACH ROW EXECUTE FUNCTION public.handle_book_return();

CREATE INDEX IF NOT EXISTS idx_book_issues_book      ON public.book_issues (book_id);
CREATE INDEX IF NOT EXISTS idx_book_issues_returned  ON public.book_issues (is_returned);
CREATE INDEX IF NOT EXISTS idx_book_issues_due       ON public.book_issues (due_at);


-- ─────────────────────────────────────────────
-- 8.  finance_transactions  (مالیات)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.finance_transactions (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  madrasa_id          UUID        REFERENCES public.madrasas(id) ON DELETE CASCADE,
  type                TEXT        NOT NULL
                                  CHECK (type IN ('donation','zakat','sadqa','expense','salary','fee')),
  amount              NUMERIC(12,2) NOT NULL,
  description         TEXT,
  person_name         TEXT,
  reference_id        TEXT,         -- student_id for fee, staff_id for salary
  date                DATE        NOT NULL DEFAULT CURRENT_DATE,
  receipt_number      TEXT,
  created_by_user_id  UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_finance_madrasa ON public.finance_transactions (madrasa_id);
CREATE INDEX IF NOT EXISTS idx_finance_type    ON public.finance_transactions (type);
CREATE INDEX IF NOT EXISTS idx_finance_date    ON public.finance_transactions (date);


-- ═══════════════════════════════════════════════════════════════
-- 9.  Row Level Security (RLS)
-- ═══════════════════════════════════════════════════════════════

-- Helper: get current user's role from profiles
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;


-- ── madrasas ──────────────────────────────────
ALTER TABLE public.madrasas ENABLE ROW LEVEL SECURITY;

-- superAdmin sees and manages all
CREATE POLICY "superAdmin full access on madrasas"
  ON public.madrasas FOR ALL
  USING  (public.get_my_role() = 'superAdmin')
  WITH CHECK (public.get_my_role() = 'superAdmin');

-- admin sees only their own madrasa
CREATE POLICY "admin sees own madrasa"
  ON public.madrasas FOR SELECT
  USING (admin_user_id = auth.uid() OR public.get_my_role() = 'superAdmin');


-- ── darja_sections ─────────────────────────────
ALTER TABLE public.darja_sections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated users read darja_sections"
  ON public.darja_sections FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin manage darja_sections"
  ON public.darja_sections FOR ALL
  USING  (public.get_my_role() IN ('admin','superAdmin'))
  WITH CHECK (public.get_my_role() IN ('admin','superAdmin'));


-- ── library_books ──────────────────────────────
ALTER TABLE public.library_books ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read library_books"
  ON public.library_books FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin manage library_books"
  ON public.library_books FOR ALL
  USING  (public.get_my_role() IN ('admin','superAdmin'))
  WITH CHECK (public.get_my_role() IN ('admin','superAdmin'));


-- ── book_issues ────────────────────────────────
ALTER TABLE public.book_issues ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read book_issues"
  ON public.book_issues FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin manage book_issues"
  ON public.book_issues FOR ALL
  USING  (public.get_my_role() IN ('admin','superAdmin'))
  WITH CHECK (public.get_my_role() IN ('admin','superAdmin'));


-- ── finance_transactions ───────────────────────
ALTER TABLE public.finance_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read finance"
  ON public.finance_transactions FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "admin manage finance"
  ON public.finance_transactions FOR ALL
  USING  (public.get_my_role() IN ('admin','superAdmin'))
  WITH CHECK (public.get_my_role() IN ('admin','superAdmin'));


-- ── announcements (update existing RLS) ────────

-- Allow superAdmin to manage all announcements
DROP POLICY IF EXISTS "superAdmin manage announcements" ON public.announcements;
CREATE POLICY "superAdmin manage announcements"
  ON public.announcements FOR ALL
  USING  (public.get_my_role() = 'superAdmin')
  WITH CHECK (public.get_my_role() = 'superAdmin');


-- ═══════════════════════════════════════════════════════════════
-- 10. CREATE SUPERADMIN USER
--     Run this block separately after creating the user in
--     Supabase Auth Dashboard OR use the SQL below.
--
--     OPTION A — SQL method (uses service_role, run in SQL Editor):
-- ═══════════════════════════════════════════════════════════════

/*
  Step 1: Create the user via Supabase Auth (service_role required):

  SELECT auth.users; -- verify no existing user with this email

  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    role,
    is_super_admin
  )
  VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000',
    'superadmin@madrasa360.com',         -- ← change to your email
    crypt('***REDACTED-PASSWORD-ROTATED-2026-09-25***', gen_salt('bf')), -- ← change to your password
    NOW(),
    '{"role": "superAdmin", "provider": "email", "providers": ["email"]}',
    '{"name": "Super Admin"}',
    NOW(),
    NOW(),
    'authenticated',
    FALSE
  );

  Step 2: Verify the profile was auto-created (via trigger):

  SELECT id, name, role FROM public.profiles
   WHERE role = 'superAdmin';

  If profile was NOT auto-created (trigger may not run for direct inserts), run:

  INSERT INTO public.profiles (id, name, role)
  SELECT id, 'Super Admin', 'superAdmin'
    FROM auth.users
   WHERE email = 'superadmin@madrasa360.com'
  ON CONFLICT (id) DO UPDATE SET role = 'superAdmin';
*/


-- ═══════════════════════════════════════════════════════════════
-- PROMOTE EXISTING USER TO superAdmin
-- Run this if you already have a user and just want to make them superAdmin:
-- ═══════════════════════════════════════════════════════════════

/*
  -- Step 1: Update app_metadata (controls login routing)
  UPDATE auth.users
     SET raw_app_meta_data = raw_app_meta_data || '{"role": "superAdmin"}'::jsonb
   WHERE email = 'your-existing-user@email.com';  -- ← replace with actual email

  -- Step 2: Update profile table
  UPDATE public.profiles
     SET role = 'superAdmin'
   WHERE id = (SELECT id FROM auth.users WHERE email = 'your-existing-user@email.com');
*/
