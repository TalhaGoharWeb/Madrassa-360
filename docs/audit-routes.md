# Routes, Navigation & Screen-Structure Audit — Madrassa 360 (FINAL, Phase 13)

Branch: `redesign/ux-v2` · Working copy: `~/workspace/madrassa-redesign-fix`
Date: 2026-09-29 · Audit phase: **Phase 13 (final audit)**.

This document **supersedes the pre-Phase-13 snapshot** of this file (preserved in
git history). Every claim below was verified against the current working copy on
2026-09-29. The companion checklist + deletion log lives in
[phase13-final-audit.md](phase13-final-audit.md).

## 1. Architecture in one paragraph

Single `AppShell` (`lib/presentation/shell/app_shell.dart`), shell-based
navigation via the destination-id registry in
`lib/presentation/shell/nav_destinations.dart` — **no go_router**, no named
routes in the app. Bodies swap in place (`PageStorage` + `KeyedSubtree`); there
is no back stack inside the shell by design. Deep screens are pushed with
`MaterialPageRoute` (or a local `go()` helper doing the same) and rely on the
default back button. The platform console lives on the `/master` route
(`lib/main.dart`) behind `MasterAdminGuard`, mounted as `MasterAdminShell`.

## 2. The IA — 7 groups, 30 destinations (all real screens)

Verified from `kNavGroups` in `nav_destinations.dart`. Visibility: OR-semantics
over `requiredPermissions` (empty = all authenticated users) AND
`visibleForRoleKeys` (empty = no role filtering). The file's own rule —
"a destination may only point at a screen class that EXISTS in the repo" —
holds for all 30; the old `planned: true`/`PlannedScreen` mechanism is **gone**
(only a doc-comment mention remains). Hostel/transport/certificates are real
Phase 8 hub screens whose *data layers* are backend-pending (see §6).

### مرکزی (markazi)

| id | Label | Screen | Visibility |
|---|---|---|---|
| `dashboard` | ڈیش بورڈ | `RoleHomeScreen` (role router) | all users |
| `announcements` | اعلانات | `AnnouncementsScreen` (badge: announcement count) | all users |
| `guide` | رہنمائی | `DashboardGuideScreen(roleKey: 'generic')` | all users |

### طلبہ (students)

| id | Label | Screen | Visibility |
|---|---|---|---|
| `student-list` | طلبہ کی فہرست | `StudentListScreen` | `students.view/create/edit` (any) |
| `my-classes` | میری جماعتیں | `MyClassesScreen` | `teachers.view`/`darjas.view`/`students.view` (any) |
| `my-students` | میرے طلبہ | `MyStudentsScreen` | role keys `teacher`, `ustad`, `ustad_hifz` |
| `parent-fees` | فیس کا ریکارڈ | `FeeHistoryScreen` | role key `parent` |

### تعلیمی نظام (academics)

| id | Label | Screen | Visibility |
|---|---|---|---|
| `darjas` | درجات | `DarjaScreen` | `darjas.view`/`darjas.manage` (any) |
| `exams` | امتحانات | `ExamDashboardScreen` | `exams.view/create/manage` (any) |
| `results` | نتائج | `ResultsScreen` | `results.view`/`enter`/`publish` (any) |

### حاضری (attendance)

| id | Label | Screen | Visibility |
|---|---|---|---|
| `attendance` | حاضری لگائیں | `AttendanceScreen` | `attendance.mark`/`view` (any) |

### مالی (finance) — Phase 9 unified finance experience

All eight destinations render `FinanceHubScreen` with a `FinanceSection`:
dashboard, dues, invoices, payments, ledger, expenses, reports (replacing the
old separate `FeeManagementScreen`/`FinanceScreen` destinations; the standalone
`FeeManagementScreen` remains reachable at `student_fees` and is pushed to by
fee quick actions).

| id | Label | Section | Visibility |
|---|---|---|---|
| `finance_dashboard` | مالی ڈیش بورڈ | `FinanceSection.dashboard` | `viewFinance`/`viewFees` (any) |
| `student_fees` | طلبہ کی فیس | `FeeManagementScreen` | `collectFees`/`viewFees` (any) |
| `finance_dues` | واجبات | `FinanceSection.dues` | `collectFees`/`viewFees` (any) |
| `finance_invoices` | انوائسز | `FinanceSection.invoices` | `viewFinance`/`approveFinance` (any) |
| `finance_payments` | ادائیگیاں | `FinanceSection.payments` | `viewFinance`/`approveFinance` (any) |
| `finance_ledger` | لیجر | `FinanceSection.ledger` | `viewFinance`/`approveFinance` (any) |
| `finance_expenses` | اخراجات | `FinanceSection.expenses` | `viewFinance`/`approveFinance` (any) |
| `finance_reports` | مالی رپورٹس | `FinanceSection.reports` | `viewReports`/`exportReports` (any) |

