# SaaS Gap Analysis — Madrasa 360 → Multi-Tenant Platform

**Scope:** MASTER MISSION §§4–74 mapped to the current repo state, verified against code (2026-09-25).
**Inputs:** `ARCHITECTURE_AUDIT.md`, `DATABASE_AUDIT.md`, `SECURITY_AUDIT.md`, `UI_UX_AUDIT.md`, `DEPENDENCIES_AUDIT.md`.
**Legend:** ✅ Exists & adequate · ⚠️ Partial (extendable) · 🔴 Must replace · ❌ Missing · ⛔ SaaS blocker

## Executive summary

1. **Multi-tenancy is 0% implemented, not 10%.** `tenant_id` occurs 0× in Dart (`ARCHITECTURE_AUDIT.md §8`); no `tenants` table, no `get_current_tenant_id()` (`DATABASE_AUDIT.md §2`); `madrasas` exists but 13/19 tables lack `madrasa_id` and **zero** RLS policies filter by it. Any permission-holder sees all institutions' rows.
2. **Security must be fixed before anything else is built on top.** Committed service_role + anon keys, service_role used from the client, a live privilege-escalation path (`profiles_update_own` w/o `WITH CHECK`), and permissive stale policies OR-stacked under the new ones — see `SECURITY_AUDIT.md` Top-10 and `DATABASE_AUDIT.md §8`.
3. **The skeleton is not empty.** Real Supabase Auth, real Riverpod repos for students/attendance/fees/exams, seeded permission codes (57) + roles (16) in `06_rbac.sql`, Jameel Noori Nastaleeq wired through the theme, `madrasas` as a tenant-shaped placeholder. These survive the rebuild; most of the Dart permission plumbing does not.
4. **The largest "partial" areas are one honest fix away from working:** attendance UI wired to a dead mock (`attendance_screen.dart:18-237` vs real `attendanceRecordNotifierProvider`), fake logout (`profile_screen.dart:532-539`), and demo data in dashboards (`todayPresent: 142`).
5. **Everything operational is missing:** no migrations ledger, no CI, no Windows installer, no offline DB/sync, no provisioning flow, no licensing tables, no reporting engine, ~zero tests. §§60/74 acceptance is nowhere near passing today.

---

## §4 Core architectural transformation (single → multi-tenant)

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| One app, N isolated tenants | ⛔ ❌ | 0 `tenant_id` in Dart; `madrasas` table only; unscoped repos | 🔴 Design tenant layer (§§5–8) then migrate |
| Master Admin vs Customer platform split | ❌ | `super_admin` screens exist as a shell; no tenant management | 🔴 Rebuild per §§10–11 |
| Supabase+Postgres+RLS foundation | ⚠️ | Real Supabase client, RLS enabled on tables — but policies role-only, stale ones stacked | 🔴 Rewrite policies per §§15–16 |

## §§5–8 Tenant model, settings, modules, memberships

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| `tenants` table (id, code, name, name_urdu, slug, logo, address…, status trial/active/suspended/expired/cancelled/archived) | ❌ | No `tenants` table. `madrasas` (`05_new_modules.sql:49`) is tenant-adjacent: `admin_user_id`, `subscription_plan` basic/standard/premium — franchise branches, not SaaS tenants | Replace with `tenants` + migrate `madrasas` rows in |
| `tenant_settings` (language, timezone, currency, theme, colors, receipt header/footer…) | ❌ | Nothing. `MadrassaConfig` (`lib/core/config/madrassa_config.dart`) is a hard-coded runtime constant ("Khawaja Educational System / Qili Piranwali") | Build; `MadrassaConfig` becomes tenant-driven |
| `tenant_modules` (students/staff/attendance/exams/fees/library/hostel…) per-tenant flags | ❌ | 57 permission codes in `permissions` table (`06_rbac.sql:77`) — permissions ≠ modules; no per-tenant enablement | Build; UI must read enabled-modules |
| `profiles` + `tenant_memberships(user_id, tenant_id, role, is_active)` | 🔴 | `profiles` exists but has **no tenant/madrasa column**; app reads `profile['madrasa_id']` which was never created (`auth_repository.dart:93`); `user_roles.madrasa_id` nullable (NULL = global) | 🔴 Add memberships; remove client-writable `role` from `profiles` (escalation path, §16) |
| One user, many tenants (e.g. admin@A, teacher@B) | ❌ | `UNIQUE(user_id, role_id, madrasa_id)` exists but scoping is decorative (NULL-wildcard in `get_my_permissions`, `06:506`) | Redesign per §16 |

