# Madrassa 360 — Product Map (Redesign Phase 2)

**Branch:** `redesign/ux-v2` · **Commit:** `5599da27` · **Date:** 2026-09-29
**Sources:** `docs/audit-routes.md`, `docs/audit-modules.md`, `docs/audit-design.md`
**Status:** Read-only synthesis. No code changed.

This is the BEFORE/AFTER record required by the mission (§36).
Part A = CURRENT state with problems. Part B = TARGET state to implement.

---

## PART A — CURRENT (verified in code)

### A.1 Roles (27 keys, permission-gated)

Permission vocabulary: **66 dotted codes** + **56 legacy underscore codes** (coexist;
client accepts the union, no translation). Resolution: `get_my_permissions_detailed`
RPC server-side (deny > grant > delegation > role), fail-closed offline chain,
RLS as real enforcement. UI gating is permission-derived (`PermissionGuard`,
`RoleGuard`, `ScopeGuard`, capability helpers) — **preserve as-is**.

| Role key | Urdu | Offline permission profile |
|---|---|---|
| `tenant_owner` | مالک | Full tenant set |
| `tenant_admin` | ناظم اعلیٰ | Full tenant set |
| `mohtamim` | مہتمم | Full tenant set |
| `naib_mohtamim` | نائب مہتمم | Full tenant set |
| `principal` | پرنسپل | Academics + exams/results incl. publish + reports + staff view + fees view |
| `nazim_aala` | ناظم اعلیٰ | Students/teachers/staff/attendance CRUD + academics + reports + users view + announcements send |
| `nazim_taleem` | ناظم تعلیم | Academics + exams/results incl. publish + attendance view + teachers view + reports |
| `nazim_intizamia` | ناظم انتظامیہ | Staff CRUD + documents + announcements send + users view |
| `nazim_maliyat` | ناظم مالیات | Fees + finance incl. approve |
| `nazim_hifz` | ناظم حفظ | Darjas view, exams create/view, results enter/edit, attendance view |
| `nazim_darul_iqama` | ناظم دارالاقامہ | Hostel mgmt + students/attendance view |
| `daftar_dar` | دفتر دار | Students create/edit/view, fees collect, certificates issue, documents mgmt |
| `accountant` | محاسب | Fees + finance incl. approve + reports |
| `teacher` / `ustad` | استاد | Students view, attendance view/mark/edit, exams view, results view/enter/edit |
| `ustad_hifz` | مدرس حفظ | Teacher base + hostel view |
| `mumtahin` | ممتحن | Exams create/edit/view, results enter/edit/view, students view |
| `librarian` | لائبریرین | Library view/manage |
| `hostel_manager` / `warden` | ہاسٹل مینیجر / وارڈن | Hostel view/manage, attendance view/mark (warden) |
| `store_incharge` | اسٹور انچارج | Documents mgmt + reports view |
| `hr_incharge` | عملہ انچارج | Staff CRUD + users view + attendance view + reports |
| `staff` | عملہ | Attendance view/mark only |
| `parent` / `student` | والدین / طالب علم | Announcements view only (portals expose data via scoped queries) |
| `platform_owner` / `platform_support` | پلیٹ فارم | All codes / tenants view + users view + audit view + reports view |

Platform admin is **not** a tenant role: resolved via `platform_admins` table
(`isPlatformAdmin`), routed to `AuthRoute.home` → `AppShell`, master console at
`/master` behind `MasterAdminGuard`. There is **no `isSuperAdmin`** in this branch.

### A.2 Role → dashboard mapping (`role_home.dart`, first match wins)

| Role family | Dashboard |
|---|---|
| `daftar_dar` | Clerk (دفتر) |
| `accountant`, `nazim_maliyat` | Accountant (مالیات) |
| `nazim_taleem`, `nazim_hifz` | Academic admin (تعلیمی نظام) |
| `nazim_darul_iqama`, `warden`, `hostel_manager` | Hostel (دارالاقامہ) — honest empty state |
| `librarian` | Library (کتب خانہ) |
| `mumtahin` | Exam (امتحانات) |
| permission-derived `isPrincipal()` | Principal (پرنسپل) |
| `teacher`, `ustad`, `ustad_hifz` | TeacherHome (tab shell) |
| `parent`, `student` | Generic (never blank) |
| any other staff / unknown | Principal (sections self-gate) / Generic fallback |

### A.3 Modules — route, purpose, CRUD, data, UX problems

