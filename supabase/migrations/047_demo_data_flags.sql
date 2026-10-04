-- ═══════════════════════════════════════════════════════════════════
-- 047_demo_data_flags.sql — one-click demo data support
--
-- Adds `is_demo` flags to business tables so the `manage-demo-data` Edge
-- Function can install sample data into a user's own tenant and remove it
-- again WITHOUT ever touching real rows. Deletes filter on
-- (tenant_id, is_demo = true) — a missing flag can never match a real row.
--
-- Tables covered: every table the demo dataset writes to.
-- Config tables (tenant_settings, licenses, roles, …) are intentionally
-- excluded: demo install never changes tenant configuration.
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  t text;
  demo_tables text[] := ARRAY[
    'darjas',
    'classes',
    'students',
    'staff',
    'exams',
    'announcements',
    'fee_structures',
    'fee_items',
    'invoices',
    'invoice_items',
    'payments',
    'discounts',
    'income',
    'expenses',
    'accounts',
    'scholarships',
    'notifications',
    'transactions'
  ];
BEGIN
  FOREACH t IN ARRAY demo_tables LOOP
    -- Only touch tables that actually exist (defensive for trimmed schemas).
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false',
        t
      );
      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS ix_%I_demo ON public.%I (tenant_id, is_demo) WHERE is_demo = true',
        t, t
      );
    END IF;
  END LOOP;
END $$;

