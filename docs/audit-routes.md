# Routes, Navigation & Screen-Structure Audit — Madrassa 360

Branch: `redesign/ux-v2` · Working copy: `~/workspace/madrassa-redesign-fix`
Date: 2026-09-29 · Scope: `lib/presentation/screens/` (67 files), `lib/presentation/shell/`, auth routing.

This is a read-only audit. No code was changed. Every claim below is grounded in the
source files named.

---

## 1. Route inventory — all 67 screen files

No named-route table exists in the app; navigation is widget-direct
(`MaterialPageRoute(builder: …)`) plus the shell's destination-id registry
(`nav_destinations.dart`). "Route" below therefore means the screen file/class
and how it is reached.

### 1a. `admin/` (10 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `admin/admin_dashboard_screen.dart` | `AdminDashboardScreen` | Legacy tenant admin dashboard: live stats + module cards gated by permissions and enabled modules. **DEAD** — only mounted inside dead `AdminMainScreen`. |
| `admin/admin_main_screen.dart` | `AdminMainScreen` | Legacy permission-driven bottom-nav shell ("All 11 staff roles land here"). **DEAD** — zero external references. |
| `admin/backup_screen.dart` | `BackupScreen` | One-file offline backup & restore UI (backup now, verify, restore with typed confirmation, list, delete). **UNREACHABLE** — only referenced from dead `AdminDashboardScreen`. |
| `admin/darja_screen.dart` | `DarjaScreen` | درجات (classes/levels) management: level headers + darja cards, CRUD. |
| `admin/fee_management_screen.dart` | `FeeManagementScreen` | Fee collection: وصولی tab with tenant collection stats + recent receipts, "نیا واؤچر" FAB flow. |
| `admin/finance_screen.dart` | `FinanceScreen` | Financial ledger: invoice → payment → receipt → ledger; posted rows immutable, delete only on drafts. |
| `admin/library_screen.dart` | `LibraryScreen` | Library: books list + issues list (issue/return). |
| `admin/staff_list_screen.dart` | `StaffListScreen` | عملہ کی فہرست — staff list for admin. |
| `admin/student_list_screen.dart` | `StudentListScreen` | Student list: filters, create/edit/fee dialogs; row tap opens `StudentProfileScreen`. |
| `admin/user_management_screen.dart` | `UserManagementScreen` | **Legacy** admin CRUD for user accounts + roles/permissions tabs. Superseded by `settings/user_management_hub.dart` but still deep-pushed from `PrincipalDashboardScreen` (line 1102). |

### 1b. `auth/` (5 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `auth/auth_gate.dart` | `AuthGate` | Cold-start entry: restores session behind a branded splash, then renders per `AuthRoute` (AppShell / TenantPicker / NoAccess / Login). |
| `auth/forgot_password_screen.dart` | `ForgotPasswordScreen` | Sends Supabase password-reset email, shows success state. |
| `auth/login_screen.dart` | `LoginScreen` | Email+password login with "remember me"; post-login navigation follows `AuthRoute`. |
| `auth/no_access_screen.dart` | `NoAccessScreen` | Signed in but no active tenant membership (and not a platform admin); offers sign-out / contact admin. |
| `auth/tenant_picker_screen.dart` | `TenantPickerScreen` | Shown when the user has >1 active membership; tap selects tenant via `TenantContext`. |

### 1c. `common/` (5 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `common/about_screen.dart` | `AboutScreen` | Product + tenant (institution) info, contact; institution identity from `tenantBrandingProvider`. |
| `common/announcements_screen.dart` | `AnnouncementsScreen` | Published announcements list (badge-count hooked in shell). |
| `common/dashboard_guide_screen.dart` | `DashboardGuideScreen` | Urdu "how to use" guide (`roleKey` param, 'generic' from shell); `DashboardGuideButton` opens it from dashboards. |
| `common/notifications_screen.dart` | `NotificationsScreen` | In-app notifications list; header action marks all read; Urdu-first with English toggle. |
| `common/profile_screen.dart` | `ProfileScreen` | Account profile + settings tiles (doc comment still says "Placeholder for Phase 1" but the file is 888 lines of real UI; also hosts entry points to `UserManagementHubScreen`, `DelegationScreen`, backup-related tiles). |

