-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 025: repair finance document-number columns
--
-- Run AFTER 024.
--
-- Why this exists:
--   On databases where the finance tables (invoices, payments, income) were
--   created BEFORE migration 014 ran, 014's `CREATE TABLE IF NOT EXISTS`
--   skipped the tables — so the document-number columns were never added —
--   while 014's `finance_fill_doc_numbers()` trigger WAS created
--   (CREATE OR REPLACE + CREATE TRIGGER always run). Every INSERT into
--   invoices / payments / income then fails with:
--     42703: record "new" has no field "invoice_number"
--   This breaks invoice creation from the app itself, not just the demo seed.
--
-- What it does (fully idempotent — safe to re-run):
--   1. Adds the three document-number columns 014 intended, only if missing.
--   2. Adds 014's UNIQUE (tenant_id, invoice_number) constraint, only if
--      missing. (Postgres permits multiple NULLs in a UNIQUE constraint, so
--      pre-existing rows without numbers are unaffected.)
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS invoice_number TEXT;

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS receipt_number TEXT;

ALTER TABLE public.income
  ADD COLUMN IF NOT EXISTS receipt_number TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'invoices_tenant_id_invoice_number_key'
       AND conrelid = 'public.invoices'::regclass
  ) THEN
    ALTER TABLE public.invoices
      ADD CONSTRAINT invoices_tenant_id_invoice_number_key
      UNIQUE (tenant_id, invoice_number);
  END IF;
END
$$;

COMMENT ON COLUMN public.invoices.invoice_number IS
  '025: backfilled — auto-generated INV-… by finance_fill_doc_numbers() when NULL.';
COMMENT ON COLUMN public.payments.receipt_number IS
  '025: backfilled — auto-generated RCP-… by finance_fill_doc_numbers() when NULL.';
COMMENT ON COLUMN public.income.receipt_number IS
  '025: backfilled — auto-generated RCP-… by finance_fill_doc_numbers() when NULL.';
