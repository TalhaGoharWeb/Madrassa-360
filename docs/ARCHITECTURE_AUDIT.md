# ARCHITECTURE AUDIT — `al_markaz_al_islami` (Madrasa 360)

**Date:** 2026-09-25 · **Scope:** all 85 Dart files (`lib/`, 19,778 LOC) + 6 SQL files (`supabase/`) + 3 root docs
**Auditor:** subagent (Flutter architecture)
**Method:** every file in `lib/` was read or grepped; claims below cite `file:line`. Nothing was run (`flutter analyze` unavailable in sandbox).

---

## Executive summary (5 bullets)

1. **Single-tenant app with tenant-shaped scaffolding.** `tenant_id` occurs **0 times** in Dart. A `madrasas` table, `madrasa_id` on some models, and a Super Admin shell exist, but no repo enforces tenancy: `madrasa_id` filters are *optional client-side params* (`if (madrasaId != null)`), RLS policies are role-based only (`supabase/02_rls.sql` has zero `madrasa_id` references), and students/staff/attendance/fees/results repos query **unscoped** (no filter at all).
2. **Auth works, session restore is half-wired, logout is broken.** `AuthRepository` → Supabase Auth + `profiles` role resolution + `get_my_permissions()` RPC is real. But `main.dart` always starts on `LoginScreen` with no auto-redirect on restored session, and `profile_screen.dart:532-539` "logout" navigates to login **without calling `auth.signOut()`** — the session stays alive.
3. **Two parallel everything.** Two `NetworkService` classes (compile-collision if co-imported), two permission systems (`AppPermissions` string codes vs `Permission` enum + `allSystemRoles`), two user stores (`profiles` vs `user_accounts`), two attendance stacks (mock `StateNotifier` vs real repo+`AsyncNotifier` — and **the UI screen is wired to the mock**). Dead Phase-1 mock `auth_service.dart` with hardcoded passwords ships unreferenced.
4. **Service-role key read from client code.** `user_management_provider.dart:129,240` reads `SUPABASE_SERVICE_KEY` from `assets/.env` and calls the Auth Admin API from the app. The `.env.example` template doesn't document this key, and `assets/` is bundled into the APK — any service key placed there ships inside the binary. The integration-plan doc itself embeds a **live-looking service_role JWT in plaintext** (`SUPABASE_INTEGRATION_PLAN.md:107`).
5. **Docs describe a different, older app.** `IMPROVEMENTS.md` (Feb 2026) claims "Mock Authentication / No Backend / No real-time sync" — all false now. `SUPABASE_INTEGRATION_PLAN.md` is a pre-integration plan with an all-unchecked checklist and embedded credentials. README over-claims (Hijri dates, fee-slip generation, push-notification readiness, tested platforms).

---

## File inventory

| Layer | Files | LOC | Notes |
|---|---|---|---|
| `lib/main.dart` | 1 | ~105 | Bootstrap, ProviderScope, MaterialApp (no router) |
| `lib/core/config/` | 3 | — | `app_config.dart`, `madrassa_config.dart` (hardcoded identity), `role_config.dart` (visual + nav builder) |
| `lib/core/constants/` | 5 | — | colors, permissions (string codes), strings, typography, `constants.dart` (barrel) |
| `lib/core/services/` | 8 | — | auth (DEAD mock), network ×2 (dup), network_improved (dup), offline_sync, permission, storage, supabase |
| `lib/core/theme/` | 1 | — | `app_theme.dart` (dark theme = TODO) |
| `lib/core/utils/` | 4 | — | date (no Hijri), error_handler, responsive, validators |
| `lib/core/widgets/` | 4 | — | buttons, empty_state, loading_overlay, loading_widget |
| `lib/data/models/` | 13 | — | includes duplicate student models + barrel `models.dart` |
| `lib/data/repositories/` | 7 | — | auth, attendance, fee, result, staff, storage, student (interface + Supabase impl only) |
| `lib/providers/` | 12 | 1,728 | mixed StateNotifier/FutureProvider/AsyncNotifier |
| `lib/presentation/screens/` | 20 | — | admin×9, auth×1, common×3, parent×3, super_admin×3, teacher×3 |
| `lib/presentation/widgets/` | 3 | — | app_drawer (UNUSED), attendance tile, common widgets |
| `supabase/` | 6 | — | schema, RLS, storage, seed, new modules, RBAC |
| **Total** | **85 Dart + 6 SQL** | **19,778** | |

