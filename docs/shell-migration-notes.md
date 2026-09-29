# شیل مائیگریشن نوٹس — Phase 6 (2026-09-29)

`feat(shell): single AppShell with responsive RTL navigation, command search, no nested scaffolds`

## What changed

### One AppShell, one Scaffold
- `lib/presentation/shell/app_shell.dart` — the single root `Scaffold` for the
  whole post-login app. Layout: `MaterialApp → AppShell → Sidebar/TopBar/ContentArea`.
- Responsive: persistent right rail ≥ 1100px (`AppNavRail`), drawer on
  tablet/mobile, 4-primary bottom nav + "مزید" drawer below 600px (`MobileNavBar`).
- Role routing preserved: the "ڈیش بورڈ" destination's builder is
  `RoleHomeScreen`; permission filtering (`userPermissionsProvider` +
  `activeRoleKeysProvider`) is unchanged.

### Command palette (Ctrl+K)
- `lib/presentation/shell/command_palette.dart` — global search dialog:
  permission-filtered pages, quick commands (also permission-filtered),
  and client-side data search over already-loaded students / staff /
  darjas / fees (same documented limitation as `GlobalSearchPage`:
  only cached data is searchable — no fake server search).
- Keyboard: ↑/↓ move, Enter activates, Esc closes (explicit handler;
  the dialog is also barrier-dismissible). Ctrl+K / Cmd+K opens it from
  anywhere in the shell; a guard flag prevents stacking dialogs.
- Data results jump to the relevant in-shell list destination
  (`student-list`, `staff`, `darjas`, `fees`).

### Top bar (single header for the app)
- Back chevron on non-root destinations → dashboard (RTL-mirrored).
- Breadcrumb: group › destination (Nastaleeq).
- Global search trigger with visible `Ctrl+K` hint.
- Tenant chip: institution logo/name; opens the tenant picker only when
  the user has > 1 membership (single-tenant tap is a no-op).
- Notifications bell with unread badge → in-shell `notifications`
  destination (no duplicate pushed screen).
- Profile chip: avatar + name + role label → in-shell `profile`
  destination.

### Navigation rail restyle
- `app_nav_rail.dart`: full deep-teal gradient (`#0F6B63 → #094742`),
  white/soft-mint text, subtle selected state (white 14% + gold
  inline-start border). No raw `#009688`, no raw Nastaleeq font usage,
  no "جلد" pills anywhere in production UI.
- The rail footer's settings gear now selects the in-shell `profile`
  destination instead of pushing a duplicate `ProfileScreen`.

### Logout
- The "لاگ آؤٹ" destination is intercepted by `AppShell._select`:
  `M360ConfirmDialog` → `authProvider.notifier.logout()`. No stub.

### Route fixes
- `TenantPickerScreen._select` → `AppShell` (was bypassing the shell via
  `RoleHomeScreen`).
- `MasterAdminShell._backToApp` fallback → `AppShell` (was near-dead
  `MainScreen`).
- Principal dashboard "صارفین" → canonical `UserManagementHubScreen`
  (was legacy `UserManagementScreen`).

### Navigation catalog
- `nav_destinations.dart`: added "ترتیبات" group (profile, notifications,
  backup, about, logout); notifications moved out of "مرکزی"; "مالیات"
  group renamed "مالی نظام"; hostel → real `HostelDashboardScreen`;
  transport/certificates → honest `BackendUnavailableScreen`
  (backend missing per `docs/audit-backend-capabilities.md`).
- The `planned` flag is now purely internal (drives the unavailable
  screen); nothing production-visible says "جلد آرہا ہے".

### Chrome stripped (Scaffold/AppBar → ShellPageBody)
`ShellPageBody` (`lib/presentation/shell/shell_page_body.dart`) is the
interim no-chrome wrapper: preserves background color, former
`AppBar.actions` (slim toolbar), former `AppBar.bottom` TabBar (restyled
for the light body), `floatingActionButton`, and `bottomNavigationBar`
(attendance save CTA). Deep-pushed screens automatically get a back
chevron in the toolbar when the route can pop.

