# Business-Logic Vulnerability Audit — Madrassa-360

Date: 2026-10-03 | Scope: workflow manipulation, state transitions, races, idempotency, deletion semantics | Read-only audit, no code modified

## Method

The app's write path was traced end-to-end: Flutter repositories write **local-first**,
then the sync engine pushes ops through the `sync_apply` RPC
(`supabase/migrations/016_sync.sql`), which is `SECURITY DEFINER` and **bypasses RLS
entirely** — it checks only tenant *membership*, never permissions and never
status-transition rules. Direct PostgREST writes are RLS-gated (with careful
per-status policies in `014_finance.sql`), but the app does not use them for writes.
So the **effective server-side enforcement for all real app traffic** is:
`sync_apply` membership check + Postgres `CHECK` constraints + triggers.
Every place the RLS policies are stricter than that trio is a bypassable rule.

---

## State-transition tables

### invoices (`014`, RLS policies + `finance_immutable_guard('paid,cancelled,void')`)

| Transition | RLS (direct PostgREST) | Via sync_apply (real app path) | Verdict |
|---|---|---|---|
| draft → issued | allowed (fees.collect) | allowed | OK |
| draft/issued → cancelled, void | allowed (fees.collect) | allowed | OK |
| issued → draft (backwards) | allowed (WITH CHECK includes 'draft') | allowed | WEAK — backwards transition permitted |
| any → paid / partially_paid / overdue | **forbidden** (WITH CHECK excludes them; set only by `finance_refresh_invoice_status` trigger) | **ALLOWED** — sync writes any status | **CRITICAL (C1)** |
| paid/cancelled/void → anything | blocked (USING + trigger) | blocked (trigger) | OK |
| amount_paid / subtotal / discount_total edited directly | RLS-gated, trigger-recalc'd | **ALLOWED** — writable sync columns | **CRITICAL (C2)** |

### payments (`014`, guard `'posted,void'`)

| Transition | RLS | Via sync_apply | Verdict |
|---|---|---|---|
| draft → posted | allowed (fees.collect) | allowed; `trg_payments_post` fires → ledger + allocation + invoice update | OK |
| draft → void | allowed | allowed | OK |
| posted/void → anything | blocked | blocked (trigger) | OK |
| **INSERT with status='posted'** | RLS requires 'draft' | **ALLOWED** — `trg_payments_post` is `BEFORE UPDATE OF status`, never fires on INSERT → receipt exists with **no ledger entry, no allocation, invoice untouched** | **CRITICAL (C2)** |

### refunds (`014`, guard `'approved,posted,void'`)

| Transition | RLS | Via sync_apply | Verdict |
|---|---|---|---|
| draft → approved | allowed (finance.approve, approved_by NOT NULL) | allowed | OK |
| approved → posted | **allowed by RLS** (`refunds_post_tenant`) | **RAISES** — immutable guard treats 'approved' as final | **BROKEN WORKFLOW (C3)** — refunds can never post |
| draft → posted (skip approval) | forbidden by RLS | **ALLOWED** via sync | **HIGH (H1)** |
| INSERT with status='posted' | RLS requires 'draft' | **ALLOWED** — `trg_refunds_post` never fires → no reversing ledger entry, invoice not relieved | **CRITICAL (C2)** |

### expenses / income (`014`, guard `'posted,void'`)

| Transition | RLS | Via sync_apply | Verdict |
|---|---|---|---|
| draft → approved | allowed (finance.approve) | allowed | OK |
| approved → posted | allowed | allowed; `trg_expenses_post` fires | OK |
| draft → posted (skip approval) | forbidden by RLS | **ALLOWED** via sync | **HIGH (H1)** |
| INSERT with status='posted' | RLS requires 'draft' | **ALLOWED** — posting trigger never fires → ledger entry missing | **CRITICAL (C2)** |

### transactions — canonical ledger (`014`, guard `'posted,void'`)

