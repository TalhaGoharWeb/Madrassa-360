# Phase 13 — Final Audit (deletions, regressions, final state)

Date: 2026-09-29 · Branch: `redesign/ux-v2` · Working copy: `~/workspace/madrassa-redesign-fix`.
Read-only audit of the Phase 13 working tree (docs-only task; no code touched).
Every claim verified against the code; git status shows the 14 deletions staged.

## 1. Full route checklist

Source of truth: `lib/presentation/shell/nav_destinations.dart`
(`kNavGroups`, `kMobilePrimaryIds`). Every builder target was verified to
exist. Status is `live` for all — there are no planned/coming-soon
destinations left in the IA.

### مرکزی (markazi)

| destination id | screen class | permissions / roles | status |
|---|---|---|---|
| `dashboard` | `RoleHomeScreen` | — (all authenticated) | live |
| `announcements` | `AnnouncementsScreen` | — | live (badge: announcement count) |
| `guide` | `DashboardGuideScreen(roleKey: 'generic')` | — | live |

### طلبہ (students)

| destination id | screen class | permissions / roles | status |
|---|---|---|---|
| `student-list` | `StudentListScreen` | `students.view`/`create`/`edit` (any) | live |
| `my-classes` | `MyClassesScreen` | `teachers.view`/`darjas.view`/`students.view` (any) | live |
| `my-students` | `MyStudentsScreen` | role keys `teacher`, `ustad`, `ustad_hifz` | live |
| `parent-fees` | `FeeHistoryScreen` | role key `parent` | live |

### تعلیمی نظام (academics)

| destination id | screen class | permissions / roles | status |
|---|---|---|---|
| `darjas` | `DarjaScreen` | `darjas.view`/`manage` (any) | live |
| `exams` | `ExamDashboardScreen` | `exams.view`/`create`/`manage` (any) | live |
| `results` | `ResultsScreen` | `results.view`/`enter`/`edit`/`publish` (any) | live |

### حاضری (attendance)

| destination id | screen class | permissions / roles | status |
|---|---|---|---|
| `attendance` | `AttendanceScreen` | `attendance.mark`/`view` (any) | live |

### مالی (finance) — `FinanceHubScreen` sections (Phase 9)

| destination id | screen class | permissions / roles | status |
|---|---|---|---|
| `finance_dashboard` | `FinanceHubScreen(dashboard)` | `viewFinance`/`viewFees` (any) | live |
| `student_fees` | `FeeManagementScreen` | `collectFees`/`viewFees` (any) | live |
| `finance_dues` | `FinanceHubScreen(dues)` | `collectFees`/`viewFees` (any) | live |
| `finance_invoices` | `FinanceHubScreen(invoices)` | `viewFinance`/`approveFinance` (any) | live |
| `finance_payments` | `FinanceHubScreen(payments)` | `viewFinance`/`approveFinance` (any) | live |
| `finance_ledger` | `FinanceHubScreen(ledger)` | `viewFinance`/`approveFinance` (any) | live |
| `finance_expenses` | `FinanceHubScreen(expenses)` | `viewFinance`/`approveFinance` (any) | live |
| `finance_reports` | `FinanceHubScreen(reports)` | `viewReports`/`exportReports` (any) | live |

### ادارہ (institution)

| destination id | screen class | permissions / roles | status |
|---|---|---|---|
| `staff` | `StaffListScreen` | `staff.view`/`teachers.view` (any) | live |
| `library` | `LibraryScreen` | `library.view`/`manage` (any) | live |
| `users-roles` | `UserManagementHubScreen` | `users.view`/`roles.assign` (any) | live |
| `hostel` | `HostelScreen` (Phase 8 hub) | `hostel.view`/`manage` (any) | live — honest backend-unavailable data states |
| `transport` | `TransportScreen` (Phase 8 hub) | `transport.view`/`manage` (any) | live — honest backend-unavailable data states |
| `certificates` | `CertificatesScreen` (Phase 8) | `certificates.view`/`issue` (any) | live — real PDF generation; issuance history backend-pending |

### ترتیبات (settings)

| destination id | screen class | permissions / roles | status |
|---|---|---|---|
| `profile` | `ProfileScreen` | — | live |
| `notifications` | `NotificationsScreen` | — | live (badge: unread count) |
| `backup` | `BackupScreen` | `manageSettings` | live (restored from orphaned to shell destination) |
| `about` | `AboutScreen` | — | live |
| `logout` | intercepted action (confirm + sign-out); builder never rendered | — | live |