| Module | Screens | Providers | Tables | CRUD | Key UX problems |
|---|---|---|---|---|---|
| **طلبہ Students** | `student_list_screen` (list, filters, DataTable desktop / cards mobile), `student_profile_screen` (5 tabs), `student_dialogs` (create/edit/fee dialogs) | `student_provider` (repository → local Drift, sync queue) | local `students` (+ `classes`/`darjas` joins); sync via `sync_apply` | create/update work; **delete has no UI trigger** | **CRITICAL: dialogs hardcode 8 darja names and store display strings as `class_id`** → dialog-created students drop out of rosters/filters; dead form fields (section, fee description, fee type); validators declared but never run (no `Form`); profile stale after edit (`studentByIdProvider` not invalidated); attendance badge always "حاضر" (unmeasured); no pagination/sort |
| **حاضری Attendance** | `attendance_screen` (class selector, date chip, bulk حاضر, 4-segment per-student control, sticky save bar, offline banner) | `attendance_provider` (repository → local) | local `attendance_records` | mark/save (upsert full roster); no delete | No search/filter on roster; `note` field exists with no UI; save writes full roster not overrides; teacher attendance does not exist; no teacher-attendance anywhere |
| **فیس Fees** | `fee_management_screen` (2 tabs: fee detail + collection hero, 4-step collect wizard, new-voucher FAB, PDF receipt) | `fee_provider` (repository; remote reads, queue-first writes) | `fees`, `fee_structures`, `fee_items`, `invoices`, `payments`, `payment_allocations`, `discounts`, `scholarships`, `refunds` | collect/voucher create; delete exists in repo, no UI | **Two fee systems disconnected** (collected `fees` rows never reach invoice/payment/ledger); fee status labels differ between screens; queue-first writes + remote reads = offline "not saved" appearance; two inconsistent fee-collection UIs |
| **مالیات Finance** | `finance_screen` (ledger list, income/expense/fee-payment add dialog, draft-only delete) | `finance_provider` (StateNotifier; fetches ledger+accounts+invoices+payments) | `transactions`, `accounts`, `income`, `expenses`, `invoices`, `payments` | draft lifecycle (create/update/transition/delete-draft); posted immutable | **Hardcodes `₹` (INR)** in labels/tiles/cards (must be PKR); **hardcoded indigo** `0xFF1A237E` summary bar breaks palette; **no error UI at all** (`state.error` never displayed); draft delete with **no confirmation**; add dialog silently fails validation (no feedback); invoices/payments fetched but never rendered; most finance backend (refunds, scholarships) has no UI |
| **امتحانات Exams** | `exam_dashboard` (stats + quick actions), `exam_wizard_screen` (8-step wizard: create → subjects → students → marks → review → result → approval → publish) | `result_provider` (repository → local) | local `exams`, `results` | create exam, enter marks; **no delete for exams or results anywhere** | **Entry tab creates duplicate exam headers + duplicate rows on re-save**; hardcoded subjects in entry tab vs free-form in wizard; wizard darja choice doesn't filter roster; approval is in-memory only; grade color gaps (الف+/فیل render gray); `substring(0,1)` crash risk on empty names; fixed 90/80/70/60/50 cutoffs hardcoded |
| **نتائج Results** | `results_screen` (2 tabs: view + entry) | `result_provider` | local `results` | enter marks; no edit/delete | Same as exams; N+1 provider watches in build; no pagination/sort/search |
| **اساتذہ/عملہ Teachers/Staff** | `staff_list_screen` (search, dept chips, salary stats, detail sheet, add/edit dialogs), `teacher_home` (permission-gated tabs), `teacher_dashboard`, `my_classes_screen`, `my_students_screen` | `staff_provider`, `teacher_portal_provider`, `day_schedule_provider` | `staff`, `teacher_class_assignments`, `classes`, `students`, `attendance`; photos → `staff-photos` bucket | add/edit work; **delete exists in repo, no UI trigger**; no activate/deactivate toggle | **Two divergent `TeacherDashboardScreen` classes** (one dead, same class name = compile hazard); dead copy shows permanent "—" زیر التواء card with TODO; validators declared, not wired to Form; dept chips hardcoded to 3 values; salary formats "0K", truncated 'ر ' prefix; no pagination |
| **درجات Darjas** | `darja_screen` (level-grouped list, add dialog, per-darja sections) | `darja_provider` (StateNotifier; remote read, local-first write + sync queue; 8 hardcoded seed darjas fallback) | `darjas`, `darja_sections` | create/delete; **update exists in provider, no UI calls it**; no edit UI | **Delete darja/section fires immediately on tap — zero confirmation (highest UX risk)**; add dialog allows empty name; `state.error` never displayed; no search/pagination |
| **اعلانات Announcements** | `announcements_screen` (pinned/regular, create dialog, pin toggle + delete) | `announcement_provider` (StateNotifier → Supabase + sync queue) | `announcements` | create/delete/pin toggle | **Delete + pin-toggle are one-tap, no confirmation/undo**; `postedByName` renders the poster's **email address**; admin gate uses **role-name string matching** (`role.name == 'admin'`) vs permission gating elsewhere; `specific` target is dead enum; scheduling doesn't exist in UI |
| **اطلاعات Notifications** | `notifications_screen` (inbox, Urdu/EN toggle, mark-all-read) | `notification_providers` (local Drift + unread stream) | local `notifications` | mark read | Mark-read errors silently swallowed; no search |
| **کتب خانہ Library** | `library_screen` (3 tabs, add-book dialog, issue/return dialogs with fine) | `library_provider` (StateNotifier → Supabase + sync queue) | `library_books`, `book_issues` | add/issue/return/delete | **Delete book has no confirmation**; no search; admin gate is `role.name.contains('admin')` string matching; no add-copies flow; no fine auto-calculation |
| **رپورٹس Reports** | `reports_hub_screen` (2 tabs, catalog, filter bottom-sheet, PDF preview/print/share/save, CSV/XLSX) | `reports_service`, `report_catalog` (15 static definitions), `pdf_kit`, `urdu_pdf` (Nastaleeq embedding), `report_branding` | local Drift (offline-first) | generate/export | Filter validation gap (class-wide attendance with no class silently aggregates everything); no saved-reports list (only raw path in snackbar); machine-style filenames; no report history; student search fires per keystroke (no debounce); zero-rows vs generation-failure indistinguishable |
| **صارفین/کردار Users/Roles** | `user_management_hub` (صارفین/ذمہ داریاں tabs), `user_wizard_screen` (5-step), `user_detail_screen`, `delegation_screen` + `delegation_create_screen`, `scope_manager_screen` | `user_management_provider`, `role_ux_provider`, `delegation_provider`, `scope_manager_provider` | `tenant_users`, `tenant_roles`, `tenant_role_permissions`, `permission_delegations`, `permission_scopes`, `tenant_memberships`, `permissions`, `user_accounts`, `app_roles`; RPCs: `delegate_permission`, `assign_tenant_role`, `set_user_permission`, `get_my_permissions_detailed` | full user/role/delegation/scope CRUD via Edge Functions (service key never on client) | **Tenant-isolation gap: `user_management_provider` has zero `tenant_id` references** — reads `user_accounts`/`app_roles` unfiltered (all isolation depends on RLS — verify server-side); **duplicate live user management** (sidebar hub + legacy screen deep-pushed from principal dashboard); roles tab is read-only preview ("ships in 8b") — admin sees a tab they can't act on; wizard has no draft persistence |
| **ادارہ Institution** | `about_screen` (info tabs, call/email), `profile_screen` (account/management/support groups) | `tenant_branding_provider` (live `tenants` path); `madrasa_provider` (**dead** — legacy `madrasas` table, only consumed by dead super_admin screens) | `tenants`, `tenant_settings`, `tenant_modules` | branding read-only for end users — **no tenant-settings edit screen** | Two parallel tenant models (legacy dead but in tree); no visible tenant-switch entry outside login-time picker |
| **پلیٹ فارم Master admin** | `/master` behind `MasterAdminGuard`: dashboard (KPIs + health), madrasa list (**only real pagination in app**, `.range()`), madrasa detail (lifecycle actions, typed confirmation), create-madrasa wizard (5-step → `provision-tenant` Edge Function), plans CRUD, subscriptions, licenses (read-only), modules catalog, platform users, audit logs (Urdu, date filters) | direct Supabase | `tenants`, `tenant_subscriptions`, `license_plans`, `licenses`, `modules_catalog`, `tenant_modules`, `platform_admins`, `audit_logs` | full platform CRUD | Licenses can't be revoked/extended from UI; audit log has **no export**; legacy `super_admin/` tree (3 files, 684 lines) is fully dead — two parallel consoles existed, only `/master` wired; `_backToApp()` fallback lands on near-dead `MainScreen` instead of `AppShell` |
| **والدین Parent portal** | `fee_history_screen` (live); `parent_main_screen` + `parent_dashboard_screen` (**dead**) | `parent_portal_provider` (scoped by `student_guardians` link; forged ids return []) | `student_guardians`, `fees`, `results`, `attendance` | view-only | Dead dashboard pair; parent role lands on `GenericDashboardScreen`; **two permanent empty sections** (timeline, upcoming exams) on the dead dashboard; `parentAnnouncementsProvider` defined but consumed by nothing — announcements unreachable in parent portal |
| **بیک اپ Backup** | `backup_screen` (backup now, verify, restore with typed confirmation, list, delete) | local | local | full backup/restore | **Complete UI with no live entry point** (only reachable from dead admin dashboard) — orphaned feature |