---

## 1. Entry point & bootstrap

| Finding | file:line | Severity | Recommended action |
|---|---|---|---|
| No provider overrides, no DI: repositories are `new`ed directly inside `Provider((ref) => SupabaseXRepository())`; notifiers grab `SupabaseService.client` as a static. Nothing in bootstrap is replaceable for tests. | `lib/main.dart:48-53`, `lib/providers/student_provider.dart:12-14` | High | Introduce `ProviderScope(overrides:)` or a `SupabaseClient` provider; inject client into repositories. |
| No session-restore redirect: `home:` is always `LoginScreen`; nothing listens to `isAuthenticatedProvider` to auto-navigate, so a valid restored session still lands on the login page. | `lib/main.dart:95` | High | Add a bootstrap gate widget that watches auth state and routes. |
| Env crash risk: `dotenv.env['SUPABASE_URL']!` force-unwraps; a missing `assets/.env` crashes before first frame with no fallback. | `lib/core/services/supabase_service.dart:28-29` | High | Validate + show fatal-config screen; fail loudly but gracefully. |
| `assets/.env` is bundled: pubspec ships **all of `assets/`** into the APK, so the "never commit" `.env` still ships inside the binary (extractable via unzip). | `pubspec.yaml` (assets section), `lib/core/services/supabase_service.dart:25` | High | Move to `--dart-define` / compile-time config; stop bundling `.env`. |
| No router: `MaterialApp(home:)`, imperative `Navigator.push/pushReplacement` everywhere, zero deep links. | `lib/main.dart:52-99` | Medium | Adopt `go_router` with redirect guards in Phase 2. |
| `OfflineSyncService.init()` called with no repository → `_attendanceRepo` is null → connectivity flush path is permanently dead code. | `lib/main.dart:29`, `lib/core/services/offline_sync_service.dart:20-33` | Medium | Pass the real repository or remove the flush path. |
| Hardcoded identity: package name `al_markaz_al_islami`, README "Al Markaz al Islami Kasur", but `MadrassaConfig.nameUrdu = 'خواجہ ایجوکیشنل سسٹم'`, `nameEnglish = 'Khawaja Educational System'`. Three conflicting identities. | `lib/core/config/madrassa_config.dart:25-28`, `pubspec.yaml:1`, `README.md:1` | Medium | Decide identity; Phase 2 removes hardcoded identity entirely. |

---

## 2. State management (Riverpod)

Totals across `lib/providers/` + screens: **8 StateNotifierProvider, 5 AsyncNotifierProvider, 9 FutureProvider.family, 6 FutureProvider, 2 Provider.family, 16 Provider, 1 StreamProvider.family**. No `Notifier`, no `StateProvider`.

| Finding | file:line | Severity | Recommended action |
|---|---|---|---|
| Three generations coexist: legacy `StateNotifier`+mutable mock state, `FutureProvider`-query layer, newer `AsyncNotifier` mutators — with **two live attendance stacks** (see §6). | `lib/providers/attendance_provider.dart` (whole file) | High | Pick one pattern (AsyncNotifier + FutureProvider) and delete the other. |
| Half the providers bypass repositories and hit Supabase directly from the notifier (`final _client = SupabaseService.client`), violating the repo pattern the plan mandated: announcement, darja, finance, library, madrasa, user_management. | `lib/providers/announcement_provider.dart:34`, `darja_provider.dart:36`, `finance_provider.dart:37`, `library_provider.dart:28`, `madrasa_provider.dart:39`, `user_management_provider.dart:50` | High | Move all queries into repositories; providers become state-only. |
| Silent-failure mutations: `delete`, `updateDarja`, `togglePin` etc. `catch (_) {}` and then **apply the change optimistically anyway**, returning success. The UI cannot distinguish a failed write from a real one; local state diverges from DB. | `lib/providers/announcement_provider.dart:77-91`, `lib/providers/darja_provider.dart:116-118`, `lib/providers/library_provider.dart:52-64`, `lib/providers/madrasa_provider.dart:93-109` | High | Surface errors; only mutate state on confirmed success. |
| `as dynamic` casts to chain `.eq()` after a conditional (`q = q.eq('madrasa_id', madrasaId) as dynamic`) — postgrest builder typing worked around with dynamic in 4 providers. | `lib/providers/darja_provider.dart:44`, `announcement_provider.dart:40`, `finance_provider.dart:41`, `library_provider.dart:33` | Medium | Use proper `PostgrestFilterBuilder` typing. |
| Provider overrides impossible: repository providers construct concrete classes, no interface injection point is exercised. | `lib/providers/*_provider.dart` (all) | Medium | Constructor-inject client; keep the `I…Repository` interfaces actually used. |

