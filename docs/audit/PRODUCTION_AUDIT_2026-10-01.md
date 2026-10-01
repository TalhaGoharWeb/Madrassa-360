# Production Audit — Madrassa-360 — 2026-10-01

**Repo:** `TalhaGoharWeb/Madrassa-360` · **Branch:** `redesign/ux-v2` · **HEAD:** `90b41e59` (CI-green, 6/6)
**Audit date:** 2026-10-01 · **Method:** static read-only scan of `lib/`, `supabase/`, `demo/` (three worker auditors) + parent's live-Supabase audit.
**Raw reports:** `BACKEND_AUDIT.md`, `FRONTEND_AUDIT.md`, `REPORTS_AUDIT.md`, `LIVE_DB_FINDINGS_2026-10-01.md` (same directory).

Constraints honored: read-only, no source edits, no commits. Every finding cites a real file:line read during the audit. Urdu-first bar applied: Nastaleeq display, Naskh inputs/body, no fake data, no dead buttons, no "Coming Soon".

---

## Executive summary — counts by severity

| Area | Blocker | Major | Minor |
|---|---|---|---|
| Live DB (parent audit) | 5 | 0 | 0 |
| Backend (static: migrations/functions/data layer) | 1 | 6 | 10 |
| Frontend (UI/UX, Flutter code health) | 0 | 2 | 28 |
| Reports (PDF generators) | 1 | 0 | 8 |
| **TOTAL** | **7** | **8** | **46** |