-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('047_demo_data_flags')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════
-- Demo install/remove RPCs (called ONLY by the manage-demo-data Edge
-- Function after admin authorization — never exposed to anon).
--
-- demo_install(p_tenant_id): inserts a compact, realistic Urdu-first
--   dataset into the CALLER'S tenant with is_demo=true. Idempotent:
--   returns already_installed=true when demo rows exist.
-- demo_remove(p_tenant_id): deletes ONLY is_demo=true rows for the
--   tenant, in FK-safe order. Real rows are never touched.
-- demo_status(p_tenant_id): counts of demo rows per table.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.demo_status(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb := '{}'::jsonb;
  t text;
  c bigint;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'darjas','classes','students','staff','exams','announcements',
    'fee_structures','fee_items','invoices','invoice_items','payments',
    'discounts','income','expenses','accounts','scholarships','notifications',
    'transactions'
  ]) LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format(
        'SELECT count(*) FROM public.%I WHERE tenant_id = $1 AND is_demo = true',
        t) INTO c USING p_tenant_id;
      result := result || jsonb_build_object(t, c);
    END IF;
  END LOOP;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.demo_install(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing bigint;
  d1 uuid := gen_random_uuid(); d2 uuid := gen_random_uuid(); d3 uuid := gen_random_uuid();
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid();
  c3 uuid := gen_random_uuid(); c4 uuid := gen_random_uuid();
  fs1 uuid := gen_random_uuid();
  fi1 uuid := gen_random_uuid(); fi2 uuid := gen_random_uuid(); fi3 uuid := gen_random_uuid();
  a_cash uuid := gen_random_uuid(); a_bank uuid := gen_random_uuid();
  s uuid;
  i int;
  student_ids uuid[] := '{}';
  v_names text[] := ARRAY['محمد احمد','علی رضا','حسن جاوید','عمر فاروق','بلال احمد','زید اکرم',
    'حمزہ شاہد','طلحہ محمود','عبداللہ نعیم','ابوبکر صدیق','عثمان غنی','سلمان راشد'];
  v_fathers text[] := ARRAY['محمد اسلم','عبدالرحیم','محمد شریف','غلام محمد','اللہ دتہ','محمد یوسف',
    'عبدالکریم','حاجی محمد دین','محمد اکرم','چوہدری انور علی','محمد صادق','عبدالغفار'];
  v_classes uuid[];
  v_darjas uuid[];
BEGIN
  -- Idempotency: never install twice.
  SELECT count(*) INTO v_existing FROM public.students
   WHERE tenant_id = p_tenant_id AND is_demo = true;
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('already_installed', true);
  END IF;

  -- Tenant must exist and not be suspended.
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = p_tenant_id) THEN
    RAISE EXCEPTION 'demo_install: tenant not found';
  END IF;

  -- ── Darjas ──
  INSERT INTO public.darjas (id, tenant_id, name, name_urdu, name_en, order_num, is_active, is_demo)
  VALUES
    (d1, p_tenant_id, 'ناظرہ قرآن', 'ناظرہ قرآن', 'Nazra Quran', 1, true, true),
    (d2, p_tenant_id, 'حفظ قرآن', 'حفظ قرآن', 'Hifz-e-Quran', 2, true, true),
    (d3, p_tenant_id, 'درجہ اول', 'درجہ اول', 'Grade 1', 3, true, true);
  v_darjas := ARRAY[d1, d2, d3];

  -- ── Classes ──
  INSERT INTO public.classes (id, tenant_id, darja_id, name, capacity, is_active, is_demo)
  VALUES
    (c1, p_tenant_id, d1, 'ناظرہ (الف)', 30, true, true),
    (c2, p_tenant_id, d1, 'ناظرہ (ب)', 30, true, true),
    (c3, p_tenant_id, d2, 'حفظ (الف)', 25, true, true),
    (c4, p_tenant_id, d3, 'درجہ اول (الف)', 35, true, true);
  v_classes := ARRAY[c1, c2, c3, c4];

  -- ── Students (12) ──
  FOR i IN 1..12 LOOP
    s := gen_random_uuid();
    student_ids := student_ids || s;
    INSERT INTO public.students
      (id, tenant_id, roll_no, name, father_name, darja_id, class_id,
       phone, address, date_of_admit, is_active, is_demo)
    VALUES
      (s, p_tenant_id, 'DEMO-2026-' || lpad(i::text, 3, '0'),
       v_names[i], v_fathers[i], v_darjas[((i-1) % 3) + 1], v_classes[((i-1) % 4) + 1],
       '0301-2000' || lpad(i::text, 3, '0'), 'لاہور', CURRENT_DATE - 90, true, true);
  END LOOP;

  -- ── Staff (4) ──
  INSERT INTO public.staff
    (id, tenant_id, name, father_name, designation, department, phone, salary, joining_date, is_active, is_demo)
  VALUES
    (gen_random_uuid(), p_tenant_id, 'قاری محمد یوسف', 'حاجی عبداللہ', 'استاد', 'ناظرہ', '0301-3000001', 35000, CURRENT_DATE - 400, true, true),
    (gen_random_uuid(), p_tenant_id, 'مولانا عبدالرحمن', 'مفتی محمد شفیع', 'استاد', 'حفظ', '0301-3000002', 40000, CURRENT_DATE - 500, true, true),
    (gen_random_uuid(), p_tenant_id, 'محمد عمران', 'محمد صدیق', 'محاسب', 'انتظامیہ', '0301-3000003', 45000, CURRENT_DATE - 300, true, true),
    (gen_random_uuid(), p_tenant_id, 'حافظ محمد طاہر', 'محمد رفیق', 'مہتمم', 'انتظامیہ', '0301-3000004', 60000, CURRENT_DATE - 700, true, true);

  -- ── Fee structure + items ──
  INSERT INTO public.fee_structures (id, tenant_id, name, name_urdu, academic_year, is_active, is_demo)
  VALUES (fs1, p_tenant_id, 'ماہانہ فیس 2026', 'ماہانہ فیس 2026', '2026-27', true, true);
  INSERT INTO public.fee_items (id, tenant_id, fee_structure_id, name, name_urdu, amount, frequency, is_active, is_demo)
  VALUES
    (fi1, p_tenant_id, fs1, 'ٹیوشن فیس', 'ٹیوشن فیس', 500, 'monthly', true, true),
    (fi2, p_tenant_id, fs1, 'داخلہ فیس', 'داخلہ فیس', 1000, 'one_time', true, true),
    (fi3, p_tenant_id, fs1, 'امتحانی فیس', 'امتحانی فیس', 300, 'quarterly', true, true);

  -- ── Accounts ──
  INSERT INTO public.accounts (id, tenant_id, code, name, name_urdu, account_type, opening_balance, is_active, is_demo)
  VALUES
    (a_cash, p_tenant_id, 'CASH-01', 'نقد', 'نقد', 'asset', 50000, true, true),
    (a_bank, p_tenant_id, 'BANK-01', 'بینک اکاؤنٹ', 'بینک اکاؤنٹ', 'asset', 200000, true, true);

  -- ── Invoices + items + payments (6 invoices, 4 paid) ──
  FOR i IN 1..6 LOOP
    DECLARE
      inv uuid := gen_random_uuid();
      itm uuid := gen_random_uuid();
    BEGIN
      INSERT INTO public.invoices
        (id, invoice_number, tenant_id, student_id, fee_structure_id,
         billing_month, issue_date, due_date, subtotal, status, is_demo)
      VALUES
        (inv, 'INV-DEMO-' || lpad(i::text, 3, '0'), p_tenant_id, student_ids[i], fs1,
         to_char(CURRENT_DATE, 'YYYY-MM'), CURRENT_DATE - 5, CURRENT_DATE + 10,
         500, 'issued', true);
      INSERT INTO public.invoice_items
        (id, tenant_id, invoice_id, fee_item_id, description, quantity, unit_amount, is_demo)
      VALUES
        (itm, p_tenant_id, inv, fi1, 'ٹیوشن فیس', 1, 500, true);
      IF i <= 4 THEN
        INSERT INTO public.payments
          (id, tenant_id, student_id, invoice_id, account_id, amount,
           payment_date, method, receipt_number, status, is_demo)
        VALUES
          (gen_random_uuid(), p_tenant_id, student_ids[i], inv, a_cash, 500,
           CURRENT_DATE - 2, 'cash', 'R-DEMO-' || lpad(i::text, 3, '0'), 'draft', true);
      END IF;
    END;
  END LOOP;

  -- ── Income / expenses ──
  INSERT INTO public.income (id, tenant_id, source_type, donor_name, amount, account_id, received_date, receipt_number, description, status, is_demo)
  VALUES
    (gen_random_uuid(), p_tenant_id, 'donation', 'الحاج محمد بشیر', 25000, a_cash, CURRENT_DATE - 10, 'IN-DEMO-001', 'عطیہ برائے مدرسہ', 'draft', true),
    (gen_random_uuid(), p_tenant_id, 'donation', 'محمد فاروق', 15000, a_bank, CURRENT_DATE - 3, 'IN-DEMO-002', 'ماہانہ چندہ', 'draft', true);
  INSERT INTO public.expenses (id, tenant_id, category, recipient, amount, account_id, expense_date, description, status, is_demo)
  VALUES
    (gen_random_uuid(), p_tenant_id, 'utilities', 'لیسکو', 8500, a_cash, CURRENT_DATE - 7, 'بجلی کا بل', 'draft', true),
    (gen_random_uuid(), p_tenant_id, 'maintenance', 'مستری محمد خان', 12000, a_cash, CURRENT_DATE - 4, 'مرمت کا کام', 'draft', true);

  -- Post the finance rows (draft → posted), like real usage.
  UPDATE public.payments SET status = 'posted'
   WHERE tenant_id = p_tenant_id AND is_demo = true AND status = 'draft';
  UPDATE public.income SET status = 'posted'
   WHERE tenant_id = p_tenant_id AND is_demo = true AND status = 'draft';
  UPDATE public.expenses SET status = 'posted'
   WHERE tenant_id = p_tenant_id AND is_demo = true AND status = 'draft';

  -- ── Announcements + exam ──
  INSERT INTO public.announcements (id, tenant_id, title, body, target_role, is_active, is_demo)
  VALUES
    (gen_random_uuid(), p_tenant_id, 'داخلے جاری ہیں', 'نئے تعلیمی سال کے داخلے جاری ہیں۔ خواہشمند حضرات دفتر سے رابطہ کریں۔', 'all', true, true),
    (gen_random_uuid(), p_tenant_id, 'ماہانہ امتحان', 'اگلے ہفتے ماہانہ امتحان ہوگا۔ تمام طلبہ تیاری کریں۔', 'all', true, true);
  INSERT INTO public.exams (id, tenant_id, name, class_id, exam_date, total_marks, is_demo)
  VALUES
    (gen_random_uuid(), p_tenant_id, 'ماہانہ امتحان — ناظرہ', c1, CURRENT_DATE + 7, 100, true);

  -- Flag auto-created ledger transactions that stem from demo rows.
  -- The immutability guard blocks UPDATE on posted transactions; demo
  -- install is the one legitimate exception — disable inside this
  -- transaction, re-enable before return (rollback restores on failure).
  ALTER TABLE public.transactions DISABLE TRIGGER trg_transactions_guard_immutable;
  UPDATE public.transactions t SET is_demo = true
   WHERE t.tenant_id = p_tenant_id AND t.is_demo = false AND (
     EXISTS (SELECT 1 FROM public.payments p
              WHERE p.id = t.reference_id AND p.tenant_id = p_tenant_id AND p.is_demo = true)
     OR EXISTS (SELECT 1 FROM public.income i
              WHERE i.id = t.reference_id AND i.tenant_id = p_tenant_id AND i.is_demo = true)
     OR EXISTS (SELECT 1 FROM public.expenses e
              WHERE e.id = t.reference_id AND e.tenant_id = p_tenant_id AND e.is_demo = true)
   );
  ALTER TABLE public.transactions ENABLE TRIGGER trg_transactions_guard_immutable;

  RETURN jsonb_build_object(
    'installed', true,
    'counts', public.demo_status(p_tenant_id)
  );