## §9 Role system (permission-level, not just names)

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Base roles platform_owner → student | ⚠️ | 16 system roles seeded in `roles` (`06:94`, scope platform/madrasa/external) — good raw material | Keep table, re-scope to tenant |
| Permission-level auth (`students.view`, `fees.collect`…) | ⚠️ | 57 codes seeded (`06:77`); Dart has **two** competing systems: `AppPermissions` string codes vs `Permission` enum + `allSystemRoles` | 🔴 Collapse to one; bind every check to tenant |
| Enforcement in DB, not UI | ⛔ | Policies check permissions globally, never per-tenant; Dart-side `AppPermissions` checks are UI decoration | Rewrite policies §16 |

## §§10–12 Master Admin + provisioning

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Private Master Admin (Dashboard, Madrasas, Users, Plans, Licenses, Modules, Audit Logs, Health, Support) | ❌ | `lib/presentation/screens/super_admin/` exists (shell + static dashboard); no tenant CRUD, no plans/licenses UI | 🔴 Rebuild as real Master Admin |
| Master dashboard KPIs + system health | ❌ | Static numbers; no health checks | Build |
| **Create Madrasa wizard → tenant + settings + modules + subscription + admin user + membership + license + audit event, no manual SQL** | ❌ | Provisioning = hand-run SQL in editor (`DATABASE_AUDIT.md §7`) | Build §12 flow; Edge Function for privileged steps (service-role stays server-side) |

## §13 Customer admin

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Per-tenant admin dashboard (students, teachers, attendance, fees, exams, reports…) | ⚠️ | Admin screens exist and are provider-backed (B-grade, `UI_UX_AUDIT.md §2`) but ship hard-coded demo data (`todayPresent: 142`, fake activity feed) and query **unscoped** repos | Fix data wiring + scope; then tenant-gate modules |
| Name/logo from tenant config | 🔴 | Name comes from `MadrassaConfig` constant; **no logo mechanism** (`assets/images/` missing, `AppConfig.logoImage` dangles); colors hard-coded consts; "Developed by HijaziApps" hard-coded in login/about | Dynamic tenant branding per §37 |

## §14 Remove hard-coded institution identity

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| No "Al Markaz"/"Kasur"/phones/addresses in app logic | ⛔ | **Split identity:** runtime = "Khawaja Educational System / Qili Piranwali" (`madrassa_config.dart`), package/Android/iOS/docs/test still "Al Markaz Al Islami Kasur / `al_markaz_al_islami`"; About screen shows real developer PII (`goharenaqshband@gmail.com`, `03287819000`) | Sweep per `SECURITY_AUDIT.md §2` identity table; seed demo tenant, not source identity |

## §§15–16 Tenant isolation + RLS (CRITICAL)

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| `tenant_id` on every business table + FK + indexes | ❌ | 0 in Dart; 6/19 tables have `madrasa_id` (nullable); FKs are real where present | Migration `004_tenant_columns` (`DATABASE_AUDIT.md §9`) |
| `get_current_tenant_id()` server-trusted; `tenant_id = get_current_tenant_id()` on every policy | ❌ | Function doesn't exist; policies key on JWT role or `profiles.role` | Build SECURITY DEFINER fn on `tenant_memberships` |
| Never trust client-supplied tenant; no Flutter-side filtering as security | ⛔ | Client `if (madrasaId != null)` filters are the only "scoping" anywhere | 🔴 Server-enforced RLS; client filters become UX only |
| Fix live escalation: `profiles` role writable by any user | ⛔ | `profiles_update_own` (02:48) no `WITH CHECK`; `profiles_insert_own` (02:62) id-only; 06's DROPs targeted names that never existed so stale policies still live and OR-stack | Drop by exact 02 names; move role to memberships |

## §§17, 55–56, 60 Cross-tenant + security tests

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Automated: A can't SELECT/UPDATE/DELETE B's rows; storage/realtime/reports isolation; role-escalation attempts fail | ❌ | 1 test file (`test/widget_test.dart`, 30-line smoke); zero DB/RLS/security tests; no pgTAP | Build per §17 scenario (Tenant A/B × Admin/Teacher × Student A/B) in CI |

## §18 Service-role security

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Never in client/APK/repo; privileged ops in Edge Functions | ⛔ | Service-role key **committed** (`SUPABASE_INTEGRATION_PLAN.md:107`) and **used from client** (`user_management_provider.dart:129,240` → Auth Admin API from bundled `.env`) | Rotate keys, purge history, move to Edge Functions |

