# Production Readiness — Madrasa 360

**Verdict: NOT production-ready.** The app is a functional single-institution prototype with live Critical/High security findings. Every §60 checklist item is marked below with one-line evidence. Full detail lives in the five sibling audit docs.

## Overall readiness scorecard

| Dimension | Rating | One-line basis |
|---|---|---|
| Security | 🔴 1/10 | Committed service-role key + client-side service-role use + live privilege escalation (`SECURITY_AUDIT.md`, `DATABASE_AUDIT.md §8`) |
| Tenant isolation | 🟡 3/10 | Architecture + RLS written (001–010, fail-loud stale-policy guard) but unapplied; 0 `tenant_id` enforcement live until staging run |
| Auth & sessions | 🔴 3/10 | Real Supabase Auth, but fake logout, no restore redirect, plaintext demo creds, plaintext session storage |
| Data layer | 🟡 4/10 | Real repos + adequate indexes, but no migrations ledger, drift-masking idempotency, finance too flat |
| Offline/sync | 🔴 1/10 | No local DB; SharedPreferences caches; sync queue dead — Phase 5 (`feature/offline-sync`, unpushed): Drift-backed engine + local-first repos + offline-capable attendance screen are code-complete, pending staging run; stays red until a staging sync is observed end-to-end |
| UI/UX | 🟡 5/10 | B-grade admin dashboards (demo data), D-grade parent/teacher, no desktop shell, portrait locked |
| Build/release | 🔴 2/10 | No CI, debug-signed Android, no Windows installer, no signing |
| Testing | 🟡 2/10 | Isolation suite written (30 assertions, parse-validated) but never executed; one fragile smoke test; zero unit tests |
| Docs | 🟡 4/10 | Existing docs misrepresent the app; this audit set is the new baseline |

---

## Mission §60 security checklist — pass/fail

| # | Checklist item | Verdict | Evidence (one line) |
|---|---|---|---|
| 1 | No service-role keys in client | ❌ FAIL | `user_management_provider.dart:129,240` calls Auth Admin API with `SUPABASE_SERVICE_KEY` from bundled `assets/.env` |
| 2 | No secrets committed | ❌ FAIL | Live anon + service-role keys in `SUPABASE_INTEGRATION_PLAN.md:105,107`; `crypt('***REDACTED-PASSWORD-ROTATED-2026-09-25***'…)` in `05_new_modules.sql:354` (commented) |
| 3 | Tenant RLS complete | 🟡 WRITTEN (unapplied) | `007_tenant_rls.sql` (Phase 2): 81 legacy policies dropped by verified name, tenant+permission policies on all 13 tables + `profiles` lockdown, fail-loud stale-policy guard — parse-validated, NOT yet applied to any DB. Phase 4 adds `015_parent_links.sql`: `student_guardians` + `teacher_class_assignments` link tables with the same policy template (self-SELECT for linked users, tenant-admin management) — also parse-validated, also unapplied |
| 4 | Cross-tenant tests pass | 🟡 WRITTEN (unexecuted) | `supabase/tests/cross_tenant_isolation.sql` (Phase 2): 30 assertions, Tenant A/B × Admin/Teacher matrix + escalation + storage + stale-policy guard — parse-validated, never executed (no staging DB) |
| 5 | Storage policies isolated | 🟡 WRITTEN (unapplied) | `008_tenant_storage.sql` (Phase 2): `{tenant_id}/` prefixes + membership-checked policies on all 3 buckets, 13 legacy policies dropped — parse-validated, not applied |
| 6 | Realtime isolated | 🟡 WRITTEN (unapplied) | Realtime inherits table RLS; tenant boundary arrives with 007 once applied; `security_invoker` set on the two views |
| 7 | Auth hardened | 🟡 DB-LAYER CODE-COMPLETE (Dart pending) | Profiles escalation closed in DB: 007 `profiles_lock_role()` trigger + 013 drops `user_roles`/`get_user_role()`/`get_my_role()`; platform guard = `platform_admins` + self-read policy (011). Dart side still red: fake logout, demo creds, plaintext sessions (Worker 2) |
| 8 | Password reset works | ❌ FAIL | Flow not verified end-to-end; demo-credential mock still ships — cannot pass |
| 9 | Session management works | ❌ FAIL | Logout doesn't call `signOut()`; no restored-session redirect (`main.dart` always → Login); no secure storage |
| 10 | Audit logs work | 🟡 CODE-COMPLETE (pending staging run) | `012_audit_logs.sql`: `audit_logs` table (tenant + platform events), append-only (no client write policies), `log_audit()` SECURITY DEFINER RPC, tenant-admin/platform-admin SELECT policies — parse-validated, NOT applied/executed |
| 11 | Privileged APIs protected | 🟡 CONTRACT CODE-COMPLETE (Dart pending) | Guard contract written: `is_platform_admin()`, RLS on all platform tables, service-role Edge Function pattern for provisioning (no UI can self-elevate). `user_management_provider.dart:129,240` still calls Auth Admin with bundled service key — still blocks |
| 12 | File upload validated | ❌ FAIL | `uploadPhoto` builds storage path from filename extension; allow-list/size limits exist in `AppConfig` but are never enforced (`student_provider.dart:89-107`) |
| 13 | Input validation implemented | ❌ FAIL | Upload path unvalidated; no systematic input-validation audit passed — cannot certify |
| 14 | SQL injection protections verified | ✅ PASS | No raw SQL in Dart; all DB access via parameterized PostgREST client (verified in `SECURITY_AUDIT.md §7`) |
| 15 | Error messages safe | ✅ PASS | `ErrorHandler` maps errors to user-safe Urdu messages (`error_handler.dart:8-28`); no raw stack traces to users |
| 16 | Sensitive logs removed | ❌ FAIL | `avoid_print` lint disabled (`analysis_options.yaml:20-24`); `logError` = `debugPrint` + Crashlytics TODO; no enforced log hygiene |

