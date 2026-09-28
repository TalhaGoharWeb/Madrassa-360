-- ═══════════════════════════════════════════════════════════════
-- Migration 014 — Finance rebuild (Phase 4, mission §§28–29)
--
-- Replaces the flat legacy finance_transactions log with a proper
-- invoice → payment → receipt → ledger flow:
--
--   fee_structures / fee_items      — what is charged (per darja / year)
--   invoices / invoice_items        — what is billed to a student
--   payments / payment_allocations  — money received (+ receipt numbers)
--   refunds                         — money returned (reversal entries)
--   discounts / scholarships        — reductions applied to invoices
--   income / expenses               — non-fee money in / out
--   accounts                        — chart of accounts (cash, bank, …)
--   transactions                    — the canonical posted ledger
--
-- Every table carries tenant_id (NOT NULL, FK → tenants) and follows the
-- Phase-2 helper pattern from 007_tenant_rls.sql:
--   is_platform_admin() OR (is_tenant_member(tid) AND
--   tenant_has_permission(tid, '<code>'))
-- All 9 permission codes used below are real codes seeded in 005_rbac.sql
-- (verified): fees.view/create/collect/refund,
-- finance.view/create/update/delete/approve.
-- (007 established the contract: 005 has no fees.update/delete, so
--  fees.collect covers fee-domain mutation; results.* pattern not needed.)
--
-- IMMUTABILITY (mission-critical): finalized/posted rows are immutable.
-- Enforced TWICE —
--   1. RLS: UPDATE/DELETE policies only match non-final rows
--      (final rows match NO policy, so default-deny applies — even to
--      platform admins), and
--   2. public.finance_immutable_guard() trigger raises on any
--      UPDATE/DELETE of a final row (backstop for service_role / bugs).
-- Corrections happen via REVERSAL entries only (refunds, void invoices,
-- reversing ledger lines), never by editing history.
--
-- AUDIT: 012_audit_logs.log_audit() requires the CALLER to be a tenant
-- admin/owner, so accountant-initiated writes (fees.collect etc.) cannot
-- call it directly. Instead the SECURITY DEFINER trigger
-- public.finance_audit() writes equivalent append-only rows to
-- public.audit_logs (user_id = auth.uid(), tenant from the row) on every
-- INSERT/UPDATE/DELETE of the 13 tables — same table, same shape as
-- log_audit() would produce. Edge Functions (service_role) may still use
-- log_audit() for higher-level actions.
--
-- LEGACY RECONCILIATION (no silent-miss DROPs — names verified by grep):
--   * public.finance_transactions (05_new_modules.sql:216, tenant_id added
--     by 006, tenant policies by 007) — KEPT AS-IS. Historical data stays
--     readable; NEW writes go to the 014 ledger. NOT dropped, NOT altered.
--   * public.fees (01_schema.sql:161, retrofitted by 006/007) — KEPT AS-IS
--     (owned by the fees worker); new fee flows use invoices.
--   * This file creates NO object named finance_transactions/fees and
--     drops no legacy finance object.
--
-- Conventions (per 001 header): ordered, idempotent
-- (IF NOT EXISTS / OR REPLACE / DROP IF EXISTS + pg_policies guards),
-- version stamped in public.schema_migrations.
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) Document/receipt sequences
-- ═══════════════════════════════════════════════════════════════

CREATE SEQUENCE IF NOT EXISTS public.finance_invoice_seq;
CREATE SEQUENCE IF NOT EXISTS public.finance_receipt_seq;


-- ═══════════════════════════════════════════════════════════════
-- (b) TABLES
-- ═══════════════════════════════════════════════════════════════

-- ── accounts: chart of accounts (config, not posted records) ──
CREATE TABLE IF NOT EXISTS public.accounts (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  code            TEXT        NOT NULL,
  name            TEXT        NOT NULL,
  name_urdu       TEXT,
  account_type    TEXT        NOT NULL
                    CHECK (account_type IN ('asset','liability','equity','income','expense')),
  parent_id       UUID        REFERENCES public.accounts(id) ON DELETE SET NULL,
  is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
  opening_balance NUMERIC(14,2) NOT NULL DEFAULT 0,
  created_by      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
COMMENT ON TABLE public.accounts IS '014: chart of accounts per tenant (cash, bank, …). Config data — RLS-governed, no posted-row immutability.';

-- ── fee_structures: named fee schedules (per darja / academic year) ──
CREATE TABLE IF NOT EXISTS public.fee_structures (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name          TEXT        NOT NULL,
  name_urdu     TEXT,
  darja_id      UUID        REFERENCES public.darjas(id) ON DELETE SET NULL,
  academic_year TEXT        NOT NULL,
  is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
  created_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name, academic_year)
);
COMMENT ON TABLE public.fee_structures IS '014: fee schedules — what is charged per darja/year. Invoices are generated from these.';

-- ── fee_items: line items inside a fee structure ──
CREATE TABLE IF NOT EXISTS public.fee_items (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  fee_structure_id UUID        NOT NULL REFERENCES public.fee_structures(id) ON DELETE CASCADE,
  name             TEXT        NOT NULL,
  name_urdu        TEXT,
  amount           NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
  frequency        TEXT        NOT NULL DEFAULT 'monthly'
                     CHECK (frequency IN ('monthly','quarterly','annual','one_time')),
  is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
  created_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.fee_items IS '014: individual charges inside a fee structure (tuition, admission, exam fee …).';

-- ── invoices: bills raised against students ──
CREATE TABLE IF NOT EXISTS public.invoices (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  student_id       UUID        NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
  fee_structure_id UUID        REFERENCES public.fee_structures(id) ON DELETE SET NULL,
  invoice_number   TEXT,
  billing_month    TEXT,                       -- 'YYYY-MM'
  issue_date       DATE        NOT NULL DEFAULT CURRENT_DATE,
  due_date         DATE        NOT NULL,
  subtotal         NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  discount_total   NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (discount_total >= 0),
  tax_total        NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tax_total >= 0),
  total            NUMERIC(14,2)
                     GENERATED ALWAYS AS (subtotal - discount_total + tax_total) STORED,
  amount_paid      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  balance_due      NUMERIC(14,2)
                     GENERATED ALWAYS AS (subtotal - discount_total + tax_total - amount_paid) STORED,
  status           TEXT        NOT NULL DEFAULT 'draft'
                     CHECK (status IN ('draft','issued','partially_paid','paid','overdue','cancelled','void')),
  reversed_by_id   UUID        REFERENCES public.invoices(id) ON DELETE SET NULL,
  notes            TEXT,
  created_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, invoice_number)
);
COMMENT ON TABLE public.invoices IS '014: student invoices. Final states (paid/cancelled/void) are IMMUTABLE — corrections via reversal invoices (reversed_by_id), never edits.';