### 1d. `dashboards/` (13 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `dashboards/academic_admin_dashboard.dart` | `AcademicAdminDashboardScreen` | Dashboard for `nazim_taleem`/`nazim_hifz`: درجات، اساتذہ، طلبہ، آج حاضری، زیرِ تکمیل نتائج; launches `ExamWizardScreen`. |
| `dashboards/accountant_dashboard.dart` | `AccountantDashboardScreen` | Dashboard for `accountant`/`nazim_maliyat`: آج کی وصولی، اخراجات، بقایا فیس، نقد رقم + tasks. |
| `dashboards/clerk_dashboard.dart` | `ClerkDashboardScreen` | Dashboard for `daftar_dar` (clerk): new admissions (last 7 days), alerts, quick actions, tasks. |
| `dashboards/exam_dashboard.dart` | `ExamDashboardScreen` | Dashboard for `mumtahin`: جاری امتحانات، نمبر درج ہونا باقی، نتائج تیار; launches `ExamWizardScreen`. |
| `dashboards/exam_wizard_screen.dart` | `ExamWizardScreen` | Step-by-step exam creation wizard (one step visible at a time). |
| `dashboards/hostel_dashboard.dart` | `HostelDashboardScreen` | Dashboard for hostel roles; **honest empty state** — "no hostel data source in the app yet", not a fake dashboard. |
| `dashboards/library_dashboard.dart` | `LibraryDashboardScreen` | Dashboard for `librarian`: کل کتب، جاری شدہ، واپسی باقی. |
| `dashboards/my_classes_screen.dart` | `MyClassesScreen` | Teacher's own assigned classes only (Phase 7a). |
| `dashboards/my_students_screen.dart` | `MyStudentsScreen` | Students aggregated across the teacher's assigned classes only. |
| `dashboards/principal_dashboard.dart` | `PrincipalDashboardScreen` | Principal dashboard: key metrics, fake search field → `GlobalSearchPage`, today's tasks, attendance summary, pending fees, recent admissions, announcements, upcoming exams, departments. Sections self-gate on permissions + enabled modules. |
| `dashboards/role_home.dart` | `RoleHomeScreen` | **Role router** (post-login home): maps role keys → dashboard; also hosts `GenericDashboardScreen` fallback ("never blank"). |
| `dashboards/teacher_dashboard.dart` | `TeacherDashboardScreen` | Phase 7a teacher dashboard: greeting + 4 cards (used inside `TeacherHomeScreen`). |
| `dashboards/teacher_home.dart` | `TeacherHomeScreen` | Teacher tab shell: ڈیش بورڈ، میری جماعتیں، میرے طلبہ، حاضری، امتحانات (tabs gated by permission-derived capabilities). |

### 1e. `main_screen.dart` (1 file)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `main_screen.dart` | `MainScreen` | Legacy Phase-1 teacher bottom-nav wrapper (teacher dashboard + attendance + results + profile). **Near-dead** — only referenced as a fallback `pushReplacement` in `MasterAdminShell._backToApp()` when the navigator stack is empty. |

