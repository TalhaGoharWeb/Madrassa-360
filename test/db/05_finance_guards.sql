-- ═══════════════════════════════════════════════════════════════════
-- 05_finance_guards.sql — SEC-C6 / SEC-H16 / SEC-H17 / 042 CHECKs
--
-- Asserts the financial safety net deployed by migrations 034
-- (transition guards) and 042 (domain CHECKs):
--   (a) finance_force_draft_on_insert: payments/refunds/expenses/income/
--       transactions cannot be INSERTed with status='posted' (ghost
--       receipts / fabricated ledger). INSERT with any non-draft status
--       must raise.
--   (b) finance_transition_guard: draft→posted on payments is legal;
--       posted is terminal (posted→draft must raise).
--   (c) finance_guard_invoice_status: derived statuses (paid,
--       partially_paid, overdue) cannot be written directly — only
--       finance_refresh_invoice_status() may set them.
--   (d) 042 CHECKs: results marks sane (0 <= obtained <= total);
--       fees amounts non-negative. Each block SKIPs if its table or
--       constraint is absent (pre-fix snapshot).
--
-- RUN: psql "<staging-direct-url>" -v ON_ERROR_STOP=1 -f test/db/05_finance_guards.sql
--      (postgres superuser / service_role connection string; everything is
--      wrapped in a transaction and ROLLED BACK at the end.)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── fixtures ─────────────────────────────────────────────────────
INSERT INTO auth.users (id, aud, role, email, encrypted_password,
                       email_confirmed_at, created_at, updated_at,
                       raw_app_meta_data, raw_user_meta_data, is_super_admin)
VALUES
  ('f5f5f5f5-f5f5-4f5f-8f5f-f5f5f5f5f5f5', 'authenticated', 'authenticated',
   'sec-clerk@example.com', 'dummy', now(), now(), now(), '{}', '{}', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenants (id, name, slug) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SEC Test Tenant A', 'sec-test-a')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_memberships (tenant_id, user_id, role, is_active) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f5f5f5f5-f5f5-4f5f-8f5f-f5f5f5f5f5f5', 'accountant', true)
ON CONFLICT (user_id, tenant_id) DO NOTHING;

DO $$
DECLARE
  v_force_draft BOOLEAN;
  v_transition  BOOLEAN;
  v_invoice_guard BOOLEAN;
  v_pay_id UUID;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_payments_force_draft')
    INTO v_force_draft;
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_payments_transition_guard')
    INTO v_transition;
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_invoices_guard_derived_status')
    INTO v_invoice_guard;
  IF NOT (v_force_draft AND v_transition AND v_invoice_guard) THEN
    RAISE NOTICE 'SKIP: 034 finance guards not fully deployed (force_draft=%, transition=%, invoice_guard=%)',
      v_force_draft, v_transition, v_invoice_guard;
    RETURN;
  END IF;
  RAISE NOTICE 'PASS (presence): 034 finance guard triggers deployed';

  -- ── (a) ghost receipt: INSERT payment as 'posted' must raise ──
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','f5f5f5f5-f5f5-4f5f-8f5f-f5f5f5f5f5f5','role','authenticated')::text, true);
  BEGIN
    INSERT INTO public.payments (tenant_id, amount, status)
    VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 50000, 'posted');
    RAISE EXCEPTION 'FAIL (a): payment inserted with status=posted (ghost receipt)';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (a)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (a): posted-on-insert rejected: %', SQLERRM;
  END;

  -- ── (a2) draft insert still works ──
  BEGIN
    INSERT INTO public.payments (tenant_id, amount, status)
    VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 50000, 'draft')
    RETURNING id INTO v_pay_id;
    RAISE NOTICE 'PASS (a2): draft payment insert works';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL (a2): draft payment insert broke: %', SQLERRM;
  END;

  -- ── (b) draft→posted legal; posted terminal ──
  BEGIN
    UPDATE public.payments SET status = 'posted' WHERE id = v_pay_id;
    RAISE NOTICE 'PASS (b): draft→posted transition allowed';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL (b): legal draft→posted transition rejected: %', SQLERRM;
  END;
  BEGIN
    UPDATE public.payments SET status = 'draft' WHERE id = v_pay_id;
    RAISE EXCEPTION 'FAIL (b2): posted→draft transition allowed (terminal state mutable)';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (b2)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (b2): posted is terminal: %', SQLERRM;
  END;
  RESET ROLE;
END $$;

-- ── (c) invoice derived-status guard (needs a students row) ──
DO $$
DECLARE
  v_students BOOLEAN;
  v_inv_id UUID;