---

## 3. Auth flow end-to-end

| Finding | file:line | Severity | Recommended action |
|---|---|---|---|
| Sign-in is real: `signInWithPassword` → `_fetchProfile` → `AppUser.fromSupabase`. Role resolution prefers `app_metadata['role']`, falls back to `profiles.role`, case-insensitive, defaulting to `teacher`. | `lib/data/repositories/auth_repository.dart:136-176, 78-100` | OK | Keep. |
| Session persistence delegated to `supabase_flutter` (secure storage); `AuthNotifier._init` listens to `onAuthStateChange` for restore/refresh. | `lib/providers/auth_provider.dart:62-88` | OK | Keep, but wire it to navigation (§1). |
| **Logout is fake.** Profile "logout" confirmation does `pushAndRemoveUntil(LoginScreen)` **without** calling `AuthRepository.signOut()` or `authProvider.notifier.logout()`. Supabase session survives; the auth listener will flip state back to authenticated. | `lib/presentation/screens/common/profile_screen.dart:532-539` | **Critical** | Call `ref.read(authProvider.notifier).logout()` before navigating. |
| No password-reset flow: strings + `ApiEndpoints.forgotPassword` exist but no screen, no `resetPasswordForEmail` call anywhere. | `lib/core/constants/app_strings.dart:48`, `lib/core/config/app_config.dart:111-112` | Medium | Implement in Phase 2 (Supabase one-liner). |
| Role switch after login is imperative: `Navigator.pushReplacement` to one of 4 shell screens based on role; no route guard prevents a teacher from pushing `AdminMainScreen` manually, and the `student` role falls through to the **teacher** `MainScreen`. | `lib/presentation/screens/auth/login_screen.dart:121-162` | High | go_router redirects keyed to role + permission. |
| `getSessionUser()` swallows all errors (`catch (_) { return null; }`) — a DB outage during restore looks identical to "signed out". | `lib/data/repositories/auth_repository.dart:184-193` | Medium | Distinguish network failure from no-session. |

---

## 4. Repository/service pattern — who bypasses it

Repositories with interfaces exist for: auth, student, staff, attendance, fee, result, storage. **Interfaces have exactly one implementation each** (no mocks — docstrings still say "Mock + Supabase implementations", which is false).

| Caller | Bypasses with | file:line |
|---|---|---|
| `AnnouncementNotifier` | direct `_client.from('announcements')` | `lib/providers/announcement_provider.dart:34-91` |
| `DarjaNotifier` | direct `_client.from('darjas'/'darja_sections')` | `lib/providers/darja_provider.dart:36-118` |
| `FinanceNotifier` | direct `_client.from('finance_transactions')` | `lib/providers/finance_provider.dart:37-56` |
| `LibraryNotifier` | direct `_client.from('library_books'/'book_issues')` | `lib/providers/library_provider.dart:28-64` |
| `MadrasaNotifier` | direct `_client.from('madrasas')` | `lib/providers/madrasa_provider.dart:39-109` |
| `UserManagementNotifier` | direct `_client.from('user_accounts'/'app_roles')` + raw `http` to Auth Admin API | `lib/providers/user_management_provider.dart:50-260` |
| `StudentNotifier.uploadPhoto`, `StaffNotifier.uploadPhoto` | direct `SupabaseService.client.storage` (bypasses `IStorageRepository`) | `lib/providers/student_provider.dart:88-108`, `lib/providers/staff_provider.dart:53-73` |
| Screens | none found querying Supabase directly (good) | — |

---

## 5. Routing/navigation