### 1f. `master_admin/` (11 files + widgets)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `master_admin/audit_logs_screen.dart` | `AuditLogsScreen` | Platform-wide audit trail rendered as human-readable Urdu ("who did what to what, when"). |
| `master_admin/create_madrasa_wizard.dart` | `CreateMadrasaWizard` | 5-step tenant provisioning wizard (institution details → defaults → license plan → …). |
| `master_admin/licenses_screen.dart` | `LicensesScreen` | Licenses table (issued by provision-tenant); read-mostly, issue/revoke are server-side. |
| `master_admin/madrasa_detail_screen.dart` | `MadrasaDetailScreen` | Tenant detail: editable info, module toggles, lifecycle actions (suspend/reactivate/archive) via manage-tenant Edge Function; destructive actions need typed confirmation. |
| `master_admin/madrasa_list_screen.dart` | `MadrasaListScreen` | Searchable, filterable, paginated tenant list; tap → `MadrasaDetailScreen`. |
| `master_admin/master_admin_shell.dart` | `MasterAdminShell` | Drawer navigation for all platform-operator sections; mounted behind `MasterAdminGuard` on the `/master` route; "Back to app" fallback. |
| `master_admin/master_dashboard_screen.dart` | `MasterDashboardScreen` | Platform KPIs + honest system health checks (licensing tables driven). |
| `master_admin/modules_screen.dart` | `ModulesScreen` | Platform-wide module catalog view (`modules_catalog`, seeded by migration 003); per-tenant enablement on the madrasa detail screen. |
| `master_admin/plans_screen.dart` | `PlansScreen` | Full CRUD on `license_plans` (create/edit/activate/deactivate/delete; delete blocked by FK). |
| `master_admin/platform_users_screen.dart` | `PlatformUsersScreen` | Manage platform operators (`platform_admins`) with roles. |
| `master_admin/subscriptions_screen.dart` | `SubscriptionsScreen` | `tenant_subscriptions` overview with status filter and expiry highlighting (≤30 days amber, expired red). |
| `master_admin/widgets/ma_widgets.dart` | `MaStatCard`, `MaSectionCard`, `MaHealthTile`, `MaStatusChip`, `MaLoadingScaffold`, `MaErrorScaffold` | Shared master-admin UI kit (stat cards, section cards, health tiles, status chips, loading/error scaffolds). Not a screen. |

### 1g. `parent/` (3 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `parent/fee_history_screen.dart` | `FeeHistoryScreen` | فیس کی تاریخ — fee history for parents; in the shell's طلبہ group, `visibleForRoleKeys: ['parent']`. |
| `parent/parent_dashboard_screen.dart` | `ParentDashboardScreen` | Parent dashboard (children via `student_guardians` link + active tenant; scoped providers). **DEAD** — only referenced from dead `ParentMainScreen`. |
| `parent/parent_main_screen.dart` | `ParentMainScreen` | Parent bottom-nav shell (home/fees/profile). **DEAD** — zero external references; parent role routes to `GenericDashboardScreen` via `RoleHomeScreen`. |

### 1h. `reports/` (1 file)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `reports/reports_hub_screen.dart` | `ReportsHubScreen` (+ internal `_PdfPreviewScreen`) | Report catalog with two tabs (طلبہ / انتظامیہ), filter bottom-sheet, PDF preview screen. |

### 1i. `settings/` (7 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `settings/delegation_create_screen.dart` | `DelegationCreateScreen` | New delegation flow: pick tenant user → pick permissions (capped at the delegator's own effective set). |
| `settings/delegation_screen.dart` | `DelegationScreen` | Delegation management: lists active delegations (who→whom, what, expiry), revoke. |
| `settings/role_ux_widgets.dart` | `ActiveBadge`, `RoleBadge`, `UxSectionTitle`, `UxEmptyState`, `UxCard` | Shared role/user-management UX widgets. Not a screen. |
| `settings/scope_manager_screen.dart` | `ScopeManagerScreen` (+ `ScopeEditorScreen`) | Data-scopes management for madrasa admins (`roles.assign`). |
| `settings/user_detail_screen.dart` | `UserDetailScreen` | User detail: name, Urdu responsibility label, active status, assigned classes, responsibility checklist, management actions. |
| `settings/user_management_hub.dart` | `UserManagementHubScreen` | Central user-management hub: `صارفین` and `ذمہ داریاں` tabs; entry to wizard/detail/delegation/scope screens. |
| `settings/user_wizard_screen.dart` | `UserWizardScreen` | 5-step user creation/edit wizard, plain Urdu throughout. |