| Operation | Verdict |
|---|---|
| INSERT with status='posted' via sync_apply | **CRITICAL (C2)** — fabricated ledger entries with no source document; the entire "posting creates the ledger entry" invariant is bypassable |
| UPDATE/DELETE of posted rows | blocked (trigger) — OK |

### discounts (`014`, guard `'applied,void'`)

| Transition | Verdict |
|---|---|
| draft → applied → (final) | OK; `trg_discounts_apply_recalc` fires on INSERT too |
| Multiple discounts stacking → discount_total > subtotal → negative balance_due | **MEDIUM (M3)** — no cap; CHECK only bounds percentage ≤ 100 |

### results / exams (`01_schema.sql`, no status column at all)

| Aspect | Verdict |
|---|---|
| marks_obtained range | **no CHECK** — negative marks and marks > total_marks accepted server-side **(M1)** |
| published/approved state | **none exists** — marks editable forever; no immutability after publishing **(M1)** |
| duplicates | UNIQUE(exam_id, student_id, subject) — OK |
| who may write | any tenant member via sync_apply (no permission check) — authz issue, cross-ref API-abuse audit |

### attendance (`01_schema.sql`)

| Aspect | Verdict |
|---|---|
| duplicates | UNIQUE(student_id, date) — OK |
| future dates | **allowed** — no constraint; teacher can mark 2030-01-01 **(M5)** |
| locked periods | none — historical attendance editable forever **(M5)** |
| student deletion | ON DELETE CASCADE wipes attendance history silently **(M5)** |

### library (`05_new_modules.sql` + `lib/providers/library_provider.dart`)

| Aspect | Verdict |
|---|---|
| issue flow | client decrements `available_copies` from **stale state** (`book.availableCopies - 1`), then syncs; no server-side decrement trigger on issue (only increment on return) |
| concurrent issue of last copy | **race → negative stock / double issue (H4)**; no CHECK (available_copies >= 0) |
| same book re-issued while out | no unique guard on unreturned (book_id, borrower) |

### students (`01_schema.sql`)

| Aspect | Verdict |
|---|---|
| date_of_admit < date_of_birth | **allowed** — no CHECK **(M6)** |
| roll_no uniqueness | UNIQUE(roll_no, class_id) — OK |
| deletion | darja/class SET NULL; check fee/invoice RESTRICT coverage — invoices.student_id is RESTRICT, legacy fees.student_id is CASCADE |

---

## Findings

### CRITICAL