- **No route table, no guards, no deep links.** `MaterialApp(home: LoginScreen)`; all navigation is imperative `push`/`pushReplacement`. `pubspec.yaml` has no routing package.
- Role shells: `SuperAdminMainScreen`, `AdminMainScreen` (permission-built tabs via `buildNavTabs`), `ParentMainScreen`, `MainScreen` (legacy teacher). Tab set in `AdminMainScreen` is capped at 5 via permission checks (`lib/core/config/role_config.dart:165-228`) — decent pattern, but enforced only in UI.
- **Guard gap:** after login the destination is chosen once; nothing re-checks permission on subsequent navigation, and `MainScreen`/`AdminMainScreen` can be pushed by any authenticated user.

---

## 6. Offline support

| Finding | file:line | Severity | Recommended action |
|---|---|---|---|
| No SQLite/Drift/Hive. "Offline" = SharedPreferences JSON caches (`cache_students_*`, `cache_attendance_*`) read only in `catch` blocks of 2 repos. | `lib/data/repositories/student_repository.dart:33-51`, `attendance_repository.dart:86-108` | High | Phase 2: real local DB (Drift) with sync queue. |
| **The attendance screen is wired to the dead mock stack.** `AttendanceScreen` watches `attendanceProvider` (legacy `StateNotifier` over `MockStudent`); its `saveAttendance()` just `await Future.delayed(1s)` + `print` — **marking attendance never touches Supabase.** The real `classAttendanceProvider` / `attendanceStreamProvider` / `attendanceRecordNotifierProvider` are defined but referenced by **zero** screens. | `lib/presentation/screens/teacher/attendance_screen.dart:18-237`, `lib/providers/attendance_provider.dart:36-118` vs `:128-220` | **Critical** | Rewire screen to `attendanceRecordNotifierProvider`; delete mock stack. |
| Offline queue exists for attendance (`OfflineSyncService.queueAttendance`) and `AttendanceRecordNotifier.save` writes to it on failure — but since no UI calls that notifier, the queue is write-only in practice, and `init()` never receives a repo so the flush path is dead. | `lib/core/services/offline_sync_service.dart:20-33`, `lib/providers/attendance_provider.dart:196-220` | High | Fix wiring; make flush actually reachable. |
| Cache staleness: caches have no TTL/expiry despite `AppConfig.cacheExpiryDays = 7` (constant exists, never enforced). | `lib/core/config/app_config.dart:52`, `lib/data/repositories/*` | Medium | Enforce TTL or drop in favor of Drift. |

---

## 7. Error handling

Centralized exceptions exist and are genuinely used: `AppException` → `NetworkException`, `ValidationException`, `AuthenticationException`, `StorageException` (`lib/core/utils/error_handler.dart:8-28`), plus `ErrorHandler.showErrorSnackBar/showErrorDialog/getErrorMessage/logError`. `AuthRepository` maps Supabase/IO errors to Urdu messages (`auth_repository.dart:158-176`).

| Finding | file:line | Severity | Recommended action |
|---|---|---|---|
| `ErrorHandler.logError` is `debugPrint` + a TODO for Crashlytics. No crash reporting, no structured logging. | `lib/core/utils/error_handler.dart:97-103` | Medium | Add Crashlytics/Sentry in Phase 2. |
| Over-broad `catch (_) {}` in 4 notifiers silently converts failures into fake-success optimistic updates (see §2). | `lib/providers/{announcement,darja,library,madrasa}_provider.dart` | High | Propagate typed errors to UI. |
| `uploadPhoto` swallows everything and returns `null` — caller can't tell "no photo picked" from "upload failed". | `lib/providers/student_provider.dart:105-107`, `staff_provider.dart:71-73` | Low | Return a result type. |

---

## 8. Tenant-awareness — the `tenant_id` inventory

`grep -rni 'tenant' lib/ --include='*.dart'` → **0 matches.** There is no tenant concept in Dart at all.

| Where `madrasa_id` exists (74 hits) | What it actually does |
|---|---|
| Models: `announcement`, `darja`, `darja_sections`, `finance_transaction`, `library_book`, `book_issue` | Nullable field, parsed/serialized. **Absent** from `student`, `staff`, `attendance`, `fee`, `exam`, `result` models entirely. |
| `AppUser.madrasaId` | Read from `profiles.madrasa_id`; passed to `PermissionService.loadForUser` → `get_my_permissions(p_madrasa_id)`. | 
| Providers (announcement, darja, finance, library) | `load({String? madrasaId})` — filter applied **only if non-null**. |
| Screens (darja, finance, library, announcements) | Accept `madrasaId` constructor param and pass it through. |