### ادارہ (institution)

| id | Label | Screen | Visibility |
|---|---|---|---|
| `staff` | عملہ | `StaffListScreen` | `staff.view`/`teachers.view` (any) |
| `library` | کتب خانہ | `LibraryScreen` | `library.view`/`manage` (any) |
| `users-roles` | صارفین و کردار | `UserManagementHubScreen` | `users.view`/`roles.assign` (any) |
| `hostel` | دارالاقامہ | `HostelScreen` (Phase 8 hub) | `hostel.view`/`manage` (any) |
| `transport` | ٹرانسپورٹ | `TransportScreen` (Phase 8 hub) | `transport.view`/`manage` (any) |
| `certificates` | اسناد | `CertificatesScreen` (Phase 8) | `certificates.view`/`issue` (any) |

### ترتیبات (settings) — new group in Phase 9/13

| id | Label | Screen | Visibility |
|---|---|---|---|
| `profile` | پروفائل | `ProfileScreen` | all users |
| `notifications` | اطلاعات | `NotificationsScreen` (badge: unread count) | all users |
| `backup` | بیک اپ | `BackupScreen` | `manageSettings` |
| `about` | ادارے کے بارے میں | `AboutScreen` | all users |
| `logout` | لاگ آؤٹ | intercepted: `AppShell._confirmLogout()` (M360 confirm + sign-out); stub never rendered | all users |

`logout` is handled in `AppShell._select` via `kLogoutDestinationId`
(`app_shell.dart:50,72`); `shellNavRequestProvider` requests never trigger it
(`app_shell.dart:117`).

### Mobile bottom nav

`kMobilePrimaryIds` (`nav_destinations.dart:616`):
`dashboard`, `student-list`, `attendance`, **`student_fees`** + "مزید" drawer.
Phase 13 fixed the stale `'fees'` id → `'student_fees'`: the old id matched no
destination, so mobile users silently lost the fees tab. Primaries are
permission-filtered per user; missing ones fall back to the next visible.

### Shell chrome

- Desktop (≥1100px): persistent right-side `AppNavRail` (264px, teal-gradient
  branding header, grouped collapsible destinations, badges, `_UserFooter` +
  settings footer). Tablet (600–1099px): rail content in a drawer. Mobile
  (<600px): `MobileNavBar` bottom nav + "مزید".
- Top bar: breadcrumb `group › destination` (Nastaleeq), madrassa switcher
  (multi-membership only → pushes `TenantPickerScreen`), notifications bell with
  unread badge (pushes `NotificationsScreen`), and a **command palette**
  (Ctrl+K search over visible destinations, `command_palette.dart`) — the old
  "no global search" gap is closed.

## 3. Role → dashboard (`RoleHomeScreen`, `role_home.dart`)

**Teacher single-shell change (Phase 13):** `dashboards/teacher_home.dart`
(`TeacherHomeScreen`, the nested 5-tab bottom-nav shell) is **deleted**.
Teacher-family role keys (`teacher`, `ustad`, `ustad_hifz`) now render
`TeacherDashboardScreen` directly (line 91; it's a `DashboardScaffold`-based
body — no nested Scaffold/AppBar of its own). Its quick actions navigate via
`requestShellNav(ref, …)` (`lib/presentation/shell/shell_nav.dart`) —
`'attendance'`, `'my-students'`, `'results'` — consumed once by
`AppShell` (`app_shell.dart:110-120`); pushes to
`AnnouncementsScreen`/`ProfileScreen`/`DashboardGuideScreen`/platform console
remain plain `MaterialPageRoute` (those screens are also shell destinations,
so the pushed copies render with a back chevron).

Other mappings (unchanged): `daftar_dar` → Clerk; `accountant`/`nazim_maliyat`
→ Accountant; `nazim_taleem`/`nazim_hifz` → AcademicAdmin;
`nazim_darul_iqama`/`warden`/`hostel_manager` → Hostel (honest empty state);
`librarian` → Library; `mumtahin` → Exam; permission-derived `isPrincipal()`
→ Principal; `parent`/`student` → Generic; anything else → Principal (sections
self-gate) / Generic fallback (never blank). Platform operators with zero
tenant memberships land here with a "پلیٹ فارم کنسول" entry to `/master`.

## 4. Auth routing (unchanged in Phase 13)

`AuthGate`: splash → `LoginScreen` | `AppShell` (home) | `TenantPickerScreen`
| `NoAccessScreen`. **Fixed since the old snapshot:** `TenantPickerScreen`
now `pushReplacement`s to `AppShell` (`tenant_picker_screen.dart:55`) instead
of pushing `RoleHomeScreen` past the shell. Auth screens keep their own
Scaffolds — outside AppShell by design (§5).

## 5. Retained nested Scaffolds — with reasons

