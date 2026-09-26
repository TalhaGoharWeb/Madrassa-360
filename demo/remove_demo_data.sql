-- ═══════════════════════════════════════════════════════════════════
-- Madrassa-360 — Demo data pack (REMOVE)
-- File: demo/remove_demo_data.sql
--
-- Deletes the ENTIRE demo tenant ('demo-madrassa') and every row that
-- belongs to it, in foreign-key-safe order (children before parents).
--
-- ═══ ⚠ WARNINGS — READ BEFORE RUNNING ═══
--   1. This permanently deletes the demo tenant and all its data.
--      There is no undo. Run it only when you are done reviewing.
--   2. It touches ONLY rows whose tenant_id = the 'demo-madrassa' tenant.
--      Real tenants are never affected — double-check the slug below.
--   3. Run the whole file as ONE script (it is wrapped in a transaction).
--   4. The 5 demo AUTH USERS are NOT deleted here (Supabase Auth lives
--      outside public.*). Delete them manually:
--        Dashboard → Authentication → Users → select the demo.* users → Delete.
--      Their public.profiles rows are also left in place on purpose.
--
-- ═══ HOW TO RUN ═══
--   Supabase Dashboard → SQL Editor → New query → paste this whole file →
--   Run. Re-runnable: deleting an already-removed tenant is a harmless no-op.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Resolve the demo tenant once.
DO $$
DECLARE
  v_tenant UUID;
BEGIN
  SELECT id INTO v_tenant FROM public.tenants WHERE slug = 'demo-madrassa';
  IF v_tenant IS NULL THEN
    RAISE NOTICE 'remove_demo_data: tenant demo-madrassa not found — nothing to do.';
  ELSE
    RAISE NOTICE 'remove_demo_data: removing tenant % (demo-madrassa)', v_tenant;
  END IF;
END $$;

-- Finance immutability guards block DELETE of posted/applied/paid rows.
-- Demo cleanup is the one legitimate exception: disable them inside this
-- transaction and re-enable before COMMIT (rollback restores them on failure).
ALTER TABLE public.invoices            DISABLE TRIGGER trg_invoices_guard_immutable;
ALTER TABLE public.payments            DISABLE TRIGGER trg_payments_guard_immutable;
ALTER TABLE public.transactions        DISABLE TRIGGER trg_transactions_guard_immutable;
ALTER TABLE public.income              DISABLE TRIGGER trg_income_guard_immutable;
ALTER TABLE public.expenses            DISABLE TRIGGER trg_expenses_guard_immutable;
ALTER TABLE public.refunds             DISABLE TRIGGER trg_refunds_guard_immutable;
ALTER TABLE public.discounts           DISABLE TRIGGER trg_discounts_guard_immutable;
ALTER TABLE public.payment_allocations DISABLE TRIGGER trg_payment_allocations_guard_immutable;

-- ── Finance: deepest children first ─────────────────────────────
DELETE FROM public.payment_allocations WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.refunds             WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.payments            WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.invoice_items       WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.discounts           WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.invoices            WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.fee_items           WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.fee_structures      WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.transactions        WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.expenses            WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.income              WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.accounts            WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.scholarships        WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');

-- ── Legacy business tables ───────────────────────────────────────
DELETE FROM public.attendance          WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.fees                WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.results             WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.book_issues         WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.library_books       WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.finance_transactions WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.student_guardians   WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.teacher_class_assignments WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.students            WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.classes             WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.darja_sections      WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.darjas              WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.staff               WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.exams               WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.announcements       WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');

-- ── Notifications & devices ─────────────────────────────────────
DELETE FROM public.notifications               WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.notification_preferences    WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.notification_device_tokens  WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.device_sessions              WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.devices                      WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');

-- ── Audit (deleted last among children: audit triggers fire on deletes) ──
DELETE FROM public.audit_logs WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');

-- ── RBAC / permissions ──────────────────────────────────────────
DELETE FROM public.user_permissions      WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.permission_delegations WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.permission_scopes     WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.tenant_role_permissions WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.tenant_roles          WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.tenant_memberships    WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');

-- ── Tenant config, licensing ────────────────────────────────────
DELETE FROM public.tenant_modules       WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.tenant_settings     WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.licenses             WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');
DELETE FROM public.tenant_subscriptions WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'demo-madrassa');

-- ── The tenant itself, last ─────────────────────────────────────
DELETE FROM public.tenants WHERE slug = 'demo-madrassa';

-- Re-enable the finance immutability guards.
ALTER TABLE public.invoices            ENABLE TRIGGER trg_invoices_guard_immutable;
ALTER TABLE public.payments            ENABLE TRIGGER trg_payments_guard_immutable;
ALTER TABLE public.transactions        ENABLE TRIGGER trg_transactions_guard_immutable;
ALTER TABLE public.income              ENABLE TRIGGER trg_income_guard_immutable;
ALTER TABLE public.expenses            ENABLE TRIGGER trg_expenses_guard_immutable;
ALTER TABLE public.refunds             ENABLE TRIGGER trg_refunds_guard_immutable;
ALTER TABLE public.discounts           ENABLE TRIGGER trg_discounts_guard_immutable;
ALTER TABLE public.payment_allocations ENABLE TRIGGER trg_payment_allocations_guard_immutable;

COMMIT;

-- ─── Verification: every count must be 0 ───
SELECT count(*) AS remaining_demo_tenants FROM public.tenants WHERE slug = 'demo-madrassa';