Headline: the app is **not production-ready**. The live database has five blockers (a table the app reads/writes doesn't exist; an RLS-enabled table with zero policies; finance triggers missing live; migration ledger out of sync; migration 024 unapplied). The static scan adds a finance-trigger definition bug, a tenant-isolation read hole, a wrong permission gate on fee deletes, a report-generation crash on long tables, and a logo-upload feature broken by a missing RLS UPDATE policy.

---

## Top 5 blockers

1. **Live: `public.user_accounts` table missing entirely** — app reads/writes it (`user_management_provider.dart`); user management is broken live. → Create the table + RLS via migration, backfill from auth/users, verify provider round-trip live. (Source: `LIVE_DB_FINDINGS_2026-10-01.md`)
2. **Live: `public.app_roles` has RLS enabled with zero policies** — deny-all on a table the RBAC path needs; role reads fail closed. → Add SELECT/USING policies scoped to platform admins + tenant members as appropriate, verify live. (Source: `LIVE_DB_FINDINGS_2026-10-01.md`)
3. **Finance doc-number triggers broken in definition AND missing live** — `014_finance.sql`: shared `finance_fill_doc_numbers()` references `NEW.invoice_number`/`NEW.receipt_number` across invoices/payments/income tables with different columns (intermittent 42703 on pooled connections breaks ALL finance inserts); live DB lacks the triggers entirely. → Split into per-table trigger functions referencing only existing columns; re-apply live; add a regression test inserting into each table over a pooled connection. (Static: `supabase/migrations/014_finance.sql`; live: `LIVE_DB_FINDINGS_2026-10-01.md`)
4. **Live: migration tracking out of sync** — 025/026 applied but unrecorded in the ledger. → Reconcile `schema_migrations` with actual live state before any further migration work; a wrong baseline will mis-apply or skip future migrations. (Source: `LIVE_DB_FINDINGS_2026-10-01.md`)
5. **Reports: income/expense PDF crashes on long data** — `lib/core/reports/documents/admin_reports.dart:270`: `incomeExpense` `section()` wraps the `dataTable` in `pw.Column` inside a MultiPage; pdf throws "Widget won't fit into the page" instead of paginating (confirmed against vendored pdf 3.12.0 `multi_page.dart`). → Replace `pw.Column` wrapper with a spanning table widget / restructure so the table paginates.

(Honorable mentions, also blocker-grade: migration 024 unapplied — tenant logos dead until applied **and** an UPDATE policy is added, see B-F2; `sync_apply` letting any member bypass finance status-lifecycle gates, see B-F5.)

---

## Live DB findings (parent audit — merged, not duplicated)

Source: `docs/audit/LIVE_DB_FINDINGS_2026-10-01.md`. These are live-Supabase facts; the static sections below cite migration files and corroborate where noted.

- **L-1 — blocker** — `public.user_accounts` table missing entirely, but the app reads/writes it. → Create via migration + RLS; verify provider round-trip live.
- **L-2 — blocker** — `public.app_roles` has RLS enabled with **zero policies** (deny-all). → Add policies; verify live.
- **L-3 — blocker** — finance doc-number triggers missing live. → Re-apply corrected per-table triggers live. (Corroborates B-F1: the definition itself is buggy — fix the SQL first.)
- **L-4 — blocker** — migration tracking out of sync: 025/026 applied but unrecorded. → Reconcile ledger before further migrations.
- **L-5 — blocker** — migration 024 (tenant logos) not applied to live Supabase; needs explicit user approval. → Apply only with approval **plus** the B-F2 UPDATE-policy fix, otherwise the feature stays broken.

Cross-check notes:
- Static audit confirms `user_accounts`/`app_roles` are queried/written by `lib/providers/user_management_provider.dart` but created by **no** migration (B-F6) — the tables were never defined in the repo, so this is a missing-migration bug, not just a missed apply.
- Static audit found `tenants` has no UPDATE policy for tenant members (B-F2): applying 024 alone does **not** unblock logo upload. Both must ship together.

---

## Backend findings (static: `supabase/`, data layer)

### Blockers
- `supabase/migrations/014_finance.sql` / invoices, payments, income — **blocker** — shared BEFORE INSERT trigger `finance_fill_doc_numbers()` references `NEW.invoice_number` and `NEW.receipt_number` across three tables with different columns; intermittent 42703 on pooled connections breaks ALL finance inserts. Migration 025 only adds columns; the seed works around it by drop/re-create. → **Fix:** split into per-table trigger functions, each referencing only columns that exist on its table; add pooled-connection insert regression test. (Corroborates L-3.)

### Majors
- `supabase/migrations/024_tenant_logos.sql` / tenants — **major** — migration header claims existing tenant-member policies allow members to read their tenant row and `settings.update` holders to update it, but `public.tenants` has NO UPDATE policy for tenant members (only 001 `"platform admins manage tenants"` FOR ALL + 004 `"members read own tenants"` FOR SELECT). `lib/services/tenant_logo_service.dart:85,108,142` (`update({'logo_url': …})`, `update({'logo_url': null})`, `update({'use_logo_on_reports': …})`) are RLS-denied for non-platform tenant admins. → **Fix:** add `tenants_member_update` policy gated on `tenant_has_permission(tenant_id,'settings.update')`; ship together with 024.
- `supabase/migrations/007_tenant_rls.sql:828-835` / madrasas — **major** — `madrasas_member_select` USING only checks the caller is an active member of *any* tenant: any member can SELECT every row of the legacy `madrasas` table (still read by master-admin screens). → **Fix:** scope USING to the member's own tenant(s).
- `supabase/migrations/007_tenant_rls.sql:466-470` / fees — **major** — `fees_delete_tenant` DELETE policy checks `tenant_has_permission(fees.tenant_id, 'fees.collect')` instead of `'fees.delete'`; fee deletes are gated by the wrong permission code. → **Fix:** change to `'fees.delete'`.
- `supabase/migrations/016_sync.sql` / sync_apply — **major** — SECURITY DEFINER RPC checks only `is_platform_admin() OR is_tenant_member(tenant)`; any active member can insert/update/soft-delete across all 26 whitelisted tables with no fine-grained permission-code check and no status-transition validation — including writing `status='posted'` directly on finance tables, bypassing 014's status-lifecycle RLS gates. `finance_immutable_guard()` only guards already-final rows. → **Fix:** add per-table permission-code checks and validate status transitions server-side.
- `lib/providers/user_management_provider.dart` / user_accounts, app_roles — **major** — reads AND writes tables that **no migration creates**; `deleteAccount` deletes the real Auth user via `manage-users` then fails on the missing-table delete; optimistic local state never persists server-side (legacy path duplicating new RBAC). → **Fix:** create the tables via migration with RLS (see L-1/L-2); retire the legacy path or wire it to the real tables.
- `supabase/migrations/024_tenant_logos.sql` / tenant-logos bucket — **major** — not applied live (needs explicit approval); app reads `logo_url`/`use_logo_on_reports` and uploads to the bucket. → **Fix:** apply with user approval + B-F2 UPDATE policy. (Corroborates L-5.)

### Minors
- `supabase/migrations/016_sync.sql` / sync_apply — **minor** — update-branch writable-column exclusion omits `updated_by`; payloads containing it hit the audit stamp's extra `, updated_by = $3` → duplicate-SET SQL error. → **Fix:** add `updated_by` to the exclusion list.
- `supabase/migrations/001_tenant_core.sql` / schema_migrations — **minor** — RLS never enabled on the migration ledger (read-only version table; convention gap). → **Fix:** enable RLS with read-only policies.
- `supabase/migrations/018_devices.sql` / platform_config — **minor** — SELECT policy `USING (true)` exposes all rows publicly (documented pre-login update-check intent). → **Fix:** verify no sensitive values stored there.
- `supabase/migrations/018_devices.sql` / devices, device_sessions — **minor** — revocation enforcement is advisory only (auth hook / check-session edge function not wired). → **Fix:** wire the hook or document as accepted risk.
- `supabase/migrations/019_role_ux.sql`, `020_role_ux_rls.sql` — **minor** — `is_tenant_admin()`, `user_is_tenant_admin()`, `protect_last_owner()` keyed on literal `'tenant_owner'`/`'tenant_admin'` while 019 made the role catalog tenant-editable; deleting/renaming those keys silently disables admin gating. → **Fix:** resolve admin keys dynamically or protect them from rename/delete.
- misc — **minor** — `updated_at` without `set_updated_at` triggers: `notification_preferences`, `notification_device_tokens`, `platform_config`; `licenses`/`tenant_subscriptions` have no `updated_at` despite Phase-11 status transitions. → **Fix:** add triggers/columns.
- `supabase/migrations/022_scope_failclosed.sql` / attendance, results — **minor** — writes fail-CLOSED on `scope_allows()`; teachers holding 'classes' scope rows are denied writes with NULL `class_id` (by design — keep in runbook).
- `demo/seed_demo_madrassa.sql`, `demo/remove_demo_data.sql` — **minor** — seed drops/re-creates three production triggers (42703 workaround; a failure between DROP and CREATE leaves them missing); removal DISABLEs 8 immutability guards in-transaction (abort mid-window leaves them off); removal deletes `audit_logs` rows for the demo tenant (append-only exception). → **Fix:** wrap trigger swap in a transaction-safe pattern; document demo-only scope.
- `supabase/migrations/010_tenant_seed.sql` — **minor** — dev/staging-only seed ("NEVER RUN IN PRODUCTION"); ensure runbook excludes it.
- `demo/seed_demo_madrassa.sql` — **minor** — shared demo password `Demo@1234` hardcoded in comments for the five demo accounts. → **Fix:** move to runbook/secret, out of the repo file.

### Verified clean (backend)
- All 26 migrations read (8,638 lines); every RPC the app calls exists (`sync_apply`, `assign_tenant_role`, `set_user_permission`, `delegate_permission`, `log_audit`).
- Functions diff: 4 called functions exist; `export-tenant` exists but is uncalled (docs-only). Deploy status unverifiable statically.
- Seed pack safe apart from the two minors above.

---

## Frontend findings (`lib/`)

**Counts: 0 blocker / 2 major / 28 minor.** Verified clean: zero dead buttons (`onPressed: null`, empty callbacks, TODO-in-callback, "not implemented" snackbars); zero "coming soon"/جلد آرہا ہے/fake-data UI text; all 25 `.when(` sites and 21 Future/StreamBuilders handle loading+error+empty; no widths > 340px; dialogs maxWidth-constrained and scrollable; all `IconButton`s have tooltips; only `/master` named route; all 63 `Navigator.push` targets resolve; `ShellPageBody` restores back chevron on `canPop`; theme default is JameelNooriNastaleeq with height 2.0–2.2.

### Majors
- `lib/presentation/screens/teacher/teacher_dashboard_screen.dart:15` — **major** — dead legacy teacher dashboard imported only by dead `main_screen.dart`, AND declares `class TeacherDashboardScreen` — same class name as the live `lib/presentation/screens/dashboards/teacher_dashboard.dart:37`; a wrong import silently builds the dead dashboard. → **Fix:** delete the dead file (and the other dead shells below) to remove the name collision.
- `lib/providers/madrasa_provider.dart:97` — **major** — `update()` wraps the Supabase write in `catch (_) {}` and returns `null` (success) while optimistically updating local state: a failed write shows as succeeded with divergent state. (Reachable only via dead super-admin screens today; blocker-grade if reused.) → **Fix:** surface the error instead of swallowing; roll back optimistic state on failure.

### Minors (dead code)
- `lib/presentation/screens/parent/parent_dashboard_screen.dart:21` — dead island; only referenced by dead `parent_main_screen.dart`. → Delete.
- `lib/presentation/screens/super_admin/madrasa_management_screen.dart:21` — dead island; live console uses `madrasa_list_screen.dart`. → Delete.
- `lib/presentation/screens/super_admin/super_admin_dashboard_screen.dart:22` — dead island; only referenced by dead `super_admin_main_screen.dart`. → Delete.
- `lib/presentation/screens/main_screen.dart:17` — legacy teacher tab shell, zero references. → Delete.
- `lib/presentation/screens/admin/admin_main_screen.dart:15` — legacy admin tab shell, zero references. → Delete.
- `lib/presentation/screens/parent/parent_main_screen.dart:15` — legacy parent tab shell, zero references. → Delete.
- `lib/presentation/screens/super_admin/super_admin_main_screen.dart:15` — legacy super-admin shell, zero references. → Delete.
- `lib/core/widgets/loading_overlay.dart:6` — duplicate `LoadingOverlay`, unused (live: `lib/core/widgets/loading_widget.dart:49`). → Delete.
- `lib/presentation/widgets/common/app_widgets.dart:496` — a THIRD `LoadingOverlay`, unused. → Delete.
- `lib/core/widgets/confirm_dialog.dart:10` — `showConfirmDialog` never called (design system uses `showM360ConfirmDialog`). → Delete or re-export.
- `lib/core/widgets/custom_buttons.dart:8` — `PrimaryButton`/`SecondaryButton`/`IconButtonWidget` never used (design system `M360PrimaryButton` used). → Delete.
- `lib/providers/madrasa_provider.dart:113` — `delete()` same false-success `catch (_) {}` pattern as `update()`. → Surface errors.

### Minors (design-system / polish)
- `lib/presentation/screens/master_admin/master_admin_nav.dart:268` — Urdu 'پلیٹ فارم کنسول' at `height: 1.6`, below the repo's ≥ 2.0 Nastaleeq policy; nuqta-clipping risk. → **Fix:** raise to 2.0.
- `lib/presentation/screens/teacher/attendance_screen.dart:328` — `Text(classes.first.name)` in a `Row` with no `Flexible`/`Expanded`/`overflow`; long class names can overflow at 360px. → **Fix:** wrap in `Expanded` + ellipsis.
- `lib/presentation/widgets/common/app_widgets.dart:401` — section-header `Row`: title `Text` has no `Expanded`/ellipsis next to action button. → **Fix:** same.
- `lib/presentation/screens/crash_screen.dart:45,46,52` — hardcoded `Color(0xFF0B6E4F)`, `Color(0xFFD4AF37)`, `Color(0xFFF6F8F7)` instead of `AppColors` tokens. → **Fix:** use design tokens.
- `lib/presentation/shell/app_nav_rail.dart:30` — local `const Color _kGold = Color(0xFFC9A227)`. → **Fix:** use `AppColors` gold token.
- `lib/presentation/screens/settings/madrassa_logo_screen.dart:312` — `Color(0x52000000)` scrim literal. → **Fix:** token or shared scrim.
- `lib/providers/tenant_branding_provider.dart:75-77,102-106` — hardcoded fallback brand colors (`0xFF0E7C5B`, `0xFF14532D`, `0xFFF59E0B`) instead of `AppColors`. → **Fix:** use tokens.

### Minors (silent failures)
- `lib/data/repositories/finance_repository.dart:561,643` — best-effort notification `catch (_) {}` with no logging. → **Fix:** log via `AppLogger`.
- `lib/providers/announcement_provider.dart:129` — same pattern. → **Fix:** log via `AppLogger`.

### Minors (accessibility)
- Logo/user images without `semanticLabel`: `lib/presentation/screens/auth/login_screen.dart:213`, `lib/presentation/screens/auth/tenant_picker_screen.dart:132`, `lib/presentation/shell/app_nav_rail.dart:269,580,250`, `lib/presentation/screens/master_admin/master_admin_nav.dart:248,491`, `lib/presentation/screens/common/profile_screen.dart:320`, `lib/presentation/screens/master_admin/console_profile_screen.dart:127`, `lib/presentation/screens/settings/madrassa_logo_screen.dart:73`. → **Fix:** add `semanticLabel`s.

---

## Reports findings (`lib/core/reports/`)

**Verified clean:** all 19 generators have live triggers (no dead menu entries); product-logo fallback holds on every header path including the bare ID-card and audit-log; zero `pw.Text` with Urdu literals (scanned); header/footer consistent; empty states honest; branding pipeline tenant-scoped with no cross-tenant leak.

### Blocker
- `lib/core/reports/documents/admin_reports.dart:270` — **blocker** — `incomeExpense` `section()` wraps the income/expense `dataTable` in `pw.Column` inside a MultiPage; pdf throws "Widget won't fit into the page" instead of paginating on long lists (confirmed against vendored pdf 3.12.0 `multi_page.dart`). → **Fix:** restructure so the table is a direct spanning child of the MultiPage (no `pw.Column` wrapper).

### Minors
- `lib/core/reports/documents/admin_reports.dart:198-216` — **minor** — fee-collection "طریقے" StatBox `subEn` renders payment-method values via Latin-only `e()` (`pdf_kit.dart:511`); app method labels are Urdu (`نقد`, `بینک ٹرانسفر`, `finance.dart:119-133`), so Urdu values render as tofu (table cells correctly route via `auto()`). → **Fix:** route `subEn` through `auto()` too.
- `lib/core/reports/documents/student_documents.dart:156` — **minor** — `pw.Spacer()` is a direct child of the MultiPage build list (spacing no-op outside Flex); contact band not bottom-pinned on the CR80 card as intended. → **Fix:** move inside a `pw.Column` with `mainAxisAlignment.end` or drop it.
- `lib/core/reports/documents/student_documents.dart:117` — **minor** — ID-card brand-band madrassa name via `s.u()` with no maxWidth; long institution names overflow the 226pt card width. → **Fix:** constrain width / wrap.
- `lib/core/reports/documents/student_documents.dart:320` — **minor** — ID-card `_idLine` values via `s.auto()` with no maxWidth; long names can overflow CR80 width. → **Fix:** constrain + ellipsis.
- `lib/core/reports/documents/student_documents.dart:173` — **minor** — ID-card contact line assumes Latin-only phone/email (`replaceAll('فون: ', 'Ph: ')` then `s.e()`); Urdu-digit phone numbers render as tofu. → **Fix:** route through `auto()`.
- `lib/core/reports/documents/student_reports.dart:132-166` — **minor** — attendance report has no signature block (certificates/result cards/fee receipt have `signatureRow`). → **Fix:** add `signatureRow`.
- `lib/core/reports/documents/student_reports.dart:190-261` — **minor** — fee statement has no signature block. → **Fix:** add `signatureRow`.
- `lib/core/reports/documents/admin_reports.dart` — **minor** — none of the 8 admin tabular reports include a signature/verification block. → **Fix:** add `signatureRow` to each.
- `lib/core/reports/documents/result_documents.dart:35-58` — **minor** — `resultCard` renders headers-only table when `result.subjects` is empty, no `emptyNotice` (sibling `resultsSummary` has one). → **Fix:** add `emptyNotice`.

---

## Suggested fix sequencing

1. **Live DB blockers first** (need user/operator): create `user_accounts` + `app_roles` policies (L-1, L-2); reconcile migration ledger (L-4); re-apply corrected per-table finance triggers (L-3 + B-F1); apply 024 + tenants UPDATE policy with explicit approval (L-5 + B-F2).
2. **Code blockers/majors on the branch**: fix finance trigger definitions (B-F1); fix reports MultiPage crash (R blocker); scope `madrasas_member_select` to own tenant (B-F3); fix `fees.delete` permission gate (B-F4); harden `sync_apply` (B-F5); wire `user_management_provider` to real tables (B-F6); delete dead screens/widgets incl. the `TeacherDashboardScreen` name collision (FE majors); fix `madrasa_provider` false-success (FE major).
3. **Minors sweep**: signature blocks on reports, Urdu `auto()` routing, ID-card width constraints, Nastaleeq line-height, design-token colors, `semanticLabel`s, `AppLogger` on silent catches, demo SQL hygiene, `sync_apply` `updated_by` exclusion.
4. **Then**: full CI, then Windows + Android builds from the pinned green commit, then visual confirmation on real devices.