### 1j. `students/` (3 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `students/student_dialogs.dart` | `StudentDialogs` | Shared student create/edit dialogs + `_LabeledField`, `_PhotoPicker` helpers. Not a screen. |
| `students/student_profile_screen.dart` | `StudentProfileScreen` | Student profile hub: identity header, overview/personal/attendance/fees/exams tabs; stat cards. Deep-pushed from `StudentListScreen` row tap. |
| `students/student_widgets.dart` | `StudentAvatar`, `SectionDivider`, `SectionHeading` | Shared student presentation widgets (avatar, fee badge, attendance badge). Not a screen. |

### 1k. `super_admin/` (3 files) — ALL DEPRECATED, ALL DEAD

| File | Main class | Purpose (1 line) |
|---|---|---|
| `super_admin/madrasa_management_screen.dart` | `MadrasaManagementScreen` | `@deprecated` Phase-3 legacy madrasa management; superseded by master_admin screens. **Zero references.** |
| `super_admin/super_admin_dashboard_screen.dart` | `SuperAdminDashboardScreen` | `@deprecated` legacy single-tenant super-admin dashboard. **Zero references.** |
| `super_admin/super_admin_main_screen.dart` | `SuperAdminMainScreen` | `@deprecated` legacy super-admin shell. **Zero references.** |

### 1l. `teacher/` (3 files)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `teacher/attendance_screen.dart` | `AttendanceScreen` | Attendance marking (حاضری لگائیں). In shell's حاضری group. |
| `teacher/results_screen.dart` | `ResultsScreen` | Results entry/view (نتائج). In shell's تعلیمی نظام group. |
| `teacher/teacher_dashboard_screen.dart` | `TeacherDashboardScreen` | **Legacy** Phase-4 teacher dashboard (name collides with `dashboards/teacher_dashboard.dart`). **DEAD** — only referenced from dead `main_screen.dart`. |

### 1m. `crash_screen.dart` (1 file)

| File | Main class | Purpose (1 line) |
|---|---|---|
| `crash_screen.dart` | `CrashScreen` | Bilingual Urdu/English fatal-error screen (failed bootstrap / uncaught async error), mounted from `lib/main.dart`. |

**File-type note:** 5 of the 67 files are widget/dialog libraries, not screens:
`master_admin/widgets/ma_widgets.dart`, `settings/role_ux_widgets.dart`,
`students/student_dialogs.dart`, `students/student_widgets.dart`
(and `reports_hub_screen.dart` contains the internal `_PdfPreviewScreen`).

---

## 2. Navigation map — `lib/presentation/shell/`

Files: `nav_destinations.dart` (single source of truth for the IA),
`app_shell.dart` (responsive scaffold), `app_nav_rail.dart` (desktop rail / drawer),
`mobile_nav.dart` (bottom nav).

### 2a. Shell layout

- **Desktop (≥1100px):** persistent RIGHT-side `AppNavRail` (264px, teal-gradient
  branding header with tenant logo/name, grouped collapsible destinations,
  permission-filtered, badges, bottom user-profile + settings footer).
- **Tablet (600–1099px):** same rail content inside a drawer.
- **Mobile (<600px):** `MobileNavBar` bottom nav — 4 primary tabs + "مزید"
  (opens the full drawer). If the active destination is drawer-only, "مزید"
  renders active.
- **Top app bar** (`_ShellAppBar`, teal): breadcrumb `group › destination` in
  Nastaleeq, madrassa switcher (only when the user has >1 membership → pushes
  `TenantPickerScreen`), notifications bell with unread badge (pushes
  `NotificationsScreen`).
- Selection state is a destination-id string; bodies are swapped in place
  (`PageStorage` + `KeyedSubtree`), **not** pushed — so in-shell navigation has
  no back stack by design. Deep screens pushed via `Navigator.push` get the
  default AppBar back button.