**C1 — Invoice status can be set to 'paid' without any payment via the sync write path**
- Location: `supabase/migrations/016_sync.sql` (`sync_apply` UPDATE branch) vs `supabase/migrations/014_finance.sql` (`invoices_update_tenant` WITH CHECK)
- Problem: RLS deliberately excludes `'paid'/'partially_paid'/'overdue'` from the invoice status values a client may write — paid is supposed to be derived only by `finance_refresh_invoice_status()`. But every app write goes through `sync_apply`, which is SECURITY DEFINER, skips RLS, and treats `status` as an ordinary writable column (only `id, tenant_id, revision, server_version, deleted_at, created_at, updated_at` are excluded).
- Why it matters: the "an invoice is paid only when money was received" invariant — the core of the whole finance module — is enforced nowhere on the real write path.
- Scenario: a malicious clerk (or a tampered app) calls `sync_apply('invoices', id, rev, '{"status":"paid"}', 'update')`. The immutable guard only blocks updates *from* final states, not *to* 'paid'. The invoice now reads paid with `amount_paid = 0`, permanently (it can never be edited again — it's now "final"). The student's dues vanish with no payment, no receipt, no ledger entry.
- Fix: add a `BEFORE UPDATE OF status` trigger on invoices that rejects direct writes to derived statuses (`paid`, `partially_paid`, `overdue`) — these may only be set by `finance_refresh_invoice_status()`; or strip `status` from sync_apply's writable columns for invoices and route transitions through a dedicated RPC.

**C2 — Financial documents can be INSERTed already-posted, bypassing the entire posting pipeline**
- Location: `supabase/migrations/016_sync.sql` (INSERT branch — no status validation) + `014_finance.sql` posting triggers (`BEFORE UPDATE OF status` only)
- Problem: `trg_payments_post`, `trg_refunds_post`, `trg_expenses_post`/`trg_income_post` fire only on UPDATE of status. `sync_apply` INSERT accepts any `status`, including `'posted'`. RLS would require `'draft'` on insert, but sync bypasses RLS.
- Why it matters: two corruption modes. (a) *Ghost receipts*: a payment inserted as posted never creates its `transactions` ledger row, never creates a `payment_allocations` row, never touches the invoice — the receipt exists but the money is invisible to every financial report and the invoice still shows due. (b) *Fabricated ledger*: `transactions` itself is in the sync whitelist, so a client can insert `status='posted'` ledger rows directly — inventing income/expenses with no source document.
- Scenario: clerk inserts payment `{"status":"posted","amount":50000}` via sync. The printed receipt looks legitimate; the invoice still shows the full balance due, so the student may be asked to pay again — or the clerk pockets cash against a "posted" receipt that never hit the ledger. Alternatively, insert a posted `transactions` row for fake donations to inflate reported income.
- Fix: `BEFORE INSERT` trigger on payments/refunds/expenses/income/transactions forcing `NEW.status = 'draft'` (or raising unless draft); remove `transactions` from the sync_apply whitelist entirely — the ledger must be writeable only by posting triggers.

**C3 — Refund approval is a dead end: approved refunds can never be posted**
- Location: `supabase/migrations/014_finance.sql:815` (`trg_refunds_guard_immutable` … `'approved,posted,void'`) vs the `refunds_post_tenant` RLS policy (explicitly allows approved→posted) and `lib/data/repositories/finance_repository.dart:706` (`transitionRefund`)
- Problem: the immutable guard treats `'approved'` as a final state, so the RLS-sanctioned `approved → posted` transition raises `finance: refunds.<id> is approved and immutable`. The intended lifecycle draft→approved→posted (which the RLS policies and the app both implement) cannot complete.
- Why it matters: `finance_post_refund()` — the trigger that writes the reversing ledger entry and relieves the invoice — never fires for an approved refund. A real-world cash refund recorded in the app stays `approved` forever with zero ledger effect; the invoice still shows paid. Staff will either leave refunds half-done (books wrong) or learn to bypass approval via C2/H1 (controls erode).
- Scenario: accountant creates a refund draft, principal approves it, accountant taps "post" → server raises; the sync op retries 5× then parks as dead-letter. The UI showed local success (local-first), so everyone believes the refund posted. Month-end: ledger missing the reversal, invoice still paid.
- Fix: change the refunds guard list to `'posted,void'` (matching expenses/income); add a separate transition guard enforcing draft→approved→posted order.

### HIGH

**H1 — Approval steps are skippable through the sync path (no transition enforcement)**
- Location: `016_sync.sql` vs `014_finance.sql` RLS (`expenses_approve_tenant`, `refunds_approve_tenant`, `income` equivalents)
- Problem: RLS encodes draft→approved (requires `finance.approve` + `approved_by NOT NULL`) → posted as distinct policies. `sync_apply` enforces none of it: any tenant member can move expenses/income/refunds draft→posted directly, skipping the approver and the `finance.approve` permission. The app's own `recordExpense`/`recordIncome` do perform the approve step, but that is client convention, not server enforcement.
- Scenario: a clerk with only `fees.collect` (no `finance.approve`) records a Rs. 200,000 "expense" to a personal account and posts it directly via a crafted sync call. No approver ever sees it; the ledger entry is created by the posting trigger as if approved.
- Fix: implement a single `finance_transition_guard()` trigger per document table encoding the legal transition graph (see tables above), firing on the real write path; or move financial writes off `sync_apply` into dedicated RPCs (`post_payment`, `approve_expense`, …) with permission checks.

**H2 — Concurrent payment posting race: over-allocation with no row lock**
- Location: `supabase/migrations/014_finance.sql` `finance_post_payment()` — `SELECT LEAST(NEW.amount, balance_due) …` then a separate `UPDATE invoices SET amount_paid = amount_paid + v_alloc`
- Problem: the invoice row is never locked (`FOR UPDATE`). Two clerks posting payments against the same invoice concurrently both read the same `balance_due` and both allocate the full amount. There is no CHECK preventing `amount_paid > total`.
- Why it matters: `amount_paid` can exceed the invoice total; `payment_allocations` rows can sum to more than the invoice. `finance_refresh_invoice_status` then marks it `paid` (amount_paid >= total). Financial reports and the invoice disagree with reality.
- Scenario: invoice balance Rs. 10,000. Two cashiers collect Rs. 10,000 each at the same second (or one double-submits across two devices). Both allocations succeed → amount_paid = 20,000, two receipts, ledger shows 20,000 income for a 10,000 bill.
- Fix: `SELECT … FOR UPDATE` on the invoice row inside `finance_post_payment()` (and the refund counterpart); add `CHECK (amount_paid <= subtotal - discount_total + tax_total)` or at least a trigger warning; consider capping allocation at balance_due *at post time under lock* (the LEAST already does this — it just needs the lock).

**H3 — Duplicate payments on resubmission: no idempotency key**
- Location: `lib/presentation/screens/finance/finance_payments_tab.dart:439` (`_record`), `lib/providers/finance_provider.dart:186` (`recordPayment`), `lib/data/repositories/finance_repository.dart:620`
- Problem: every submit generates a fresh payment ID (`_newId()`). The `_saving` flag guards double-*tap*, but if the first attempt errors (or the user is offline and retries, or the sheet stays open after a failure), the retry creates a *second* payment row for the same physical cash. The sync engine's idempotency is per-ID (`already_exists`), which doesn't help across IDs. There is no dedupe key (e.g., student + amount + invoice + time window) and no unique constraint that would catch it.
- Scenario: cashier collects Rs. 5,000, taps record, gets a transient error, taps again → two Rs. 5,000 draft payments sync; both post; two receipt numbers; ledger double-counts; invoice overpaid (feeds H2).
- Fix: generate the payment ID once per user *intent* (keep it across retries of the same sheet session); add an idempotency-key column (UNIQUE per tenant) populated from the client; and/or a server-side dedupe guard (same student+invoice+amount within N minutes raises for review).

**H4 — Library double-issue race: stock decremented from stale client state**
- Location: `lib/providers/library_provider.dart:142-207` (`issueBook`), `supabase/05_new_modules.sql` (`library_books`, `book_issues`, `handle_book_return`)
- Problem: issuing computes `newAvailable = book.availableCopies - 1` from the *locally cached* book list, then syncs an update. There is no server-side decrement on issue (only an increment trigger on return), no `CHECK (available_copies >= 0)`, and no guard against issuing when `available_copies = 0`. Two librarians (or two devices) issuing the last copy both compute 0 from a stale 1; conflict resolution rebases the *stale-computed* value, so the final write can be -1 or silently double-issue.
- Scenario: one copy of a textbook remains. Two staff issue it to two students within the sync window → both issues recorded, `available_copies` = -1, and there is no server record of which issue is invalid.
- Fix: `BEFORE INSERT` trigger on `book_issues` that atomically decrements `available_copies` under row lock and raises when it would go negative; remove the client-side decrement (or keep it as optimistic UI only); add `CHECK (available_copies >= 0)`; add a partial unique index preventing duplicate unreturned issues per (book_id, borrower_id).

### MEDIUM

**M1 — Results have no marks range check and no published state**
- Location: `supabase/01_schema.sql` (`results`: `marks_obtained NUMERIC(6,2) NOT NULL` — no CHECK)
- Problem: negative marks and marks exceeding `total_marks` are accepted server-side. There is no published/locked state at all — results are mutable forever, so "final" report cards can be altered after issuance with no trail beyond the generic audit log.
- Scenario: tampered client submits `marks_obtained = 999` for `total_marks = 100`; or a teacher quietly edits last term's marks months later.
- Fix: `CHECK (marks_obtained >= 0 AND marks_obtained <= total_marks)`; add a `status`/`is_published` column with an immutability trigger once published (corrections via re-issue, not silent edit).

**M2 — Legacy `fees` table accepts negative amounts, corrupting its generated status**
- Location: `supabase/01_schema.sql` (`fees.amount_due`, `fees.amount_paid` — no CHECK); still read/written (`lib/data/repositories/fee_repository.dart`, sync entity `'fees'`)
- Problem: negative `amount_due` makes the generated `status` instantly `'paid'`; negative `amount_paid` is storable.
- Fix: `CHECK (amount_due >= 0 AND amount_paid >= 0)`; decide whether this table is legacy (then remove from sync whitelist) or live (then harden).

**M3 — Discount stacking can drive an invoice negative**
- Location: `014_finance.sql` (`discounts` — percentage capped at 100, but multiple discounts sum unboundedly; `invoices.balance_due` generated with no floor)
- Problem: a 100% discount plus a fixed discount (or two fixed discounts) can make `discount_total > subtotal` → negative `balance_due`. Nothing rejects it.
- Scenario: clerk applies "50% hardship" + "Rs. 5,000 staff" discounts on a Rs. 8,000 invoice → balance_due negative; invoice can never be sensibly paid; reports show negative receivables.
- Fix: CHECK/trigger `discount_total <= subtotal` on the invoice (recomputed in `finance_recalc_invoice` — raise if violated).

**M4 — Receipt numbers are duplicated across document types**
- Location: `supabase/migrations/028_finance_per_table_doc_triggers.sql` — payments and income share `finance_receipt_seq`
- Problem: a payment and an income record can both be `RCP-00000001` (UNIQUE is per-table). Receipt numbers are supposed to uniquely identify a receipt for audit; duplicates across types break that.
- Fix: separate sequences per document type, or prefix per type (`RCP-` vs `INC-`).

**M5 — Attendance: future dates, no locked periods, cascade wipes history**
- Location: `01_schema.sql` (`attendance.date` no constraint; `ON DELETE CASCADE` on student_id/class_id)
- Problem: teachers can mark future attendance; past attendance is editable forever (no month-close lock); deleting a student silently deletes their entire attendance history.
- Fix: `CHECK (date <= CURRENT_DATE)`; term/period locking (a `locked_before` per tenant); change student FK to RESTRICT or soft-delete students instead.

**M6 — Impossible student dates accepted**
- Location: `01_schema.sql` (`students.date_of_birth`, `date_of_admit` — no cross-check)
- Problem: admission before birth, birth in the future — accepted server-side.
- Fix: `CHECK (date_of_birth IS NULL OR (date_of_birth <= CURRENT_DATE AND date_of_admit >= date_of_birth))`.

**M7 — Invoice status can move backwards (issued → draft)**
- Location: `014_finance.sql` `invoices_update_tenant` WITH CHECK includes `'draft'`
- Problem: minor, but a backwards transition shouldn't be legal; it lets a user re-open a cancelled-leaning workflow.
- Fix: WITH CHECK should require the new status to be a forward transition from the old.

**M8 — `approved_by` is client-writable through sync**
- Location: `016_sync.sql` (not in the excluded column list)
- Problem: the approver identity — the entire evidence of the approval step — can be set to any UUID by the requester, including self-approving.
- Fix: exclude `approved_by` from sync-writable columns; set it only inside the approve transition (server stamps `auth.uid()`).

**M9 — Tenant deletion irreversibly wipes all financial history**
- Location: `014_finance.sql` (`ON DELETE CASCADE` on every `tenant_id` FK)
- Problem: deleting a tenant destroys the canonical ledger with no soft-delete, no archive, no confirmation backstop at the DB level. One privileged misclick (or compromised platform admin) = total, unrecoverable loss for a school.
- Fix: block tenant DELETE at the DB level (trigger) or require a two-step archive-then-purge; at minimum document the backup expectation.

### LOW

**L1 — Certificate serials are client-assigned; duplicates possible**
- Location: `lib/data/repositories/certificate_repository.dart` (no issuance table by design; serial assigned client-side "until backend exists")
- Problem: two devices can issue the same serial number; no server-side uniqueness or verification.
- Fix: when the issuance backend is built, assign serials from a per-tenant sequence.

**L2 — Internal finance functions are RPC-callable by any authenticated user**
- Location: `014_finance.sql` (`finance_refresh_invoice_status`, `finance_recalc_invoice` — SECURITY DEFINER, no REVOKE)
- Problem: exposed via PostgREST `/rpc/` to every authenticated user. They only recompute from existing data (limited direct abuse), but they are internals that shouldn't be public; combined with C2 they complete the fake-paid workflow without needing sync.
- Fix: `REVOKE EXECUTE … FROM PUBLIC, authenticated, anon` on all `finance_*` internals; keep only documented RPCs (`sync_apply`, permission helpers) granted.

**L3 — Invoice void/cancel needs no reason and no approval**
- Location: `014_finance.sql` — draft/issued → cancelled/void requires only `fees.collect`
- Problem: a clerk can void an issued invoice (erasing a receivable) with no note, no approver. The audit log records it, but nothing requires justification.
- Fix: require `notes`/reason non-empty for void/cancel transitions (trigger), and consider `finance.approve` for voiding issued invoices.

---

## Prioritized remediation order

1. **C2** — force `status='draft'` on INSERT for all financial document tables + remove `transactions` from the sync whitelist. (Closes ghost receipts and fabricated ledger entries; small trigger, huge blast radius.)
2. **C1** — forbid direct writes to derived invoice statuses / `amount_paid` except through the posting pipeline. (Closes fake-paid invoices.)
3. **C3** — fix the refunds guard list to `'posted,void'` so the sanctioned approve→post flow works. (Un-breaks refunds; without it every other refund fix is moot.)
4. **H1** — add a real transition-guard trigger per document table (or move financial writes to permission-checked RPCs). (Closes approval skipping.)
5. **H2** — `SELECT … FOR UPDATE` in `finance_post_payment`/`finance_post_refund` + overpayment CHECK. (Closes the double-collection race.)
6. **H3** — idempotency keys for payments (client-stable ID per intent + server UNIQUE). (Closes duplicate receipts.)
7. **H4** — server-side atomic book-issue decrement + `available_copies >= 0`. (Closes double-issue.)
8. **M1, M2, M3, M5, M6** — CHECK constraints batch (marks range + published lock; fees non-negative; discount cap; attendance date bounds; student date sanity).
9. **M4, M7, M8, M9, L1–L3** — hygiene batch (per-type receipt sequences; forward-only transitions; server-stamped approver; tenant-delete guard; REVOKE internals; void reasons; certificate serials).

## Notes / limitations

- Static analysis of migrations + the Flutter write path; no live-DB exploit testing was performed (read-only brief).
- The central architectural finding: **the app has two authorization regimes** — strict RLS transition policies for direct PostgREST writes, and membership-only `sync_apply` for all real writes. Every RLS rule stricter than CHECKs+triggers is currently decorative. Remediation should converge on ONE enforced path: either harden `sync_apply` per-entity (status/permission/column rules) or move financial writes to dedicated RPCs and shrink the sync whitelist to non-financial entities.
- Cross-cutting: the same "sync bypasses RLS" pattern likely affects non-financial entities too (e.g., any member editing another class's results) — covered in the sibling API-abuse/tenant-isolation audits.
