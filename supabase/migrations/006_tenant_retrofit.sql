-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 006: tenant retrofit (add tenant_id)
-- Phase 2 / Author B
--
-- Run AFTER 001–005 (Author A: tenants, tenant_settings, tenant_modules,
-- tenant_memberships + platform_admins + helper functions, RBAC reconcile).
--
-- What it does:
--   1. Adds tenant_id UUID to all 13 business tables.
--   2. Backfills tenant_id from madrasa_id via the tenants rows migrated
--      from madrasas in 004 (joined on the deterministic tenant_code).
--   3. Creates a 'Legacy Institution' (slug 'legacy') tenant IFF any rows
--      remain unresolvable, and assigns them to it.
--   4. Sets tenant_id NOT NULL, adds FK -> tenants(id) ON DELETE RESTRICT,
--      and installs an immutability trigger on every table.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS / DROP CONSTRAINT IF EXISTS /
--             DROP TRIGGER IF EXISTS / ON CONFLICT DO NOTHING.
-- Indexes on tenant_id are intentionally NOT created here (see 009).
--
-- Contract dependencies (Author A):
--   public.tenants(id, name, name_urdu, slug UNIQUE, status, ...)
--   public.schema_migrations(version) with a uniqueness on version.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- Immutability guard: tenant_id may never change once set.
-- (Moving a row between tenants is a data-migration operation,
--  never an application UPDATE.)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.prevent_tenant_id_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
    RAISE EXCEPTION 'tenant_id is immutable and cannot be changed (table: %)', TG_TABLE_NAME;
  END IF;
  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- Step 1–3: add columns, backfill, legacy tenant
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_legacy_id  UUID;
  v_unresolved BIGINT;