| Tenant violation | file:line | Severity |
|---|---|---|
| `AdminMainScreen` constructs `StudentListScreen`, `AttendanceScreen`, `StaffListScreen`, `FeeManagementScreen`, `UserManagementScreen`, `ResultsScreen` **without** `madrasaId` → filter is null → queries return **all madrasas' rows**. | `lib/presentation/screens/admin/admin_main_screen.dart:33-44` | **Critical** |
| Student/staff/attendance/fee/result repositories have **no madrasa filter at all** — not even optional. | `lib/data/repositories/student_repository.dart`, `staff_repository.dart`, `attendance_repository.dart`, `fee_repository.dart`, `result_repository.dart` | **Critical** |
| RLS is role-based only: `02_rls.sql` contains **zero** `madrasa_id` references; e.g. `USING (auth.role() = 'authenticated')` grants cross-tenant reads to any signed-in user. | `supabase/02_rls.sql:77,85` | **Critical** |
| Parent `FeeHistoryScreen` watches `allFeesProvider` → any parent sees **every student's fees** (no child linkage at all). | `lib/presentation/screens/parent/fee_history_screen.dart:18` | **Critical** |
| `MadrasaNotifier.loadAll` lists **all** madrasas to whoever can call it; scoping is UI-convention only. | `lib/providers/madrasa_provider.dart:41-53` | High |
| Tenant isolation today = hoping RLS role checks suffice. They don't: a teacher in madrasa A can read madrasa B's students. | — | **Critical** |

---

## 9. Permission/authorization

`PermissionService.loadForUser` calls the `get_my_permissions()` RPC and falls back to the hardcoded `AppPermissions.roleDefaults` map when offline/failed (`lib/core/services/permission_service.dart:27-48`, `lib/core/constants/app_permissions.dart:225-330`).

| Finding | file:line | Severity | Recommended action |
|---|---|---|---|
| Two parallel permission systems: `AppPermissions` string codes (used by auth flow/nav) vs `Permission` **enum** + `AppRole.allSystemRoles` in `lib/data/models/app_role.dart` (used by user-management screens). They can drift; only the string codes are synced with `06_rbac.sql`. | `lib/core/constants/app_permissions.dart`, `lib/data/models/app_role.dart:11-24,327` | High | Unify on one system in Phase 2. |
| Role-name stringly-typed everywhere: `PermissionService.isStaffRole` etc. hardcode role-name sets (`{'madrasaAdmin','admin','editor',…}`); adding a role requires touching 4+ files. | `lib/core/services/permission_service.dart:50-76` | Medium | Derive from DB roles/permissions. |
| Enforcement is UI-only: nav tabs and buttons hide without permission, but **no repository or RPC checks permission before writing** — security rests entirely on RLS, which is role-based and tenant-blind (§8). | `lib/core/config/role_config.dart:165-228` | High | Server-side checks; tenant-scoped RLS. |
| Offline fallback grants full static permission sets with no expiry — a revoked permission persists until next successful RPC. | `lib/core/services/permission_service.dart:44-46` | Medium | Timestamp + TTL on cached permissions. |
| `AppUser.can()` / `hasPermissionProvider` exist and are clean. | `lib/data/repositories/auth_repository.dart:103`, `lib/providers/auth_provider.dart:177-180` | OK | Keep. |

---

## 10. Dead code, duplicates, incomplete features