### Outside the shell

| route | screen(s) | status |
|---|---|---|
| `AuthGate` flow | `LoginScreen`, `ForgotPasswordScreen`, `TenantPickerScreen`, `NoAccessScreen` → `AppShell` | live |
| `/master` (guarded by `MasterAdminGuard`) | `MasterAdminShell` + 11 console screens (dashboard, madrasa list/detail, create wizard, plans, subscriptions, licenses, modules, platform users, audit logs) | live |
| deep pushes | `StudentProfileScreen`, `ExamWizardScreen`, `CollectFeeScreen`, `UserWizardScreen`, `UserDetailScreen`, `DelegationScreen`, `DelegationCreateScreen`, `ScopeManagerScreen`/`ScopeEditorScreen`, `_PdfPreviewScreen` (internal) | live |

Mobile bottom nav (`kMobilePrimaryIds`): `dashboard`, `student-list`,
`attendance`, `student_fees` + "مزید". **Phase 13 fix:** the stale `'fees'`
id was renamed to `'student_fees'` — the old id matched no destination, so
mobile users silently lost the fees tab.

## 2. Deletion log — 14 files

All verified absent from the working tree; zero imports of any of them remain
in `lib/` or `test/`.

| # | file | why it was dead |
|---|---|---|
| 1 | `lib/presentation/screens/admin/admin_main_screen.dart` | Legacy permission-driven bottom-nav shell ("All 11 staff roles land here"); zero external references |
| 2 | `lib/presentation/screens/main_screen.dart` | Legacy Phase-1 teacher bottom-nav wrapper; only reachable as the `_backToApp()` fallback in `MasterAdminShell` — that fallback now targets `AppShell`, so the file had no path left |
| 3 | `lib/presentation/screens/parent/parent_dashboard_screen.dart` | Only referenced from dead `ParentMainScreen`; parent role routes via `RoleHomeScreen` → `GenericDashboardScreen` + the `parent-fees` destination |
| 4 | `lib/presentation/screens/parent/parent_main_screen.dart` | Dead parent bottom-nav shell (home/fees/profile); zero external references |
| 5 | `lib/presentation/screens/teacher/teacher_dashboard_screen.dart` | Legacy Phase-4 teacher dashboard, same class name (`TeacherDashboardScreen`) as the live `dashboards/teacher_dashboard.dart` — compile hazard and maintenance trap; only referenced from dead `main_screen.dart` |
| 6 | `lib/presentation/screens/super_admin/madrasa_management_screen.dart` | `@deprecated` legacy madrasa management; superseded by the `master_admin/` platform console; zero references |
| 7 | `lib/presentation/screens/super_admin/super_admin_dashboard_screen.dart` | `@deprecated` legacy single-tenant super-admin dashboard; zero references |
| 8 | `lib/presentation/screens/super_admin/super_admin_main_screen.dart` | `@deprecated` legacy super-admin shell; zero references |
| 9 | `lib/presentation/screens/dashboards/teacher_home.dart` | Nested 5-tab teacher shell eliminated: `role_home.dart` now renders `TeacherDashboardScreen` directly (single shell); quick actions route through `shellNavRequestProvider` (`lib/presentation/shell/shell_nav.dart`), consumed once by `AppShell` |
| 10 | `lib/core/widgets/confirm_dialog.dart` | Superseded by `M360ConfirmDialog` / `showM360ConfirmDialog` (`lib/core/design/m360_dialog.dart`); destructive confirmations across darja/library/staff already use the m360 one |
| 11 | `lib/core/widgets/custom_buttons.dart` | Superseded by the m360 button set (`M360PrimaryButton`, `M360IconButton`, …); the design system is now wired (70+ importers in `lib/presentation/`) |
| 12 | `lib/core/widgets/loading_overlay.dart` | Duplicate; the live `LoadingOverlay` is `lib/core/widgets/loading_widget.dart` |
| 13 | `lib/presentation/widgets/app_drawer.dart` | Superseded by `AppNavRail` (`lib/presentation/shell/app_nav_rail.dart`) |
| 14 | `lib/presentation/widgets/profile_avatar_button.dart` | Zero references (dashboards no longer have per-dashboard AppBars); profile is reached via the rail `_UserFooter` and the `profile` destination |