### A.4 Shell / navigation (current)

- **Desktop (≥1100px):** persistent RIGHT rail, 264px, teal-gradient branding header, grouped collapsible destinations, permission-filtered, badges, user footer + settings gear.
- **Tablet (600–1099px):** same rail in a drawer. **Mobile (<600px):** bottom nav (4 primaries + "مزید" drawer).
- **Top app bar (teal):** breadcrumb `group › destination`, tenant switcher (multi-tenant only), notifications bell with badge.
- **Destinations:** 6 groups, 22 items — 19 real + 3 **planned placeholders** (دارالاقامہ، ٹرانسپورٹ، اسناد → "جلد آرہا ہے" with "جلد" pill). Permission-gated (OR semantics) + role-key narrowing only on `my-students`/`parent-fees`.
- **No named-route table.** Widget-direct `MaterialPageRoute` + destination-id registry. In-shell switching swaps bodies (no back stack by design); deep screens pushed get default AppBar back (all verified present).
- **No global search** (confirmed by code comment); principal dashboard search is a fake field → client-data-only `GlobalSearchPage`.
- **No settings group** in the IA; profile lives behind the rail footer's gear icon.

### A.5 Components (current) — 4 parallel systems, 0% adoption of the standard

| # | System | Location | Status |
|---|---|---|---|
| 1 | m360_\* design system | `lib/core/design/` (8 files, ~2000 lines: buttons, cards, inputs, table, badges, states, tokens, responsive) | **0 files import it** (no barrel export — undiscoverable) |
| 2 | Legacy core widgets | `lib/core/widgets/` (PrimaryButton, EmptyStateWidget, LoadingWidget, LoadingOverlay, shimmer…) | used (e.g. login) |
| 3 | Presentation widgets | `lib/presentation/widgets/common/app_widgets.dart` (AppCard, StatCard, EmptyState, SearchField, LoadingOverlay…) | used by 8+ screens |
| 4 | Dashboard widgets | `lib/presentation/widgets/dashboard/` (StatCard #3, DashboardScaffold, QuickActions, AlertCard…) | used by all dashboards |

- **3 `StatCard` implementations**, **2 `LoadingOverlay`s**.
- Raw usage counts: 275 `Card(`, 37 `ElevatedButton(`, 52 `TextButton(`, 71 raw text fields, 69 raw spinners, 126 raw `SnackBar`s, 27 `showDialog` sites, 8 bottom sheets, 1 `DataTable`, 19 `ListView.builder`.
- **Palette violations (file:line):** `app_nav_rail.dart:271` old `#009688` teal; `role_config.dart:40-163` per-role rainbow gradients (purple/blue/brown/deep-orange); `Colors.red/green/grey/amber` literals across 8+ screens; login CTA teal (`login_screen.dart:462`) vs theme orange; `finance_screen` hardcoded indigo `0xFF1A237E`; `₹` currency symbol in finance (must be PKR).
- **Typography bypasses:** 93 hardcoded `fontSize` literals; `fontFamily: 'JameelNooriNastaleeq'` literals in reports_hub, app_nav_rail, notifications_screen (no fallback/line-height guard → clipping risk); `fontFamily: 'monospace'` in crash/modules/platform_users screens.
- **States:** `M360EmptyState/LoadingState/ErrorState` = 0 usages; 6+ screens show bare `Text('کوئی …')`; 69 ad-hoc full-screen spinners.
- **Dialogs/feedback:** m360_\* has **no dialog, no snackbar/toast** — the 73 dialogs + 126 snackbars are all ad hoc.

### A.6 Data-layer problems affecting UX

1. **Split-brain data access:** 10 provider files use repositories, 10 hit Supabase directly — no rule.
2. **~40 silent `catch (_) {}`** blocks; 8 convert failures to `return const []` (all 5 day-schedule providers) — error states unreachable, "no data" vs "load failed" indistinguishable.
3. **Migration drift:** `023_super_admin.sql` live on Supabase but missing from branch — branch can't reproduce live schema.
4. **Legacy `UserRole` enum** still exported; dual permission vocabularies (66 dotted + 56 legacy).
5. `TenantPickerScreen` pushes `RoleHomeScreen` directly, **bypassing AppShell** (multi-tenant users lose chrome after picking).

### A.7 Dead code to remove (verified by grep, zero references)

`super_admin/` (3 files) · `admin_main_screen.dart` · `parent_main_screen.dart` ·
`parent_dashboard_screen.dart` · `teacher/teacher_dashboard_screen.dart` (name collides with live one) ·
`admin_dashboard_screen.dart` · `backup_screen.dart` (→ relocate, not delete: feature is complete) ·
`main_screen.dart` (→ fix `_backToApp` fallback to `AppShell` first) ·
`madrasa_provider.dart` (legacy `madrasas` table) · `attendanceStreamProvider` ·
`feesByMonthProvider` · `parentAnnouncementsProvider` · legacy `role_config.dart` gradients.

---

## PART B — TARGET (what the redesign implements)

### B.1 Navigation IA (adopt + complete the existing `nav_destinations.dart`)

Keep the 6-group IA and permission gating (it works). Changes:

1. **Add a ترتیبات (Settings) group** in the shell (currently missing): Profile, Notifications preferences, Language, About, Backup (relocate orphaned `BackupScreen` here), Logout.
2. **Resolve the 3 planned placeholders** (دارالاقامہ، ٹرانسپورٹ، اسناد): HIDE from nav until screens exist (remove `planned: true` advertising). Do not ship "جلد آرہا ہے" in the sidebar of a production app.
3. **Fix duplicate user management:** sidebar hub is canonical; remove the legacy deep-push from `PrincipalDashboardScreen` (line 1102) → route to the hub.
4. **Fix `TenantPickerScreen` → `AppShell`** (not `RoleHomeScreen` directly).
5. **Fix `MasterAdminShell._backToApp()`** fallback → `AppShell`.
6. **Remove dead code** listed in A.7 (after relocating BackupScreen).
7. **Add global search trigger** in the top header (Ctrl+K) → real command-search over students/teachers/classes/subjects/exams/fees/pages (server-side where data is remote, local where local).
8. Keep: 22-destination registry shape, permission OR-semantics, role-key narrowing, mobile 4+مزید pattern, PageStorage body-swap.

### B.2 Data-critical fixes (must land before/with the UI — UI depends on correct data)

These are **not** redesign scope-creep; the new UI cannot be built on wrong data:

1. **Student class identity bug** — `StudentDialogs.classOptions` hardcoded strings stored as `class_id`. Fix: dialogs must select from real `classes`/`darjas` rows and store UUIDs. (Without this, attendance rosters and filters stay broken.)
2. **Finance currency** — replace all `₹` with PKR formatting (`formatPK` already exists in fee module; adopt app-wide).
3. **Darja/section/library/announcement deletes → confirmation dialogs** (use the new `M360ConfirmDialog`). Highest risk: darja delete.
4. **Exam duplicate headers** — guard entry-tab re-save (reuse `_resultIds` pattern from the wizard).
5. **`postedByName` email bug** — store/display the user's name, not email.
6. **Migration 023** — add the missing migration file to the branch (schema reproducibility).
7. **Silent `catch (_)` hygiene** — at minimum for dashboard aggregate providers (day-schedule ×5, dashboard stats) so error states become reachable; loading/error/empty states in the new UI depend on it.
8. **Verify RLS** on `user_accounts`/`app_roles` (unfiltered client reads in `user_management_provider`).

Out of redesign scope (document, don't fix silently): the two fee systems' backend unification; teacher attendance; report-history storage; SMS/WhatsApp (design doc only).

### B.3 Component strategy — consolidate 4 systems → 1

**Canonical system: `lib/core/design/` (m360_\*)**, extended to close gaps. Add barrel export `m360.dart`.

| Action | Detail |
|---|---|
| KEEP as-is | `design_tokens.dart` (fix `M360Brand.gold` dupe), `m360_badges.dart`, `m360_inputs.dart`, `m360_states.dart`, `responsive.dart` |
| REFACTOR then adopt | `m360_buttons.dart` (fix stale "filled teal" docstring; add tertiary/text variant), `m360_cards.dart` (unify 3 StatCards → **one horizontal** stat card per reference image), `m360_table.dart` (add pagination + bulk selection; fix `Alignment.centerLeft` → `AlignmentDirectional.centerEnd`) |
| ADD (missing) | `M360Dialog` + `M360ConfirmDialog`, `M360Toast`/`showM360SnackBar` (central feedback), `M360Dropdown`/`M360Select`, `M360SearchField`, `M360AppBar`, `M360DatePicker` wrapper, `M360LatinText` (documented LTR helper), skeleton variants |
| DELETE after migration | `core/widgets/` duplicates, `app_widgets.dart` duplicates, `dashboard/` widget duplicates (2 `LoadingOverlay`s, 3 `StatCard`s → 1) |
| PURGE | `#009688` leftover, `role_config.dart` rainbow gradients, all `Colors.red/green/grey/amber` literals → `AppColors`, hardcoded `fontSize`/`fontFamily` literals → `AppTypography`, 173+ `BorderRadius.circular` literals → `M360Radius`, 42 `boxShadow` → elevation tokens (keep minimal) |

**Adoption rule:** every screen migrates to m360_\* components; no new raw `Card(`/`ElevatedButton(`/`SnackBar(` in presentation code. Enforced by the no-mock-data-style CI guard if feasible (grep-based).

### B.4 Screen-by-screen redesign scope

- **Auth:** login keeps flow; fix CTA to theme orange; session-expiry message; keep remember-me.
- **Dashboards (10):** rebuild on the new hierarchy — welcome/context area (greeting, Islamic + Gregorian date), 4–6 metric cards (horizontal stat card), quick-action strip (primary orange + secondary mint/teal), 3-column info area (attendance summary, announcements, today's tasks), bottom area (recent activity, upcoming). Role-specific per §A.2 mapping. Clerk/accountant/academic/exam/library dashboards keep their actions, new visual language.
- **Students:** list (M360 table with search/filter/sort/pagination; fix class filter to real IDs), profile (5 tabs, keep), dialogs (real class/darja dropdowns, real `Form` validation, section persistence, address editable, isActive toggle, roll-no assignment).
- **Attendance:** keep the marking UX (it's good); add roster search/filter; add note UI; write only changed records where feasible.
- **Fees:** keep wizard + PDF receipt; unify fee-collection entry points (one UI, not two); align status labels across screens.
- **Finance:** PKR everywhere; remove indigo bar; render fetched invoices/payments or stop fetching; add error UI; confirm on draft delete; numeric keyboard + validation feedback on add dialog.
- **Exams/Results:** fix duplicates; wizard keeps 8 steps with new styling; entry tab uses wizard's subject model (no hardcoded subjects); darja filter actually filters roster; grade colors complete; add exam/result delete (permission-gated, confirmed).
- **Staff:** one teacher dashboard (delete the dead twin); salary PKR formatting; real Form validation; department list from data not hardcoded 3.
- **Darjas:** add confirmation on deletes; add edit UI (provider already supports `updateDarja`); validate add dialog; surface `state.error`.
- **Announcements:** confirmation on delete; permission-gated create (replace role-name string check); fix postedByName; hide `specific` target until implemented.
- **Library:** confirmation on delete; add search; permission-gated (replace string check); fine auto-calculation.
- **Reports:** fix filter validation gap; human filenames; saved-reports list; debounce student search; distinguish zero-rows from failure.
- **Users/Roles:** single canonical hub (remove legacy deep-push); roles tab: either implement or remove until 8b ships (no dead tabs in production); wizard draft persistence.
- **Settings group (new):** profile, notification prefs, language, about, backup (relocated), logout.
- **Master admin (`/master`):** keep IA; new visual language; licenses: add revoke/extend if backend supports; audit log export.

### B.5 Responsive strategy

- Desktop ≥1100: right rail (keep 264px, refine to mission spec: deep teal, compact, grouped, selected state = subtle mint/orange accent).
- Tablet 600–1099: rail in drawer (keep).
- Mobile <600: bottom nav 4+مزید (keep); tables → `M360ResponsiveTable` card fallback; forms single-column; quick actions stay reachable.
- Adopt `responsive.dart` helpers everywhere (replace hand-rolled `MediaQuery` checks).

### B.6 Accessibility pass

- 48px touch targets (`M360TouchTarget`); visible focus states; semantic labels on icon buttons (tooltips — audit found gaps); contrast check on orange-on-white; keyboard navigation for sidebar; screen-reader semantics on metric cards and tables.

### B.7 Regression test plan (Phase 15)

For **every live route** (19 destinations + deep screens): opens · correct role can access · unauthorized role cannot · data loads · create/edit/delete work · search/filters/sort/pagination work · back navigation works · empty/loading/error states render · RTL correct · responsive at 3 breakpoints. Auth matrix: login/logout/remember-me/tenant-picker/no-access/session-expiry. Role matrix: all 27 keys spot-checked against their dashboards + one negative test each. Master admin: full `/master` flow.

---

## Appendix — Decisions (UPDATED per production-readiness directives §§46–77, 2026-09-29)

1. The 3 planned modules (hostel/transport/certificates): **BUILD real screens** —
   do NOT hide, do NOT ship "جلد آرہا ہے". A backend-capability audit
   (`docs/audit-backend-capabilities.md`) determines per module: BUILDABLE NOW /
   PARTIAL (build UI + isolate missing backend pieces) / BACKEND MISSING (build
   full UI architecture + states, document the dependency, never fake success).
2. Finance: **UI unification WITHOUT backend rewrite** — confirmed. New financial
   IA: مالی نظام → مالی ڈیش بورڈ، طلبہ کی فیس، واجبات، انوائسز، ادائیگیاں،
   لیجر، اخراجات، مالی رپورٹس. Common UI view-model layer (FeeRecord/Invoice/
   Payment/LedgerEntry/OutstandingBalance) over the existing separate backends.
3. Master admin: **audit backend capabilities first** (license revoke/extend/renew,
   audit export). Implement every supported operation for real; unsupported ones
   get isolated service boundaries + honest "backend unavailable" states — never
   fake success.
4. **Single application shell**: ONE `AppShell` (sidebar + top bar + content).
   Pages provide ONLY content via `PageContainer`/`PageHeader` (breadcrumb,
   title, description, actions). NO nested Scaffolds, NO duplicate AppBars,
   NO page-level navigation chrome. Modals/dialogs for small actions, full pages
   for complex workflows.
5. **Production CRUD standard** every module: list → search → filter → view →
   create → edit → delete/archive → confirmation → success/error. Unified
   `M360Status` component for all statuses. Complete lifecycle on every screen:
   loading → content → empty → error → success → action-in-progress.

**Nothing here changes:** auth flow, permission resolution, RLS, tenant isolation,
role→dashboard mapping, Supabase tables/RPCs, offline sync engine, report PDF
pipeline. New UI, same functionality, better UX.

---

## Appendix B — Backend capability verdicts (2026-09-29, `docs/audit-backend-capabilities.md`)

| Module | Verdict | Build plan |
|---|---|---|
| Hostel (دارالاقامہ) | **BACKEND MISSING** — no tables/models/providers; only permission codes + catalog entry | Build full UI architecture (dashboard, buildings, rooms, beds, allocation) against an isolated `HostelRepository` interface; honest "backend not connected" states; zero fake data. New migrations are backend work — NOT authored in this redesign. |
| Transport (ٹرانسپورٹ) | **BACKEND MISSING** — same | Build full UI architecture (vehicles, drivers, routes, stops, assignments) against an isolated `TransportRepository` interface; honest states; zero fake data. |
| Certificates (اسناد) | **PARTIAL** — no issuance table, but PDF generation works today (`character_certificate`, `transfer_certificate` in report pipeline) | Build generation UI against the REAL report pipeline; issuance tracking (serials, verification, history) behind an isolated repository interface. |
| License revoke/extend | **BUILDABLE NOW** — RLS grants platform admins `FOR ALL` on `licenses`; no RPC exists | Implement real revoke (`status='cancelled'`) + extend (`expires_at` update) as direct table updates with confirmation dialogs + `log_audit()` entries. Fix impossible `'revoked'` status filter chip (not a valid CHECK value). |
| Audit-log export | **BUILDABLE NOW** — client reads authorized rows | Client-side CSV (existing export pattern) + PDF (existing pipeline) with active filters. No fake export buttons. |