| Item | file:line | Status |
|---|---|---|
| `AuthService` — entire Phase-1 mock (hardcoded `admin/admin123`, `teacher/teacher123`, `parent/parent123`, plaintext passwords) | `lib/core/services/auth_service.dart:1-170` | **DEAD — imported nowhere** (`grep services/auth_service` → 0). Delete. |
| `NetworkService` (old, `StreamController<bool>`) vs `NetworkService` (improved, widget+retry) — **same class name in two files**; importing both in one file is a compile error | `lib/core/services/network_service.dart:9`, `network_service_improved.dart:8` | DUPLICATE — delete old; note: neither is imported anywhere currently |
| `MockStudent` + legacy attendance `StateNotifier` (empty `loadStudentsForDarja`, print-only `saveAttendance`) | `lib/data/models/student_model.dart`, `lib/providers/attendance_provider.dart:36-118` | DEAD stack — but **the live screen still uses it** (§6). Delete after rewiring. |
| `MockStorageRepository` (placeholder.com URLs) — docstring says "Mock + Supabase implementations" for all repos; only Supabase impls exist | `lib/data/repositories/storage_repository.dart:32-51` | DEAD — delete |
| `AppDrawer` widget | `lib/presentation/widgets/app_drawer.dart` | DEAD — used by 0 screens |
| `AppRole.allSystemRoles` (335-line parallel role registry) vs `UserRole` enum vs `AppPermissions.roleDefaults` — three role registries | `lib/data/models/app_role.dart:327` | DUPLICATE — unify in Phase 2 |
| `ApiEndpoints` — REST endpoint constants for a backend that doesn't exist ("future Firebase/Backend integration") | `lib/core/config/app_config.dart:88-132` | DEAD — delete |
| `kUseSupabase` flag — always `true`; mock branches it guarded are gone | `lib/core/config/app_config.dart:17` | DEAD — delete |
| Parent dashboard hardcoded child: `'محمد احمد'`, `'درجہ اولیٰ (اول سال) - رول نمبر 1'`, static timeline/exam lists — parent portal is a **mockup**, not wired to data | `lib/presentation/screens/parent/parent_dashboard_screen.dart:107-118` | INCOMPLETE |
| No parent↔child linkage: no `guardian_id`/`parent_id` on student model, no query "my children" anywhere | `lib/data/models/student.dart` | INCOMPLETE |
| TODOs: dark theme (`app_theme.dart:164`), Crashlytics (`error_handler.dart:101`) | — | TODO |
| `student` role login → falls to `default:` → teacher `MainScreen` | `lib/presentation/screens/auth/login_screen.dart:157-159` | BUG |

---

## 11. Networking & secrets

| Finding | file:line | Severity |
|---|---|---|
| Client constructed once: `SupabaseService.init()` → `dotenv.load('assets/.env')` → `Supabase.initialize(url, anonKey)`. Single global client via `Supabase.instance.client`. | `lib/core/services/supabase_service.dart:22-33` | OK pattern |
| **Service-role key used in client code.** `UserManagementNotifier.createAccount`/`deleteAccount` read `SUPABASE_SERVICE_KEY` from dotenv and call `POST/DELETE $SUPABASE_URL/auth/v1/admin/users` via raw `http`. If any deployer follows the prompt and pastes the service key into `assets/.env`, it ships **inside the APK** (pubspec bundles all of `assets/`) with full admin rights. | `lib/providers/user_management_provider.dart:129-160,240-252` | **Critical** |
| `.env.example` documents only `SUPABASE_URL` + `SUPABASE_ANON_KEY`; the service-key requirement is undocumented → the user-creation feature errors out (`'SUPABASE_SERVICE_KEY .env میں شامل کریں'`) on a clean setup. | `assets/.env.example`, `lib/providers/user_management_provider.dart:133-134` | Medium |
| **Plaintext credentials in repo docs.** `SUPABASE_INTEGRATION_PLAN.md:104-107` embeds a project URL, a full anon JWT, and a full **service_role JWT**. If this repo is pushed anywhere, those keys are burned — rotate them. | `SUPABASE_INTEGRATION_PLAN.md:104-107` | **Critical** |
| No certificate pinning, no request signing beyond Supabase defaults; `enableBiometricAuth = false`, `AppConfig.sessionTimeoutMinutes = 30` is declared but never enforced (Supabase owns the session). | `lib/core/config/app_config.dart:45,72` | Low |

> No secret *values* are reproduced in this audit. Exposure paths only, as above.

---

## 12. Docs-vs-reality mismatch table