- Explicitly documented in `app_shell.dart`: **no global-search trigger**
  ("no global search exists in the repo"); the principal dashboard's search
  field is a tappable fake that opens `GlobalSearchPage`
  (`lib/presentation/widgets/global_search.dart`, client-side search only).

### 2b. All destinations (6 groups, 22 items — 19 real, 3 planned)

Visibility: `requiredPermissions` (OR semantics — user needs ANY; empty = all
authenticated users) AND `visibleForRoleKeys` (role_home template keys; empty =
no role filtering). `planned: true` renders the shared "جلد آرہا ہے"
`PlannedScreen` with a "جلد" pill in the rail.

**مرکزی (markazi)**
| id | Label | Icon | Screen | Visibility |
|---|---|---|---|---|
| `dashboard` | ڈیش بورڈ | `dashboard_outlined` | `RoleHomeScreen` (role router) | all users |
| `announcements` | اعلانات | `campaign_outlined` | `AnnouncementsScreen` (badge: announcement count) | all users |
| `notifications` | اطلاعات | `notifications_outlined` | `NotificationsScreen` (badge: unread count) | all users |
| `guide` | رہنمائی | `help_outline` | `DashboardGuideScreen(roleKey: 'generic')` | all users |

**طلبہ (students)**
| id | Label | Icon | Screen | Visibility |
|---|---|---|---|---|
| `student-list` | طلبہ کی فہرست | `school_outlined` | `StudentListScreen` | `students.view/create/edit` (any) |
| `my-classes` | میری جماعتیں | `class_outlined` | `MyClassesScreen` | `teachers.view`/`darjas.view`/`students.view` (any) |
| `my-students` | میرے طلبہ | `groups_outlined` | `MyStudentsScreen` | role keys `teacher`, `ustad`, `ustad_hifz` only |
| `parent-fees` | فیس کا ریکارڈ | `receipt_long_outlined` | `FeeHistoryScreen` | role key `parent` only |

**تعلیمی نظام (academics)**
| id | Label | Icon | Screen | Visibility |
|---|---|---|---|---|
| `darjas` | درجات | `layers_outlined` | `DarjaScreen` | `darjas.view`/`darjas.manage` (any) |
| `exams` | امتحانات | `assignment_outlined` | `ExamDashboardScreen` | `exams.view/create/manage` (any) |
| `results` | نتائج | `grade_outlined` | `ResultsScreen` | `results.view`/`enter`/`publish` (any) |

**حاضری (attendance)**
| id | Label | Icon | Screen | Visibility |
|---|---|---|---|---|
| `attendance` | حاضری لگائیں | `fact_check_outlined` | `AttendanceScreen` | `attendance.mark`/`attendance.view` (any) |

**مالیات (finance)**
| id | Label | Icon | Screen | Visibility |
|---|---|---|---|---|
| `fees` | فیس وصولی | `payments_outlined` | `FeeManagementScreen` | `fees.collect`/`fees.view` (any) |
| `ledger` | مالیاتی کھاتہ | `account_balance_wallet_outlined` | `FinanceScreen` | `finance.view`/`finance.approve` (any) |
| `reports` | رپورٹیں | `bar_chart_outlined` | `ReportsHubScreen` | `reports.view`/`reports.export` (any) |

**ادارہ (institution)**
| id | Label | Icon | Screen | Visibility |
|---|---|---|---|---|
| `staff` | عملہ | `badge_outlined` | `StaffListScreen` | `staff.view`/`teachers.view` (any) |
| `library` | کتب خانہ | `local_library_outlined` | `LibraryScreen` | `library.view`/`library.manage` (any) |
| `users-roles` | صارفین و کردار | `manage_accounts_outlined` | `UserManagementHubScreen` | `users.view`/`roles.assign` (any) |
| `hostel` | دارالاقامہ | `hotel_outlined` | `PlannedScreen` ("جلد آرہا ہے") | `hostel.view`/`hostel.manage` |
| `transport` | ٹرانسپورٹ | `directions_bus_outlined` | `PlannedScreen` ("جلد آرہا ہے") | `transport.view`/`transport.manage` |
| `certificates` | اسناد | `workspace_premium_outlined` | `PlannedScreen` ("جلد آرہا ہے") | `certificates.view`/`certificates.issue` |
| `about` | ادارے کے بارے میں | `info_outline` | `AboutScreen` | all users |