The shell owns the only top-level Scaffold for in-shell destinations (they
render via `ShellPageBody`/`PageContainer`). Nested Scaffolds survive only
where the screen lives **outside** the shell or is a **pushed full-screen
route**:

| Screen | Own Scaffold? | Why retained |
|---|---|---|
| `auth/login_screen.dart` (also forgot-password, tenant-picker, no-access) | yes | Outside `AppShell` by design — auth flow renders instead of the shell |
| `dashboards/exam_wizard_screen.dart` | yes | Pushed full-screen 8-step wizard; never a shell destination |
| `settings/user_wizard_screen.dart`, `user_detail_screen.dart`, `delegation_screen.dart`, `delegation_create_screen.dart`, `scope_manager_screen.dart` | yes (4/1/2/1/3 Scaffold sites) | Pushed deep screens from `UserManagementHubScreen`; default back button |
| `students/student_profile_screen.dart` | yes | Pushed from `StudentListScreen` row tap |
| `master_admin/master_admin_shell.dart` | yes | Separate `/master` platform console; outside the tenant `AppShell` |
| `finance/collect_fee_screen.dart` | **no** — renders in `ShellPageBody` | Phase 9 migration: the old `_CollectFeeFlow` nested Scaffold was removed; the wizard works both as a pushed screen and a shell-hub route |
| `reports/_PdfPreviewScreen` | **no** — renders in `ShellPageBody` with a `PageHeader` | Same rationale; deep-pushed preview with restored back chevron |

**Correction vs the Phase 13 task brief:** the brief listed the fee-collection
wizard and PDF preview as "retained nested Scaffolds". In the actual code both
were de-nested (Phase 9) — see their header comments. No other in-shell
destination carries its own Scaffold.

## 6. Honest backend-pending states (not fake UI)

- `hostel` / `transport`: `UnavailableHostelRepository` /
  `UnavailableTransportRepository` throw `BackendUnavailableException` on
  every call (`lib/data/repositories/hostel_repository.dart`,
  `transport_repository.dart`); providers catch it into
  `HostelState.backendUnavailable` / `TransportState.backendUnavailable`
  (`hostel_provider.dart`, `transport_provider.dart`). The Phase 8 hubs
  (buildings→rooms→beds→allocations; vehicles/drivers/routes/assignments)
  render honest dependency states.
- `certificates`: `UnavailableCertificateRepository` throws for issuance
  history and serial tracking (no issuance table yet,
  `certificate_repository.dart:87`). The **generation** path is real: PDF
  certificates through `ReportsService`, live preview/print/share/save.
- `HostelDashboardScreen` keeps its honest empty state ("no hostel data
  source yet").
- Exam wizard step 7: the `exams` table has no publish flag — "شائع" means
  entered results are live on the نتائج screen; the wizard says exactly that.

No other `BackendUnavailableException` throw sites exist in `lib/`.

## 7. Dead code — status after Phase 13

**Deleted (verified gone; see deletion log in phase13-final-audit.md):**
`admin/admin_main_screen.dart`, `screens/main_screen.dart`,
`parent/parent_dashboard_screen.dart`, `parent/parent_main_screen.dart`,
`teacher/teacher_dashboard_screen.dart`, the entire
`screens/super_admin/` directory (3 files), `dashboards/teacher_home.dart`,
`core/widgets/confirm_dialog.dart`, `core/widgets/custom_buttons.dart`,
`core/widgets/loading_overlay.dart`, `presentation/widgets/app_drawer.dart`,
`presentation/widgets/profile_avatar_button.dart`. Zero imports of any of them
remain in `lib/` or `test/`.

**Still present but unreferenced (left by Phase 13 — candidates for a follow-up
pass):** `admin/admin_dashboard_screen.dart` (only reference is a widget test),
`admin/user_management_screen.dart` (legacy; only reference is the dead admin
dashboard), `providers/madrasa_provider.dart` (legacy `madrasas`-table
provider; no references in `lib/presentation/`).

**Resolved old gaps:** `MasterAdminShell._backToApp()` now falls back to
`AppShell` (was dead `MainScreen`); `BackupScreen` is a live `backup`
destination (was unreachable); the m360 design system is wired
(70+ importers in `lib/presentation/` — the old "100% dead design system"
claim no longer holds; deletions of `custom_buttons`/`confirm_dialog`
consolidated on it); `TenantPickerScreen` routes into `AppShell`.

## Appendix — counts (final)

- Shell destinations: **30** across **7 groups** (all real screens; `logout`
  is an intercepted action). No planned/coming-soon destinations remain.
- Auth routes: 5 screens (`login`, `forgot_password`, `tenant_picker`,
  `no_access`, gate) behind `AuthRoute`.
- Role dashboards via `RoleHomeScreen`: 10 (clerk, accountant, academic-admin,
  hostel, library, exam, teacher, principal, generic ×2 paths).
- Platform console: `/master` → `MasterAdminShell` (11 screens + widget kit).
