# Database Layer Audit — Madrassa-360

**Scope:** `supabase/migrations/` (001–028), legacy `supabase/01_schema.sql` / `05_new_modules.sql`,
`demo/seed_demo_madrassa.sql`, Flutter local DB (`lib/data/local/app_database.dart`, drift),
sync engine (`lib/core/sync/sync_engine.dart`).
**Type:** read-only audit. No code or database modified.
**Date:** 2026-10-03. Branch `redesign/ux-v2`.

**Method:** every `CREATE TABLE` extracted (43 tables across migrations + 12 legacy tables),
all FK `ON DELETE` actions catalogued, `sync_apply` (016) and finance posting triggers (014)
read statement-by-statement, sync engine push/pull/conflict paths traced.

**What's solid (don't break):** `tenant_id NOT NULL` + FK + immutability trigger on the 13
retrofitted tables (006); per-table doc-number triggers using atomic `nextval` (028);
final-row immutability enforced twice (RLS + `finance_immutable_guard`); append-only
`audit_logs` via SECURITY DEFINER trigger; optimistic-concurrency `revision` design;
good FK/tenant index coverage (009, 014); `is_tenant_member()` correctly requires
`is_active`.

---

## CRITICAL

### C-1. `sync_apply` INSERT leaks full rows cross-tenant before any membership check
- **Location:** `supabase/migrations/016_sync.sql` — `sync_apply`, INSERT branch
  (`SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1)` → returns
  `'already_exists'` with the full `server_row` JSON **before** the
  `is_tenant_member(v_tenant)` check two statements later).
- **Problem:** any authenticated user (even with zero tenant memberships) can call
  `sync_apply('students', <guessed-uuid>, …)` with `p_op='insert'`. If the UUID exists
  in *any* tenant, the RPC returns the entire row — names, tenant_id, financial data —
  bypassing RLS and tenant isolation completely.
- **Why it matters:** UUIDs are unguessable but not secret — they leak via shared URLs,
  exports, logs, and receipts. This turns every UUID into a cross-tenant read oracle.
- **Attack scenario:** attacker harvests one student UUID (e.g. from a shared fee
  receipt), then scripts `sync_apply` insert-probes across all 26 entities × UUID
  variants to exfiltrate other tenants' students, invoices, and payments.
- **Fix:** move the membership check before the existence probe, and never return
  `server_row` for a row in a tenant the caller is not a member of:
  ```sql
  v_tenant := NULLIF(p_payload->>'tenant_id','')::UUID;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'sync: insert payload missing tenant_id'; END IF;
  IF NOT (public.is_platform_admin() OR public.is_tenant_member(v_tenant)) THEN
    RAISE EXCEPTION 'sync: not a member of tenant %', v_tenant;
  END IF;
  -- THEN the EXISTS check; on 'already_exists' return server_row only if the
  -- existing row's tenant_id = v_tenant (or caller is platform admin).
  ```

### C-2. `sync_apply` UPDATE/DELETE has a TOCTOU race — optimistic concurrency is not atomic
- **Location:** `supabase/migrations/016_sync.sql` — UPDATE branch and DELETE branch.
- **Problem:** the revision check is a plain `SELECT … INTO` followed by a *separate*
  `UPDATE … WHERE t.id = $2` with **no revision predicate and no row lock**.
  Two concurrent writers with the same `base_revision` both pass the check; both
  UPDATEs execute; the second silently overwrites the first. The `bump_revision`
  trigger still increments, so the lost update is invisible in the revision counter.