-- ── invoice_items: billed lines on an invoice ──
CREATE TABLE IF NOT EXISTS public.invoice_items (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  invoice_id   UUID        NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  fee_item_id  UUID        REFERENCES public.fee_items(id) ON DELETE RESTRICT,
  description  TEXT        NOT NULL,
  quantity     NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_amount  NUMERIC(14,2) NOT NULL CHECK (unit_amount >= 0),
  line_total   NUMERIC(14,2)
                 GENERATED ALWAYS AS (quantity * unit_amount) STORED,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.invoice_items IS '014: billed lines; subtotal is recomputed on the parent invoice by trigger.';

-- ── payments: money received (receipts) ──
CREATE TABLE IF NOT EXISTS public.payments (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  student_id     UUID        REFERENCES public.students(id) ON DELETE RESTRICT,
  invoice_id     UUID        REFERENCES public.invoices(id) ON DELETE SET NULL,
  account_id     UUID        REFERENCES public.accounts(id) ON DELETE RESTRICT,
  amount         NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  payment_date   DATE        NOT NULL DEFAULT CURRENT_DATE,
  method         TEXT        NOT NULL DEFAULT 'cash'
                   CHECK (method IN ('cash','bank_transfer','jazzcash','easypaisa','cheque','other')),
  receipt_number TEXT,
  status         TEXT        NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','posted','void')),
  posted_at      TIMESTAMPTZ,
  notes          TEXT,
  created_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, receipt_number)
);
COMMENT ON TABLE public.payments IS '014: receipts. Posting (draft→posted) auto-creates the ledger entry + allocation via trigger. Posted/void rows are IMMUTABLE.';

