-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 028: per-table finance doc-number triggers
--
-- Why this exists:
--   The shared finance_fill_doc_numbers() (014) branched on TG_TABLE_NAME
--   and referenced NEW.invoice_number / NEW.receipt_number across tables.
--   On some Supavisor connections the cached plan resolved a field that
--   does not exist on the triggering table → intermittent
--   42703: record "new" has no field "invoice_number".
--   Splitting into one tiny function per table removes the cross-table
--   field reference entirely.
--
-- Each new function references ONLY columns verified to exist:
--   invoices.invoice_number   (014 line 135; backfilled by 025)
--   payments.receipt_number   (014 line 187; backfilled by 025)
--   income.receipt_number     (014 line 303; backfilled by 025)
--
-- Doc-number format and sequences are UNCHANGED from 014:
--   'INV-' || lpad(nextval('public.finance_invoice_seq')::text, 8, '0')
--   'RCP-' || lpad(nextval('public.finance_receipt_seq')::text, 8, '0')
-- Trigger names are unchanged (trg_invoices/payments/income_fill_doc_numbers),
-- so the demo seed's drop/re-create block keeps working.
--
-- Idempotent: IF EXISTS / IF NOT EXISTS / CREATE OR REPLACE throughout.
-- ═══════════════════════════════════════════════════════════════


-- ── 1) Drop the shared triggers, then the shared function ──────
-- (Trigger drop must come first: a function with dependent triggers
-- cannot be dropped.)

DROP TRIGGER IF EXISTS trg_invoices_fill_doc_numbers ON public.invoices;
DROP TRIGGER IF EXISTS trg_payments_fill_doc_numbers ON public.payments;
DROP TRIGGER IF EXISTS trg_income_fill_doc_numbers  ON public.income;

DROP FUNCTION IF EXISTS public.finance_fill_doc_numbers();


-- ── 2) Sequences (created by 014; IF NOT EXISTS keeps partial DBs safe) ──

CREATE SEQUENCE IF NOT EXISTS public.finance_invoice_seq;
CREATE SEQUENCE IF NOT EXISTS public.finance_receipt_seq;


-- ── 3) Per-table functions (each touches only its own table's column) ──

CREATE OR REPLACE FUNCTION public.finance_fill_invoice_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.invoice_number IS NULL OR btrim(NEW.invoice_number) = '' THEN
    NEW.invoice_number :=
      'INV-' || lpad(nextval('public.finance_invoice_seq')::text, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.finance_fill_receipt_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.receipt_number IS NULL OR btrim(NEW.receipt_number) = '' THEN
    NEW.receipt_number :=
      'RCP-' || lpad(nextval('public.finance_receipt_seq')::text, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.finance_fill_income_doc_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.receipt_number IS NULL OR btrim(NEW.receipt_number) = '' THEN
    NEW.receipt_number :=
      'RCP-' || lpad(nextval('public.finance_receipt_seq')::text, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;


-- ── 4) Re-create the three BEFORE INSERT triggers (same names as 014) ──

CREATE TRIGGER trg_invoices_fill_doc_numbers
  BEFORE INSERT ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.finance_fill_invoice_number();

CREATE TRIGGER trg_payments_fill_doc_numbers
  BEFORE INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.finance_fill_receipt_number();

CREATE TRIGGER trg_income_fill_doc_numbers
  BEFORE INSERT ON public.income
  FOR EACH ROW EXECUTE FUNCTION public.finance_fill_income_doc_number();