## §19 Authentication

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Email/password, reset, persistence, expiry, logout, recovery — real Supabase Auth, no mocks | ⚠️ | Real Supabase Auth + role resolution via `get_my_permissions()` RPC (`auth_repository.dart`) — but: **logout is fake** (`profile_screen.dart:532-539` navigates w/o `signOut`), no session-restore redirect (`main.dart` always → `LoginScreen`), plaintext demo creds `admin123/teacher123/parent123` still in dead `auth_service.dart:61-81`, sessions in plaintext SharedPreferences | Fix logout/redirect; delete mock auth; flutter_secure_storage; password-reset flow E2E |

## §§20–23 Offline-first + sync + conflicts

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| SQLite/Drift local DB (not SharedPreferences) for students/classes/attendance/fees/exams/results/settings | ❌ | No Drift/SQLite; "offline" = SharedPreferences JSON caches read only in 2 repos' `catch` blocks; `AppConfig.cacheExpiryDays=7` never enforced | Build |
| Sync engine: UI → Repository → SQLite → Sync Queue → Supabase; `sync_queue` table with operation/entity/payload/status/retry | ❌ | `OfflineSyncService` exists but `init()` gets no repo (flush dead); queue written only by a notifier no screen calls | 🔴 Rebuild wiring |
| Create/Update/Delete/Retry/offline queue/auto-sync/conflict handling; `revision/updated_at` deterministic resolution; financial records never silently overwritten | ❌ | None | Build per §§22–23 |

## §§24–28 Students, academics, attendance, exams, fees/finance

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §24 Student management (configurable fields, admission/roll, documents, status) | ⚠️ | Real `students` repo/model/screens; unscoped; per-tenant field config absent | Scope + configurability |
| §25 Configurable academic hierarchy (Program → Darja → Class → Section → Subjects; Hifz/Nazra/Dars-e-Nizami/custom) | ⚠️ | `darjas`/`classes`/`darja_sections` exist; **duplicate legacy columns** (`name` vs `name_urdu`, `announcements.target_role` vs `target`) from 05 rebuild; no per-tenant program config | Consolidate schema; add tenant program config |
| §26 Fast attendance (bulk, leave/late, history, %, teacher attendance), offline-capable | 🔴 | Real provider stack exists but **UI is wired to the dead mock** — `saveAttendance()` = `delay(1s)` + `print`; marking attendance is a no-op | Rewire to `attendanceRecordNotifierProvider`; delete mock |
| §27 Configurable exams, grading systems per tenant, result publication | ⚠️ | `exams`/`results` tables + screens exist; unscoped; no per-tenant grading config | Scope + grading config |
| §28 Proper finance entities (fee_structures, invoices, payments, allocations, refunds, discounts, expenses, ledger) | 🔴 | `fees` = flat per-student-per-month row (generated `status`); `finance_transactions` flat; no invoices/payments/ledger | 🔴 Rebuild finance per §28 |

## §§29–30 Financial audit + audit logs

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Immutable financial trail (`created_by/approved_by`, no silent edits) | ❌ | Nothing; 06 adds view/create/delete on `finance_transactions` but UPDATE silently denied (inconsistent) | Build ledger semantics |
| `audit_logs(tenant_id, user_id, action, entity, old_data, new_data, …)` for logins, CRUD, fee collection, role changes | ❌ | No `audit_logs` table | Build + wire to provisioning/auth/fee flows |

## §31 Reporting engine

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| PDF/Excel/CSV/Print reports (admission form, ID card, result card, registers, fee statements…) with tenant name/logo/address | ❌ | No reporting code; **no pdf/excel deps** in `pubspec.yaml`; README claims fee-slip generation (docs-vs-reality) | Build |

## §§32–33 Parent / teacher portals

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Parent sees only own children (attendance, results, fees, announcements…) — RLS-enforced | 🔴 | Parent dashboard is a **mockup**: hard-coded child name/roll/exam lists; `fee_history_screen` renders `allFeesProvider` — **every student's fees visible to any parent** | 🔴 Rebuild on real scoped queries |
| Teacher: my classes/students/attendance/exams, only authorized records | ⚠️ | Teacher screens exist; unscoped queries; `staff_teacher_view` leaks `salary`/`cnic` | Scope + fix leaks |

## §§34–36 Library, hostel, notifications

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §34 Library (books/copies/issue/return/fine), tenant-scoped | ⚠️ | `library_books`/`book_issues` exist; `borrower_id` is **TEXT, not an FK**; unscoped | Scope + normalize borrower |
| §35 Hostel (buildings/rooms/beds/allocations/fees), optional module | ❌ | No hostel tables | Build (module-gated) |
| §36 Notification framework (in-app/push/email; SMS/WhatsApp later) | ❌ | README claims push readiness; no notification code | Build |