Stripped (17 screens + shared dashboard scaffold):
- admin: `darja_screen`, `student_list_screen`, `finance_screen`,
  `library_screen` (TabBar restyled: white-on-teal → teal-on-light),
  `staff_list_screen`, `fee_management_screen` (main; TabBar restyled)
- teacher: `attendance_screen` (sticky save bar kept via
  `bottomNavigationBar`), `results_screen` (TabBar restyled)
- common: `announcements_screen`, `notifications_screen` (language
  toggle + mark-read kept), `about_screen` (tenant SliverAppBar header
  kept as content chrome), `profile_screen`, `dashboard_guide_screen`
- parent: `fee_history_screen`
- dashboards: `my_classes_screen`, `my_students_screen`
- settings: `user_management_hub` (incl. the no-permission empty state)
- reports: `reports_hub_screen` (main; TabBar restyled)
- `DashboardScaffold` (shared by all 9 role dashboards): no longer
  builds its own Scaffold/AppBar. The old AppBar (madrasa title +
  profile avatar) duplicated the shell's tenant chip + profile chip.
  Dashboard `actions` (guide buttons, search, bell) now render in a
  slim row above the greeting header. The dead `madrasaName` parameter
  and its 9 call-site locals were removed.

### Intentionally KEPT Scaffold/AppBar (deep workflows)
- `fee_management_screen.dart` `_CollectFeeFlow` (~line 1043): the
  multi-step fee-collection wizard, pushed as its own page.
- `reports_hub_screen.dart` `_PdfPreviewScreen` (~line 526): the PDF
  preview page, pushed as its own page.
- User-management deep screens (`user_detail_screen`,
  `user_wizard_screen`, `scope_manager_screen`): standalone deep-page
  chrome until Phase 10.

## Deferred to Phase 10
- Full `PageContainer`/`PageHeader` conversion of every destination
  (replacing the interim `ShellPageBody` + slim toolbar).
- Dashboard visual redesign (Phase 7 owns dashboard look; Phase 6 only
  removed the nested chrome).
- `nav_destinations.dart`: consider renaming the internal `planned`
  flag to `backendDependency` for clarity.
- `GlobalSearchPage` (old standalone search): keep or retire once the
  palette proves sufficient — currently still reachable from the
  principal dashboard's search action.
- `MainScreen` (`screens/main_screen.dart`): ~~now unreferenced by the
  shell paths; decide whether to delete or repurpose.~~ **Phase 13: deleted**
  (its only remaining role, the `_backToApp()` fallback in
  `MasterAdminShell`, now targets `AppShell`).
- `admin_main_screen.dart` / `admin_dashboard_screen.dart`: ~~legacy
  screens still deep-push stripped screens (works via the automatic
  back chevron) — audit whether they should route in-shell instead.~~
  **Phase 13:** `admin_main_screen.dart` deleted; `admin_dashboard_screen.dart`
  remains with zero live references (only a widget test) — follow-up
  deletion candidate.

## Verification
- `dart format --set-exit-if-changed lib` → 0 changed (run at the repo's
  language version via `.dart_tool/package_config.json`, per AGENTS.md).
- Identifier audit: every provider, model field, and constructor
  referenced by the new/edited shell files was verified against its
  definition (`safeDarjaListProvider`, `allStudentsProvider`,
  `allStaffProvider`, `allFeesProvider`, `tenantMembershipsProvider`,
  `tenantBrandingProvider`, `currentUserProvider`,
  `userPermissionsProvider`, `activeRoleKeysProvider`,
  `roleServiceProvider.roleUrduLabel`, `unreadNotificationsCountProvider`,
  `Student.rollNo/darjaName`, `Staff.designation`, `Darja.nameUrdu`,
  `Fee.studentName/month/studentClass`, `M360SearchField(hint, autofocus)`,
  `showM360ConfirmDialog`, `BackupScreen`, `HostelDashboardScreen`).
- Flutter SDK is unavailable in this environment, so `dart analyze`
  cannot resolve `package:flutter/*` locally; **CI is the final
  analyzer/test gate** — do not merge until CI is green.