| Doc claim | Reality | Location |
|---|---|---|
| IMPROVEMENTS.md: "Mock Authentication — currently using hardcoded credentials" / "No Backend — all data is mock/local" / "No Real-time Sync" (Known Issues) | False. Real Supabase Auth, PostgREST repos, and a realtime attendance stream exist. The doc describes the Feb-2026 codebase, not this one. | `IMPROVEMENTS.md` "Known Issues & Limitations" |
| IMPROVEMENTS.md §2: "Auth Service — Mock authentication… Session management with SharedPreferences" | `auth_service.dart` is dead code; sessions are Supabase-managed. | `IMPROVEMENTS.md:§2`, `lib/core/services/auth_service.dart` |
| IMPROVEMENTS.md: "Next Steps Phase 1: replace mock auth, connect to real database" | Already done. Checklist is stale. | `IMPROVEMENTS.md` "Recommended Next Steps" |
| SUPABASE_INTEGRATION_PLAN.md: "Current state: All data is local/mock" | Stale — integration is ~80% complete. | `SUPABASE_INTEGRATION_PLAN.md:5` |
| PLAN: migration checklist, all boxes unchecked | Phases 0–7 largely implemented; checklist never updated. | `SUPABASE_INTEGRATION_PLAN.md:1145+` |
| PLAN Step 0.2: "service role key … **never put this in the app**" | The app **does** read `SUPABASE_SERVICE_KEY` for the Admin API. Direct contradiction. | `SUPABASE_INTEGRATION_PLAN.md:Step 0.1`, `lib/providers/user_management_provider.dart:129` |
| README: "Date formatters (Gregorian & Hijri)" | `date_utils.dart` has no Hijri code. | `README.md` tech stack; `lib/core/utils/date_utils.dart` |
| README: "Fee Slip Generation… Payment Collection & Receipts" | No slip/receipt generation code; fee screens are CRUD lists. | `README.md` §3 |
| README: "strict Role-Based Access Control" / "enterprise-grade security powered by RLS" | RLS is role-based only, tenant-blind; client-side permission checks are UI-only. | `README.md` RBAC section; `supabase/02_rls.sql` |
| README: "multi-tenant capabilities" | No tenant isolation anywhere (see §8). | `README.md` Overview |
| README: "push notifications" implied by `enableNotifications = true` + `StorageKeys.fcmToken` | No FCM wiring anywhere in Dart. | `lib/core/config/app_config.dart:44` |
| README: "Platform: Android | iOS | Web | Desktop" | IMPROVEMENTS.md admits iOS/web untested, desktop untested. | `README.md` vs `IMPROVEMENTS.md` |
| README identity: "Al Markaz al Islami Kasur" | `MadrassaConfig` says Khawaja Educational System, Qili Piranwali; package `al_markaz_al_islami`. | `README.md:1`, `lib/core/config/madrassa_config.dart:25-28` |
| Code docstrings: repos "Mock + Supabase implementations" | Only Supabase implementations exist. | `lib/data/repositories/*_repository.dart` headers |

---

## 13. Architecture diagram — what ACTUALLY exists

```
                        ┌─────────────────────────────┐
                        │          main.dart          │
                        │  Storage.init → Supabase    │
                        │  .init → OfflineSync.init   │
                        │  (no repo!) → runApp(       │
                        │  ProviderScope NO overrides)│
                        └──────────────┬──────────────┘
                                       │ home: ALWAYS LoginScreen
                                       ▼
┌──────────────┐   signInWithPassword   ┌──────────────────────────────┐
│ LoginScreen  │ ───────────────────▶  │ AuthRepository (REAL)        │
│ (imperative  │   profiles.role       │  ├─ app_metadata.role →     │
│  pushReplace │   get_my_permissions  │  │   profiles.role → teacher │
│  by role)    │ ◀───────────────────  │  └─ RPC get_my_permissions() │
└──────────────┘                       └──────────────┬───────────────┘
                                                     │ AuthNotifier
                                                     │ (StateNotifier)
                        ┌────────────────────────────┼────────────────────────────┐
                        ▼                            ▼                            ▼
              SuperAdminMainScreen          AdminMainScreen              ParentMainScreen / MainScreen
              (madrasa CRUD,                (permission-built tabs,       (parent: HARDCODED mock
               user mgmt)                   max 5, UI-only gating)        data; student→teacher UI)
                        │                            │
                        ▼                            ▼
              ┌─────────────────────────────────────────────────┐
              │  PROVIDERS — two tribes                         │
              │  A) Repo-backed: student, staff, fee, result     │
              │     (FutureProvider + AsyncNotifier, clean)      │
              │  B) Direct-Supabase notifiers: announcement,    │
              │     darja, finance, library, madrasa,           │
              │     user_management (catch(_){} optimistic,     │
              │     optional madrasa_id filter)                 │
              │  C) DEAD: legacy attendance StateNotifier       │
              │     over MockStudent ◀── AttendanceScreen       │
              │     STILL USES THIS (save = delay+print)        │
              └──────────────────────┬──────────────────────────┘
                                     │ PostgREST / Realtime / Storage
                                     ▼
              ┌─────────────────────────────────────────────────┐
              │  SUPABASE — role-based RLS, NO tenant scoping   │
              │  students/staff/fees/attendance/results:        │
              │  queried UNFILTERED (no madrasa_id anywhere)   │
              │  user_accounts ⊕ profiles: two user stores      │
              │  service_role key reachable from client code    │
              └─────────────────────────────────────────────────┘

OFFLINE: SharedPreferences JSON caches (students, attendance) read in catch-blocks only.
         OfflineSyncService queue exists but init() gets no repo → flush dead.
```