**Score: 2/16 pass, 4 items code-complete pending staging execution** (items 3–6: migrations + isolation suite written and parse-validated 2026-09-25, never applied/executed). Both passes are narrow technical facts, not endorsements — item 15's safety collapses the moment secrets sit client-side (item 1).

> **Phase 2 update (2026-09-25, branch `feature/tenant-architecture`, unpushed):** tenant data architecture is implemented as ordered idempotent migrations `001`–`010` + `TenantContext` in Dart + 30-assertion isolation suite. The P0 items 4–6 in "stop the bleeding" (profiles escalation, stale-policy drops, PII leaks) are addressed **in code** by 007/008 — they become actually fixed only when the migrations run on staging and the tests go green. Key rotation (P0 items 1–3) is still entirely outstanding and still blocks everything.

> **Phase 3 update (2026-09-25, branch `feature/master-admin`, unpushed, Worker 4):** migrations `011_licensing` (license_plans/licenses/tenant_subscriptions + 3 editable seed plans + `platform_admins_self_read` policy), `012_audit_logs` (append-only `audit_logs` + `log_audit()` RPC), `013_auth_cleanup` (drops legacy `user_roles` + 2 policies + `get_user_role()`/`get_my_role()` by verified name; rewrites `get_my_permissions()` without the `user_roles` branch; single-arg `has_permission()` proven non-existent and NOT dropped) — all pglast parse-validated, every DROP name script-verified against the source files. §60 items 7/10/11 move to "code-complete, pending staging run" — **nothing is marked pass**: the migrations have never been applied to any database, Edge Functions (Worker 1) and Dart auth rewrites (Worker 2) are still in flight, and key rotation (P0 items 1–3) remains the hard blocker.

> **Phase 4 update (2026-09-25, branch `feature/phase4-portals`, unpushed):** migration `015_parent_links.sql` (`student_guardians` + `teacher_class_assignments` + link-scoped RLS, pglast parse-validated); two new tenant-scoped portal providers (`parent_portal_provider.dart`, `teacher_portal_provider.dart`) that bail out on null tenant and filter every query by `tenant_id` + link table; parent dashboard/fee-history and teacher dashboard/results screens rewired to the scoped providers (hardcoded class lists and the global fee list removed from the portals). **No §60 verdict changes**: 015 is written-not-applied like the rest; item 3's evidence is extended, not its verdict. No Dart compilation was possible in this environment (no Flutter toolchain) — the code is balance-checked only. Deferred to Phase 5: teacher attendance screen still runs on its local mock stack (now has scoped providers to consume), parent activity timeline + upcoming-exams sections still static, module-gating is client-UX-only (RLS does not consult `tenant_modules`).

> **Phase 5 — offline sync update (2026-09-25, branch `feature/offline-sync`, unpushed, Worker 4):** teacher attendance screen rewritten off the mock stack onto the tenant-scoped repository path (`classAttendanceProvider` + `attendanceRecordNotifierProvider`, classes from `teacherAssignedClassesProvider`); `AttendanceStatus.late` added for late arrivals (`attendance_status.dart`, `attendance_record.dart`, legacy tile switches updated); `docs/OFFLINE_SYNC.md` added (architecture diagram, queue schema, push/pull loops, conflict rules — normal: latest valid revision wins; financial: never overwrite → `sync_conflicts` → manual review; retry: exponential backoff, 5 attempts → `dead_letter`; crash-safety: transactional enqueue + `in_progress` reclaim; per-tenant engine; logout/tenant-switch behavior; offline test checklist). **No §60 verdict changes — score stays 2/16, nothing marked pass**: the sync engine (`lib/core/sync/`, incl. `pendingSyncCountProvider`) and the local-first repository conversions are sibling-worker code still in flight, nothing has run on staging, and P0 key rotation still blocks everything. The `Offline/sync` scorecard dimension is now "code-complete, pending staging run" — still red until a staging sync is observed. No Dart compilation was possible in this environment (no Flutter toolchain) — new/edited Dart files are delimiter-balance-checked only. Open reconciliations for the coordinator: `lib/core/sync/sync_providers.dart` landed mid-task (sibling worker) and was verified — `pendingSyncCountProvider` is a `StreamProvider<int>` scoped to the active tenant (counts `pending`+`in_progress`+`failed`, excludes `dead_letter`), which the screen's defensive read handles; `OfflineSyncService._parseStatus` and `SupabaseAttendanceRepository._parseStatus` still map `'late'` → `present` and need the sync sibling to handle the new status.