**Teacher single-shell detail (verified):** `role_home.dart:58` routes
teacher-family role keys straight to `TeacherDashboardScreen`, which builds a
`DashboardScaffold` body widget — explicitly *not* a Material
Scaffold/AppBar ("Must be hosted inside AppShell"). Quick actions call
`requestShellNav(ref, 'attendance' | 'my-students' | 'results')`; pushes to
announcements/profile/guide/platform console stay `MaterialPageRoute`.

## 3. Retained nested Scaffolds + reasons

AppShell owns the only top-level Scaffold for all 29 in-shell destinations
(they render via `ShellPageBody`/`PageContainer`). Nested Scaffolds survive
only outside the shell or on pushed full-screen routes:

- **Auth screens** (`login`, `forgot_password`, `tenant_picker`, `no_access`)
  — render *instead of* `AppShell` by design.
- **`ExamWizardScreen`** — pushed 8-step full-screen wizard; never a shell
  destination.
- **Settings deep screens** (`UserWizardScreen`, `UserDetailScreen`,
  `DelegationScreen`, `DelegationCreateScreen`, `ScopeManagerScreen`) —
  pushed from `UserManagementHubScreen`; default AppBar back button.
- **`StudentProfileScreen`** — pushed from `StudentListScreen` row tap.
- **`MasterAdminShell`** — the separate `/master` platform console; outside
  the tenant `AppShell`.

Two items from the brief needed correction (verified in code, see §5):
the **fee-collection wizard** (`CollectFeeScreen`) and the reports
**PDF preview** (`_PdfPreviewScreen`) were already de-nested in Phase 9 —
both render in `ShellPageBody` with restored back chevrons.

## 4. Known honest limitations

- **Hostel / transport tables don't exist.** `UnavailableHostelRepository`
  and `UnavailableTransportRepository` throw `BackendUnavailableException`
  on every call; providers map it to `backendUnavailable` states; the Phase 8
  hubs show honest dependency states (no fake rows).
- **Certificate issuance history / serial tracking backend-pending.**
  `UnavailableCertificateRepository` throws; the **generation** path (real
  branded Urdu PDFs via `ReportsService`, preview/print/share/save) is fully
  functional and independent of the repository.
- **Exam wizard step 7:** the `exams` table has no publish flag; the wizard
  states honestly that "شائع" = results live on the نتائج screen.
- **Hostel role dashboard** (`HostelDashboardScreen`) keeps its honest empty
  state until a hostel data source exists.
- No other `BackendUnavailableException` throw sites exist in `lib/`
  (verified by grep: only the three `Unavailable*` repositories).

## 5. Discrepancies (brief vs code)

1. **Fee-collection wizard / PDF preview are NOT nested Scaffolds.** The
   brief listed them under "retained nested Scaffolds". Code says otherwise:
   `collect_fee_screen.dart` header — "It now renders inside [ShellPageBody]
   — the AppShell keeps the only Scaffold/AppBar" (Phase 9 migration of the
   old `_CollectFeeFlow`); `_PdfPreviewScreen` — "AppShell owns the only
   Scaffold/AppBar, so the preview renders inside ShellPageBody".
2. **Three more dead files remain in the tree, not deleted:** the brief's
   list didn't include them and Phase 13 didn't remove them —
   `admin/admin_dashboard_screen.dart` (sole reference is a widget test),
   `admin/user_management_screen.dart` (legacy; sole reference is the dead
   admin dashboard), `providers/madrasa_provider.dart` (legacy
   `madrasas`-table provider; no references in `lib/presentation/`).
   Candidates for a follow-up pass.
3. **Old audit claims now false** (relevant when reading earlier docs):
   `lib/core/design/` is no longer dead (70+ importers of m360 components
   in `lib/presentation/`); `TenantPickerScreen` no longer bypasses
   `AppShell` (now `pushReplacement`s to it); `MasterAdminShell._backToApp()`
   no longer falls back to dead `MainScreen` (now `AppShell`); the global
   "no search" gap is closed by `command_palette.dart` (Ctrl+K, wired in
   `app_shell.dart`); `BackupScreen` is no longer unreachable (now the
   `backup` destination); the `planned:`/`PlannedScreen` placeholder
   mechanism is gone from `nav_destinations.dart`.