**What the docs claim** (and doesn't exist): tenant isolation via RLS, Hijri dates, fee-slip generation, push notifications, session-timeout enforcement, a route table with guards, repository-only data access, mock implementations alongside Supabase ones, "Mock Data Phase" status.

---

## 14. Replace vs refactor verdicts (Phase 2 input — no implementation)

| Area | Verdict | Rationale |
|---|---|---|
| `lib/core/services/auth_service.dart` | **DELETE** | Dead; hardcoded plaintext passwords in shipped source. |
| `lib/core/services/network_service.dart` (old) | **DELETE** | Duplicate class name; unused. Keep `_improved`, rename to `connectivity_service.dart`. |
| Legacy attendance stack (`MockStudent`, old `AttendanceNotifier`, `attendanceProvider`) | **DELETE after rewiring** | Screen must move to `attendanceRecordNotifierProvider` first; then delete `student_model.dart` mock. |
| `MockStorageRepository`, `kUseSupabase`, `ApiEndpoints` | **DELETE** | Dead flags/constants. |
| `AppDrawer` | **DELETE or wire** | Unused; decide. |
| Permission system | **REPLACE with one** | Merge `AppPermissions` codes + `Permission` enum + `roleDefaults` + `allSystemRoles` into a single DB-driven source. |
| Providers hitting Supabase directly | **REFACTOR** | Extract repositories (announcement, darja, finance, library, madrasa, user_management). Keep Riverpod. |
| Silent optimistic mutations | **REFACTOR** | Return `Result<T, AppException>`; mutate state only on success. |
| Auth + session + routing | **REFACTOR** | Fix logout (1 line), add bootstrap gate, migrate to `go_router` with role/permission redirects. |
| Offline layer | **REPLACE** | SharedPreferences JSON → Drift/SQLite with real sync queue; `OfflineSyncService` becomes the queue runner with injected repo. |
| Tenant isolation | **REPLACE (greenfield)** | Nothing to salvage: add `tenant_id`/`madrasa_id` to ALL tables, mandatory server-side scoping, tenant-scoped RLS, master-admin role; remove optional client-side filters. This is the Phase-2 core. |
| Service-role usage | **REPLACE** | Move Auth Admin API calls to a backend (Edge Function); never ship service key in app. Rotate the key embedded in the plan doc. |
| Parent portal | **REBUILD data layer** | Add guardian↔student linkage; replace hardcoded dashboard. |
| Docs | **REWRITE** | Archive `IMPROVEMENTS.md`; mark plan complete; scrub secrets from `SUPABASE_INTEGRATION_PLAN.md:104-107`. |

### Phase-2 critical path (suggested order)
1. Rotate exposed Supabase keys; scrub plan doc; remove service-key-from-client.
2. Tenant data model + RLS (blocks everything multi-tenant).
3. Fix logout, session-restore routing, go_router guards.
4. Rewire attendance screen; delete dead stacks.
5. Repository extraction for direct-Supabase providers; unify permissions.
6. Drift offline layer; parent-portal data wiring.

---

*End of audit. All findings cite exact files; no code was modified and nothing was committed.*
