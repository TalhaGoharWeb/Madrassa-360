# Production Readiness — Madrasa 360

**Verdict: NOT production-ready.** The app is a functional single-institution prototype with live Critical/High security findings. Every §60 checklist item is marked below with one-line evidence. Full detail lives in the five sibling audit docs.

## Overall readiness scorecard

| Dimension | Rating | One-line basis |
|---|---|---|
| Security | 🔴 1/10 | Committed service-role key + client-side service-role use + live privilege escalation (`SECURITY_AUDIT.md`, `DATABASE_AUDIT.md §8`) |
| Tenant isolation | 🔴 0/10 | 0 `tenant_id` in Dart; 0 policies filter by tenant; any permission-holder reads all institutions |
| Auth & sessions | 🔴 3/10 | Real Supabase Auth, but fake logout, no restore redirect, plaintext demo creds, plaintext session storage |
| Data layer | 🟡 4/10 | Real repos + adequate indexes, but no migrations ledger, drift-masking idempotency, finance too flat |
| Offline/sync | 🔴 1/10 | No local DB; SharedPreferences caches; sync queue dead |
| UI/UX | 🟡 5/10 | B-grade admin dashboards (demo data), D-grade parent/teacher, no desktop shell, portrait locked |
| Build/release | 🔴 2/10 | No CI, debug-signed Android, no Windows installer, no signing |
| Testing | 🔴 1/10 | One fragile smoke test; zero security/cross-tenant tests |
| Docs | 🟡 4/10 | Existing docs misrepresent the app; this audit set is the new baseline |

---

## Mission §60 security checklist — pass/fail

| # | Checklist item | Verdict | Evidence (one line) |
|---|---|---|---|
| 1 | No service-role keys in client | ❌ FAIL | `user_management_provider.dart:129,240` calls Auth Admin API with `SUPABASE_SERVICE_KEY` from bundled `assets/.env` |
| 2 | No secrets committed | ❌ FAIL | Live anon + service-role keys in `SUPABASE_INTEGRATION_PLAN.md:105,107`; `crypt('***REDACTED-PASSWORD-ROTATED-2026-09-25***'…)` in `05_new_modules.sql:354` (commented) |
| 3 | Tenant RLS complete | ❌ FAIL | Zero policies filter by tenant; `get_current_tenant_id()` doesn't exist; 13/19 tables lack even `madrasa_id` |
| 4 | Cross-tenant tests pass | ❌ FAIL | No isolation exists to test; `test/` has one smoke test only |
| 5 | Storage policies isolated | ❌ FAIL | All-authenticated reads on `student-photos`/`staff-photos` (`03:38,86`) and `documents` (`03:118`); no tenant prefixes |
| 6 | Realtime isolated | ❌ FAIL | Realtime inherits table RLS, which has no tenant boundary; no per-tenant scoping verified |
| 7 | Auth hardened | ❌ FAIL | Fake logout (`profile_screen.dart:532-539`), plaintext `admin123/teacher123/parent123` in `auth_service.dart:61-81`, sessions in plaintext SharedPreferences, role escalation live |
| 8 | Password reset works | ❌ FAIL | Flow not verified end-to-end; demo-credential mock still ships — cannot pass |
| 9 | Session management works | ❌ FAIL | Logout doesn't call `signOut()`; no restored-session redirect (`main.dart` always → Login); no secure storage |
| 10 | Audit logs work | ❌ FAIL | No `audit_logs` table; no audit trail on auth, fees, or role changes |
| 11 | Privileged APIs protected | ❌ FAIL | Supabase Admin Auth called directly from the app — any decompiled APK yields auth-admin power |
| 12 | File upload validated | ❌ FAIL | `uploadPhoto` builds storage path from filename extension; allow-list/size limits exist in `AppConfig` but are never enforced (`student_provider.dart:89-107`) |
| 13 | Input validation implemented | ❌ FAIL | Upload path unvalidated; no systematic input-validation audit passed — cannot certify |
| 14 | SQL injection protections verified | ✅ PASS | No raw SQL in Dart; all DB access via parameterized PostgREST client (verified in `SECURITY_AUDIT.md §7`) |
| 15 | Error messages safe | ✅ PASS | `ErrorHandler` maps errors to user-safe Urdu messages (`error_handler.dart:8-28`); no raw stack traces to users |
| 16 | Sensitive logs removed | ❌ FAIL | `avoid_print` lint disabled (`analysis_options.yaml:20-24`); `logError` = `debugPrint` + Crashlytics TODO; no enforced log hygiene |

**Score: 2/16 pass.** Both passes are narrow technical facts, not endorsements — item 15's safety collapses the moment secrets sit client-side (item 1).

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
