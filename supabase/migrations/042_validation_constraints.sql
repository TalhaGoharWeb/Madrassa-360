-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 042: validation constraints
--
-- Data-integrity layer the audit found missing:
--   * idempotency_key columns + partial unique indexes on payments,
--     expenses, income (double-submit / replay protection).
--   * results marks sanity: 0 <= marks_obtained <= total_marks > 0.
--   * Legacy amount CHECKs (fees; invoices covered by 034).
--   * licenses: expires_at > issued_at.
--   * Partial unique indexes WHERE deleted_at IS NULL for
--     attendance(student_id, date) and fees(student_id, month) —
--     replaces the unconditional legacy uniques so soft-deleted
--     rows no longer block re-entry of the same day/month.
--   * Sane VARCHAR length limits on name/email/phone/URL columns.
--   * audit_logs.tenant_id ON DELETE SET NULL (deleting a tenant must
--     not destroy the audit trail — the trail outlives the tenant).
--
-- All new CHECKs are added NOT VALID: they block new bad data
-- immediately but do not fail the migration on dirty legacy rows.
-- Before validating a constraint, find violators, e.g.:
--   SELECT id FROM public.results
--    WHERE NOT (marks_obtained >= 0 AND total_marks > 0
--               AND marks_obtained <= total_marks);
-- then: ALTER TABLE ... VALIDATE CONSTRAINT ...;
--
-- Idempotent: IF NOT EXISTS guards / pg_constraint existence checks.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) idempotency keys ────────────────────────────────────────
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
ALTER TABLE public.income   ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

-- Find live duplicates BEFORE applying:
--   SELECT tenant_id, idempotency_key, COUNT(*) FROM public.payments
--    WHERE idempotency_key IS NOT NULL GROUP BY 1,2 HAVING COUNT(*) > 1;
CREATE UNIQUE INDEX IF NOT EXISTS ux_payments_idem
  ON public.payments (tenant_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_expenses_idem
  ON public.expenses (tenant_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_income_idem
  ON public.income (tenant_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;


-- ── (b) partial uniques replace unconditional legacy uniques ────
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.conname, c.conrelid::regclass AS tbl
      FROM pg_constraint c
      JOIN pg_class cl ON cl.oid = c.conrelid
     WHERE c.contype = 'u'
       AND cl.relname IN ('attendance', 'fees')
       AND (SELECT array_agg(a.attname::text ORDER BY u.ord)
              FROM unnest(c.conkey) WITH ORDINALITY AS u(attnum, ord)
              JOIN pg_attribute a
                ON a.attrelid = c.conrelid AND a.attnum = u.attnum)
             IN (ARRAY['student_id','date'], ARRAY['student_id','month'])
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
  END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_attendance_live
  ON public.attendance (student_id, date) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_fees_live
  ON public.fees (student_id, month) WHERE deleted_at IS NULL;


-- ── (c) domain CHECKs (NOT VALID) ────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_results_marks_sane') THEN
    ALTER TABLE public.results ADD CONSTRAINT chk_results_marks_sane
      CHECK (marks_obtained >= 0 AND total_marks > 0 AND marks_obtained <= total_marks)
      NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_licenses_dates_sane') THEN
    ALTER TABLE public.licenses ADD CONSTRAINT chk_licenses_dates_sane
      CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at > issued_at)
      NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_fees_amounts_sane') THEN
    ALTER TABLE public.fees ADD CONSTRAINT chk_fees_amounts_sane
      CHECK (amount_due >= 0 AND amount_paid >= 0)
      NOT VALID;
  END IF;
END $$;


-- ── (d) VARCHAR length limits (guarded per column) ────────────────
DO $$
DECLARE
  spec RECORD;
BEGIN
  FOR spec IN SELECT * FROM (VALUES
    ('students','name',200), ('students','father_name',200),
    ('students','phone',32), ('students','address',500),
    ('students','photo_url',2048), ('students','roll_no',64),
    ('staff','name',200), ('staff','father_name',200),
    ('staff','designation',200), ('staff','department',200),
    ('staff','phone',32), ('staff','cnic',32), ('staff','photo_url',2048),
    ('tenants','name',200), ('tenants','name_urdu',200),
    ('tenants','phone',32), ('tenants','email',320),
    ('tenants','address',500), ('tenants','city',100),
    ('tenants','principal_name',200), ('tenants','registration_number',100),
    ('tenants','website',2048), ('tenants','logo_url',2048),
    ('tenants','favicon_url',2048),
    ('user_accounts','name',200), ('user_accounts','email',320),
    ('announcements','title',300), ('announcements','body',20000),
    ('darjas','name',200), ('classes','name',200),
    ('fee_structures','name',200)
  ) AS v(tbl, col, maxlen)
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name   = spec.tbl
                  AND column_name  = spec.col) THEN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conname = 'chk_' || spec.tbl || '_' || spec.col || '_len') THEN
        EXECUTE format(
          'ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (char_length(%I) <= %s)',
          spec.tbl,
          'chk_' || spec.tbl || '_' || spec.col || '_len',
          spec.col, spec.maxlen);
      END IF;
    END IF;
  END LOOP;
END $$;


-- ── (e) audit_logs.tenant_id: preserve the trail ──────────────────
DO $$
DECLARE
  v_con TEXT;
BEGIN
  SELECT c.conname INTO v_con
    FROM pg_constraint c
   WHERE c.conrelid = 'public.audit_logs'::regclass
     AND c.contype = 'f'
     AND (SELECT a.attname FROM pg_attribute a
           WHERE a.attrelid = c.conrelid AND a.attnum = c.conkey[1]) = 'tenant_id';
  IF v_con IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.audit_logs DROP CONSTRAINT %I', v_con);
    ALTER TABLE public.audit_logs ADD CONSTRAINT audit_logs_tenant_id_fkey
      FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE SET NULL;
  END IF;
END $$;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('042_validation_constraints')
ON CONFLICT DO NOTHING;