**Mobile bottom nav** (`kMobilePrimaryIds`): `dashboard`, `student-list`,
`attendance`, `fees` + "مزید" drawer. Primaries are permission-filtered per
user; missing ones fall back to the next visible.

### 2c. Role → dashboard mapping (`RoleHomeScreen`, used by the `dashboard` destination)

Order matters (first match wins):

1. role keys empty → `GenericDashboardScreen`
2. `teacher`, `ustad`, `ustad_hifz` → `TeacherHomeScreen` (tab shell)
3. `parent`, `student` → `GenericDashboardScreen`
4. `daftar_dar` → `ClerkDashboardScreen`
5. `accountant`, `nazim_maliyat` → `AccountantDashboardScreen`
6. `nazim_taleem`, `nazim_hifz` → `AcademicAdminDashboardScreen`
7. `nazim_darul_iqama`, `warden`, `hostel_manager` → `HostelDashboardScreen`
8. `librarian` → `LibraryDashboardScreen`
9. `mumtahin` → `ExamDashboardScreen`
10. `roleService.isPrincipal()` (permission-derived, not role-name matching) → `PrincipalDashboardScreen`
11. any other staff role → `PrincipalDashboardScreen` (sections self-gate on permissions)
12. fallback → `GenericDashboardScreen` (never blank; greeting + announcements + profile)

Platform operators with zero tenant memberships land here too, with a
"پلیٹ فارم کنسول" entry into the guarded `/master` route.

**Note:** there is no `isSuperAdmin` anywhere in this branch. Platform access
is `isPlatformAdmin` (row in `platform_admins`), routed to `AuthRoute.home`
→ `AppShell`, with the master console at `/master` behind `MasterAdminGuard`.
There is no separate super-admin dashboard route in the current flow.

---

## 3. AuthGate routing — full decision tree

Files: `lib/presentation/screens/auth/auth_gate.dart`,
`lib/providers/auth_provider.dart` (549 lines; `AuthNotifier`, `AuthState`, `AuthRoute`).

### 3a. Cold start (`AuthGate`)

1. Branded splash (`_Splash`) while `AuthNotifier.restoreSession()` runs.
   `restoreSession()` honors the "remember me" flag — if unchecked, the
   persisted session is signed out instead of restored.
2. After restore settles:
   - `!isAuthenticated` → `LoginScreen`
   - `AuthRoute.home` → `AppShell`
   - `AuthRoute.tenantPicker` → `TenantPickerScreen`
   - `AuthRoute.noAccess` → `NoAccessScreen`
   - `AuthRoute.login` → `LoginScreen`

### 3b. Route resolution (`_resolveRoute`, after `_handleSignedIn`)

Inputs: active `memberships` (tenant_memberships), `isPlatformAdmin`
(row in `platform_admins`; any failure incl. RLS denial = not admin),
`tenantLoadOk` (whether the tenant/membership fetch succeeded).

```
memberships.isEmpty?
├─ YES → isPlatformAdmin?
│         ├─ YES → home        (master admin area; enters AppShell, console via RoleHome)
│         └─ NO  → tenantLoadOk?
│                   ├─ NO  → restored activeTenantId != null ? home : noAccess
│                   │         (offline leniency: previously restored tenant lets the user in)
│                   └─ YES → noAccess
├─ NO → memberships.length == 1 ? home        (tenant auto-selected by init())
│       : memberships.length > 1 ? tenantPicker
```

### 3c. Session lifecycle events (Supabase `authStateChanges`)