BEGIN
  SELECT to_regclass('public.students') IS NOT NULL INTO v_students;
  IF NOT v_students THEN
    RAISE NOTICE 'SKIP (c): public.students not in migration chain (schema drift SEC-M) — invoice guard block skipped';
    RETURN;
  END IF;
  -- Minimal student row; column set kept to the stable core.
  BEGIN
    INSERT INTO public.students (id, tenant_id, name)
    VALUES ('c9c9c9c9-c9c9-4c9c-8c9c-c9c9c9c9c9c9',
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'SEC Student')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'SKIP (c): cannot seed students row: %', SQLERRM;
    RETURN;
  END;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','f5f5f5f5-f5f5-4f5f-8f5f-f5f5f5f5f5f5','role','authenticated')::text, true);
  INSERT INTO public.invoices (tenant_id, student_id, due_date, subtotal, status)
  VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'c9c9c9c9-c9c9-4c9c-8c9c-c9c9c9c9c9c9',
          CURRENT_DATE + 30, 10000, 'draft')
  RETURNING id INTO v_inv_id;

  BEGIN
    UPDATE public.invoices SET status = 'paid' WHERE id = v_inv_id;
    RAISE EXCEPTION 'FAIL (c): invoice flipped to derived status paid with no payment';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL (c)%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS (c): derived invoice status rejected: %', SQLERRM;
  END;

  BEGIN
    UPDATE public.invoices SET status = 'issued' WHERE id = v_inv_id;
    RAISE NOTICE 'PASS (c2): legal draft→issued transition allowed';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL (c2): legal draft→issued rejected: %', SQLERRM;
  END;
  RESET ROLE;
END $$;

-- ── (d) 042 domain CHECKs ──
DO $$
DECLARE
  v_marks_chk BOOLEAN;
  v_fees_chk  BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_results_marks_sane')
    INTO v_marks_chk;
  IF NOT v_marks_chk THEN
    RAISE NOTICE 'SKIP (d): chk_results_marks_sane not deployed';
  ELSE
    BEGIN
      INSERT INTO public.results (tenant_id, marks_obtained, total_marks)
      VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 999999, 100);
      RAISE EXCEPTION 'FAIL (d): marks_obtained=999999/100 accepted';
    EXCEPTION WHEN check_violation THEN
      RAISE NOTICE 'PASS (d): insane marks rejected by CHECK';
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL (d): rejected but not by CHECK (SQLSTATE %): %', SQLSTATE, SQLERRM;
    END;
    BEGIN
      INSERT INTO public.results (tenant_id, marks_obtained, total_marks)
      VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', -5, 100);
      RAISE EXCEPTION 'FAIL (d2): negative marks accepted';
    EXCEPTION WHEN check_violation THEN
      RAISE NOTICE 'PASS (d2): negative marks rejected by CHECK';
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL (d2): rejected but not by CHECK (SQLSTATE %): %', SQLSTATE, SQLERRM;
    END;
  END IF;

  SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_fees_amounts_sane')
    INTO v_fees_chk;
  IF NOT v_fees_chk THEN
    RAISE NOTICE 'SKIP (d3): chk_fees_amounts_sane not deployed (legacy fees table)';
  ELSE
    BEGIN
      INSERT INTO public.fees (tenant_id, amount_due, amount_paid)
      VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', -100, 0);
      RAISE EXCEPTION 'FAIL (d3): negative fee amount accepted';
    EXCEPTION WHEN check_violation THEN
      RAISE NOTICE 'PASS (d3): negative fee amount rejected by CHECK';
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL (d3): rejected but not by CHECK (SQLSTATE %): %', SQLSTATE, SQLERRM;
    END;
  END IF;
END $$;

-- ── (e) idempotency: duplicate idempotency_key rejected (SEC-H17) ──
DO $$
DECLARE
  v_idem BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ux_payments_idem')
    INTO v_idem;
  IF NOT v_idem THEN
    RAISE NOTICE 'SKIP (e): ux_payments_idem not deployed';
    RETURN;
  END IF;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub','f5f5f5f5-f5f5-4f5f-8f5f-f5f5f5f5f5f5','role','authenticated')::text, true);
  BEGIN
    INSERT INTO public.payments (tenant_id, amount, status, idempotency_key)
    VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1000, 'draft', 'idem-test-001');
    INSERT INTO public.payments (tenant_id, amount, status, idempotency_key)
    VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1000, 'draft', 'idem-test-001');
    RAISE EXCEPTION 'FAIL (e): duplicate idempotency_key accepted (double-charge possible)';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS (e): duplicate idempotency_key rejected';
  WHEN OTHERS THEN
    IF SQLERRM LIKE 'FAIL (e)%' THEN RAISE; END IF;
    RAISE EXCEPTION 'FAIL (e): unexpected error (SQLSTATE %): %', SQLSTATE, SQLERRM;
  END;
  RESET ROLE;
END $$;

ROLLBACK;