---

## Release blockers (must clear before ANY production claim)

**P0 — rotate & scrub (today):**
1. Rotate the Supabase anon key AND service-role key (both committed verbatim in `SUPABASE_INTEGRATION_PLAN.md:105,107`), then purge from git history (`git filter-repo`) — delete-commit is not enough.
2. Delete `crypt('***REDACTED-PASSWORD-ROTATED-2026-09-25***'…)` block from `05_new_modules.sql:353-354`.
3. Remove service-role usage from the client (`user_management_provider.dart:129,240`) → Edge Function.

**P0 — stop the bleeding (before Phase 2 builds on this DB):**
4. Fix the `profiles` privilege escalation: drop 02 policies by exact name (`profiles_update_own`, `profiles_insert_own`, …), keep `WITH CHECK` versions, remove client-writable `role`.
5. Drop all stale 02/05 policies by their **real** names (06's DROPs were no-ops) before any new policy set goes live.
6. Close PII leaks: all-authenticated photo reads, `salary`/`cnic` to teachers/parents, world-readable `profiles`.

**P1 — make the app honest:**
7. Fix fake logout; add session-restore redirect; delete dead mock `auth_service.dart` and its demo credentials.
8. Rewire `AttendanceScreen` to the real provider stack; delete the mock attendance stack.
9. Replace all dashboard demo data (`todayPresent: 142`, fake activity/fees) with provider data; fix the `Placeholder()` module tile.

**P1 — release engineering:**
10. Stand up CI (analyze with lints re-enabled, format, tests, Windows + Android builds) — currently no `.github/` at all.
11. Android: real release signing (currently debug key), monotonic `versionCode`, camera/media permissions for `image_picker`.
12. Windows: Inno Setup installer, Authenticode signing, `Runner.rc` branding, auto-update check.

---

## What "production ready" requires (mission §74, in order)

`Architecture` (tenant model + RLS rewrite) → `Security` (secrets rotated, escalation closed, uploads validated) → `Tenant isolation` (cross-tenant tests green in CI) → `Authentication` (real logout/sessions/reset) → `Authorization` (single permission system, tenant-bound) → `Offline support` (Drift) → `Sync` (queue + conflicts) → `Backups` (tenant export) → `Auditability` (`audit_logs` + financial immutability) → `Testing` (unit/widget/integration/security) → `Performance` (pagination, query audits) → `Deployment` (dev/staging/prod, migrations ledger) → `Updates` (forced-upgrade path) → `Documentation` (§62 set).

Until every §60 item above reads ✅, the project must not be described as production-ready to anyone — including in the README.

> **Phase 6 — reporting/notifications/backup/mock-purge update (2026-09-25, branch `feature/reporting-notifications`, unpushed):** offline-first reporting engine (15 tenant-branded PDF reports from local Drift, Urdu via engine-shaped raster — see `docs/REPORTING.md` §3, CSV/XLSX export, reports hub; `pdf`/`printing`/`excel` pinned to Dart-3.5-compatible lines); notifications framework (`017_notifications.sql` pglast parse-validated 21 statements, channel interface + in-app/push/email channels, offline outbox, per-user preferences, 4 of 5 triggers wired — result-published unwired: no publish flow exists yet); one-file offline tenant backup (`_backup_manifest` inside the .db, SHA-256, verify-before-restore, typed-`RESTORE` confirmation, server-side `export-tenant` function; `docs/BACKUP_RESTORE.md`); mock-data purge (dead mock auth/model/widget/provider code deleted, live fakes rewired to real data with empty states, `tool/no_mock_check.dart` CI guard passing on 139 files, dev-only `010_tenant_seed.sql` proven unreferenced from Dart and excluded from the runbook glob); notifications inbox screen + admin dashboard cards (Reports/Backup/Notifications) wired. **No §60 verdict changes — score stays 2/16, nothing marked pass**: no Dart compilation possible here (no Flutter toolchain; drift codegen `app_database.g.dart` not regenerated), migrations 001–017 unapplied, isolation suite unexecuted, P0 key rotation still user-blocked.