## §§37–38 Branding + localization

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Per-tenant logo/name/colors/fonts/dark mode/receipt branding, dynamic UI | 🔴 | Half-dynamic: name from config; no logo; hard-coded colors; vendor footer hard-coded | Tenant-driven theme + assets |
| Urdu/English/Arabic l10n, RTL/LTR, Urdu numerals, Nastaleeq preserved | 🔴 | **No real l10n**: 0 `.arb` files; locale pinned `ur-PK` (`main.dart:86`); 67 `AppStrings` keys vs ~157 inline literals; RTL force-wrapped globally | Real `intl` l10n + locale-driven direction |

## §39 Windows desktop

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| Production `.exe`: icon, splash, installer, shortcuts, uninstaller, versioning, logging, crash handling, auto-update | 🔴 | Builds (`BINARY_NAME "madrasa_360"`) but: **no installer** (no Inno `.iss`/MSIX), **no signing**, placeholder `Runner.rc` branding (`CompanyName "com.madrasa360"`), no auto-update, `logError` = debugPrint | Full productionization per §§65–66 |

## §§40–45 White-label, licensing, devices, updates

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §40 One codebase, many tenants (never per-madrasa forks) | ✅ | Single codebase today | Guard in CI/review |
| §41 Optional white-label branded `.exe` later | ❌ | Not architected | Design hook only (optional) |
| §§42–43 `license_plans`/`licenses`/`tenant_subscriptions` (trial/active/grace/expired…, max_users/students, enabled_modules), Master-Admin-editable plans | ❌ | Only a `subscription_plan` enum on `madrasas` (basic/standard/premium) | Build real licensing |
| §44 Device management (device/OS/version/last-active, revoke) | ❌ | None | Build |
| §45 Version checking (`latest_version`, `minimum_supported_version` force-upgrade) | ❌ | None | Build |

## §§46–50 Error handling, observability, backups, offboarding, Master-Admin security

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §46 Centralized exceptions, user-friendly messages, no raw errors | ⚠️ | **Exists and used**: `AppException` hierarchy + `ErrorHandler` (`error_handler.dart:8-28`); but `logError` = debugPrint + Crashlytics TODO; 4 notifiers swallow errors into fake-success | Keep hierarchy; add real logging; fix swallowing |
| §47 Production logging/crash/API/sync/auth observability; never log secrets | 🔴 | No crash reporting; `avoid_print` lint **disabled** | Add Sentry/Crashlytics; re-enable lints |
| §48 Backups, tenant export, restore | ❌ | Nothing in-app (Supabase dashboard only) | Build tenant export |
| §49 Tenant offboarding: suspend → archive → export → retention → delete | ❌ | No status flow | Build (ties to `tenants.status`) |
| §50 Master Admin hardening (MFA, session handling, privileged confirmations, audit) | ❌ | Super-admin is the **easiest** role to reach — any user can escalate to it (§16) | Build after isolation |

## §§51–54 Performance, indexes, migrations, seeds

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §51 Pagination, lazy loading, efficient queries for thousands of students | ⚠️ | No pagination observed; repos fetch full tables | Add pagination + query audits |
| §52 Indexes on tenant_id, student/class/teacher/date/year/status | ✅ | Adequate (`DATABASE_AUDIT.md §1`); extend with `tenant_id` composites in migration | Keep + extend |
| §53 Ordered, reproducible migrations (`001_initial`…), never hand-edited prod | ❌ | Manual SQL-editor runs, `IF NOT EXISTS` drift-masking, no ledger | Migration runner + `schema_migrations` |
| §54 Demo seed system, never leaking into prod | 🔴 | `04_seed.sql`/`05` mix schema + seed; commented `crypt('***REDACTED-PASSWORD-ROTATED-2026-09-25***'…)` for `superadmin@madrasa360.com`; institution emails in seed | Separate seeds; delete credential blocks |

## §§55–59 Testing, UI/UX, responsive, accessibility

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §55 Unit/widget/integration/security tests | ❌ | 1 fragile full-app smoke test; no mocking lib; no integration_test | Build suite per §55 + §17 |
| §57 Commercial SaaS UI (cards, hierarchy, search/filter/pagination, empty/loading/error states, confirmations) | ⚠️ | Admin/super-admin B-grade but demo data; teacher/parent D-grade static; dead widgets (`PrimaryButton`, `EmptyStateWidget`, `ShimmerLoading`, `AppDrawer` — defined, 0 uses); `Placeholder()` shipped behind a module tile | Fix wiring; delete/adopt dead widgets; kill demo data |
| §58 Responsive: desktop sidebar + mobile bottom-nav, not stretched | 🔴 | Bottom-nav everywhere; **portrait locked** (`main.dart:42-45`); `responsive.dart` toolkit has **zero** call sites; no desktop shell | Build desktop shell using existing toolkit |
| §59 Accessibility | ⚠️ | Quick-pass only; no systematic Semantics/focus work | Incremental |