-- ── payment_allocations: which invoice(s) a payment settled ──
CREATE TABLE IF NOT EXISTS public.payment_allocations (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  payment_id UUID        NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  invoice_id UUID        NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  amount     NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.payment_allocations IS '014: payment→invoice links. Fully immutable (no UPDATE/DELETE for anyone) — fix by reversing the payment.';

-- ── refunds: money returned (reversal entries) ──
CREATE TABLE IF NOT EXISTS public.refunds (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  payment_id  UUID        NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
  student_id  UUID        REFERENCES public.students(id) ON DELETE RESTRICT,
  amount      NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  reason      TEXT        NOT NULL,
  refund_date DATE        NOT NULL DEFAULT CURRENT_DATE,
  status      TEXT        NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','approved','posted','void')),
  posted_at   TIMESTAMPTZ,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.refunds IS '014: refunds are reversal entries — the correction mechanism for posted payments. Approved/posted/void rows immutable.';

-- ── discounts: reductions applied to invoices ──
CREATE TABLE IF NOT EXISTS public.discounts (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  student_id    UUID        REFERENCES public.students(id) ON DELETE RESTRICT,
  invoice_id    UUID        REFERENCES public.invoices(id) ON DELETE CASCADE,
  discount_type TEXT        NOT NULL CHECK (discount_type IN ('percentage','fixed')),
  value         NUMERIC(14,2) NOT NULL CHECK (value >= 0),
  reason        TEXT,
  status        TEXT        NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','applied','void')),
  applied_at    TIMESTAMPTZ,
  created_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (discount_type <> 'percentage' OR value <= 100)
);
COMMENT ON TABLE public.discounts IS '014: invoice discounts. Applying (draft→applied) recomputes the invoice discount_total via trigger. Applied/void rows immutable.';

-- ── scholarships: longer-term grants per student ──
CREATE TABLE IF NOT EXISTS public.scholarships (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  student_id       UUID        NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
  name             TEXT        NOT NULL,
  discount_percent NUMERIC(5,2) NOT NULL CHECK (discount_percent >= 0 AND discount_percent <= 100),
  start_date       DATE        NOT NULL,
  end_date         DATE,
  status           TEXT        NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active','expired','revoked')),
  created_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.scholarships IS '014: scholarship grants. Revocation is a status change, not a delete.';

-- ── expenses: money out (non-fee) ──
CREATE TABLE IF NOT EXISTS public.expenses (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  category    TEXT        NOT NULL,
  recipient   TEXT,
  amount      NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  account_id  UUID        REFERENCES public.accounts(id) ON DELETE RESTRICT,
  expense_date DATE       NOT NULL DEFAULT CURRENT_DATE,
  receipt_url TEXT,
  description TEXT,
  status      TEXT        NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','approved','posted','void')),
  posted_at   TIMESTAMPTZ,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.expenses IS '014: expenses. Lifecycle draft→approved (finance.approve)→posted (finance.create); posting writes the ledger entry. Posted/void immutable.';

-- ── income: money in (non-fee: donations, zakat, sadqa …) ──
CREATE TABLE IF NOT EXISTS public.income (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  source_type    TEXT        NOT NULL
                   CHECK (source_type IN ('donation','zakat','sadqa','fee','other')),
  donor_name     TEXT,
  amount         NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  account_id     UUID        REFERENCES public.accounts(id) ON DELETE RESTRICT,
  received_date  DATE        NOT NULL DEFAULT CURRENT_DATE,
  receipt_number TEXT,
  description    TEXT,
  status         TEXT        NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','approved','posted','void')),
  posted_at      TIMESTAMPTZ,
  created_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, receipt_number)
);
COMMENT ON TABLE public.income IS '014: non-fee income. Same draft→approved→posted lifecycle as expenses. Posted/void immutable.';

-- ── transactions: the canonical posted ledger ──
CREATE TABLE IF NOT EXISTS public.transactions (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  entry_date     DATE        NOT NULL DEFAULT CURRENT_DATE,
  kind           TEXT        NOT NULL CHECK (kind IN ('income','expense','transfer')),
  category       TEXT        NOT NULL,
  amount         NUMERIC(14,2) NOT NULL CHECK (amount > 0),
  account_id     UUID        REFERENCES public.accounts(id) ON DELETE RESTRICT,
  description    TEXT,
  reference_type TEXT        CHECK (reference_type IN ('payment','refund','expense','income','invoice','manual')),
  reference_id   UUID,
  status         TEXT        NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','posted','void')),
  posted_at      TIMESTAMPTZ,
  created_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.transactions IS '014: canonical financial ledger. Posted/void rows are IMMUTABLE — corrections are new reversing rows (reference_type of the original), never edits.';


-- ═══════════════════════════════════════════════════════════════
-- (c) INDEXES — btree on tenant_id for every table + composites
-- ═══════════════════════════════════════════════════════════════

-- accounts
CREATE INDEX IF NOT EXISTS idx_accounts_tenant          ON public.accounts (tenant_id);
CREATE INDEX IF NOT EXISTS idx_accounts_tenant_created  ON public.accounts (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_accounts_parent          ON public.accounts (parent_id);

-- fee_structures
CREATE INDEX IF NOT EXISTS idx_fee_structures_tenant         ON public.fee_structures (tenant_id);
CREATE INDEX IF NOT EXISTS idx_fee_structures_tenant_active ON public.fee_structures (tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_fee_structures_darja          ON public.fee_structures (darja_id);

-- fee_items
CREATE INDEX IF NOT EXISTS idx_fee_items_tenant     ON public.fee_items (tenant_id);
CREATE INDEX IF NOT EXISTS idx_fee_items_structure  ON public.fee_items (fee_structure_id);
CREATE INDEX IF NOT EXISTS idx_fee_items_tenant_active ON public.fee_items (tenant_id, is_active);

-- invoices
CREATE INDEX IF NOT EXISTS idx_invoices_tenant          ON public.invoices (tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_created  ON public.invoices (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_tenant_status   ON public.invoices (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_student         ON public.invoices (student_id);
CREATE INDEX IF NOT EXISTS idx_invoices_student_status  ON public.invoices (student_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_billing_month   ON public.invoices (tenant_id, billing_month);
CREATE INDEX IF NOT EXISTS idx_invoices_due_date        ON public.invoices (due_date);

-- invoice_items
CREATE INDEX IF NOT EXISTS idx_invoice_items_tenant  ON public.invoice_items (tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON public.invoice_items (invoice_id);

-- payments
CREATE INDEX IF NOT EXISTS idx_payments_tenant         ON public.payments (tenant_id);
CREATE INDEX IF NOT EXISTS idx_payments_tenant_created ON public.payments (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_tenant_status  ON public.payments (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_payments_student        ON public.payments (student_id);
CREATE INDEX IF NOT EXISTS idx_payments_invoice        ON public.payments (invoice_id);
CREATE INDEX IF NOT EXISTS idx_payments_date           ON public.payments (tenant_id, payment_date DESC);

-- payment_allocations
CREATE INDEX IF NOT EXISTS idx_pay_allocs_tenant  ON public.payment_allocations (tenant_id);
CREATE INDEX IF NOT EXISTS idx_pay_allocs_payment ON public.payment_allocations (payment_id);
CREATE INDEX IF NOT EXISTS idx_pay_allocs_invoice ON public.payment_allocations (invoice_id);

-- refunds
CREATE INDEX IF NOT EXISTS idx_refunds_tenant         ON public.refunds (tenant_id);
CREATE INDEX IF NOT EXISTS idx_refunds_tenant_created ON public.refunds (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_refunds_tenant_status  ON public.refunds (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_refunds_payment         ON public.refunds (payment_id);
CREATE INDEX IF NOT EXISTS idx_refunds_student         ON public.refunds (student_id);

-- discounts
CREATE INDEX IF NOT EXISTS idx_discounts_tenant         ON public.discounts (tenant_id);
CREATE INDEX IF NOT EXISTS idx_discounts_tenant_status  ON public.discounts (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_discounts_invoice        ON public.discounts (invoice_id);
CREATE INDEX IF NOT EXISTS idx_discounts_student        ON public.discounts (student_id);

-- scholarships
CREATE INDEX IF NOT EXISTS idx_scholarships_tenant         ON public.scholarships (tenant_id);
CREATE INDEX IF NOT EXISTS idx_scholarships_tenant_status  ON public.scholarships (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_scholarships_student        ON public.scholarships (student_id);

-- expenses
CREATE INDEX IF NOT EXISTS idx_expenses_tenant         ON public.expenses (tenant_id);
CREATE INDEX IF NOT EXISTS idx_expenses_tenant_created ON public.expenses (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_tenant_status  ON public.expenses (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_expenses_date           ON public.expenses (tenant_id, expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_category       ON public.expenses (tenant_id, category);

-- income
CREATE INDEX IF NOT EXISTS idx_income_tenant         ON public.income (tenant_id);
CREATE INDEX IF NOT EXISTS idx_income_tenant_created ON public.income (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_income_tenant_status  ON public.income (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_income_date           ON public.income (tenant_id, received_date DESC);
CREATE INDEX IF NOT EXISTS idx_income_source         ON public.income (tenant_id, source_type);

-- transactions (ledger)
CREATE INDEX IF NOT EXISTS idx_transactions_tenant         ON public.transactions (tenant_id);
CREATE INDEX IF NOT EXISTS idx_transactions_tenant_created ON public.transactions (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_tenant_status  ON public.transactions (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_transactions_date           ON public.transactions (tenant_id, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_kind           ON public.transactions (tenant_id, kind);
CREATE INDEX IF NOT EXISTS idx_transactions_account        ON public.transactions (account_id);
CREATE INDEX IF NOT EXISTS idx_transactions_reference      ON public.transactions (reference_type, reference_id);


-- ═══════════════════════════════════════════════════════════════
-- (d) TRIGGER FUNCTIONS
-- Automation functions are SECURITY DEFINER (SET search_path = public)
-- so posting flows work regardless of the caller's row-level grants;
-- RLS still gates what the CLIENT may initiate.
-- ═══════════════════════════════════════════════════════════════

-- ── Audit writer ──
-- Writes append-only rows to public.audit_logs (same shape log_audit()
-- produces). A SECURITY DEFINER trigger — NOT log_audit() itself —
-- because log_audit() requires the caller to be a tenant admin/owner,
-- which would break accountant-initiated writes (fees.collect etc.).
CREATE OR REPLACE FUNCTION public.finance_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old    JSONB;
  v_new    JSONB;
  v_id     TEXT;
  v_tenant UUID;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_new := to_jsonb(NEW); v_id := NEW.id::text; v_tenant := NEW.tenant_id;
  ELSIF TG_OP = 'UPDATE' THEN
    v_old := to_jsonb(OLD); v_new := to_jsonb(NEW);
    v_id := NEW.id::text; v_tenant := NEW.tenant_id;
  ELSE
    v_old := to_jsonb(OLD); v_id := OLD.id::text; v_tenant := OLD.tenant_id;
  END IF;

  INSERT INTO public.audit_logs
    (tenant_id, user_id, action, entity, entity_id, old_data, new_data, metadata)
  VALUES
    (v_tenant, auth.uid(), TG_OP || '_' || TG_TABLE_NAME, TG_TABLE_NAME, v_id,
     v_old, v_new, jsonb_build_object('source', 'finance_014_trigger'));

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ── Immutability guard ──
-- TG_ARGV[0]: comma-separated final statuses, or 'ALL' (no status column).
-- Raises on ANY update/delete touching a final row — backstop behind RLS.
CREATE OR REPLACE FUNCTION public.finance_immutable_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_ARGV[0] = 'ALL' THEN
    RAISE EXCEPTION 'finance: %.% is immutable; correct via reversal entry',
      TG_TABLE_NAME, COALESCE(OLD.id::text, NEW.id::text);
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.status = ANY (string_to_array(TG_ARGV[0], ',')) THEN
      RAISE EXCEPTION 'finance: %.% is % and immutable; correct via reversal entry',
        TG_TABLE_NAME, OLD.id::text, OLD.status;
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.status = ANY (string_to_array(TG_ARGV[0], ',')) THEN
    RAISE EXCEPTION 'finance: %.% is % and immutable; correct via reversal entry',
      TG_TABLE_NAME, OLD.id::text, OLD.status;
  END IF;
  RETURN NEW;
END;
$$;

-- ── Document numbers: INV-… / RCP-… ──
CREATE OR REPLACE FUNCTION public.finance_fill_doc_numbers()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_TABLE_NAME = 'invoices'
     AND (NEW.invoice_number IS NULL OR btrim(NEW.invoice_number) = '') THEN
    NEW.invoice_number :=
      'INV-' || lpad(nextval('public.finance_invoice_seq')::text, 8, '0');
  ELSIF TG_TABLE_NAME IN ('payments', 'income')
     AND (NEW.receipt_number IS NULL OR btrim(NEW.receipt_number) = '') THEN
    NEW.receipt_number :=
      'RCP-' || lpad(nextval('public.finance_receipt_seq')::text, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

-- ── Invoice status refresh (paid / partially_paid / overdue …) ──
CREATE OR REPLACE FUNCTION public.finance_refresh_invoice_status(p_invoice_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.invoices
     SET status = CASE
                    WHEN status IN ('draft','cancelled','void') THEN status
                    WHEN amount_paid >= total AND total > 0 THEN 'paid'
                    WHEN amount_paid > 0 THEN 'partially_paid'
                    WHEN due_date < CURRENT_DATE THEN 'overdue'
                    ELSE 'issued'
                  END,
         updated_at = now()
   WHERE id = p_invoice_id;
END;
$$;

-- ── Invoice totals recalc (subtotal from lines, discount_total from
--    applied discounts) + status refresh ──
CREATE OR REPLACE FUNCTION public.finance_recalc_invoice(p_invoice_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub NUMERIC(14,2);
BEGIN
  SELECT COALESCE(SUM(line_total), 0) INTO v_sub
    FROM public.invoice_items
   WHERE invoice_id = p_invoice_id;

  UPDATE public.invoices i
     SET subtotal       = v_sub,
         discount_total = COALESCE((
                            SELECT SUM(
                              CASE WHEN d.discount_type = 'fixed' THEN d.value
                                   ELSE round(v_sub * d.value / 100, 2)
                              END)
                              FROM public.discounts d
                             WHERE d.invoice_id = p_invoice_id
                               AND d.status = 'applied'
                          ), 0),
         updated_at = now()
   WHERE i.id = p_invoice_id;

  PERFORM public.finance_refresh_invoice_status(p_invoice_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.finance_trg_recalc_invoice()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice UUID;
BEGIN
  v_invoice := COALESCE(NEW.invoice_id, OLD.invoice_id);
  IF v_invoice IS NOT NULL THEN
    PERFORM public.finance_recalc_invoice(v_invoice);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ── invoice_items may only change while the parent is draft/issued ──
CREATE OR REPLACE FUNCTION public.finance_guard_invoice_item_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status  TEXT;
  v_invoice UUID;
BEGIN
  v_invoice := COALESCE(NEW.invoice_id, OLD.invoice_id);
  SELECT status INTO v_status FROM public.invoices WHERE id = v_invoice;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'finance: parent invoice % not found', v_invoice;
  END IF;
  IF v_status NOT IN ('draft', 'issued') THEN
    RAISE EXCEPTION 'finance: invoice % is % — line items immutable; issue a reversal invoice',
      v_invoice, v_status;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ── Payment posting: ledger entry + allocation + invoice update ──
CREATE OR REPLACE FUNCTION public.finance_post_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alloc NUMERIC(14,2);
BEGIN
  IF NEW.status = 'posted' AND OLD.status <> 'posted' THEN
    NEW.posted_at := COALESCE(NEW.posted_at, now());

    -- 1. canonical ledger entry (born posted)
    INSERT INTO public.transactions
      (tenant_id, entry_date, kind, category, amount, account_id,
       description, reference_type, reference_id, status, posted_at, created_by)
    VALUES
      (NEW.tenant_id, NEW.payment_date, 'income', 'fee', NEW.amount,
       NEW.account_id,
       COALESCE('Payment ' || NEW.receipt_number, 'Fee payment'),
       'payment', NEW.id, 'posted', now(), NEW.created_by);

    -- 2. allocate against the invoice (never over-allocate)
    IF NEW.invoice_id IS NOT NULL THEN
      SELECT LEAST(NEW.amount, balance_due) INTO v_alloc
        FROM public.invoices WHERE id = NEW.invoice_id;
      IF v_alloc IS NOT NULL AND v_alloc > 0 THEN
        INSERT INTO public.payment_allocations
          (tenant_id, payment_id, invoice_id, amount)
        VALUES (NEW.tenant_id, NEW.id, NEW.invoice_id, v_alloc);

        UPDATE public.invoices
           SET amount_paid = amount_paid + v_alloc,
               updated_at  = now()
         WHERE id = NEW.invoice_id;

        PERFORM public.finance_refresh_invoice_status(NEW.invoice_id);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ── Refund posting: reversing ledger entry + invoice amount_paid down ──
CREATE OR REPLACE FUNCTION public.finance_post_refund()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice UUID;
  v_relief  NUMERIC(14,2);
BEGIN
  IF NEW.status = 'posted' AND OLD.status <> 'posted' THEN
    NEW.posted_at := COALESCE(NEW.posted_at, now());

    INSERT INTO public.transactions
      (tenant_id, entry_date, kind, category, amount, account_id,
       description, reference_type, reference_id, status, posted_at, created_by)
    SELECT NEW.tenant_id, NEW.refund_date, 'expense', 'refund', NEW.amount,
           p.account_id,
           'Refund: ' || NEW.reason,
           'refund', NEW.id, 'posted', now(), NEW.created_by
      FROM public.payments p WHERE p.id = NEW.payment_id;

    -- relieve the invoice the original payment settled
    SELECT invoice_id INTO v_invoice
      FROM public.payments WHERE id = NEW.payment_id;
    IF v_invoice IS NOT NULL THEN
      SELECT LEAST(NEW.amount, amount_paid) INTO v_relief
        FROM public.invoices WHERE id = v_invoice;
      IF v_relief IS NOT NULL AND v_relief > 0 THEN
        UPDATE public.invoices
           SET amount_paid = amount_paid - v_relief,
               updated_at  = now()
         WHERE id = v_invoice;
        PERFORM public.finance_refresh_invoice_status(v_invoice);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ── Expense / income posting: ledger entry ──
CREATE OR REPLACE FUNCTION public.finance_post_expense_income()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'posted' AND OLD.status <> 'posted' THEN
    NEW.posted_at := COALESCE(NEW.posted_at, now());
    IF TG_TABLE_NAME = 'expenses' THEN
      INSERT INTO public.transactions
        (tenant_id, entry_date, kind, category, amount, account_id,
         description, reference_type, reference_id, status, posted_at, created_by)
      VALUES
        (NEW.tenant_id, NEW.expense_date, 'expense', NEW.category, NEW.amount,
         NEW.account_id, NEW.description, 'expense', NEW.id,
         'posted', now(), NEW.created_by);
    ELSE
      INSERT INTO public.transactions
        (tenant_id, entry_date, kind, category, amount, account_id,
         description, reference_type, reference_id, status, posted_at, created_by)
      VALUES
        (NEW.tenant_id, NEW.received_date, 'income', NEW.source_type, NEW.amount,
         NEW.account_id,
         COALESCE(NEW.description, 'Income ' || NEW.receipt_number),
         'income', NEW.id, 'posted', now(), NEW.created_by);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ── Discount apply/void: stamp applied_at + recalc parent invoice ──
CREATE OR REPLACE FUNCTION public.finance_trg_discount_applied()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'applied' AND OLD.status <> 'applied' THEN
    NEW.applied_at := COALESCE(NEW.applied_at, now());
  END IF;
  IF NEW.invoice_id IS NOT NULL
     AND (OLD.status IS DISTINCT FROM NEW.status OR TG_OP = 'DELETE') THEN
    PERFORM public.finance_recalc_invoice(NEW.invoice_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;


-- ═══════════════════════════════════════════════════════════════
-- (e) TRIGGER ATTACHMENTS
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  t TEXT;
BEGIN
  -- updated_at maintenance + tenant_id immutability + audit on all 13
  FOREACH t IN ARRAY ARRAY[
    'accounts','fee_structures','fee_items','invoices','invoice_items',
    'payments','payment_allocations','refunds','discounts','scholarships',
    'expenses','income','transactions'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_prevent_tenant_change ON public.%1$s', t);
    EXECUTE format('CREATE TRIGGER trg_%1$s_prevent_tenant_change
                      BEFORE UPDATE ON public.%1$s
                      FOR EACH ROW EXECUTE FUNCTION public.prevent_tenant_id_change()', t);

    EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_audit ON public.%1$s', t);
    EXECUTE format('CREATE TRIGGER trg_%1$s_audit
                      AFTER INSERT OR UPDATE OR DELETE ON public.%1$s
                      FOR EACH ROW EXECUTE FUNCTION public.finance_audit()', t);

    IF t <> 'payment_allocations' THEN  -- allocations have no updated_at
      EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_set_updated_at ON public.%1$s', t);
      EXECUTE format('CREATE TRIGGER trg_%1$s_set_updated_at
                        BEFORE UPDATE ON public.%1$s
                        FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', t);
    END IF;
  END LOOP;
END;
$$;

-- ── Immutability guards (final rows: no UPDATE/DELETE, anyone) ──
DROP TRIGGER IF EXISTS trg_invoices_guard_immutable ON public.invoices;
CREATE TRIGGER trg_invoices_guard_immutable
  BEFORE UPDATE OR DELETE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('paid,cancelled,void');

DROP TRIGGER IF EXISTS trg_payments_guard_immutable ON public.payments;
CREATE TRIGGER trg_payments_guard_immutable
  BEFORE UPDATE OR DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('posted,void');

DROP TRIGGER IF EXISTS trg_transactions_guard_immutable ON public.transactions;
CREATE TRIGGER trg_transactions_guard_immutable
  BEFORE UPDATE OR DELETE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('posted,void');

DROP TRIGGER IF EXISTS trg_income_guard_immutable ON public.income;
CREATE TRIGGER trg_income_guard_immutable
  BEFORE UPDATE OR DELETE ON public.income
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('posted,void');

DROP TRIGGER IF EXISTS trg_expenses_guard_immutable ON public.expenses;
CREATE TRIGGER trg_expenses_guard_immutable
  BEFORE UPDATE OR DELETE ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('posted,void');

DROP TRIGGER IF EXISTS trg_refunds_guard_immutable ON public.refunds;
CREATE TRIGGER trg_refunds_guard_immutable
  BEFORE UPDATE OR DELETE ON public.refunds
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('approved,posted,void');

DROP TRIGGER IF EXISTS trg_discounts_guard_immutable ON public.discounts;
CREATE TRIGGER trg_discounts_guard_immutable
  BEFORE UPDATE OR DELETE ON public.discounts
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('applied,void');

DROP TRIGGER IF EXISTS trg_payment_allocations_guard_immutable ON public.payment_allocations;
CREATE TRIGGER trg_payment_allocations_guard_immutable
  BEFORE UPDATE OR DELETE ON public.payment_allocations
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('ALL');

-- ── Document numbers ──
DROP TRIGGER IF EXISTS trg_invoices_fill_doc_numbers ON public.invoices;
CREATE TRIGGER trg_invoices_fill_doc_numbers
  BEFORE INSERT ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.finance_fill_doc_numbers();

DROP TRIGGER IF EXISTS trg_payments_fill_doc_numbers ON public.payments;
CREATE TRIGGER trg_payments_fill_doc_numbers
  BEFORE INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.finance_fill_doc_numbers();

DROP TRIGGER IF EXISTS trg_income_fill_doc_numbers ON public.income;
CREATE TRIGGER trg_income_fill_doc_numbers
  BEFORE INSERT ON public.income
  FOR EACH ROW EXECUTE FUNCTION public.finance_fill_doc_numbers();

-- ── invoice_items: parent guard + totals recalc ──
DROP TRIGGER IF EXISTS trg_invoice_items_parent_guard ON public.invoice_items;
CREATE TRIGGER trg_invoice_items_parent_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.invoice_items
  FOR EACH ROW EXECUTE FUNCTION public.finance_guard_invoice_item_parent();

DROP TRIGGER IF EXISTS trg_invoice_items_recalc ON public.invoice_items;
CREATE TRIGGER trg_invoice_items_recalc
  AFTER INSERT OR UPDATE OR DELETE ON public.invoice_items
  FOR EACH ROW EXECUTE FUNCTION public.finance_trg_recalc_invoice();

-- ── discounts: apply stamp + parent recalc ──
DROP TRIGGER IF EXISTS trg_discounts_apply_recalc ON public.discounts;
CREATE TRIGGER trg_discounts_apply_recalc
  BEFORE INSERT OR UPDATE OR DELETE ON public.discounts
  FOR EACH ROW EXECUTE FUNCTION public.finance_trg_discount_applied();

-- ── Posting flows: payment / refund / expense / income → ledger ──
DROP TRIGGER IF EXISTS trg_payments_post ON public.payments;
CREATE TRIGGER trg_payments_post
  BEFORE UPDATE OF status ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.finance_post_payment();

DROP TRIGGER IF EXISTS trg_refunds_post ON public.refunds;
CREATE TRIGGER trg_refunds_post
  BEFORE UPDATE OF status ON public.refunds
  FOR EACH ROW EXECUTE FUNCTION public.finance_post_refund();

DROP TRIGGER IF EXISTS trg_expenses_post ON public.expenses;
CREATE TRIGGER trg_expenses_post
  BEFORE UPDATE OF status ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.finance_post_expense_income();

DROP TRIGGER IF EXISTS trg_income_post ON public.income;
CREATE TRIGGER trg_income_post
  BEFORE UPDATE OF status ON public.income
  FOR EACH ROW EXECUTE FUNCTION public.finance_post_expense_income();


-- ═══════════════════════════════════════════════════════════════
-- (f) RLS — tenant-bound policies (Phase-2 helper pattern, 007-style)
-- Final/posted rows match NO update/delete policy (default-deny), so
-- they are immutable even for platform admins; corrections use
-- reversal entries. public.finance_immutable_guard() is the backstop.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.accounts            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_structures      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_items           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discounts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scholarships        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.income              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions        ENABLE ROW LEVEL SECURITY;


-- ── accounts (finance.*) — config table, plain CRUD ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='accounts' AND policyname='accounts_select_tenant') THEN
    CREATE POLICY "accounts_select_tenant" ON public.accounts FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(accounts.tenant_id)
        AND public.tenant_has_permission(accounts.tenant_id, 'finance.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='accounts' AND policyname='accounts_insert_tenant') THEN
    CREATE POLICY "accounts_insert_tenant" ON public.accounts FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(accounts.tenant_id)
        AND public.tenant_has_permission(accounts.tenant_id, 'finance.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='accounts' AND policyname='accounts_update_tenant') THEN
    CREATE POLICY "accounts_update_tenant" ON public.accounts FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(accounts.tenant_id)
        AND public.tenant_has_permission(accounts.tenant_id, 'finance.view'))
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(accounts.tenant_id)
        AND public.tenant_has_permission(accounts.tenant_id, 'finance.update'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='accounts' AND policyname='accounts_delete_tenant') THEN
    CREATE POLICY "accounts_delete_tenant" ON public.accounts FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(accounts.tenant_id)
        AND public.tenant_has_permission(accounts.tenant_id, 'finance.delete'))
    );
  END IF;
END $$;


-- ── fee_structures (fees.view / fees.create / fees.collect) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_structures' AND policyname='fee_structures_select_tenant') THEN
    CREATE POLICY "fee_structures_select_tenant" ON public.fee_structures FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(fee_structures.tenant_id)
        AND public.tenant_has_permission(fee_structures.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_structures' AND policyname='fee_structures_insert_tenant') THEN
    CREATE POLICY "fee_structures_insert_tenant" ON public.fee_structures FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(fee_structures.tenant_id)
        AND public.tenant_has_permission(fee_structures.tenant_id, 'fees.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_structures' AND policyname='fee_structures_update_tenant') THEN
    CREATE POLICY "fee_structures_update_tenant" ON public.fee_structures FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(fee_structures.tenant_id)
        AND public.tenant_has_permission(fee_structures.tenant_id, 'fees.view'))
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(fee_structures.tenant_id)
        AND public.tenant_has_permission(fee_structures.tenant_id, 'fees.collect'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_structures' AND policyname='fee_structures_delete_tenant') THEN
    CREATE POLICY "fee_structures_delete_tenant" ON public.fee_structures FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(fee_structures.tenant_id)
        AND public.tenant_has_permission(fee_structures.tenant_id, 'fees.collect'))
    );
  END IF;
END $$;


-- ── fee_items (fees.view / fees.create / fees.collect) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_items' AND policyname='fee_items_select_tenant') THEN
    CREATE POLICY "fee_items_select_tenant" ON public.fee_items FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(fee_items.tenant_id)
        AND public.tenant_has_permission(fee_items.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_items' AND policyname='fee_items_insert_tenant') THEN
    CREATE POLICY "fee_items_insert_tenant" ON public.fee_items FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(fee_items.tenant_id)
        AND public.tenant_has_permission(fee_items.tenant_id, 'fees.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_items' AND policyname='fee_items_update_tenant') THEN
    CREATE POLICY "fee_items_update_tenant" ON public.fee_items FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(fee_items.tenant_id)
        AND public.tenant_has_permission(fee_items.tenant_id, 'fees.view'))
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(fee_items.tenant_id)
        AND public.tenant_has_permission(fee_items.tenant_id, 'fees.collect'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='fee_items' AND policyname='fee_items_delete_tenant') THEN
    CREATE POLICY "fee_items_delete_tenant" ON public.fee_items FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(fee_items.tenant_id)
        AND public.tenant_has_permission(fee_items.tenant_id, 'fees.collect'))
    );
  END IF;
END $$;


-- ── invoices (fees.*) — paid/cancelled/void rows immutable ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices' AND policyname='invoices_select_tenant') THEN
    CREATE POLICY "invoices_select_tenant" ON public.invoices FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(invoices.tenant_id)
        AND public.tenant_has_permission(invoices.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices' AND policyname='invoices_insert_tenant') THEN
    CREATE POLICY "invoices_insert_tenant" ON public.invoices FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(invoices.tenant_id)
        AND public.tenant_has_permission(invoices.tenant_id, 'fees.create')
        AND invoices.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices' AND policyname='invoices_update_tenant') THEN
    CREATE POLICY "invoices_update_tenant" ON public.invoices FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(invoices.tenant_id)
        AND public.tenant_has_permission(invoices.tenant_id, 'fees.collect')
        AND invoices.status IN ('draft', 'issued'))
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(invoices.tenant_id)
        AND public.tenant_has_permission(invoices.tenant_id, 'fees.collect')
        AND invoices.status IN ('draft', 'issued', 'cancelled', 'void'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices' AND policyname='invoices_delete_tenant') THEN
    CREATE POLICY "invoices_delete_tenant" ON public.invoices FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(invoices.tenant_id)
        AND public.tenant_has_permission(invoices.tenant_id, 'fees.collect')
        AND invoices.status = 'draft')
    );
  END IF;
END $$;


-- ── invoice_items (fees.*) — parent guard trigger enforces draft/issued ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoice_items' AND policyname='invoice_items_select_tenant') THEN
    CREATE POLICY "invoice_items_select_tenant" ON public.invoice_items FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(invoice_items.tenant_id)
        AND public.tenant_has_permission(invoice_items.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoice_items' AND policyname='invoice_items_insert_tenant') THEN
    CREATE POLICY "invoice_items_insert_tenant" ON public.invoice_items FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(invoice_items.tenant_id)
        AND public.tenant_has_permission(invoice_items.tenant_id, 'fees.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoice_items' AND policyname='invoice_items_update_tenant') THEN
    CREATE POLICY "invoice_items_update_tenant" ON public.invoice_items FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(invoice_items.tenant_id)
        AND public.tenant_has_permission(invoice_items.tenant_id, 'fees.view'))
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(invoice_items.tenant_id)
        AND public.tenant_has_permission(invoice_items.tenant_id, 'fees.collect'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoice_items' AND policyname='invoice_items_delete_tenant') THEN
    CREATE POLICY "invoice_items_delete_tenant" ON public.invoice_items FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(invoice_items.tenant_id)
        AND public.tenant_has_permission(invoice_items.tenant_id, 'fees.collect'))
    );
  END IF;
END $$;


-- ── payments (fees.view / fees.collect) — posted/void immutable ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='payments' AND policyname='payments_select_tenant') THEN
    CREATE POLICY "payments_select_tenant" ON public.payments FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(payments.tenant_id)
        AND public.tenant_has_permission(payments.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='payments' AND policyname='payments_insert_tenant') THEN
    CREATE POLICY "payments_insert_tenant" ON public.payments FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(payments.tenant_id)
        AND public.tenant_has_permission(payments.tenant_id, 'fees.collect')
        AND payments.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='payments' AND policyname='payments_update_tenant') THEN
    CREATE POLICY "payments_update_tenant" ON public.payments FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(payments.tenant_id)
        AND public.tenant_has_permission(payments.tenant_id, 'fees.collect')
        AND payments.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(payments.tenant_id)
        AND public.tenant_has_permission(payments.tenant_id, 'fees.collect')
        AND payments.status IN ('draft', 'posted', 'void'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='payments' AND policyname='payments_delete_tenant') THEN
    CREATE POLICY "payments_delete_tenant" ON public.payments FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(payments.tenant_id)
        AND public.tenant_has_permission(payments.tenant_id, 'fees.collect')
        AND payments.status = 'draft')
    );
  END IF;
END $$;


-- ── payment_allocations — insert-only linkage, fully immutable ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='payment_allocations' AND policyname='payment_allocations_select_tenant') THEN
    CREATE POLICY "payment_allocations_select_tenant" ON public.payment_allocations FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(payment_allocations.tenant_id)
        AND public.tenant_has_permission(payment_allocations.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='payment_allocations' AND policyname='payment_allocations_insert_tenant') THEN
    CREATE POLICY "payment_allocations_insert_tenant" ON public.payment_allocations FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(payment_allocations.tenant_id)
        AND public.tenant_has_permission(payment_allocations.tenant_id, 'fees.collect'))
    );
  END IF;
  -- Deliberately NO update/delete policies: immutable linkage.
END $$;


-- ── refunds (fees.view / fees.refund; approval via finance.approve) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='refunds' AND policyname='refunds_select_tenant') THEN
    CREATE POLICY "refunds_select_tenant" ON public.refunds FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='refunds' AND policyname='refunds_insert_tenant') THEN
    CREATE POLICY "refunds_insert_tenant" ON public.refunds FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'fees.refund')
        AND refunds.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='refunds' AND policyname='refunds_update_tenant') THEN
    CREATE POLICY "refunds_update_tenant" ON public.refunds FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'fees.refund')
        AND refunds.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'fees.refund')
        AND refunds.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='refunds' AND policyname='refunds_approve_tenant') THEN
    CREATE POLICY "refunds_approve_tenant" ON public.refunds FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'finance.approve')
        AND refunds.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'finance.approve')
        AND refunds.status = 'approved' AND refunds.approved_by IS NOT NULL)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='refunds' AND policyname='refunds_post_tenant') THEN
    CREATE POLICY "refunds_post_tenant" ON public.refunds FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'fees.refund')
        AND refunds.status = 'approved')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'fees.refund')
        AND refunds.status = 'posted')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='refunds' AND policyname='refunds_delete_tenant') THEN
    CREATE POLICY "refunds_delete_tenant" ON public.refunds FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(refunds.tenant_id)
        AND public.tenant_has_permission(refunds.tenant_id, 'fees.refund')
        AND refunds.status = 'draft')
    );
  END IF;
END $$;


-- ── discounts (fees.view / fees.create / fees.collect) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='discounts' AND policyname='discounts_select_tenant') THEN
    CREATE POLICY "discounts_select_tenant" ON public.discounts FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(discounts.tenant_id)
        AND public.tenant_has_permission(discounts.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='discounts' AND policyname='discounts_insert_tenant') THEN
    CREATE POLICY "discounts_insert_tenant" ON public.discounts FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(discounts.tenant_id)
        AND public.tenant_has_permission(discounts.tenant_id, 'fees.create')
        AND discounts.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='discounts' AND policyname='discounts_update_tenant') THEN
    CREATE POLICY "discounts_update_tenant" ON public.discounts FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(discounts.tenant_id)
        AND public.tenant_has_permission(discounts.tenant_id, 'fees.collect')
        AND discounts.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(discounts.tenant_id)
        AND public.tenant_has_permission(discounts.tenant_id, 'fees.collect')
        AND discounts.status IN ('draft', 'applied', 'void'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='discounts' AND policyname='discounts_delete_tenant') THEN
    CREATE POLICY "discounts_delete_tenant" ON public.discounts FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(discounts.tenant_id)
        AND public.tenant_has_permission(discounts.tenant_id, 'fees.collect')
        AND discounts.status = 'draft')
    );
  END IF;