BEGIN
  -- ── 1) add tenant_id to all 13 business tables ──────────────
  ALTER TABLE public.darjas               ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.classes              ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.students             ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.staff                ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.attendance           ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.fees                 ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.exams                ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.results              ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.announcements        ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.darja_sections       ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.library_books        ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.book_issues          ADD COLUMN IF NOT EXISTS tenant_id UUID;
  ALTER TABLE public.finance_transactions ADD COLUMN IF NOT EXISTS tenant_id UUID;

  -- ── 2) backfill tables that carry madrasa_id ────────────────
  -- Mapping: 004 migrates each madrasa to exactly one tenant with a
  -- DETERMINISTIC tenant_code = 'M-' + first 8 hex chars of the madrasa id
  -- (uppercased). Joining on tenant_code is exact and immune to duplicate
  -- madrasa names (a name-based fallback is unnecessary: if 004 ran, the
  -- code join resolves; if it did not, no madrasa-derived tenant exists).
  -- Tables without madrasa_id (classes, students, staff, attendance, fees,
  -- exams, results) are intentionally NOT chain-resolved here; they fall
  -- through to the legacy tenant in step 3 (per migration spec).
  UPDATE public.darjas d
     SET tenant_id = t.id
    FROM public.madrasas m
    JOIN public.tenants t
      ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
   WHERE d.madrasa_id = m.id AND d.tenant_id IS NULL;

  UPDATE public.announcements a
     SET tenant_id = t.id
    FROM public.madrasas m
    JOIN public.tenants t
      ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
   WHERE a.madrasa_id = m.id AND a.tenant_id IS NULL;

  UPDATE public.darja_sections ds
     SET tenant_id = t.id
    FROM public.madrasas m
    JOIN public.tenants t
      ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
   WHERE ds.madrasa_id = m.id AND ds.tenant_id IS NULL;

  UPDATE public.library_books lb
     SET tenant_id = t.id
    FROM public.madrasas m
    JOIN public.tenants t
      ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
   WHERE lb.madrasa_id = m.id AND lb.tenant_id IS NULL;

  UPDATE public.book_issues bi
     SET tenant_id = t.id
    FROM public.madrasas m
    JOIN public.tenants t
      ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
   WHERE bi.madrasa_id = m.id AND bi.tenant_id IS NULL;

  UPDATE public.finance_transactions ft
     SET tenant_id = t.id
    FROM public.madrasas m
    JOIN public.tenants t
      ON t.tenant_code = 'M-' || upper(substr(replace(m.id::text, '-', ''), 1, 8))
   WHERE ft.madrasa_id = m.id AND ft.tenant_id IS NULL;

  -- ── 3) legacy tenant for anything still unresolvable ────────
  SELECT COUNT(*) INTO v_unresolved FROM (
    SELECT 1 FROM public.darjas               WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.classes              WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.students             WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.staff                WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.attendance           WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.fees                 WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.exams                WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.results              WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.announcements        WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.darja_sections       WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.library_books        WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.book_issues          WHERE tenant_id IS NULL UNION ALL
    SELECT 1 FROM public.finance_transactions WHERE tenant_id IS NULL
  ) s;

  IF v_unresolved > 0 THEN
    -- 002/003 triggers auto-provision tenant_settings / tenant_modules.
    INSERT INTO public.tenants (name, name_urdu, slug, status)
    VALUES ('Legacy Institution', 'لیگیسی ادارہ', 'legacy', 'trial')
    ON CONFLICT (slug) DO NOTHING;

    SELECT id INTO v_legacy_id FROM public.tenants WHERE slug = 'legacy';

    UPDATE public.darjas               SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.classes              SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.students             SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.staff                SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.attendance           SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.fees                 SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.exams                SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.results              SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.announcements        SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.darja_sections       SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.library_books        SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.book_issues          SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;
    UPDATE public.finance_transactions SET tenant_id = v_legacy_id WHERE tenant_id IS NULL;

    RAISE NOTICE '006: % unresolvable rows assigned to legacy tenant', v_unresolved;
  ELSE
    RAISE NOTICE '006: all rows resolved to migrated tenants; no legacy tenant created';
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────
-- Step 4: NOT NULL + FK + immutability trigger, per table
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- darjas
  ALTER TABLE public.darjas ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.darjas DROP CONSTRAINT IF EXISTS darjas_tenant_id_fkey;
  ALTER TABLE public.darjas ADD CONSTRAINT darjas_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.darjas;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.darjas
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- classes
  ALTER TABLE public.classes ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.classes DROP CONSTRAINT IF EXISTS classes_tenant_id_fkey;
  ALTER TABLE public.classes ADD CONSTRAINT classes_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.classes;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.classes
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- students
  ALTER TABLE public.students ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.students DROP CONSTRAINT IF EXISTS students_tenant_id_fkey;
  ALTER TABLE public.students ADD CONSTRAINT students_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.students;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.students
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- staff
  ALTER TABLE public.staff ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_tenant_id_fkey;
  ALTER TABLE public.staff ADD CONSTRAINT staff_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.staff;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.staff
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- attendance
  ALTER TABLE public.attendance ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS attendance_tenant_id_fkey;
  ALTER TABLE public.attendance ADD CONSTRAINT attendance_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.attendance;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.attendance
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- fees
  ALTER TABLE public.fees ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.fees DROP CONSTRAINT IF EXISTS fees_tenant_id_fkey;
  ALTER TABLE public.fees ADD CONSTRAINT fees_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.fees;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.fees
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- exams
  ALTER TABLE public.exams ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.exams DROP CONSTRAINT IF EXISTS exams_tenant_id_fkey;
  ALTER TABLE public.exams ADD CONSTRAINT exams_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.exams;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.exams
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- results
  ALTER TABLE public.results ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.results DROP CONSTRAINT IF EXISTS results_tenant_id_fkey;
  ALTER TABLE public.results ADD CONSTRAINT results_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.results;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.results
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- announcements
  ALTER TABLE public.announcements ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.announcements DROP CONSTRAINT IF EXISTS announcements_tenant_id_fkey;
  ALTER TABLE public.announcements ADD CONSTRAINT announcements_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.announcements;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.announcements
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- darja_sections
  ALTER TABLE public.darja_sections ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.darja_sections DROP CONSTRAINT IF EXISTS darja_sections_tenant_id_fkey;
  ALTER TABLE public.darja_sections ADD CONSTRAINT darja_sections_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.darja_sections;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.darja_sections
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- library_books
  ALTER TABLE public.library_books ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.library_books DROP CONSTRAINT IF EXISTS library_books_tenant_id_fkey;
  ALTER TABLE public.library_books ADD CONSTRAINT library_books_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.library_books;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.library_books
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- book_issues
  ALTER TABLE public.book_issues ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.book_issues DROP CONSTRAINT IF EXISTS book_issues_tenant_id_fkey;
  ALTER TABLE public.book_issues ADD CONSTRAINT book_issues_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.book_issues;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.book_issues
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();

  -- finance_transactions
  ALTER TABLE public.finance_transactions ALTER COLUMN tenant_id SET NOT NULL;
  ALTER TABLE public.finance_transactions DROP CONSTRAINT IF EXISTS finance_transactions_tenant_id_fkey;
  ALTER TABLE public.finance_transactions ADD CONSTRAINT finance_transactions_tenant_id_fkey
    FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
  DROP TRIGGER IF EXISTS trg_prevent_tenant_id_change ON public.finance_transactions;
  CREATE TRIGGER trg_prevent_tenant_id_change
    BEFORE UPDATE ON public.finance_transactions
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change();
END $$;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('006_tenant_retrofit') ON CONFLICT DO NOTHING;
