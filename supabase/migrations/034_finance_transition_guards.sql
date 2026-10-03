-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 034: financial transition guards
--
-- SEC-C6: on the real write path (sync_apply) financial documents could
-- be inserted with status='posted' (ghost receipts, no ledger entry),
-- invoices flipped to derived statuses ('paid' with amount_paid = 0),
-- and approval steps skipped. This migration puts the workflow rules
-- in the DATABASE so no write path can bypass them:
--
-- (a) finance_force_draft_on_insert(): BEFORE INSERT on payments,
--     refunds, expenses, income, transactions — non-draft inserts raise,
--     except ledger rows created by the posting triggers (they set the
--     app.finance_posting GUC).
-- (b) finance_guard_invoice_status(): BEFORE UPDATE OF status on
--     invoices — derived statuses (paid/partially_paid/overdue) are
--     writable only by finance_refresh_invoice_status() (GUC-gated).
-- (c) finance_transition_guard(): legal graphs —
--       expenses/income/refunds: draft→approved (needs finance.approve,
--         approved_by server-stamped) →posted; draft→void; approved→void
--       payments/transactions: draft→posted; draft→void
--       invoices: draft→issued; draft/issued→void|cancelled
--     Server-side flows without a JWT (seeds, migrations, service_role
--     automations) bypass the approval gate but never terminal states.
-- (d) refunds immutability guard arg fixed 'approved,posted,void' →
--     'posted,void' (the old list blocked the sanctioned approve→post).
-- (e) finance_post_payment()/finance_post_refund(): SELECT ... FOR
--     UPDATE on the invoice row (SEC-H16 over-allocation race).
-- (f) Backstops: CHECK (balance_due >= 0) NOT VALID;
--     CHECK (discount_total <= subtotal) NOT VALID; explicit raise in
--     finance_recalc_invoice on over-discount.
-- (g) void_invoice(p_id, p_reason) RPC — the single sanctioned way to
--     void an invoice (reason required, audit row).
-- (h) invoices_update_tenant RLS: WITH CHECK no longer allows direct
--     'cancelled'/'void' writes (use void_invoice).
-- (i) REVOKE EXECUTE on finance_* internals from PUBLIC/anon/
--     authenticated (triggers don't need grants).
-- (j) sync_apply: 'transactions' removed from the whitelist (034 = the
--     ledger is writable only by posting triggers now) — full
--     re-declaration derived from 033.
--
-- Idempotent: DROP TRIGGER IF EXISTS / CREATE OR REPLACE / DO guards.
-- ═══════════════════════════════════════════════════════════════


-- ── (a) force draft on insert ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.finance_force_draft_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Posting triggers create ledger rows as 'posted'; they set the GUC.
  IF current_setting('app.finance_posting', true) = 'on' THEN
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'finance: %.% must be inserted with status ''draft'' (got %)',
      TG_TABLE_NAME, COALESCE(NEW.id::text, '?'), NEW.status;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payments_force_draft ON public.payments;
CREATE TRIGGER trg_payments_force_draft
  BEFORE INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.finance_force_draft_on_insert();

DROP TRIGGER IF EXISTS trg_refunds_force_draft ON public.refunds;
CREATE TRIGGER trg_refunds_force_draft
  BEFORE INSERT ON public.refunds
  FOR EACH ROW EXECUTE FUNCTION public.finance_force_draft_on_insert();

DROP TRIGGER IF EXISTS trg_expenses_force_draft ON public.expenses;
CREATE TRIGGER trg_expenses_force_draft
  BEFORE INSERT ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.finance_force_draft_on_insert();

DROP TRIGGER IF EXISTS trg_income_force_draft ON public.income;
CREATE TRIGGER trg_income_force_draft
  BEFORE INSERT ON public.income
  FOR EACH ROW EXECUTE FUNCTION public.finance_force_draft_on_insert();

DROP TRIGGER IF EXISTS trg_transactions_force_draft ON public.transactions;
CREATE TRIGGER trg_transactions_force_draft
  BEFORE INSERT ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.finance_force_draft_on_insert();


-- ── (b) invoice derived-status guard ───────────────────────────
CREATE OR REPLACE FUNCTION public.finance_guard_invoice_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('paid','partially_paid','overdue')
     AND current_setting('app.invoice_status_writer', true) IS DISTINCT FROM 'refresh' THEN
    RAISE EXCEPTION 'finance: invoice % status % is derived; set only via finance_refresh_invoice_status()',
      OLD.id, NEW.status;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoices_guard_derived_status ON public.invoices;
CREATE TRIGGER trg_invoices_guard_derived_status
  BEFORE UPDATE OF status ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.finance_guard_invoice_status();

-- finance_refresh_invoice_status: same body as 014, plus the writer GUC.
CREATE OR REPLACE FUNCTION public.finance_refresh_invoice_status(p_invoice_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('app.invoice_status_writer', 'refresh', true);
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


-- ── (c) transition guard ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.finance_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  -- Terminal states are final for everyone (immutability guard backstops).
  IF OLD.status IN ('posted','void') THEN
    RAISE EXCEPTION 'finance: %.% is % and final; correct via reversal entry',
      TG_TABLE_NAME, OLD.id, OLD.status;
  END IF;
  -- Server-side flows without a JWT (seeds, migrations, service_role
  -- automations) bypass the approval gate but never terminal states.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  v_tenant := COALESCE(NEW.tenant_id, OLD.tenant_id);
  CASE TG_TABLE_NAME
    WHEN 'expenses', 'income', 'refunds' THEN
      IF OLD.status = 'draft' AND NEW.status = 'approved' THEN
        IF NOT public.tenant_has_permission(v_tenant, 'finance.approve') THEN
          RAISE EXCEPTION 'finance: approving % requires finance.approve', TG_TABLE_NAME;
        END IF;
        NEW.approved_by := auth.uid();
        RETURN NEW;
      ELSIF (OLD.status = 'draft' AND NEW.status = 'void')
         OR (OLD.status = 'approved' AND NEW.status IN ('posted','void')) THEN
        RETURN NEW;
      END IF;
    WHEN 'payments', 'transactions' THEN
      IF OLD.status = 'draft' AND NEW.status IN ('posted','void') THEN
        RETURN NEW;
      END IF;
    WHEN 'invoices' THEN
      IF OLD.status = 'draft' AND NEW.status IN ('issued','void','cancelled') THEN
        RETURN NEW;
      ELSIF OLD.status = 'issued' AND NEW.status IN ('void','cancelled') THEN
        RETURN NEW;
      END IF;
  END CASE;
  RAISE EXCEPTION 'finance: illegal %.% status transition % → %',
    TG_TABLE_NAME, OLD.id, OLD.status, NEW.status;
END;
$$;

DROP TRIGGER IF EXISTS trg_payments_transition_guard ON public.payments;
CREATE TRIGGER trg_payments_transition_guard
  BEFORE UPDATE OF status ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.finance_transition_guard();

DROP TRIGGER IF EXISTS trg_refunds_transition_guard ON public.refunds;
CREATE TRIGGER trg_refunds_transition_guard
  BEFORE UPDATE OF status ON public.refunds
  FOR EACH ROW EXECUTE FUNCTION public.finance_transition_guard();

DROP TRIGGER IF EXISTS trg_expenses_transition_guard ON public.expenses;
CREATE TRIGGER trg_expenses_transition_guard
  BEFORE UPDATE OF status ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION public.finance_transition_guard();

DROP TRIGGER IF EXISTS trg_income_transition_guard ON public.income;
CREATE TRIGGER trg_income_transition_guard
  BEFORE UPDATE OF status ON public.income
  FOR EACH ROW EXECUTE FUNCTION public.finance_transition_guard();

DROP TRIGGER IF EXISTS trg_transactions_transition_guard ON public.transactions;
CREATE TRIGGER trg_transactions_transition_guard
  BEFORE UPDATE OF status ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.finance_transition_guard();

DROP TRIGGER IF EXISTS trg_invoices_transition_guard ON public.invoices;
CREATE TRIGGER trg_invoices_transition_guard
  BEFORE UPDATE OF status ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.finance_transition_guard();


-- ── (d) refunds immutability: approved is NOT final ────────────
DROP TRIGGER IF EXISTS trg_refunds_guard_immutable ON public.refunds;
CREATE TRIGGER trg_refunds_guard_immutable
  BEFORE UPDATE OR DELETE ON public.refunds
  FOR EACH ROW EXECUTE FUNCTION public.finance_immutable_guard('posted,void');


-- ── (e) atomic payment/refund posting (SEC-H16) ────────────────
CREATE OR REPLACE FUNCTION public.finance_post_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alloc NUMERIC(14,2);
  v_bal   NUMERIC(14,2);
BEGIN
  IF NEW.status = 'posted' AND OLD.status <> 'posted' THEN
    PERFORM set_config('app.finance_posting', 'on', true);
    NEW.posted_at := COALESCE(NEW.posted_at, now());

    INSERT INTO public.transactions
      (tenant_id, entry_date, kind, category, amount, account_id,
       description, reference_type, reference_id, status, posted_at, created_by)
    VALUES
      (NEW.tenant_id, NEW.payment_date, 'income', 'fee', NEW.amount,
       NEW.account_id,
       COALESCE('Payment ' || NEW.receipt_number, 'Fee payment'),
       'payment', NEW.id, 'posted', now(), NEW.created_by);

    IF NEW.invoice_id IS NOT NULL THEN
      -- 034: lock the invoice row before reading balance_due.
      SELECT t.balance_due INTO v_bal
        FROM public.invoices t WHERE t.id = NEW.invoice_id FOR UPDATE;
      v_alloc := LEAST(NEW.amount, v_bal);
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

CREATE OR REPLACE FUNCTION public.finance_post_refund()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice UUID;
  v_relief  NUMERIC(14,2);
  v_paid    NUMERIC(14,2);
BEGIN
  IF NEW.status = 'posted' AND OLD.status <> 'posted' THEN
    PERFORM set_config('app.finance_posting', 'on', true);
    NEW.posted_at := COALESCE(NEW.posted_at, now());

    INSERT INTO public.transactions
      (tenant_id, entry_date, kind, category, amount, account_id,
       description, reference_type, reference_id, status, posted_at, created_by)
    SELECT NEW.tenant_id, NEW.refund_date, 'expense', 'refund', NEW.amount,
           p.account_id,
           'Refund: ' || NEW.reason,
           'refund', NEW.id, 'posted', now(), NEW.created_by
      FROM public.payments p WHERE p.id = NEW.payment_id;

    SELECT invoice_id INTO v_invoice
      FROM public.payments WHERE id = NEW.payment_id;
    IF v_invoice IS NOT NULL THEN
      -- 034: lock the invoice row before reading amount_paid.
      SELECT t.amount_paid INTO v_paid
        FROM public.invoices t WHERE t.id = v_invoice FOR UPDATE;
      v_relief := LEAST(NEW.amount, v_paid);
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

CREATE OR REPLACE FUNCTION public.finance_post_expense_income()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'posted' AND OLD.status <> 'posted' THEN
    PERFORM set_config('app.finance_posting', 'on', true);
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


-- ── (f) arithmetic backstops ───────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_invoices_balance_due_nonneg') THEN
    ALTER TABLE public.invoices
      ADD CONSTRAINT chk_invoices_balance_due_nonneg CHECK (balance_due >= 0) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_invoices_discount_lte_subtotal') THEN
    ALTER TABLE public.invoices
      ADD CONSTRAINT chk_invoices_discount_lte_subtotal CHECK (discount_total <= subtotal) NOT VALID;
  END IF;
END $$;

-- Explicit loud failure on over-discount (NOT VALID constraints only guard
-- new writes; this guards the recalc path itself).
CREATE OR REPLACE FUNCTION public.finance_recalc_invoice(p_invoice_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub  NUMERIC(14,2);
  v_disc NUMERIC(14,2);
BEGIN
  SELECT COALESCE(SUM(line_total), 0) INTO v_sub
    FROM public.invoice_items
   WHERE invoice_id = p_invoice_id;

  SELECT COALESCE(SUM(
           CASE WHEN d.discount_type = 'fixed' THEN d.value
                ELSE round(v_sub * d.value / 100, 2)
           END), 0)
    INTO v_disc
    FROM public.discounts d
   WHERE d.invoice_id = p_invoice_id
     AND d.status = 'applied';

  IF v_disc > v_sub THEN
    RAISE EXCEPTION 'finance: invoice % discounts % exceed subtotal %',
      p_invoice_id, v_disc, v_sub;
  END IF;

  UPDATE public.invoices i
     SET subtotal       = v_sub,
         discount_total = v_disc,
         updated_at     = now()
   WHERE i.id = p_invoice_id;

  PERFORM public.finance_refresh_invoice_status(p_invoice_id);
END;
$$;


-- ── (g) void_invoice RPC — the sanctioned void path ────────────
CREATE OR REPLACE FUNCTION public.void_invoice(p_invoice_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_status TEXT;
BEGIN
  SELECT tenant_id, status INTO v_tenant, v_status
    FROM public.invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'void_invoice: invoice % not found', p_invoice_id;
  END IF;
  IF NOT (public.is_platform_admin()
          OR public.tenant_has_permission(v_tenant, 'finance.approve')) THEN
    RAISE EXCEPTION 'void_invoice: requires finance.approve in tenant %', v_tenant;
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'void_invoice: a reason is required';
  END IF;
  IF v_status NOT IN ('draft', 'issued') THEN
    RAISE EXCEPTION 'void_invoice: invoice % is % and cannot be voided (use a reversal invoice)',
      p_invoice_id, v_status;
  END IF;

  UPDATE public.invoices
     SET status = 'void', updated_at = now()
   WHERE id = p_invoice_id;

  INSERT INTO public.audit_logs (tenant_id, user_id, action, entity, entity_id, new_data)
  VALUES (v_tenant, auth.uid(), 'invoice.void', 'invoices', p_invoice_id::text,
          jsonb_build_object('reason', p_reason));
END;
$$;

REVOKE ALL ON FUNCTION public.void_invoice(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.void_invoice(UUID, TEXT) TO authenticated;


-- ── (h) invoices RLS: direct void/cancel removed ───────────────
-- Tenant users can no longer set cancelled/void via plain UPDATE;
-- voiding goes through void_invoice() (reason + audit).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='invoices'
             AND policyname='invoices_update_tenant') THEN
    DROP POLICY "invoices_update_tenant" ON public.invoices;
    CREATE POLICY "invoices_update_tenant" ON public.invoices FOR UPDATE USING (
      public.is_platform_admin() OR (public.is_tenant_member(invoices.tenant_id)
        AND public.tenant_has_permission(invoices.tenant_id, 'fees.collect')
        AND invoices.status IN ('draft', 'issued'))
    ) WITH CHECK (
      public.is_platform_admin() OR (public.is_tenant_member(invoices.tenant_id)
        AND public.tenant_has_permission(invoices.tenant_id, 'fees.collect')
        AND invoices.status IN ('draft', 'issued'))
    );
  END IF;
END $$;


-- ── (i) revoke finance internals from direct calls ─────────────
DO $$
DECLARE
  f TEXT;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.finance_refresh_invoice_status(UUID)',
    'public.finance_recalc_invoice(UUID)',
    'public.finance_trg_recalc_invoice()',
    'public.finance_guard_invoice_item_parent()',
    'public.finance_post_payment()',
    'public.finance_post_refund()',
    'public.finance_post_expense_income()',
    'public.finance_fill_invoice_number()',
    'public.finance_fill_receipt_number()',
    'public.finance_fill_income_doc_number()',
    'public.finance_immutable_guard()',
    'public.finance_trg_discount_applied()',
    'public.finance_audit()',
    'public.finance_force_draft_on_insert()',
    'public.finance_guard_invoice_status()',
    'public.finance_transition_guard()',
    'public.bump_revision()',
    'public.sync_stamp_insert()'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
  END LOOP;
END $$;


-- ── (j) sync whitelist: transactions removed ───────────────────
-- The canonical ledger is writable ONLY by the posting triggers
-- (finance_post_payment / _refund / _expense_income). Direct sync writes
-- to transactions now fail closed as unknown entity/op.
CREATE OR REPLACE FUNCTION public.sync_required_permission(p_entity TEXT, p_op TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE p_entity
    WHEN 'darjas' THEN 'academics.manage'
    WHEN 'classes' THEN 'academics.manage'
    WHEN 'darja_sections' THEN 'academics.manage'
    WHEN 'students' THEN CASE p_op
      WHEN 'insert' THEN 'students.create'
      WHEN 'update' THEN 'students.update'
      WHEN 'delete' THEN 'students.delete' END
    WHEN 'staff' THEN CASE p_op
      WHEN 'insert' THEN 'staff.create'
      WHEN 'update' THEN 'staff.update'
      WHEN 'delete' THEN 'staff.delete' END
    WHEN 'attendance' THEN CASE p_op
      WHEN 'insert' THEN 'attendance.mark'
      WHEN 'update' THEN 'attendance.edit'
      WHEN 'delete' THEN 'attendance.delete' END
    WHEN 'fees' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'exams' THEN CASE p_op
      WHEN 'insert' THEN 'exams.create'
      WHEN 'update' THEN 'exams.update'
      WHEN 'delete' THEN 'exams.delete' END
    WHEN 'results' THEN CASE p_op
      WHEN 'insert' THEN 'results.enter'
      ELSE 'results.edit' END
    WHEN 'announcements' THEN 'announcements.send'
    WHEN 'library_books' THEN 'library.manage'
    WHEN 'book_issues' THEN 'library.manage'
    WHEN 'finance_transactions' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    WHEN 'accounts' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    WHEN 'fee_structures' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.create' END
    WHEN 'fee_items' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.create' END
    WHEN 'invoices' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'invoice_items' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'payments' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.collect' END
    WHEN 'payment_allocations' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.collect' END
    WHEN 'refunds' THEN CASE p_op
      WHEN 'delete' THEN 'fees.delete'
      ELSE 'fees.refund' END
    WHEN 'discounts' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'scholarships' THEN CASE p_op
      WHEN 'insert' THEN 'fees.create'
      WHEN 'update' THEN 'fees.collect'
      WHEN 'delete' THEN 'fees.delete' END
    WHEN 'expenses' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    WHEN 'income' THEN CASE p_op
      WHEN 'insert' THEN 'finance.create'
      WHEN 'update' THEN 'finance.update'
      WHEN 'delete' THEN 'finance.delete' END
    ELSE NULL
  END
$$;


CREATE OR REPLACE FUNCTION public.sync_apply(
  p_entity        TEXT,
  p_entity_id     UUID,
  p_base_revision INT,
  p_payload       JSONB,
  p_op            TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entity       TEXT;
  v_financial    BOOLEAN;
  v_id           UUID;
  v_tenant       UUID;
  v_row_tenant   UUID;
  v_cur_revision INT;
  v_deleted_at   TIMESTAMPTZ;
  v_row          JSONB;
  v_new_revision INT;
  v_sv           BIGINT;
  v_uid          UUID;
  v_found        BOOLEAN;
  v_rows         INT;
  v_cols         TEXT;
  v_sel          TEXT;
  v_ins_cols     TEXT;
  v_ins_sel      TEXT;
  v_stamp        TEXT;
  v_has_updated_by BOOLEAN;
  v_has_updated_at BOOLEAN;
  v_perm         TEXT;
  v_class_id     UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sync: unauthenticated';
  END IF;

  IF p_op NOT IN ('insert', 'update', 'delete') THEN
    RAISE EXCEPTION 'sync: unknown op %', p_op;
  END IF;

  -- ── 1) whitelist p_entity via CASE — no dynamic table names ──
  CASE p_entity
    WHEN 'darjas'               THEN v_entity := 'darjas';
    WHEN 'classes'              THEN v_entity := 'classes';
    WHEN 'students'             THEN v_entity := 'students';
    WHEN 'staff'                THEN v_entity := 'staff';
    WHEN 'attendance'           THEN v_entity := 'attendance';
    WHEN 'fees'                 THEN v_entity := 'fees';
    WHEN 'exams'                THEN v_entity := 'exams';
    WHEN 'results'              THEN v_entity := 'results';
    WHEN 'announcements'        THEN v_entity := 'announcements';
    WHEN 'darja_sections'       THEN v_entity := 'darja_sections';
    WHEN 'library_books'        THEN v_entity := 'library_books';
    WHEN 'book_issues'          THEN v_entity := 'book_issues';
    WHEN 'finance_transactions' THEN v_entity := 'finance_transactions';
    WHEN 'accounts'             THEN v_entity := 'accounts';
    WHEN 'fee_structures'       THEN v_entity := 'fee_structures';
    WHEN 'fee_items'            THEN v_entity := 'fee_items';
    WHEN 'invoices'             THEN v_entity := 'invoices';
    WHEN 'invoice_items'        THEN v_entity := 'invoice_items';
    WHEN 'payments'             THEN v_entity := 'payments';
    WHEN 'payment_allocations'  THEN v_entity := 'payment_allocations';
    WHEN 'refunds'              THEN v_entity := 'refunds';
    WHEN 'discounts'            THEN v_entity := 'discounts';
    WHEN 'scholarships'         THEN v_entity := 'scholarships';
    WHEN 'expenses'             THEN v_entity := 'expenses';
    WHEN 'income'               THEN v_entity := 'income';
    ELSE RAISE EXCEPTION 'sync: unknown entity %', p_entity;
  END CASE;

  -- ── 1b) permission map — fail closed on unknown (entity, op) ──
  v_perm := public.sync_required_permission(p_entity, p_op);
  IF v_perm IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:unknown_entity_or_op');
  END IF;

  v_financial := v_entity IN (
    'accounts','fee_structures','fee_items','invoices','invoice_items',
    'payments','payment_allocations','refunds','discounts','scholarships',
    'expenses','income'
  );

  SELECT
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name=v_entity AND column_name='updated_by'),
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name=v_entity AND column_name='updated_at')
    INTO v_has_updated_by, v_has_updated_at;


  -- ── 2) INSERT ──────────────────────────────────────────────
  IF p_op = 'insert' THEN
    v_id := COALESCE(p_entity_id, NULLIF(p_payload->>'id','')::UUID, gen_random_uuid());

    -- 033: tenant + membership FIRST, before any existence probe.
    v_tenant := NULLIF(p_payload->>'tenant_id','')::UUID;
    IF v_tenant IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_tenant');
    END IF;
    IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:not_member');
    END IF;
    IF NOT public.tenant_has_permission(v_tenant, v_perm) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_permission',
                                'permission', v_perm);
    END IF;

    IF v_entity IN ('results', 'attendance') THEN
      BEGIN
        v_class_id := NULLIF(p_payload->>'class_id','')::UUID;
      EXCEPTION WHEN OTHERS THEN
        v_class_id := NULL;
      END;
      IF NOT public.sync_scope_ok(v_tenant, v_perm, v_class_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:scope');
      END IF;
    END IF;

    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1)', v_entity)
      INTO v_found USING v_id;
    IF v_found THEN
      -- 033: only reveal the row when it belongs to the caller's tenant
      -- (or the caller is a platform admin). Cross-tenant UUID probes
      -- get a bare reason — no data.
      EXECUTE format(
        'SELECT t.tenant_id, t.revision, ' ||
        'CASE WHEN $2 OR t.tenant_id = $3 THEN to_jsonb(t) END ' ||
        'FROM public.%I t WHERE t.id = $1', v_entity)
        INTO v_row_tenant, v_cur_revision, v_row
        USING v_id, public.is_platform_admin(), v_tenant;
      RETURN jsonb_build_object('ok', false, 'reason', 'already_exists',
                                'server_revision', v_cur_revision,
                                'server_row', v_row,
                                'financial', v_financial);
    END IF;

    SELECT
      string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position),
      string_agg('p.' || quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
      INTO v_ins_cols, v_ins_sel
      FROM information_schema.columns c
     WHERE c.table_schema = 'public'
       AND c.table_name   = v_entity
       AND c.is_generated = 'NEVER'
       AND c.column_name NOT IN
             ('id','revision','server_version','updated_by','deleted_at')
       AND p_payload ? c.column_name;

    IF v_ins_cols IS NULL THEN
      RAISE EXCEPTION 'sync: insert payload carries no writable columns';
    END IF;

    EXECUTE format(
      'INSERT INTO public.%I (id, %s, revision, updated_by) ' ||
      'SELECT $2, %s, 1, $3 ' ||
      'FROM jsonb_populate_record(NULL::public.%I, $1) AS p ' ||
      'RETURNING revision',
      v_entity, v_ins_cols, v_ins_sel, v_entity)
      INTO v_new_revision
      USING p_payload, v_id, v_uid;

    RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision, 'id', v_id);
  END IF;


  -- ── update / delete share the fetch + guards ────────────────
  IF p_base_revision IS NULL THEN
    RAISE EXCEPTION 'sync: base_revision is required for %', p_op;
  END IF;

  EXECUTE format(
    'SELECT t.revision, t.tenant_id, t.deleted_at, to_jsonb(t) ' ||
    'FROM public.%I t WHERE t.id = $1', v_entity)
    INTO v_cur_revision, v_tenant, v_deleted_at, v_row
    USING p_entity_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- 033: tenant_id comes from the EXISTING row; rows outside the
  -- caller's access return 'not_found' (closes the exists-vs-forbidden
  -- oracle; previously this raised a distinguishing exception).
  IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT public.tenant_has_permission(v_tenant, v_perm) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:missing_permission',
                              'permission', v_perm);
  END IF;

  IF v_entity IN ('results', 'attendance') THEN
    BEGIN
      v_class_id := NULLIF(v_row->>'class_id','')::UUID;
    EXCEPTION WHEN OTHERS THEN
      v_class_id := NULL;
    END;
    IF v_class_id IS NULL THEN
      BEGIN
        v_class_id := NULLIF(p_payload->>'class_id','')::UUID;
      EXCEPTION WHEN OTHERS THEN
        v_class_id := NULL;
      END;
    END IF;
    IF NOT public.sync_scope_ok(v_tenant, v_perm, v_class_id) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'forbidden:scope');
    END IF;
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    IF p_op = 'delete' THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'already_deleted',
                                'server_revision', v_cur_revision,
                                'server_row', v_row,
                                'financial', v_financial);
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'deleted',
                              'server_revision', v_cur_revision,
                              'server_row', v_row,
                              'financial', v_financial);
  END IF;

  -- Pre-check (fast path); the write itself is predicated on the
  -- revision below, which is the atomic guarantee.
  IF v_cur_revision IS DISTINCT FROM p_base_revision THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'conflict',
                              'server_revision', v_cur_revision,
                              'server_row', v_row,
                              'financial', v_financial);
  END IF;

  v_stamp := '';
  IF v_has_updated_by THEN v_stamp := v_stamp || ', updated_by = $3'; END IF;
  IF v_has_updated_at THEN v_stamp := v_stamp || ', updated_at = now()'; END IF;
  v_stamp := v_stamp || ', server_version = $4';


  -- ── 3) UPDATE ──────────────────────────────────────────────
  -- 033: atomic — the revision predicate is part of the UPDATE.
  IF p_op = 'update' THEN
    SELECT
      string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position),
      string_agg('p.' || quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
      INTO v_cols, v_sel
      FROM information_schema.columns c
     WHERE c.table_schema = 'public'
       AND c.table_name   = v_entity
       AND c.is_generated = 'NEVER'
       AND c.column_name NOT IN
             ('id','tenant_id','revision','server_version',
              'updated_by','deleted_at','created_at','updated_at')
       AND p_payload ? c.column_name;

    IF v_cols IS NULL THEN
      RETURN jsonb_build_object('ok', true, 'new_revision', v_cur_revision);
    END IF;

    v_sv := nextval('public.sync_server_version_seq');
    EXECUTE format(
      'UPDATE public.%I t SET (%s) = ' ||
      '(SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) AS p)' ||
      '%s WHERE t.id = $2 AND t.revision = $5 RETURNING t.revision',
      v_entity, v_cols, v_sel, v_entity, v_stamp)
      INTO v_new_revision
      USING p_payload, p_entity_id, v_uid, v_sv, p_base_revision;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
      -- Lost the race between the pre-check and the write: re-read and
      -- report a conflict with fresh server state.
      EXECUTE format(
        'SELECT t.revision, to_jsonb(t) FROM public.%I t WHERE t.id = $1', v_entity)
        INTO v_cur_revision, v_row
        USING p_entity_id;
      RETURN jsonb_build_object('ok', false, 'reason', 'conflict',
                                'server_revision', v_cur_revision,
                                'server_row', v_row,
                                'financial', v_financial);
    END IF;

    RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision);
  END IF;


  -- ── 4) DELETE (soft) ───────────────────────────────────────
  -- 033: atomic — predicated on the revision like UPDATE.
  v_stamp := '';
  IF v_has_updated_by THEN v_stamp := v_stamp || ', updated_by = $2'; END IF;
  IF v_has_updated_at THEN v_stamp := v_stamp || ', updated_at = now()'; END IF;
  v_stamp := v_stamp || ', server_version = $3';

  v_sv := nextval('public.sync_server_version_seq');
  EXECUTE format(
    'UPDATE public.%I t SET deleted_at = now()%s ' ||
    'WHERE t.id = $1 AND t.revision = $4 RETURNING t.revision',
    v_entity, v_stamp)
    INTO v_new_revision
    USING p_entity_id, v_uid, v_sv, p_base_revision;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    EXECUTE format(
      'SELECT t.revision, to_jsonb(t) FROM public.%I t WHERE t.id = $1', v_entity)
      INTO v_cur_revision, v_row
      USING p_entity_id;
    RETURN jsonb_build_object('ok', false, 'reason', 'conflict',
                              'server_revision', v_cur_revision,
                              'server_row', v_row,
                              'financial', v_financial);
  END IF;

  RETURN jsonb_build_object('ok', true, 'new_revision', v_new_revision);
END;
$$;

COMMENT ON FUNCTION public.sync_apply(TEXT, UUID, INT, JSONB, TEXT) IS
  '034: 033 minus the transactions entity — the ledger is writable only '
  'by the posting triggers now. Permission map and correctness guarantees '
  'unchanged.';

-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('034_finance_transition_guards')
ON CONFLICT DO NOTHING;