END $$;


-- ── scholarships (fees.view / fees.create / fees.collect) ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='scholarships' AND policyname='scholarships_select_tenant') THEN
    CREATE POLICY "scholarships_select_tenant" ON public.scholarships FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(scholarships.tenant_id)
        AND public.tenant_has_permission(scholarships.tenant_id, 'fees.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='scholarships' AND policyname='scholarships_insert_tenant') THEN
    CREATE POLICY "scholarships_insert_tenant" ON public.scholarships FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(scholarships.tenant_id)
        AND public.tenant_has_permission(scholarships.tenant_id, 'fees.create'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='scholarships' AND policyname='scholarships_update_tenant') THEN
    CREATE POLICY "scholarships_update_tenant" ON public.scholarships FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(scholarships.tenant_id)
        AND public.tenant_has_permission(scholarships.tenant_id, 'fees.view'))
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(scholarships.tenant_id)
        AND public.tenant_has_permission(scholarships.tenant_id, 'fees.collect'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='scholarships' AND policyname='scholarships_delete_tenant') THEN
    CREATE POLICY "scholarships_delete_tenant" ON public.scholarships FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(scholarships.tenant_id)
        AND public.tenant_has_permission(scholarships.tenant_id, 'fees.collect'))
    );
  END IF;
END $$;