- `signedIn` → `_handleSignedIn()` (idempotent; user → tenant context init →
  memberships → platform-admin check → permissions via `AuthorizationService`
  → route).
- `tokenRefreshed` / `userUpdated` → `_refreshSessionUser()` (refresh user +
  permissions, **keep current route**; refresh failure never logs the user out).
- `signedOut` (incl. expired/revoked refresh tokens) → `_handleSignedOut()`
  (clears auth/role/delegation caches + persisted permission cache + active
  tenant; state → `unauthenticated`, route → `login`).
- `selectTenant(tenantId)` → persists choice, reloads permissions, route → `home`.

**Routing state machine summary:** `login ⇄ home / tenantPicker / noAccess`,
with `home` meaning "AppShell (role-routed dashboard) for tenants, master
console entry for platform admins".

---

## 4. Dead / placeholder screens

### 4a. Fully dead code (zero references outside their own file)

| File | Class | Evidence |
|---|---|---|
| `super_admin/madrasa_management_screen.dart` | `MadrasaManagementScreen` | `@deprecated`; no references in `lib/` or `test/` |
| `super_admin/super_admin_dashboard_screen.dart` | `SuperAdminDashboardScreen` | `@deprecated`; no references |
| `super_admin/super_admin_main_screen.dart` | `SuperAdminMainScreen` | `@deprecated`; no references |
| `admin/admin_main_screen.dart` | `AdminMainScreen` | no external references |
| `parent/parent_main_screen.dart` | `ParentMainScreen` | no external references |
| `teacher/teacher_dashboard_screen.dart` | `TeacherDashboardScreen` (legacy) | only referenced from dead `main_screen.dart`; name-collides with `dashboards/teacher_dashboard.dart` |
| `parent/parent_dashboard_screen.dart` | `ParentDashboardScreen` | only referenced from dead `ParentMainScreen` |

### 4b. Dead by chain (reachable only from dead screens)

| File | Class | Chain |
|---|---|---|
| `admin/admin_dashboard_screen.dart` | `AdminDashboardScreen` | only used by dead `AdminMainScreen` |
| `admin/backup_screen.dart` | `BackupScreen` | only referenced from dead `AdminDashboardScreen` → **currently unreachable offline-backup UI** |
| `main_screen.dart` | `MainScreen` | one live reference: fallback `pushReplacement` in `MasterAdminShell._backToApp()` when the navigator stack is empty (edge case) |

### 4c. Placeholder / "coming soon" UI (live)

- `PlannedScreen` in `nav_destinations.dart` — shared "یہ سہولت جلد آرہی ہے"
  body behind 3 planned destinations: **دارالاقامہ**, **ٹرانسپورٹ**, **اسناد**
  (each with a "جلد" pill in the rail). These are intentional placeholders, not
  dead code.
- One real `Placeholder()` widget at
  `admin_dashboard_screen.dart:380` — inside the dead `AdminDashboardScreen`
  (staff module def); unreachable in the live flow.