## §§61–69 Workflow, docs, env, CI, installer, data location, crash recovery, privacy, terminology

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §61 Feature-branch git workflow | ⚠️ | History is 3 flat commits; adopt from this branch on | Adopt |
| §62 Docs (ARCHITECTURE, MULTI_TENANCY, SECURITY, DATABASE, AUTH, OFFLINE_SYNC, MASTER_ADMIN, PROVISIONING, LICENSING, WINDOWS_BUILD, DEPLOYMENT, TESTING, TROUBLESHOOTING) | ⚠️ | README/IMPROVEMENTS/SUPABASE_PLAN exist but **misrepresent** the app (see mismatch tables); this audit's 6 docs are the new baseline | Rewrite per §62 |
| §63 `.env.example`, never commit secrets; documented public config | 🔴 | `.env.example` exists; but service-role key **was** committed in docs; `SUPABASE_SERVICE_KEY` undocumented in the template | Scrub + rotate; document only public config |
| §64 Dev/staging/prod separation | ❌ | Single Supabase project in docs | Build |
| §65 GitHub Actions: analyze/format/test/build Windows+Android; releases with installer/APK/notes | ❌ | No `.github/` at all | Build |
| §66 Professional Windows installer (shortcuts, Start Menu, uninstaller, data preserved on update) | ❌ | None | Inno Setup + signing |
| §67 Local data in proper app-data dirs (never Program Files) | ➖ | N/A yet — no local business DB | Design with Drift |
| §68 Crash recovery (transactions, atomic writes, queue durability, integrity checks) | ❌ | No local DB to corrupt; future requirement | Design with §20 |
| §69 Data privacy (least privilege, private storage, audit) | ⛔ | PII leaks via RLS: student/staff photos all-auth readable; `salary`/`cnic` to teachers/parents; all users' phones world-readable | Fix policies + storage prefixes |
| §70 Product terminology "Madrassa 360", generic terms, no hard-coded madrasa | 🔴 | Product bundles are generic (`com.madrasa360.*`) ✅ but app identity is split Al-Markaz/Khawaja | Sweep §14 |

## §§71–74 Structure, acceptance, principle

| Mission requirement | Status | Current state (evidence) | Action |
|---|---|---|---|
| §71 Full module tree, dynamically enabled per tenant | ⚠️ | Screens exist for most modules; none module-gated | Gate on `tenant_modules` |
| §72 Master Admin structure (Dashboard → Madrasas/Users/Plans/Subscriptions/Licenses/Modules/Audit/Health/Support/Settings) | ❌ | Shell only | Build §§10–11 |
| §73 Acceptance scenario (create Jamia Example → exe → login → student/teacher/class/attendance/fee/exam/result → second madrasa sees only own data) | ⛔ | Fails at step 1 (no provisioning) and at isolation (no tenant boundary) | End-to-end target for Phase 2+ |
| §74 "Sell to a new madrasa without changing source code" | ⛔ | Impossible today — onboarding = hand-run SQL + config constants | The bar every phase must move toward |

---

## Replace vs extend — verdict summary (from `ARCHITECTURE_AUDIT.md §14`, `DATABASE_AUDIT.md §9`)

**Replace outright:** entire RLS policy set (02/05/06) by exact-name drops; `profiles.role` as client-writable; Auth Admin usage from client (`user_management_provider.dart`); attendance mock stack; finance schema; provisioning-by-SQL; all hard-coded identity; docs (README/IMPROVEMENTS/SUPABASE_PLAN claims).
**Extend:** Riverpod repo pattern; `ErrorHandler` exception hierarchy; 57 permission codes + 16 roles (re-scoped); `madrasas` → migrated into `tenants`; Jameel Noori theme; index coverage; `responsive.dart` toolkit.
**Build new:** `tenants`, `tenant_settings`, `tenant_modules`, `tenant_memberships`, `get_current_tenant_id()`, licensing/subscription tables, `audit_logs`, sync queue + Drift, reporting engine, Master Admin, provisioning Edge Function, CI, installer, cross-tenant tests, migrations ledger.

*Phase-2 critical path: rotate secrets → drop/rewrite RLS (001–010 migrations) → tenant membership model → provisioning Edge Function → rewire attendance/logout/demo-data → Drift+sync → licensing → Master Admin → CI/installer → tests.*