-- ── expenses (finance.*) — draft→approved (finance.approve)→posted ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='expenses_select_tenant') THEN
    CREATE POLICY "expenses_select_tenant" ON public.expenses FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='expenses_insert_tenant') THEN
    CREATE POLICY "expenses_insert_tenant" ON public.expenses FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.create')
        AND expenses.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='expenses_update_tenant') THEN
    CREATE POLICY "expenses_update_tenant" ON public.expenses FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.update')
        AND expenses.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.update')
        AND expenses.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='expenses_approve_tenant') THEN
    CREATE POLICY "expenses_approve_tenant" ON public.expenses FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.approve')
        AND expenses.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.approve')
        AND expenses.status = 'approved' AND expenses.approved_by IS NOT NULL)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='expenses_post_tenant') THEN
    CREATE POLICY "expenses_post_tenant" ON public.expenses FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.create')
        AND expenses.status = 'approved')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.create')
        AND expenses.status = 'posted')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='expenses_delete_tenant') THEN
    CREATE POLICY "expenses_delete_tenant" ON public.expenses FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(expenses.tenant_id)
        AND public.tenant_has_permission(expenses.tenant_id, 'finance.delete')
        AND expenses.status = 'draft')
    );
  END IF;
END $$;


-- ── income (finance.*) — same lifecycle as expenses ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='income' AND policyname='income_select_tenant') THEN
    CREATE POLICY "income_select_tenant" ON public.income FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='income' AND policyname='income_insert_tenant') THEN
    CREATE POLICY "income_insert_tenant" ON public.income FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.create')
        AND income.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='income' AND policyname='income_update_tenant') THEN
    CREATE POLICY "income_update_tenant" ON public.income FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.update')
        AND income.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.update')
        AND income.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='income' AND policyname='income_approve_tenant') THEN
    CREATE POLICY "income_approve_tenant" ON public.income FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.approve')
        AND income.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.approve')
        AND income.status = 'approved' AND income.approved_by IS NOT NULL)
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='income' AND policyname='income_post_tenant') THEN
    CREATE POLICY "income_post_tenant" ON public.income FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.create')
        AND income.status = 'approved')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.create')
        AND income.status = 'posted')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='income' AND policyname='income_delete_tenant') THEN
    CREATE POLICY "income_delete_tenant" ON public.income FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(income.tenant_id)
        AND public.tenant_has_permission(income.tenant_id, 'finance.delete')
        AND income.status = 'draft')
    );
  END IF;