- `HostelDashboardScreen` shows an **honest empty state** ("no hostel data
  source yet") — not a fake dashboard, per its doc comment.

---

## 5. Navigation gaps

### 5a. Screens reachable only by deep push (not in sidebar)

| Screen | Pushed from |
|---|---|
| `StudentProfileScreen` | `StudentListScreen` row tap |
| `ExamWizardScreen` | `ExamDashboardScreen`, `AcademicAdminDashboardScreen`, `PrincipalDashboardScreen` quick actions |
| `UserWizardScreen` | `UserManagementHubScreen` |
| `UserDetailScreen` | `UserManagementHubScreen` |
| `DelegationScreen`, `DelegationCreateScreen` | `UserManagementHubScreen` (and `ProfileScreen` tiles) |
| `ScopeManagerScreen` / `ScopeEditorScreen` | `UserManagementHubScreen` |
| `UserManagementScreen` (legacy admin) | `PrincipalDashboardScreen` quick action (line 1102) — **duplicate** of the hub already in the sidebar |
| `ProfileScreen` | rail `_UserFooter` settings gear (push) |
| `TenantPickerScreen` | shell `_TenantSwitcher` (multi-tenant only) |
| `NotificationsScreen` | shell `_NotificationsBell` (push, separate from the `notifications` sidebar destination — same screen, two entries) |
| `AnnouncementsScreen` | `RoleHomeScreen`/`GenericDashboardScreen` links (also a sidebar destination) |
| `GlobalSearchPage` | `PrincipalDashboardScreen` fake search field (widget, not a screen file) |
| `_PdfPreviewScreen` | internal to `ReportsHubScreen` |
| `FeeManagementScreen._CollectFeeFlow` | internal fee-collection flow |

### 5b. Back-navigation state

- All deep-pushed screens inspected (`StudentProfileScreen`, `UserDetailScreen`,
  `UserWizardScreen`, `DelegationCreateScreen`, `ScopeManagerScreen`,
  `MadrasaDetailScreen`, `CreateMadrasaWizard`, `ExamWizardScreen`,
  `ReportsHubScreen`) declare `AppBar(...)` and rely on the default
  `automaticallyImplyLeading` back button. **No missing back buttons found**
  on deep screens.
- In-shell destination switching is **stateless by design** (body swap, no
  route push): no back stack inside the shell, which is correct for rail nav
  but means deep state (e.g. scroll position, filters) is only preserved via
  `PageStorage`.
- Master console: `MasterAdminShell._backToApp()` pops if possible, else
  `pushReplacement` to legacy `MainScreen` — that fallback lands on a
  near-dead teacher shell rather than `AppShell`; worth fixing in redesign.

### 5c. Orphan / questionable reachability

1. **`BackupScreen`** — complete offline backup/restore UI with **no live
   entry point** (only reachable from the dead admin dashboard). If backup is
   a supported feature, it needs a new home (e.g. under ادارہ or profile).
2. **Duplicate user management** — sidebar `users-roles` → new
   `UserManagementHubScreen`, but `PrincipalDashboardScreen` also deep-pushes
   the legacy `UserManagementScreen`. Two implementations of the same feature
   are live simultaneously.
3. **Duplicate teacher dashboards** — `dashboards/teacher_dashboard.dart`
   (live, in `TeacherHomeScreen`) vs `teacher/teacher_dashboard_screen.dart`
   (dead). Same class name in two files; the dead one should be removed to
   avoid confusion.
4. **Parent flow** — parent role lands on `GenericDashboardScreen`
   (role_home), with `FeeHistoryScreen` in the sidebar (`parent-fees`); the
   dedicated `ParentMainScreen`/`ParentDashboardScreen` pair is dead.
5. **No global search** — confirmed by `app_shell.dart` header comment; the
   principal dashboard's search box opens a client-data-only
   `GlobalSearchPage`. A real command-search is a redesign gap.
6. **Settings destination missing from shell** — there is no settings group in
   the IA; profile/settings live only behind the rail footer's gear icon
   (`ProfileScreen` push).
7. **`my-students` / `parent-fees` role-key gating** uses
   `visibleForRoleKeys` (teacher/parent template keys) — the only two
   destinations using role-key narrowing; everything else is
   permission-gated.

---

## Appendix — file counts

- `lib/presentation/screens/`: **67 files** (62 screens/routers + 5 widget/dialog libraries)
- Shell destinations: **22** across **6 groups** (19 real screens + 3 planned placeholders)
- Auth routes: 4 (`login`, `home`, `tenantPicker`, `noAccess`)
- Role dashboards reachable via `RoleHomeScreen`: 10 (clerk, accountant,
  academic-admin, hostel, library, exam, teacher-home, principal, generic ×2 paths)
- Dead files: **10** (3 deprecated super_admin + admin_main + parent_main +
  parent_dashboard + legacy teacher dashboard + admin_dashboard + backup +
  main_screen[near-dead])