- **Why it matters:** this defeats the entire design contract of 016 ("update/delete
  succeed only if the server's current revision EQUALS p_base_revision") — including
  the "financial rows are NEVER silently overwritten" guarantee.
- **Failure scenario:** two accountants post adjustments to the same draft invoice
  concurrently; accountant A's discount is silently lost, invoice total is wrong,
  money is collected against a corrupted total.
- **Fix:** predicate the write on the revision and fail visibly:
  ```sql
  EXECUTE format('UPDATE public.%I t SET … WHERE t.id = $2 AND t.revision = $5 …',
                 …) USING p_payload, p_entity_id, v_uid, v_sv, p_base_revision;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RETURN conflict/already-changed payload; END IF;
  ```
  (Same for the soft-delete branch. Alternatively `SELECT … FOR UPDATE` the row
  before the check.)

---

## HIGH

### H-1. Payment posting over-allocation race — `amount_paid` can exceed invoice total
- **Location:** `supabase/migrations/014_finance.sql` — `finance_post_payment()`
  (`BEFORE UPDATE OF status ON public.payments`).
- **Problem:** allocation is computed as `SELECT LEAST(NEW.amount, balance_due) …
  FROM public.invoices WHERE id = …` with **no `FOR UPDATE` lock**, then
  `UPDATE invoices SET amount_paid = amount_paid + v_alloc`. Two concurrent
  draft→posted transitions for the same invoice both read the same stale
  `balance_due`; both allocate the full amount. `amount_paid` ends up greater than
  `total`; the generated `balance_due` goes negative and **no CHECK constraint
  forbids it**.
- **Failure scenario:** invoice total Rs 10,000, balance Rs 10,000. Two cashiers post
  Rs 10,000 payments within the same second (or one double-tap + one queued offline
  op). Both allocate Rs 10,000 → `amount_paid` = Rs 20,000, `balance_due` = −10,000,
  status flips to `paid`. The madrasa's books now show money it never received.
- **Fix:** lock the invoice row before reading:
  ```sql
  SELECT LEAST(NEW.amount, balance_due) INTO v_alloc
    FROM public.invoices WHERE id = NEW.invoice_id FOR UPDATE;
  ```
  plus a backstop constraint: `CHECK (amount_paid <= subtotal - discount_total + tax_total)`
  (note: CHECK on an expression of stored columns is allowed; or add a trigger
  validating `balance_due >= 0` after the allocation update). Same pattern in
  `finance_post_refund()` — add `FOR UPDATE` there too.

### H-2. No idempotency on payments/expenses/income — double-submit double-charges
- **Location:** `supabase/migrations/014_finance.sql` — `payments`, `expenses`, `income`
  tables (no idempotency key, no business-natural unique key).
- **Problem:** nothing at the DB level distinguishes "user tapped Collect twice" from
  two legitimate payments. Retry-after-timeout (the sync engine retries up to 5×)
  can post the same payment twice.
- **Failure scenario:** cashier taps "Collect fee", request times out, sync engine
  retries → two `payments` rows, two ledger entries, parent charged twice.
- **Fix:** add a client-generated idempotency key:
  ```sql
  ALTER TABLE public.payments ADD COLUMN idempotency_key TEXT;
  CREATE UNIQUE INDEX ux_payments_idem ON public.payments (tenant_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
  ```
  (Same for `expenses`, `income`. The app must send a stable key per user action.)

### H-3. Soft-deleted rows still occupy UNIQUE slots — delete→re-add breaks sync
- **Location:** `supabase/01_schema.sql` (`attendance` UNIQUE `(student_id, date)`,
  `fees` UNIQUE `(student_id, month)`); `supabase/migrations/016_sync.sql`
  (soft-delete via `deleted_at`, no partial unique indexes).
- **Problem:** 016's contract is soft-delete, but the legacy UNIQUE constraints are
  unconditional. Soft-delete an attendance row, re-mark attendance for the same
  student+date → the re-insert hits the UNIQUE violation → `sync_apply` raises →
  sync engine parks it as failed → after 5 retries `dead_letter`. The user's
  correction never syncs.
- **Fix:** replace with partial unique indexes:
  ```sql
  ALTER TABLE public.attendance DROP CONSTRAINT attendance_student_id_date_key;
  CREATE UNIQUE INDEX ux_attendance_live ON public.attendance (student_id, date)
    WHERE deleted_at IS NULL;
  ALTER TABLE public.fees DROP CONSTRAINT fees_student_id_month_key;
  CREATE UNIQUE INDEX ux_fees_live ON public.fees (student_id, month)
    WHERE deleted_at IS NULL;
  ```

### H-4. Financial-conflict manual review has no reachable UI
- **Location:** `lib/core/sync/conflict_review_screen.dart` (`ConflictReviewScreen`
  class exists but is never instantiated anywhere in `lib/`; no route references it).
- **Problem:** the entire 016 safety design for financial tables ("NEVER silently
  overwritten… client MUST surface it for MANUAL review") dead-ends: conflicts are
  parked in `sync_conflicts` with no screen to view or resolve them.
- **Why it matters:** a parked payment/invoice conflict means the local device and
  server permanently disagree about money, and nobody is told in actionable form.
- **Fix:** wire `ConflictReviewScreen` into the app shell (e.g. from the sync badge /
  finance dashboard) and add a test asserting the route exists; surface a persistent
  banner while unresolved financial conflicts exist.

### H-5. Conflict resolution uses wall-clock timestamps — device clock skew silently overwrites
- **Location:** `lib/core/sync/sync_engine.dart` — `decideNormalConflict()`
  (compares `serverUpdatedAt` vs `localUpdatedAt`); contradicts `016_sync.sql`'s
  documented rule ("the server row IS the latest valid state… the client adopts
  server_row").
- **Problem:** two devices with skewed clocks: device A's clock is 5 minutes fast.
  B's edit wins the revision race on the server, but A's later rebase compares
  timestamps, concludes "local is newer", and overwrites B's server-newer change.
- **Fix:** decide purely on revision (server revision > base ⇒ take server), never
  on timestamps; keep timestamps for display only.

### H-6. `audit_logs.tenant_id ON DELETE CASCADE` — deleting a tenant wipes its audit trail
- **Location:** `supabase/migrations/012_audit_logs.sql`.
- **Problem:** the append-only audit log, the backstop for financial accountability,
  is cascade-deleted with the tenant. A malicious tenant admin (or a mistaken
  platform operator) can erase all evidence of fraud by deleting the tenant.
- **Fix:** `ON DELETE SET NULL` (keep rows, null the tenant) or better, `ON DELETE
  RESTRICT` + a soft-delete/archive flow for tenants. Financial audit rows must
  outlive the tenant.

### H-7. Single-sided ledger — nothing enforces balanced books
- **Location:** `supabase/migrations/014_finance.sql` — `transactions` table.
- **Problem:** the "canonical posted ledger" is a flat list of single-sided rows
  (`kind` in income/expense/transfer). No double-entry invariant (debits = credits)
  is enforced anywhere, so posting bugs (like H-1) corrupt the books silently.
- **Fix (medium-term):** add a per-tenant running-balance guard or a periodic
  reconciliation RPC + test asserting `SUM(amount) FILTER (kind='income') -
  SUM(amount) FILTER (kind='expense')` matches expected cash position. At minimum,
  add the `balance_due >= 0` backstop from H-1.

---

## MEDIUM

### M-1. Cross-tenant FK references are creatable (no composite tenant FKs)
- **Location:** all FKs reference bare `id` (e.g. `invoices.student_id →
  students(id)`); `sync_apply` INSERT (016) checks payload `tenant_id` membership
  but never verifies referenced rows belong to that tenant.
- **Problem:** a tenant-A member who learns a tenant-B student UUID can insert an
  invoice/payment in tenant A pointing at tenant B's student. The row passes FK and
  RLS. Any report joining without a strict tenant filter then leaks B's data.
- **Fix:** defense in depth — in `sync_apply` INSERT, verify every `*_id` FK in the
  payload resolves to a row with `tenant_id = v_tenant` (whitelisted FK map per
  entity); longer-term, composite FKs `(tenant_id, id)`.

### M-2. `partially_paid` / `overdue` invoices are still mutable
- **Location:** `supabase/migrations/014_finance.sql` — `trg_invoices_guard_immutable`
  guards only `('paid,cancelled,void')`.
- **Problem:** after a partial payment, `subtotal`/`discount_total` can still be
  edited directly, changing `total` while `amount_paid` stays fixed → corrupt
  `balance_due`.
- **Fix:** extend the guard to `('partially_paid','overdue')` for amount-bearing
  columns, or make all amount fields immutable once `amount_paid > 0`.

### M-3. `transactions.reference_id` has no foreign key
- **Location:** `supabase/migrations/014_finance.sql` — `transactions.reference_id UUID`
  with only a `reference_type` text tag; index exists but no FK.
- **Problem:** referenced payments/refunds/expenses can be deleted (drafts are
  hard-deletable via RLS) leaving ledger rows pointing at nothing; reconciliation
  breaks silently.
- **Fix:** no single FK possible (polymorphic); add a trigger validating
  `(reference_type, reference_id)` on insert, or per-type nullable FK columns.

### M-4. `results.marks_obtained` has no CHECK constraints
- **Location:** `supabase/01_schema.sql` — `results` table.
- **Problem:** no `CHECK (marks_obtained >= 0 AND marks_obtained <= total_marks)`.
  Negative marks or marks exceeding the total are storable; result cards and
  transcripts render garbage.
- **Fix:** `ALTER TABLE public.results ADD CONSTRAINT results_marks_sane
  CHECK (marks_obtained >= 0 AND marks_obtained <= total_marks);`

### M-5. Sequence gaps burn financial document numbers (audit gap)
- **Location:** `supabase/migrations/014_finance.sql`, `028_*` — `nextval` in
  `BEFORE INSERT`; any later failure (RLS, constraint, unique) burns the number.
- **Problem:** missing receipt/invoice numbers in a financial audit look like
  suppressed records. Gaps are currently indistinguishable from fraud.
- **Fix:** log burned numbers to a `doc_number_gaps` table via an `ON CONFLICT`/
  exception handler, or document gaps as expected in the auditor's report.
  (Do not "fix" by reusing numbers.)

### M-6. Migrations 025–028 don't stamp `schema_migrations`
- **Location:** `supabase/migrations/025_*` … `028_*` (zero `schema_migrations`
  inserts; the live ledger was reconciled by hand).
- **Problem:** file state and ledger state disagree; a fresh database built from
  files alone has an incomplete ledger, breaking audit tooling and future
  idempotency checks.
- **Fix:** append the standard stamp block to each file.

### M-7. Inconsistent `ON DELETE` semantics on tenant FKs
- **Location:** `015_parent_links.sql` uses `ON DELETE RESTRICT` for
  `student_guardians.tenant_id` / `teacher_class_assignments.tenant_id`, while
  014/017 use `ON DELETE CASCADE` everywhere else.
- **Problem:** tenant deletion is half-blocked, half-cascading — unpredictable and
  untestable. Combined with H-6, a "successful" delete wipes finance + audit but
  fails on guardians, leaving a half-deleted tenant.
- **Fix:** decide one policy (recommend: RESTRICT everywhere + explicit
  archive/wipe procedure owned by platform admins).

### M-8. `payments.invoice_id ON DELETE SET NULL` vs allocations `ON DELETE CASCADE`
- **Location:** `supabase/migrations/014_finance.sql`.
- **Problem:** deleting a draft invoice orphans its payments (`invoice_id → NULL`,
  money with no bill) while deleting its allocations. Payment history loses its
  link to the invoice.
- **Fix:** `ON DELETE RESTRICT` on `payments.invoice_id` while allocations exist
  (force void-then-reversal instead of delete), consistent with the immutability
  design.

### M-9. `dead_letter` rows never auto-retry; surfaced only as a badge count
- **Location:** `lib/core/sync/sync_engine.dart` (`_recordFailure` → `dead_letter`
  after 5 tries); `lib/core/sync/sync_providers.dart` (count in badge).
- **Problem:** permanently failed rows (e.g. H-3's unique violation) sit invisible
  unless the user taps through; there is no retry/delete affordance wired to the
  dead-letter list.
- **Fix:** add a dead-letter review UI (can share the H-4 screen) with retry and
  discard actions.

### M-10. `book_issues.borrower_id` is free text; FK points at legacy `madrasas`
- **Location:** `supabase/05_new_modules.sql` — `borrower_id TEXT` ("student roll_no
  or staff id", no FK); `madrasa_id REFERENCES public.madrasas(id)`.
- **Problem:** no referential integrity on borrowers (typos create phantom loans);
  the `madrasas` table is legacy (006 migrated to `tenants`) — if it is ever
  dropped, the FK breaks.
- **Fix:** `borrower_student_id UUID REFERENCES students(id)` + `borrower_staff_id`
  UUID nullable with a CHECK that exactly one is set; repoint `madrasa_id`→`tenants`
  or drop the column.

### M-11. No documented/tested server backup & restore runbook
- **Location:** repo docs — `docs/BACKUP_RESTORE.md` covers only the *local* SQLite
  file; server recovery assumes Supabase PITR without a written, tested procedure.
- **Problem:** no RTO/RPO statement, no restore drill, and several migrations are
  not rollback-safe (no down-migrations; 006's legacy-tenant backfill is
  irreversible).
- **Fix:** write a runbook (PITR steps, who can trigger, verification queries) and
  drill it on a staging project quarterly.

### M-12. RLS permits hard deletes that the sync contract forbids
- **Location:** 014 RLS `…_delete_tenant` policies allow DELETE of draft rows;
  016 documents "Clients NEVER hard delete through sync_apply" and other devices
  converge via `'not_found'` → local row dropped.
- **Problem:** a hard delete on one device silently discards other devices' queued
  edits for that row (`_convergeRowDeleted`), and tombstone-based pull never sees
  it (no `deleted_at` row). Two designs disagree; the stricter one (soft-delete
  only) should win.
- **Fix:** remove hard DELETE from RLS policies for synced tables (keep it for
  platform admins only, if at all); route all deletes through `sync_apply`.

---

## LOW

- **L-1.** Global (non-per-tenant) doc-number sequences leak issuance volume across
  tenants via `INV-`/`RCP-` numbers. Accept or scope sequences per tenant.
- **L-2.** `UNIQUE (tenant_id, invoice_number)` permits multiple NULLs — safe only
  while the fill trigger exists; add `NOT NULL` after backfill, or keep as is
  with a comment.
- **L-3.** `payments` and `income` share `finance_receipt_seq` but enforce
  uniqueness per-table only; explicit client-supplied duplicates could collide
  across tables. Low risk; consider one `doc_numbers` registry if it matters.
- **L-4.** `devices`/`device_sessions`: no partial unique index preventing multiple
  non-revoked sessions per device (`WHERE revoked_at IS NULL`).
- **L-5.** `licenses` / `tenant_subscriptions`: no `CHECK (expires_at > issued_at)`.
- **L-6.** `notifications`: no dedup key — a retried `send-notification` call
  inserts duplicate rows.
- **L-7.** `fee_items`: no `UNIQUE (fee_structure_id, name)` — duplicate fee heads
  within a structure are possible.
- **L-8.** Pull page cap (20 × 500 rows) exits silently; it resumes next cycle via
  the persisted watermark, but log a warning when the cap is hit.
- **L-9.** Drift `onUpgrade` handles only `from < 2`; a future v3 without a handler
  throws on launch. Add a fallthrough that throws a *descriptive* error (or
  proper migration).
- **L-10.** `user_accounts.role_name` default `'teacher'` — any insert path that
  omits the role silently grants teacher. Prefer no default (fail loud).

---

## Prioritized DDL-level protections to add

1. **`sync_apply` correctness (C-1, C-2):** reorder INSERT checks; add
   `AND t.revision = $5` + `ROW_COUNT` check to UPDATE/DELETE. — *migration 029*
2. **Payment allocation lock (H-1):** `SELECT … FOR UPDATE` in
   `finance_post_payment` / `finance_post_refund`; add `balance_due >= 0` backstop.
3. **Idempotency keys (H-2):** `idempotency_key` + partial unique indexes on
   `payments`, `expenses`, `income`.
4. **Partial unique indexes (H-3):** `ux_attendance_live`, `ux_fees_live`
   `WHERE deleted_at IS NULL`.
5. **Audit trail survival (H-6):** `audit_logs.tenant_id` → `ON DELETE SET NULL`
   (or RESTRICT + archive flow).
6. **Invoice guard extension (M-2):** include `partially_paid,overdue` for
   amount-bearing columns.
7. **Results sanity (M-4):** `CHECK (marks_obtained >= 0 AND marks_obtained <= total_marks)`.
8. **Reference integrity (M-3, M-10):** validate `transactions(reference_type,
   reference_id)` via trigger; fix `book_issues` borrower references.
9. **Delete semantics (M-7, M-8, M-12):** one consistent tenant-delete policy;
   `payments.invoice_id` → RESTRICT; remove hard DELETE from synced-table RLS.
10. **Ledger stamps (M-6):** add `schema_migrations` inserts to 025–028.
11. **Cross-tenant FK verification (M-1):** payload FK tenant-match check inside
    `sync_apply` INSERT.

## Adversarial summary

- As **any authenticated user with zero memberships**: C-1 gives a cross-tenant
  row-exfiltration oracle via UUID probing (information disclosure, tenant
  isolation bypass at the RPC layer).
- As **two concurrent legitimate users**: C-2 silently drops one writer's changes
  (including financial rows); H-1 over-allocates payments so `amount_paid` exceeds
  the invoice total (financial corruption); H-5 lets a skewed device clock decide
  conflicts (silent overwrite).
- As **one frustrated legitimate user**: H-3 turns delete→re-add into permanently
  unsynced data; M-9 leaves it invisible; H-4 leaves financial conflicts
  unresolvable (no UI).
- As **a malicious tenant admin**: H-6 lets tenant deletion erase the audit trail;
  M-1 lets crafted payloads plant cross-tenant references.
- **Durability:** M-11 — server recovery is assumed (PITR) but undocumented and
  undrilled; several migrations are irreversible.