END $$;


-- ── transactions: the ledger (finance.*) — posted/void immutable ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='transactions_select_tenant') THEN
    CREATE POLICY "transactions_select_tenant" ON public.transactions FOR SELECT USING (
      public.is_platform_admin() OR (public.is_tenant_member(transactions.tenant_id)
        AND public.tenant_has_permission(transactions.tenant_id, 'finance.view'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='transactions_insert_tenant') THEN
    CREATE POLICY "transactions_insert_tenant" ON public.transactions FOR INSERT WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(transactions.tenant_id)
        AND public.tenant_has_permission(transactions.tenant_id, 'finance.create')
        AND transactions.status = 'draft')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='transactions_update_tenant') THEN
    CREATE POLICY "transactions_update_tenant" ON public.transactions FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(transactions.tenant_id)
        AND public.tenant_has_permission(transactions.tenant_id, 'finance.update')
        AND transactions.status = 'draft')
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(transactions.tenant_id)
        AND public.tenant_has_permission(transactions.tenant_id, 'finance.update')
        AND transactions.status IN ('draft', 'posted', 'void'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='transactions' AND policyname='transactions_delete_tenant') THEN
    CREATE POLICY "transactions_delete_tenant" ON public.transactions FOR DELETE USING (
      public.is_platform_admin() OR (public.is_tenant_member(transactions.tenant_id)
        AND public.tenant_has_permission(transactions.tenant_id, 'finance.delete')
        AND transactions.status = 'draft')
    );
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- (g) FAIL-LOUD verification — every 014 table must exist with RLS
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_missing TEXT;
BEGIN
  SELECT string_agg(t, ', ') INTO v_missing
  FROM (VALUES
    ('accounts'), ('fee_structures'), ('fee_items'), ('invoices'),
    ('invoice_items'), ('payments'), ('payment_allocations'), ('refunds'),
    ('discounts'), ('scholarships'), ('expenses'), ('income'), ('transactions')
  ) AS v(t)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'public' AND tablename = v.t AND rowsecurity
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '014_finance: RLS not enabled on: %', v_missing;
  END IF;
END $$;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('014_finance')
ON CONFLICT DO NOTHING;