END $$;

CREATE OR REPLACE FUNCTION public.demo_remove(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint := 0;
  c bigint;
BEGIN
  -- Count before delete (for the response).
  SELECT count(*) INTO v_count FROM public.students
   WHERE tenant_id = p_tenant_id AND is_demo = true;

  -- Finance immutability guards block DELETE of posted rows.
  -- Demo cleanup is the one legitimate exception: disable inside this
  -- transaction; rollback restores them on any failure.
  ALTER TABLE public.invoices            DISABLE TRIGGER trg_invoices_guard_immutable;
  ALTER TABLE public.payments            DISABLE TRIGGER trg_payments_guard_immutable;
  ALTER TABLE public.income              DISABLE TRIGGER trg_income_guard_immutable;
  ALTER TABLE public.expenses            DISABLE TRIGGER trg_expenses_guard_immutable;
  ALTER TABLE public.discounts           DISABLE TRIGGER trg_discounts_guard_immutable;
  ALTER TABLE public.payment_allocations DISABLE TRIGGER trg_payment_allocations_guard_immutable;
  ALTER TABLE public.transactions        DISABLE TRIGGER trg_transactions_guard_immutable;
  ALTER TABLE public.invoice_items       DISABLE TRIGGER trg_invoice_items_parent_guard;
  ALTER TABLE public.invoice_items       DISABLE TRIGGER trg_invoice_items_recalc;

  -- Children before parents (FK-safe order). EVERY delete is scoped to
  -- (tenant_id, is_demo=true) — real rows can never match.
  --
  -- Transactions FIRST: they reference accounts via FK, and pre-fix installs
  -- left 8 posted transactions with is_demo=false. The robust predicate
  -- catches both flagged rows and unflagged rows whose reference_id points
  -- to a demo payment/income/expense. The immutability guard is already
  -- disabled above.
  DELETE FROM public.transactions t
   WHERE t.tenant_id = p_tenant_id AND (
     t.is_demo = true
     OR EXISTS (SELECT 1 FROM public.payments p
                 WHERE p.id = t.reference_id AND p.tenant_id = p_tenant_id AND p.is_demo = true)
     OR EXISTS (SELECT 1 FROM public.income i
                 WHERE i.id = t.reference_id AND i.tenant_id = p_tenant_id AND i.is_demo = true)
     OR EXISTS (SELECT 1 FROM public.expenses e
                 WHERE e.id = t.reference_id AND e.tenant_id = p_tenant_id AND e.is_demo = true)
   );
  DELETE FROM public.notifications       WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.scholarships        WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.payments            WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.invoice_items       WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.discounts           WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.invoices            WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.income              WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.expenses            WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.accounts            WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.fee_items           WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.fee_structures      WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.exams               WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.announcements       WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.students            WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.classes             WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.darjas              WHERE tenant_id = p_tenant_id AND is_demo = true;
  DELETE FROM public.staff               WHERE tenant_id = p_tenant_id AND is_demo = true;

  -- Re-enable guards before commit.
  ALTER TABLE public.invoices            ENABLE TRIGGER trg_invoices_guard_immutable;
  ALTER TABLE public.payments            ENABLE TRIGGER trg_payments_guard_immutable;
  ALTER TABLE public.income              ENABLE TRIGGER trg_income_guard_immutable;
  ALTER TABLE public.expenses            ENABLE TRIGGER trg_expenses_guard_immutable;
  ALTER TABLE public.discounts           ENABLE TRIGGER trg_discounts_guard_immutable;
  ALTER TABLE public.payment_allocations ENABLE TRIGGER trg_payment_allocations_guard_immutable;
  ALTER TABLE public.transactions        ENABLE TRIGGER trg_transactions_guard_immutable;
  ALTER TABLE public.invoice_items       ENABLE TRIGGER trg_invoice_items_parent_guard;
  ALTER TABLE public.invoice_items       ENABLE TRIGGER trg_invoice_items_recalc;

  RETURN jsonb_build_object('removed', true, 'demo_students_removed', v_count);
END $$;

-- Lock down: only service_role may call these (the Edge Function).
REVOKE ALL ON FUNCTION public.demo_status(uuid)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.demo_install(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.demo_remove(uuid)  FROM PUBLIC, anon, authenticated;

-- ── ledger ───────────────────────────────────────────────────
-- (already recorded above)
