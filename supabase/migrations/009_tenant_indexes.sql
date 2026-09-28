-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 009: tenant indexes
-- Phase 2 / Author B
--
-- Run AFTER 007. All tenant_id indexes live here — 006 deliberately
-- creates none.
--
-- NOTE (deviation from brief): the brief lists students(tenant_id, status),
-- but public.students has no `status` column (it has `is_active`, verified
-- in 01_schema.sql). The composite is therefore (tenant_id, is_active).
--
-- Idempotent: every index uses IF NOT EXISTS.
-- ═══════════════════════════════════════════════════════════════


-- ── tenant_id btree on each of the 13 retrofit tables ─────────
CREATE INDEX IF NOT EXISTS idx_darjas_tenant               ON public.darjas (tenant_id);
CREATE INDEX IF NOT EXISTS idx_classes_tenant              ON public.classes (tenant_id);
CREATE INDEX IF NOT EXISTS idx_students_tenant             ON public.students (tenant_id);
CREATE INDEX IF NOT EXISTS idx_staff_tenant                ON public.staff (tenant_id);
CREATE INDEX IF NOT EXISTS idx_attendance_tenant           ON public.attendance (tenant_id);
CREATE INDEX IF NOT EXISTS idx_fees_tenant                 ON public.fees (tenant_id);
CREATE INDEX IF NOT EXISTS idx_exams_tenant                ON public.exams (tenant_id);
CREATE INDEX IF NOT EXISTS idx_results_tenant              ON public.results (tenant_id);
CREATE INDEX IF NOT EXISTS idx_announcements_tenant        ON public.announcements (tenant_id);
CREATE INDEX IF NOT EXISTS idx_darja_sections_tenant       ON public.darja_sections (tenant_id);
CREATE INDEX IF NOT EXISTS idx_library_books_tenant       ON public.library_books (tenant_id);
CREATE INDEX IF NOT EXISTS idx_book_issues_tenant         ON public.book_issues (tenant_id);
CREATE INDEX IF NOT EXISTS idx_finance_transactions_tenant ON public.finance_transactions (tenant_id);


-- ── composites on the hot query paths ────────────────────────
CREATE INDEX IF NOT EXISTS idx_attendance_tenant_date       ON public.attendance (tenant_id, date);
CREATE INDEX IF NOT EXISTS idx_attendance_tenant_class_date ON public.attendance (tenant_id, class_id, date);
CREATE INDEX IF NOT EXISTS idx_fees_tenant_student          ON public.fees (tenant_id, student_id);
CREATE INDEX IF NOT EXISTS idx_fees_tenant_month            ON public.fees (tenant_id, month);
CREATE INDEX IF NOT EXISTS idx_results_tenant_student       ON public.results (tenant_id, student_id);
CREATE INDEX IF NOT EXISTS idx_results_tenant_exam          ON public.results (tenant_id, exam_id);
CREATE INDEX IF NOT EXISTS idx_students_tenant_class        ON public.students (tenant_id, class_id);
CREATE INDEX IF NOT EXISTS idx_students_tenant_active       ON public.students (tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_announcements_tenant_active  ON public.announcements (tenant_id, is_active);


-- ── membership lookups (policy hot path) ─────────────────────
CREATE INDEX IF NOT EXISTS idx_tenant_memberships_user_active   ON public.tenant_memberships (user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_tenant_memberships_tenant_active ON public.tenant_memberships (tenant_id, is_active);


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('009_tenant_indexes') ON CONFLICT DO NOTHING;
