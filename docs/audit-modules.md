# Madrassa 360 — Modules, Roles, Permissions & Data-Flow Audit

**Branch:** `redesign/ux-v2` · **Working copy:** `~/workspace/madrassa-redesign-fix`
**Commit:** `5599da27` · **Date:** 2026-09-29
**Scope:** Read-only audit. No code was changed.

This document covers roles/permissions, all business modules, state management,
Supabase integration, tenant isolation, and the forms/tables/dialogs inventory.
It is the factual input for the redesign's product map and design system.

---

## 1. Roles & Permissions

### 1.1 Permission vocabulary (`lib/core/constants/app_permissions.dart`)

- **66 canonical dotted permission codes** (seeded by `supabase/migrations/005_rbac.sql`),
  grouped by domain:
  - `students.*` (view/create/update/delete)
  - `teachers.*` (view/create/update/delete)
  - `staff.*` (view/create/update/delete)
  - `attendance.*` (view/mark/edit/delete)
  - `academics.*` (view/manage — covers darjas/classes)
  - `exams.*` (view/create/update/delete/publish)
  - `results.*` (view/enter/edit/publish)
  - `fees.*` (view/create/collect/refund)
  - `finance.*` (view/create/update/delete/approve)
  - `library.*` (view/manage), `hostel.*` (view/manage), `transport.*` (view/manage)
  - `parents.view`
  - `notifications.*` (view/send)
  - `reports.*` (view/export)
  - `documents.*` (view/manage), `certificates.*` (view/issue)
  - `users.*` (view/create/update/deactivate), `roles.*` (view/assign)
  - `settings.*` (view/update), `modules.*` (view/manage)
  - `audit.view`
  - `tenants.*` (view/create/update/suspend — platform level)
- **56 legacy underscore codes** (e.g. `view_students`, `mark_attendance`,
  `manage_exams`, `view_admissions`, `system_full_access`) are also accepted —
  still issued by the deprecated `profiles.role` branch of `get_my_permissions()`.
  The client does **no dotted↔underscore translation**; both vocabularies coexist
  and the validator accepts exactly the union set (`AppPermissions.allCodes`).
- Every code has an **Urdu label** (`urduLabels` map, sourced from migration 019)
  for the permission-management UI; normal screens never show raw codes.

### 1.2 Role keys (`tenant_memberships.role`)

27 role keys are recognised, with static offline fallback permission sets in
`AppPermissions.roleDefaults`:

| Role key | Urdu label | Permission profile (offline fallback) |
|---|---|---|
| `tenant_owner` | مالک | All tenant codes (everything except `tenants.*` + `audit.view`) |
| `tenant_admin` | ناظم اعلیٰ | All tenant codes |
| `mohtamim` | مہتمم | All tenant codes |
| `naib_mohtamim` | نائب مہتمم | All tenant codes |
| `principal` | پرنسپل | Academics mgmt + exams/results mgmt incl. publish + reports + staff view + fees view |
| `nazim_aala` | ناظم اعلیٰ | Students/teachers/staff/attendance full CRUD + academics mgmt + reports + users view + announcements send |
| `nazim_taleem` | ناظم تعلیم | Academics mgmt + exams/results full incl. publish + attendance view + teachers view + reports |
| `nazim_intizamia` | ناظم انتظامیہ | Staff CRUD + documents mgmt + announcements send + users view |
| `nazim_maliyat` | ناظم مالیات | Fees + finance full incl. approve |
| `nazim_hifz` | ناظم حفظ | Darjas view, exams create/view, results enter/edit, attendance view |
| `nazim_darul_iqama` | ناظم دارالاقامہ | Hostel mgmt + students/attendance view |
| `daftar_dar` | دفتر دار | Students create/edit/view, fees collect, certificates issue, documents mgmt |
| `accountant` | محاسب | Fees + finance full incl. approve + reports |
| `teacher` / `ustad` | استاد | Students view, attendance view/mark/edit, exams view, results view/enter/edit, announcements view |
| `ustad_hifz` | مدرس حفظ | Teacher base + hostel view |
| `mumtahin` | ممتحن | Exams create/edit/view, results enter/edit/view, students view |
| `librarian` | لائبریرین | Library view/manage |
| `hostel_manager` | ہاسٹل مینیجر | Hostel view/manage |
| `warden` | وارڈن | Hostel view, attendance view/mark, students view |
| `store_incharge` | اسٹور انچارج | Documents mgmt + reports view |
| `hr_incharge` | عملہ انچارج | Staff CRUD + users view + attendance view + reports |
| `staff` | عملہ | Attendance view/mark only |
| `parent` | والدین | Announcements view only |
| `student` | طالب علم | Announcements view only |
| `platform_owner` | پلیٹ فارم مالک | All codes incl. `tenants.*`, `system_full_access` |
| `platform_support` | پلیٹ فارم سپورٹ | Tenants view, users view, audit view, reports view |

Notes:
- `tenant_owner`, `tenant_admin`, `mohtamim`, `naib_mohtamim` all get the **full
  tenant permission set** offline — the app treats the top four roles as
  functionally equivalent administrators.
- `parent`/`student` roles see almost nothing (announcements only); their
  dedicated portals (`parent_portal_provider`, `teacher_portal_provider`) expose
  data via scoped queries, not permissions.
- Platform admin is **not** a tenant role: it is resolved separately via the
  `platform_admins` table (`AuthNotifier._checkPlatformAdmin`) and stored as
  `AuthState.isPlatformAdmin`.

### 1.3 How roles/permissions are resolved at runtime

1. **Source of truth:** `tenant_memberships` table (one row per user+tenant;
   `role` key + `is_active`). The deprecated `profiles.role` single-role column
   is explicitly distrusted (see `RoleService` doc comment).
2. **Effective permission set:** loaded per tenant via the
   `get_my_permissions_detailed(p_tenant_id)` RPC (migration 020), which resolves
   **deny > grant > delegation > role** server-side. Unknown codes are dropped
   client-side (fail-closed).
3. **Offline chain** (`PermissionService.loadEffectivePermissions`):
   RPC → last-known persisted set (per user+tenant, in `StorageService`) →
   static `AppPermissions.fallbackFor(roleKey)` (fail-closed for unknown keys).
4. **In-memory cache:** `AuthorizationService` holds the effective set for the
   active tenant; reloaded on sign-in and tenant switch; cleared on sign-out.
5. **Data scoping:** `ScopeService` reads `permission_scopes` rows
   (`all` | `department` | `classes` | `students`), fail-closed per migration 022.
   UI uses `ScopeGuard` to hide out-of-scope affordances; RLS `scope_allows()`
   is the real enforcement.

### 1.4 How UI code performs role/permission checks

| Mechanism | File | Usage pattern |
|---|---|---|
| `hasPermissionProvider(code)` | `lib/providers/auth_provider.dart:538` | `ref.watch(hasPermissionProvider(AppPermissions.collectFees))` → bool; `hasAllPermissionsProvider` / family variants also exist |
| `userPermissionsProvider` | `auth_provider.dart:527` | Raw `Set<String>` of effective codes for the active tenant |
| `activeRoleKeysProvider` | `lib/core/services/role_service.dart` | Role keys in active tenant; re-resolves on tenant switch |
| `PermissionGuard` | `lib/core/widgets/permission_guard.dart` | Hides child unless permission held; optional `fallback` |
| `RoleGuard` | `lib/core/widgets/role_guard.dart` | Hides child unless ANY of given role keys held (for role-identity UI, not feature gating) |
| `ScopeGuard` | `lib/core/widgets/scope_guard.dart` | Hides child unless data scope covers `classId`; fails closed while loading |
| `MasterAdminGuard` / `fetchPlatformAdminRole` | `lib/core/widgets/master_admin_guard.dart` | Gates `/master` platform console |
| `RoleService` capability helpers | `role_service.dart` | `canManageRoles()`, `canCollectFees()`, `canApproveFinance()`, `canPublishResults()`, `canSendAnnouncements()`, `managesAcademics()`, `isPrincipal()` — all **permission-derived**, never role-name comparisons |
| Navigation visibility | `lib/presentation/shell/nav_destinations.dart` | `NavDestination.isVisible()`: OR-semantics over `requiredPermissions` + optional `visibleForRoleKeys` narrowing |
| Dashboard routing | `lib/presentation/screens/dashboards/role_home.dart` | `RoleHomeScreen` maps role-key families → dashboards (see §1.5) |

**Contract (enforced by convention + doc comments):** feature gating must use
permission-derived checks; role-name string matching is banned for gating. The
only legitimate role-key uses are: dashboard routing (`role_home.dart`),
`visibleForRoleKeys` nav narrowing, tenant-administration flows where the server
itself is role-based (`protect_last_owner()`), and role-badge display.
A grep found only a handful of raw role-name comparisons in UI, all in those
legitimate categories (`master_admin_shell.dart`, `platform_users_screen.dart`,
`user_wizard_screen.dart`, `tenant_picker_screen.dart`).

### 1.5 Role → dashboard routing (`role_home.dart`)

Post-login, `RoleHomeScreen` resolves the primary role family and returns:

| Role family | Dashboard |
|---|---|
| `daftar_dar` | `ClerkDashboardScreen` (دفتر) |
| `accountant`, `nazim_maliyat` | `AccountantDashboardScreen` (مالیات) |
| `nazim_taleem`, `nazim_hifz` | `AcademicAdminDashboardScreen` (تعلیمی نظام) |
| `nazim_darul_iqama`, `warden`, `hostel_manager` | `HostelDashboardScreen` (دارالاقامہ) |
| `librarian` | `LibraryDashboardScreen` (کتب خانہ) |
| `mumtahin` | `ExamDashboardScreen` (امتحانات) |
| permission-derived `isPrincipal()` (manageDarjas + publishExams + publishResults) | `PrincipalDashboardScreen` |
| `teacher`, `ustad`, `ustad_hifz` | `TeacherHomeScreen` (tabs) |
| `parent`, `student` | `GenericDashboardScreen` |
| any other staff role / no keys / unknown | `PrincipalDashboardScreen` (sections self-gate) / `GenericDashboardScreen` fallback |

Staff-dashboard mapping runs **before** the permission-derived principal check
(e.g. `nazim_taleem` technically satisfies `isPrincipal()` but is routed to the
academic dashboard). The fallback is never blank: greeting + announcements +
profile. Platform operators with zero tenant memberships land here with a
"پلیٹ فارم کنسول" entry to the guarded `/master` route.

---

## 2. Modules

> Module deep-dives were produced by parallel audit agents reading every screen,
> provider, repository and model file. Summarised below; details per file are in
> the sub-reports.

### 2.1 Students (طلبہ)

**Screens** (all under `lib/presentation/screens/`):
- `admin/student_list_screen.dart` (612 lines) — admin roster: AppBar + refresh,
  header row with count + "+ نیا طالب علم" CTA, `SearchField` (name/father/roll),
  two `FilterChip` rows (class + active/inactive) + "فلٹر صاف کریں"; responsive:
  `DataTable` on desktop ≥900px (نام، رول نمبر، کلاس، حاضری، فیس کی حالت، اعمال),
  card list on mobile. Row tap → profile; per-row actions پروفائل/ترمیم/فیس وصول کریں.
  Loading + error-with-retry + `EmptyState` all present.
- `students/student_profile_screen.dart` (946 lines) — profile hub: gradient identity
  header (avatar, name, roll/class chips, active badge, 4 quick actions), then 5 tabs:
  جائزہ (stat cards), ذاتی معلومات, حاضری (30-day), فیس, امتحانات.
- `students/student_dialogs.dart` (735 lines) — shared static dialogs:
  `showNewAdmission` (photo, name, father, phone, class dropdown, section dropdown,
  optional address), `showEditStudent`, `showFeeCollection`.
- `students/student_widgets.dart` (127 lines) — pure widgets
  (`StudentAvatar`, `feeBadge`, `attendanceBadge`, `studentStatusBadge`), no logic.

**Providers** (`lib/providers/student_provider.dart`, 183 lines): `studentRepositoryProvider`
(→ `LocalStudentRepository`); `allStudentsProvider`, `studentsByClassProvider`,
`studentsByDarjaProvider`, `studentByIdProvider` (all FutureProviders, local Drift,
empty when no tenant); `StudentNotifier` (`AsyncNotifier<void>`) with `save`
(upsert), `delete` (soft), `uploadPhoto`.

**Supabase tables:** none directly — **local-first module**. Reads are local Drift
SQL (`students` LEFT JOIN `classes`/`darjas`, `tenant_id = ?`, `deleted_at IS NULL`);
writes go to the local row + `sync_queue` (entity `students`) in one transaction;
the sync engine pushes via the `sync_apply` RPC.

**CRUD:** create/update via `upsertStudent` (used by both dialogs). `deleteStudent`
exists in repo + provider but **no UI calls it anywhere** — `students.delete`
permission is declared but never gates a visible button. Students effectively
cannot be deleted from the UI.

**UX problems (verified in code):**
- **Class/darja identity bug (critical):** `StudentDialogs.classOptions` is a
  **hardcoded** list of 8 darja display names; dialogs store the display string as
  `classId`/`darjaId`. Everything else uses real `classes`/`darjas` row ids
  (teacher assignments select `id` from `classes`; attendance repo filters
  `s.class_id = ?`; server schema types `class_id` as UUID). Dialog-created
  students will miss attendance rosters, teacher result lists, and the list's
  own class filter.
- **Dead form fields:** `selectedSection` (الف/ب/ج/د) is chosen but never persisted;
  fee dialog's `descriptionController` never reaches the `Fee` model;
  `selectedFeeType` dropped (model has no fee-type field); edit dialog has no
  address field (admission-time address is uneditable); no `isActive` toggle —
  students can never be deactivated.
- **Roll number:** new admissions create `rollNo: ''`; no assignment UI exists.
- **Validation theater:** `_LabeledField` carries `validator:` callbacks but fields
  are **not wrapped in a `Form`** — validators never run; only hand-checks on
  name/father.
- **Stale profile:** `StudentNotifier.save` invalidates list providers but **not
  `studentByIdProvider`** — the open profile shows pre-edit data after saving.
- **Misleading badge:** list's `attendanceBadge(s.attendanceStatus)` always renders
  "حاضر" (default) — data never measured.
- **N+1 provider watches:** profile's attendance tab calls
  `ref.watch(classAttendanceProvider(...))` inside a 30-iteration loop.
- No pagination, no sort; two inconsistent fee-collection UIs (dialog vs wizard).

### 2.2 Attendance (حاضری)

**Screens:** `teacher/attendance_screen.dart` (787 lines) — teacher roster: class
selector (label or dropdown), Urdu date chip (never future, ≤365 days back),
"سب کو حاضر کریں" bulk action, per-student 4-segment one-tap control
(حاضر/چھٹی/غیر حاضر/تاخیر), sticky bottom bar with live counts + "حاضری محفوظ کریں"
with saving state, offline sync-queue banner, fail-closed placeholders
(no tenant / no class / empty / error+retry).

**Providers** (`lib/providers/attendance_provider.dart`, 106 lines):
`attendanceRepositoryProvider` (→ `LocalAttendanceRepository`);
`classAttendanceProvider` (family Future on classId+date);
`attendanceStreamProvider` (Stream — **dead, zero usages**);
`AttendanceRecordNotifier` (`AsyncNotifier<void>.save`) with honest error semantics.

**Supabase tables:** none directly — **local-first**. Local SQL:
`students` LEFT JOIN `attendance_records` on (student_id, date, tenant_id),
`tenant_id = ? AND class_id = ?`, ordered by `roll_no`.

**CRUD:** read `getClassAttendance`; write `saveAttendance` (upsert per record).
No record = present ("management by exception"). No delete API.

**UX problems:** no search/filter/sort on roster; `AttendanceRecord.note` exists in
model but **no UI to enter it**; save writes the full roster, not just overrides;
**teacher attendance is referenced in a model comment but does not exist anywhere**
in the app; minor RTL-correct.

### 2.3 Fees / Dues & Finance (فیس / مالیات)

**Screens:**
- `admin/fee_management_screen.dart` (1606 lines) — two tabs. Tab 1 (فیس کی تفصیل):
  summary cards (وصول شدہ/زیر التواء/واجب الادا), student search, 5 status
  FilterChips, fee list with progress bars; row tap opens `_CollectFeeFlow`, a
  **4-step wizard** (تفصیل → رقم → تصدیق → رسید) with amount validation
  (≤ remaining) and real PDF receipt (`FeeReceiptPdf` → `Printing.layoutPdf`).
  FAB "نیا واؤچر" → dialog (student dropdown, last-6-months picker, amount).
  Tab 2 (وصولی): today's collection hero + last-5 receipts.
- `admin/finance_screen.dart` (358 lines) — ledger: indigo summary bar
  (آمدن/اخراجات/بیلنس), kind filter chips, `_LedgerCard` list; admin-only FAB
  "نئی اندراج" → add dialog (income/expense/fee-payment, category/method/account
  dropdowns). Delete icon **only on drafts**; posted/void immutable.

**Providers:** `fee_provider.dart` (120): `feeRepositoryProvider`;
`allFeesProvider`, `feesByStudentProvider`, `feesByMonthProvider` (family —
**dead**), `feeSummaryProvider`; `FeeNotifier` (AsyncNotifier: `save`, `delete`).
`finance_provider.dart` (235): `financeProvider` —
**`StateNotifierProvider<FinanceNotifier, FinanceState>`** (the only StateNotifier
among these modules); `load()` fetches ledger+accounts+invoices+payments via
`Future.wait`; actions `recordIncome/recordExpense/recordPayment/deleteLedgerDraft`.

**Supabase tables** (all reads carry `.eq('tenant_id', tenantId)`): fees module —
`fees` (select `*, students(name, roll_no)`); writes are **queue-first**
(`sync_queue` entity `fees`), a documented exception (no local fees table).
Finance — `accounts`, `transactions`, `income`, `expenses`, `invoices`,
`payments`, `payment_allocations`, `refunds`, `discounts`, `scholarships`,
`fee_structures`, `fee_items`.

**CRUD:** fees `upsertFee`/`deleteFee` (no delete button in UI); new voucher creates
`Fee(id: '')` (empty-string id as sync-queue entityId). Finance: full draft
lifecycle (create/update/transition/delete-draft); fee structures read-only.

**UX problems (verified):**
- **Wrong currency symbol:** finance screen hardcodes `'₹'` (INR) in amount label,
  summary tiles and ledger cards; fee module correctly uses PKR (`ر `/`formatPK`).
- **Orphaned finance payments:** the "فیس وصولی" option calls
  `recordPayment(..., studentId: null, invoiceId: null)` — an unlinked payment.
  **The two fee systems are disconnected:** collected `fees` rows never reach the
  invoice/payment/ledger system.
- **Fetched-but-never-rendered:** `FinanceNotifier.load()` fetches invoices and
  payments; the screen shows only ledger + accounts dropdown. `state.error` is
  never displayed — **no error UI on the finance screen at all**.
- **No confirm on destructive action:** draft delete fires from the trash icon
  with no dialog.
- **Silent validation:** finance add dialog uses plain `TextField` (no numeric
  keyboard, no `Form`); `double.tryParse(...) ?? 0; if (amount <= 0) return;`
  fails with **zero user feedback**.
- **Hardcoded indigo** `Color(0xFF1A237E)` summary bar breaks the teal palette.
- **Dead "سب دیکھیں"** button (no `onActionTap`); **unreachable `method == 'نقد'`**
  styling branch (method is always the month label).
- Bare `Text('کوئی ریکارڈ نہیں')` empty state vs `EmptyState` widget elsewhere.
- **Queue-first fee writes + remote reads:** a collected fee may appear "not saved"
  while offline (unlike local-first students/attendance which reflect instantly).
- `feesByMonthProvider` dead; `Fee.copyWith` cannot change `status` (stale until
  remote re-read); month picker limited to last 6 months; fee status labels
  differ between screens ("جزوی ادائیگی" vs "جزوی", "بقایا" vs "زیر التواء").

### 2.4 Exams / Results (امتحانات / نتائج)

**Screens:**
- `dashboards/exam_dashboard.dart` (234) — greeting header, day schedule slot,
  4 `StatCard`s (جاری امتحانات، نمبر درج ہونا باقی، نتائج تیار، نتائج شائع شدہ —
  the last is an honest static '—' since the schema has **no publish flag**),
  permission-gated quick actions (wizard, entry, view, report).
- `dashboards/exam_wizard_screen.dart` (1129) — 8-step wizard: 0 create exam
  (name, date, darja via `safeDarjaListProvider`, total marks) → 1 subjects
  (dynamic name+marks rows) → 2 students (checkbox roster, select-all/none) →
  3 enter marks (clamped to subject total) → 4 review → 5 result (pass rate,
  topper) → 6 approval (`publishResults` gate, **in-memory `_approved` flag**) →
  7 "publish" (honest: no schema flag). Real persistence at steps 0 and 3.
- `teacher/results_screen.dart` (1159) — two tabs. نتائج: assigned-class filter
  chips + result cards (grade badge, first-3-subjects preview), bottom-sheet
  result card with PDF print/share. نتیجہ درج کریں: class + exam-type dropdowns
  (ماہانہ/ہفتہ وار/سالانہ), per-student cards with 3 marks inputs.

**Providers** (`lib/providers/result_provider.dart`, 140):
`resultRepositoryProvider` (→ `LocalResultRepository`); `allExamsProvider`,
`examResultsProvider` (family), `allResultsProvider` (**sequential N+1** over
exams; docstring admits it), `studentSubjectResultsProvider` (family);
`ResultNotifier` (AsyncNotifier: `save`, `createExam`).

**Supabase tables:** none directly — **local-first** (`exams`, `results` JOIN
`students` JOIN `classes`, `tenant_id = ?`, `deleted_at IS NULL`).

**CRUD:** `createExam`, `upsertResult`. **No delete for exams or results anywhere**
(not in repo interface, providers, or UI).

**UX problems (verified):**
- **Duplicate exam headers:** entry tab always calls
  `createExam(name: '$examType — $className')` then saves marks with fresh UUIDs —
  re-saving creates a **second exam header + duplicate rows** (wizard avoids this
  via `_resultIds` reuse; entry tab has no guard).
- **Hardcoded subjects** in entry tab (`['قرآن', 'حدیث', 'فقہ']`, each /100) vs
  wizard's free-form subjects.
- **Wizard step 0's darja choice doesn't filter step 2:** roster loads **all**
  active students regardless of the chosen darja.
- **Grade color gaps:** `_getGradeColor` handles only الف/ب/ج/د — `'الف+'` and
  `'فیل'` both render gray.
- **`substring(0, 1)` crash risk** on empty student names (3 call sites).
- **N+1 watches in build:** results tab watches `teacherClassStudentsProvider`
  (a direct Supabase query) per class per rebuild; `allResultsProvider`
  sequential scan also powers the profile's exam-average card.
- No pagination/sort/search on results list; no edit/delete for exams/results;
  approval is in-memory only; `chevron_right` doesn't auto-mirror for RTL;
  fixed 90/80/70/60/50 grade cutoffs hardcoded (no per-tenant scale).

### 2.5 Teachers / Staff (اساتذہ / عملہ)

**Screens:**
- `admin/staff_list_screen.dart` (929) — staff directory: search, department filter
  chips, salary stats, detail bottom-sheet, add/edit dialogs, photo upload,
  tap-to-call.
- `dashboards/teacher_dashboard.dart` (317) — rich teacher dashboard (greeting,
  day-schedule slot, 4 stat cards, quick actions, today's-tasks checklist,
  announcements preview).
- `dashboards/teacher_home.dart` (197) — teacher bottom-nav shell with
  permission-gated tabs (ڈیش بورڈ، میری جماعتیں، میرے طلبہ، حاضری، امتحانات، نتائج).
- `dashboards/my_classes_screen.dart` (122) — assigned classes → tap opens attendance.
- `dashboards/my_students_screen.dart` (146) — aggregated students across assigned
  classes, deduped by id.

**Providers:** `staff_provider.dart` (113): `allStaffProvider`, `staffByIdProvider`
(family), `staffNotifierProvider` (AsyncNotifier: save/delete/uploadPhoto).
`teacher_portal_provider.dart`: `teacherAssignmentsProvider`,
`teacherAssignedClassIdsProvider`, `teacherAssignedClassesProvider`,
`teacherClassStudentsProvider` (family, re-validates classId against assignments),
`teacherStudentCountProvider`, `teacherTodayPresentProvider`.
`day_schedule_provider.dart`: role-specific `DayScheduleEvent` mappers (see §3.2).

**Supabase tables:** `staff` (`.eq('tenant_id')`, `is_active`, order by name),
`teacher_class_assignments` (join `classes(name)`), `classes`, `students`,
`attendance`. Photo uploads → Storage bucket `staff-photos` at
`{tenantId}/staff/{staffId}.{ext}` via `PendingUploadQueue`.

**CRUD:** add/edit via dialogs. `deleteStaff` exists in the repo (soft delete via
sync queue) but has **no UI trigger** — no delete button, no activate/deactivate
toggle. Repo hard-filters `is_active=true` with no "show inactive" view.

**UX problems (verified):**
- **Two divergent `TeacherDashboardScreen` classes** (`dashboards/teacher_dashboard.dart`
  vs `teacher/teacher_dashboard_screen.dart`, 281 lines). Verified: the latter is
  only referenced by the dead `main_screen.dart` — unreachable; the former is used
  by `TeacherHomeScreen`. Same class name in two files is a compile hazard and a
  maintenance trap.
- Teacher dashboard (dead copy) renders a **permanent "—" "زیر التواء" card** with an
  inline `TODO(phase-8)` — visible dead card on every load.
- Truncated salary prefix `'ر '` (looks like a cut-off "روپے") in add/edit fields;
  salary stat formats totals as `"0K"` for values under 1000 (no PKR formatting).
- Add/edit dialogs declare validators but **never wire them to a `Form`** — the save
  button re-checks manually; the edit dialog has almost no validation.
- No pagination; client-side `.contains` search over name/designation only.
- Department filter chips hardcoded to 3 values ('تعلیمی/انتظامیہ/مالیات') —
  other departments unfilterable.

### 2.6 Classes / Darjas (درجات)

**Screens:** `admin/darja_screen.dart` (315) — level-grouped darja list
(`ExpansionTile` cards), add-darja dialog, per-darja section add/delete.

**Providers:** `darja_provider.dart` (384): `DarjaNotifier extends
StateNotifier<DarjaState>` (darjas, sections, isLoading, error); `loadAll`,
`createDarja`, `updateDarja`, `deleteDarja`, `createSection`, `deleteSection`,
`sectionsForDarja`. Reads remote `darjas`/`darja_sections` (`.eq('tenant_id')`);
writes local-first + sync queue. Falls back to 8 hardcoded seed darjas
(ناظرہ/حفظ/درجہ اول..پنجم/تخصص) if the table query fails.

**Model:** `lib/data/models/darja.dart` (132) — `Darja`, `DarjaSection`;
`madrasaId` fields marked DEPRECATED; `level` ∈ nazra/hifz/dars_e_nizami/takhassus.

**UX problems:**
- **Destructive actions with zero confirmation:** delete icon on darja cards and
  section remove icons call `deleteDarja`/`deleteSection` **immediately on tap** —
  highest UX risk in the module (a darja with students attached is one tap away).
- **No edit UI for darjas** — provider has `updateDarja` but no screen calls it.
- Add dialog: **no validation** (empty name allowed); `state.error` is set but the
  screen never displays it; no search, no pagination.

### 2.7 Announcements / Notifications (اعلانات / اطلاعات)

**Screens:** `common/announcements_screen.dart` (271) — pinned/regular sections,
admin-gated create dialog (target dropdown, pin checkbox), per-card pin toggle +
delete. `common/notifications_screen.dart` (245) — local in-app inbox with
Urdu/EN toggle, read/unread, mark-all-read.

**Providers:** `announcement_provider.dart` (241): `AnnouncementNotifier`
(load remote `announcements` `.eq('tenant_id')`; create/delete/togglePin
local-first + sync queue). `lib/core/notifications/notification_providers.dart`:
`inboxNotificationsProvider` (local `notifications` table),
`unreadNotificationsCountProvider` (Stream), `notificationPreferencesProvider`.

**Model:** `lib/data/models/announcement.dart` (100) — `AnnouncementTarget`
{all, teachers, parents, students, **specific**} with Urdu labels; `scheduledAt`.

**Tables:** `announcements`; local `notifications` (Drift DAO); channels in
`lib/core/notifications/` (in_app, push, email). `sms_whatsapp_extension.md` is a
design doc — **no SMS/WhatsApp implementation**.

**UX problems:**
- Delete and pin-toggle are **one-tap with no confirmation/undo**.
- **`postedByName` bug:** create dialog sets `postedByName: user?.email ?? ''` —
  announcements render the poster's **email address** as the "posted by" name.
- **Admin gate uses role-name string matching** (`user?.role.name == 'admin' ||
  'superAdmin'`) — inconsistent with the permission-based gating used everywhere
  else.
- `AnnouncementTarget.specific` is a dead enum value (create dialog offers only
  all/teachers/parents/students); `scheduledAt` is never settable from the UI
  (scheduling effectively doesn't exist).
- Main screen shows all targets to everyone (client-side filtering only for
  parents); no search; notification mark-read errors silently swallowed.

### 2.8 Reports (رپورٹس)

**Screens:** `reports/reports_hub_screen.dart` (544) — two tabs (طلبہ/انتظامیہ),
catalog list, filter bottom-sheet (student search ≥2 chars capped at 20 hits,
class/darja/exam dropdowns, date range), then PDF preview / print / share / save,
plus CSV/XLSX share for tabular reports.

**Core:** `lib/core/reports/` — `report_catalog.dart` (**15 static report
definitions**), `reports_service.dart` (dispatch by id), `pdf_kit.dart` (545),
`urdu_pdf.dart` (Nastaleeq font embedding), `report_branding.dart` (tenant
logo/name), `documents/` (admin/student/result/fee-receipt docs), `export/`
(CSV with UTF-8 BOM, Excel via sharePdf bytes).

**Data:** all reports run against the **local Drift DB** (offline-first);
tenant scoping via params.

**UX problems:**
- Filter-sheet validation only covers `needsStudent`/`exam_results`; a class-wide
  attendance summary with no class selected **silently aggregates everything**.
- Save-PDF writes to the app documents dir and shows only the raw file path in a
  snackbar — **no in-app saved-reports list**, no file-manager deep link.
- Filenames are `${def.id}_${milliseconds}.pdf` — machine-style, not human.
- No report history/recent list; zero-rows vs generation-failure are
  indistinguishable (generic error snackbar).
- Student search fires per keystroke with no debounce (guarded only by a
  `q != _search` check).

### 2.9 Settings / Users / Roles / Delegation (ترتیبات)

**Screens** (`lib/presentation/screens/settings/`, ~4,100 lines total):
- `user_management_hub.dart` (670) — صارفین/ذمہ داریاں tabs, permission-gated,
  bulk role-change.
- `user_wizard_screen.dart` (982) — 5-step create/edit wizard (personal info →
  role → permission checklist → scope → summary); **no draft persistence** if
  abandoned.
- `user_detail_screen.dart` (474).
- `delegation_screen.dart` (282) — delegation list; revoke uses a **confirm
  dialog (the one place that does this right)**.
- `delegation_create_screen.dart` (432).
- `scope_manager_screen.dart` (838).
- `role_ux_widgets.dart` (233) — shared `UxEmptyState`, `confirmUxAction`, snack
  helpers.

**Providers:** `user_management_provider.dart` (369) — `UserManagementNotifier`
(accounts+roles). `role_ux_provider.dart` (342) — `tenantUsersProvider`,
`tenantRolesUxProvider`, `permissionCatalogProvider`, `roleMemberCountsProvider`.
`delegation_provider.dart` (153), `scope_manager_provider.dart` (184).

**Tables/RPCs:** `tenant_users`, `tenant_roles`, `tenant_role_permissions`,
`permission_delegations`, `permission_scopes`, `tenant_memberships`,
`permissions`; `audit_logs` (server-side). RPCs: `delegate_permission`,
`assign_tenant_role`, `set_user_permission`, `get_my_permissions_detailed`.
Edge Functions `create_user`/`manage-users` for privileged auth ops (service key
never on client).

**UX problems:**
- **Tenant-isolation gap:** `user_management_provider.dart` has **zero
  `tenant_id` references** — reads `user_accounts` and `app_roles` unfiltered,
  delete/update filter by `id` only. All isolation depends on RLS being correct
  server-side; every other module also filters client-side. **Verify RLS on
  these tables.**
- The **roles tab in the hub is a read-only preview** ("full editing ships in
  8b" per header comment) — an admin sees a tab they cannot act on.
- Wizard has no step-back validation summary until step 5; revoked delegations
  vanish with no UI-surfaced audit note.

### 2.10 Institution / Tenant management (ادارہ)

**Providers:** `madrasa_provider.dart` (135) — `MadrasaNotifier` (loadAll/create/
update/toggleStatus/delete against the **legacy `madrasas` table**).
**Verified: consumed only by the two dead `super_admin/` screens — effectively
dead.** `tenant_branding_provider.dart` (245) — `tenantBrandingProvider`,
`tenantModulesProvider`, `isModuleEnabledProvider` (family), reading `tenants` +
`tenant_settings` + `tenant_modules` (live path).

**Model:** `madrasa.dart` (119) — subscriptionPlan ∈ basic/standard/premium.

**Screens:** `common/about_screen.dart` (494) — مدرسہ/پتہ/فون/ای میل tabs, app
version, Urdu/EN toggle, call/email buttons. `common/profile_screen.dart` (888) —
account group (profile, notifications, language), management group
(users & roles, delegation — permission-gated), support group (help, about, logout).

**UX problems:**
- **Two parallel tenant models:** legacy `madrasas`-table provider vs live
  `tenants` model; the legacy side is dead but still in the tree.
- No visible "switch tenant" entry for multi-tenant users outside the login-time
  `tenant_picker_screen`.
- Branding (logo/name) is read-only for end users — no tenant-settings edit
  screen found; branding surfaces only in reports and dashboards.

### 2.11 Super admin / Master admin (پلیٹ فارم)

**Master admin** (`lib/presentation/screens/master_admin/`, ~4,170 lines) — the
**live** platform console, routed via `/master` in `main.dart` behind
`MasterAdminGuard` (→ `platform_admins` lookup, fails closed):
- `master_admin_shell.dart` (249) — drawer navigation.
- `master_dashboard_screen.dart` (450) — platform KPIs + honest system health checks.
- `madrasa_list_screen.dart` (256) — searchable, filterable, **paginated** tenant
  list (`.range()` — **the only real pagination in the audited scope**).
- `madrasa_detail_screen.dart` (537) — tenant detail.
- `create_madrasa_wizard.dart` (798) — 5-step provisioning → `provision-tenant`
  Edge Function; blocks provisioning without a `plan_id` (honest).
- `plans_screen.dart` (408) — `license_plans` full CRUD (create/edit/
  activate/deactivate; delete FK-blocked).
- `subscriptions_screen.dart` (157), `licenses_screen.dart` (181),
  `modules_screen.dart` (138) — read-only overviews.
- `platform_users_screen.dart` (391) — `platform_admins` management.
- `audit_logs_screen.dart` (604) — platform audit trail, human-readable Urdu,
  date-range filters, **no export/share**.

**Super admin** (`lib/presentation/screens/super_admin/`, 684 lines):
`super_admin_main_screen.dart` (69), `super_admin_dashboard_screen.dart` (292),
`madrasa_management_screen.dart` (323, legacy CRUD on `madrasas`).
**Verified: zero references from outside the directory — the entire `super_admin/`
tree is dead code.** Two parallel platform consoles exist; only `/master` is wired.

**Tables:** `tenants`, `tenant_subscriptions`, `license_plans`, `licenses`,
`modules_catalog`, `tenant_modules`, `platform_admins`, `audit_logs`,
`tenant_memberships`, `profiles`, cross-tenant `students`/`staff` counts.

**UX problems:** licenses can't be revoked/extended from UI (read-only);
audit log has no export despite 604 lines of filtering UI; license-plan delete
confirmation not verified in the read (flagged for pre-redesign check).

### 2.12 Parent portal (والدین)

**Screens:** `parent/parent_main_screen.dart` (132) — custom bottom nav
(home/fees/profile, IndexedStack). `parent/parent_dashboard_screen.dart` (541) —
child selector, profile card, attendance/result stats, fee-due stat; **activity
timeline and upcoming exams are permanent empty sections** (`_buildEmptySection`)
with no backing data. `parent/fee_history_screen.dart` (373).

**Providers:** `parent_portal_provider.dart` (214) — `parentChildIdsProvider`
(`student_guardians` link, guardian_user_id + tenant_id), `parentChildrenProvider`,
`parentFeesProvider`, `parentResultsProvider`, `parentAttendanceProvider`
(family; re-checks studentId against the guardian link — forged ids return []),
`parentAnnouncementsProvider` — **verified: defined but consumed by no screen**;
announcements are unreachable in the parent portal.

**UX problems:** two visible placeholder sections on every dashboard load;
parent nav has no announcements tab (3 tabs only); tapping a stat doesn't drill
into detail; no pull-to-refresh; no per-child fee breakdown on the dashboard.

### 2.13 Library (کتب خانہ)

**Screens:** `admin/library_screen.dart` (418) — 3 tabs (تمام کتابیں / جاری /
واجبُ الواپسی), add-book dialog (FAB, admin-only), issue-book dialog, return
dialog with fine.

**Providers:** `library_provider.dart` (332) — `LibraryNotifier`/`LibraryState`
(books, issues, isLoading, error); loads `library_books` + `book_issues`
(`.eq('tenant_id')`); `addBook`, `issueBook`, `returnBook(issueId, {fine})`,
`deleteBook` — all local-first + sync queue.

**Model:** `lib/data/models/library.dart` (129) — `LibraryBook`
(status: available/issued/lost), `BookIssue` (student|staff borrower, dueAt,
fine, `isOverdue` getter).

**UX problems:** **delete book has no confirmation**; no search on the books tab;
no pagination; admin gate is `role.name.contains('admin')` string matching
(inconsistent with permission gating); ISBN accepts anything; no "add copies to
existing book" flow; overdue tab has no fine auto-calculation or reminders.

### 2.14 Auth flow

**Screens:** `auth/auth_gate.dart` (100) — cold start: branded splash →
`restoreSession()` (honors "remember me"; never strands on splash). `auth/
login_screen.dart` (507) — email/password, remember-me, remembered-email
prefill, forgot-password link, `LoadingOverlay`, snackbar errors. `auth/
tenant_picker_screen.dart` (199) — multi-tenant tenant picker. `auth/
no_access_screen.dart` (101) — logout only + "contact your admin" copy. `auth/
forgot_password_screen.dart` (202).

**Providers:** `auth_provider.dart` (549) — `AuthState` (user, isLoading,
errorMessage, isAuthenticated, **permissions Set**, route, isPlatformAdmin);
`AuthNotifier` (restoreSession/login/logout/sendPasswordReset/selectTenant/
refreshPermissions); derived `currentUserProvider`, `userPermissionsProvider`,
`hasPermissionProvider` (family), `hasAllPermissionsProvider`,
`isPlatformAdminProvider`. Permissions via `get_my_permissions_detailed` RPC;
platform admin via `platform_admins` lookup.

**Routing:** `AuthRoute` {home, tenantPicker, noAccess, login}. Platform admins
with zero tenant memberships get `home` (master area) instead of noAccess —
deliberate. **Inconsistency:** login success → `pushReplacement` to `AppShell`,
but `TenantPickerScreen` pushes `RoleHomeScreen` **directly, bypassing
`AppShell`** — the post-picker path skips AppShell's chrome (nav rail/bottom
nav, notification badge).

**UX problems:** no biometric auth; session expiry surfaces as a generic login
screen with no "session expired" message; `no_access_screen` offers only logout
(no in-app access-request path); "show password" toggle not confirmed in the
read.

---

## 3. State management

### 3.1 Provider inventory (`lib/providers/`, 21 files)

All state goes through **flutter_riverpod** (v2-style: `Provider`, `FutureProvider`,
`StateNotifierProvider`; no code-generation / no Riverpod Generator).

| File (lines) | Key providers | Pattern |
|---|---|---|
| `auth_provider.dart` (549) | `authRepositoryProvider`, `authProvider` (StateNotifier<AuthState>), `authRouteProvider`, `isAuthenticatedProvider`, `currentUserProvider`, `currentUserRoleProvider`, `userPermissionsProvider`, `isPlatformAdminProvider`, `hasPermissionProvider` (family), `hasAllPermissionsProvider` | Auth state machine; also exports `AppUser`, `UserRole` from auth_repository |
| `admin_dashboard_provider.dart` (302) | `dashboardStatsProvider` (Future) | Direct Supabase queries for dashboard stats |
| `announcement_provider.dart` (241) | `announcementProvider` (StateNotifier), `announcementListProvider` (Provider<List>) | Direct Supabase |
| `attendance_provider.dart` (106) | `attendanceRepositoryProvider`, `classAttendanceProvider` (family Future), `attendanceStreamProvider` (Stream), `attendanceRecordNotifierProvider` (StateNotifier) | Repository pattern |
| `darja_provider.dart` (384) | `darjaProvider` (StateNotifier<DarjaState>), `darjaListProvider` | Direct Supabase |
| `dashboard_data_provider.dart` (347) | `todayCollectionProvider`, `examsWithoutResultsProvider`, `teacherTodayAttendanceStatusProvider`, `newAdmissionsProvider`, `financeOverviewProvider`, `libraryOverviewProvider`, `safeDarjaListProvider`, `academicOverviewProvider`, `examSummaryProvider` (all Future) | Cross-module dashboard aggregates; direct Supabase |
| `day_schedule_provider.dart` (279) | `teacherDayScheduleProvider`, `accountantDayScheduleProvider`, `examDayScheduleProvider`, `principalDayScheduleProvider`, `clerkDayScheduleProvider` (all Future<List<DayScheduleEvent>>) | 5 near-duplicate role-specific providers |
| `delegation_provider.dart` (153) | `delegationRepositoryProvider`, `delegationsProvider`, `myDelegatableCodesProvider`, `delegationControllerProvider` | Repository pattern |
| `fee_provider.dart` (120) | `feeRepositoryProvider`, `allFeesProvider`, `feesByStudentProvider`, `feesByMonthProvider` (family Futures), `feeSummaryProvider`, `feeNotifierProvider` | Repository pattern |
| `finance_provider.dart` (235) | `financeProvider` (StateNotifier<FinanceState>) | Repository pattern |
| `library_provider.dart` (332) | `libraryProvider` (StateNotifier<LibraryState>) | Direct Supabase |
| `madrasa_provider.dart` (135) | `madrasaProvider` (StateNotifier<MadrasaState>), `madrasaListProvider`, `selectedMadrasaProvider` | Direct Supabase |
| `parent_portal_provider.dart` (214) | `parentChildIdsProvider`, `parentChildrenProvider`, `parentFeesProvider`, `parentResultsProvider`, `parentAttendanceProvider`, `parentAnnouncementsProvider` (all Future) | Direct Supabase; scoped by parent links |
| `result_provider.dart` (140) | `resultRepositoryProvider`, `allExamsProvider`, `examResultsProvider`, `allResultsProvider`, `studentSubjectResultsProvider` (family), `resultNotifierProvider` | Repository pattern |
| `role_ux_provider.dart` (342) | role-UX config providers | Repository pattern (`role_ux_repository`) |
| `scope_manager_provider.dart` (184) | scope management providers | Repository pattern |
| `staff_provider.dart` (113) | staff list/detail providers | Repository pattern |
| `student_provider.dart` (183) | student list/detail/search providers | Repository pattern |
| `teacher_portal_provider.dart` | `teacherAssignmentsProvider`, teacher-scoped data | Direct Supabase |
| `tenant_branding_provider.dart` | tenant logo/name/branding | Direct Supabase |
| `user_management_provider.dart` | users, roles, grants | Direct Supabase |

Provider-type census (declarations): ~49 `FutureProvider`, ~10 `StateNotifierProvider`,
2 `StreamProvider`, remainder plain `Provider`/`Provider.family`.

Tenant scoping: `currentTenantIdProvider` (derived, membership-validated; see
`lib/core/services/tenant_context.dart:148`) is the id every data provider must
scope queries with. `activeTenantIdProvider` is the raw `StateNotifier<String?>`
behind it. The two are complementary, not duplicates — but the distinction is
subtle and only documented in one comment.

### 3.2 Anti-patterns observed

1. **Two data-access styles coexist with no rule.** 10 provider files go through
   `Repository` interfaces (`attendance`, `fee`, `finance`, `result`, `staff`,
   `student`, `delegation`, `role_ux`, `scope_manager`, partly `auth`); 10 hit
   `SupabaseService.client` directly (`admin_dashboard`, `announcement`, `darja`,
   `library`, `madrasa`, `parent_portal`, `teacher_portal`, `tenant_branding`,
   `user_management`, partly `auth`). Same app, same layer, two conventions.
2. **Silent error swallowing:** ~40 `catch (_) {}` blocks in `lib/providers/`;
   at least 8 convert failures into `return const []` (e.g. all 5
   `day_schedule_provider` role providers), so the UI cannot distinguish
   "no data" from "load failed" — no error state is ever reachable there.
3. **Duplicated role-specific providers:** `day_schedule_provider.dart` defines 5
   near-identical `FutureProvider<List<DayScheduleEvent>>` (teacher/accountant/
   exam/principal/clerk) with copy-pasted structure differing only in the source
   providers they compose.
4. **Mixed sync/async permission reads:** `AuthorizationService` caches the
   effective set (async `ensureLoaded`), while `hasPermissionProvider` reads
   `userPermissionsProvider` synchronously — two paths to the same truth that
   can disagree during the load window.
5. **`Provider<List<T>>` derived snapshots** (e.g. `announcementListProvider`,
   `madrasaListProvider`) duplicate StateNotifier state as a second provider
   instead of selecting from the notifier — two sources of truth for one list.
6. **Legacy `UserRole` enum still exported** (`auth_provider.dart` re-exports
   `UserRole` from `auth_repository.dart`; `currentUserRoleProvider` still
   exists) alongside the canonical `tenant_memberships.role` keys — the old
   single-role model lingers in the type system even though `RoleService`
   explicitly forbids trusting it.

---

## 4. Supabase integration

### 4.1 Tables used per module (from `.from('…')` grep across `lib/`)

| Module | Tables |
|---|---|
| Students | `students`, `student_guardians`, `classes` |
| Attendance | `attendance`, `students`, `teacher_class_assignments`, `classes` |
| Fees | `fees`, `fee_structures`, `fee_items`, `invoices`, `payments`, `payment_allocations`, `discounts`, `scholarships`, `refunds` |
| Finance | `transactions`, `accounts`, `income`, `expenses` |
| Exams/Results | `results` (+ exam tables via `result_repository`) |
| Staff/Teachers | `staff`, `teacher_class_assignments`, `user_accounts`, `profiles` |
| Darjas/Classes | `darjas`, `darja_sections`, `classes`, `madrasas` |
| Announcements | `announcements`, `notification_device_tokens`, `devices`, `device_sessions` |
| Users/Roles | `user_accounts`, `app_roles`, `tenant_roles`, `tenant_role_permissions`, `user_permissions`, `permission_delegations`, `permission_scopes`, `permissions` |
| Tenants | `tenants`, `tenant_memberships`, `tenant_settings`, `tenant_modules`, `platform_admins`, `platform_config` |
| Library | `library_books`, `book_issues` |
| Audit | `audit_logs` |

Migrations: **22** in `supabase/migrations/` (`001_tenant_core` → `022_scope_failclosed`).
`001–010` build the multi-tenant core (tenants, memberships, RBAC, RLS, storage,
indexes, seed); `011` licensing; `012` audit logs; `013` auth cleanup;
`014` finance; `015` parent links; `016` sync; `017` notifications;
`018` platform config; `019–022` role-UX schema, RLS, template seeds,
scope fail-closed.

### 4.2 Tenant isolation approach

- **Server-side (real enforcement):** RLS policies on every tenant table
  (migration `007_tenant_rls.sql`), helper functions `is_tenant_member()` and
  `check_tenant_access()`, plus `scope_allows()` for data-scope enforcement
  (`020`/`022`). Writes carry `tenant_id` in the payload; reads filter
  `.eq('tenant_id', tenantId)`.
- **Client-side (defence in depth):** every provider scopes queries with
  `currentTenantIdProvider` (23 `.eq('tenant_id', …)` call sites in
  `lib/providers/` alone); `tenant_context.dart` refuses to query unscoped
  (returns `[]`/null when no membership is loaded).
- **Offline:** Drift local database (`lib/data/local/app_database.dart`,
  2174+ lines, schema v2) + `OfflineSyncService` + `sync_engine.dart` with a
  `conflict_review_screen.dart`; server sync goes through the `sync_apply` RPC.
  Permission sets are cached per (user, tenant) and wiped on sign-out.

### 4.3 RPCs used

`get_my_permissions_detailed` (permission resolution — the most critical),
`sync_apply` (offline sync), `set_user_permission`, `delegate_permission`,
`assign_tenant_role` (user/role administration).

---

## 5. Forms / tables / dialogs inventory

Counts from grep over `lib/presentation/` (67 screen files):

| Element | Count | Notes |
|---|---|---|
| `showDialog` call sites | 27 | across 16 files |
| `AlertDialog(` | 34 | confirm + form dialogs; no shared dialog builder |
| `showModalBottomSheet` | 8 | staff list, user mgmt, profile, fee history, parent dashboard, reports hub, user mgmt hub, results |
| `TextFormField(` | 36 | across only 8 files containing a `Form(` widget — i.e. most text inputs are **not** inside a `Form` (no unified validation) |
| `Form(` widgets | 8 files | form validation is the exception, not the rule |
| `DataTable` / `PaginatedDataTable` | 1 | tables are hand-rolled `ListView`s, not data tables |
| `ListView.builder(` | 19 | the dominant list pattern |
| `SnackBar(` | 126 | feedback is Snackbar-heavy; no centralised toast/snackbar service found |

**Inconsistencies:**
- Dialogs: some modules use `AlertDialog` via `showDialog` (darja, finance,
  library, staff, fee), others use bottom sheets for the same kind of task
  (staff list uses **both**); `student_dialogs.dart` is the only module with a
  dedicated dialogs file. No shared confirm-dialog helper — each screen builds
  its own.
- Forms: only 8 files use `Form`+validation; the rest use bare `TextFormField`s
  with ad-hoc validation. No shared form-field widget is used by screens
  (the `m360_inputs.dart` design widget exists but is unimported — see §6).
- Tables: effectively no `DataTable` usage — 1 instance total. No shared
  sortable/filterable/paginated table component; each list screen re-implements
  search/filter/sort locally (or omits them).
- Feedback: 126 raw `SnackBar` constructions; wording and duration vary per
  screen; no central feedback helper.

---

## 6. Dead code & drift risks

1. **`lib/core/design/` is 100% dead code.** 8 files (~2,000 lines:
   `design_tokens`, `m360_badges`, `m360_buttons`, `m360_cards`, `m360_inputs`,
   `m360_states`, `m360_table`, `responsive`) — **zero** imports from anywhere in
   `lib/`, `test/`, `integration_test/` or `tool/`. A complete design system was
   built and never wired in; every screen uses raw Material widgets
   (36 raw `ElevatedButton` vs 0 `M360Button`).
2. **`lib/presentation/screens/main_screen.dart` (199 lines) is unreferenced** —
   no import anywhere; superseded by `AppShell`. Its only dependent,
   `lib/presentation/screens/teacher/teacher_dashboard_screen.dart` (281 lines),
   is therefore also unreachable — a **second, orphaned teacher dashboard**
   alongside the live `dashboards/teacher_dashboard.dart` (317 lines).
   `role_home.dart` routes teachers to `TeacherHomeScreen`, not either of these.
3. **Migration drift:** `023_super_admin.sql` was applied to live Supabase
   (2026-09-27) but **does not exist in this working copy** (`supabase/migrations/`
   ends at `022`). The branch cannot reproduce the live schema from its own
   migrations directory.
4. **`lib/presentation/screens/super_admin/` (3 files, 684 lines) is fully dead.**
   Verified: zero references from outside the directory. `madrasa_provider.dart`
   (legacy `madrasas`-table provider) is consumed only by two of those dead
   screens — effectively dead too. Two parallel platform consoles existed; only
   `/master` (`master_admin/`) is wired in `main.dart`.
5. **`parentAnnouncementsProvider` is defined but consumed by no screen** —
   announcements are unreachable in the parent portal.
6. **Legacy `UserRole` enum** still exported from `auth_provider.dart` and a
   `currentUserRoleProvider` still provided, though the architecture forbids
   trusting them.
7. **Dual permission vocabularies** (66 dotted + 56 legacy underscore codes)
   permanently double the permission surface every UI check must consider.
8. **"جلد آرہا ہے" (coming-soon) placeholders:** 7 occurrences — the nav IA
   (`nav_destinations.dart`) marks **hostel, transport, certificates** as
   `planned: true` with a shared `PlannedScreen`, even though permission codes
   (`hostel.*`, `transport.*`, `certificates.*`), role fallbacks, and a
   `HostelDashboardScreen` exist. The IA advertises modules with no screens.
   The parent dashboard also shows permanent empty timeline/exams sections, and
   the (dead) teacher dashboard shows a permanent "—" pending card.

---

## 7. Key findings for the redesign (summary)

1. **Permission architecture is sound and must be preserved as-is**: server-resolved
   effective sets, fail-closed offline chain, UI-only guards, RLS as real
   enforcement. The redesign changes *what checks where*, never *how auth works*.
2. **27 role keys, 122 permission codes, 10+ dashboards** — role-aware IA already
   exists (`nav_destinations.dart`); the redesign should adopt and complete it,
   not reinvent it.
3. **The design system exists but is orphaned** (`lib/core/design/`): the fastest
   path to visual consistency is wiring it in (or replacing it deliberately),
   not building a third system.
4. **Data layer is split-brain** (repository vs direct-Supabase providers) and
   **errors are swallowed** (~40 silent catches) — the redesign's loading/error/
   empty states need a provider-hygiene pass first.
5. **No shared table/form/dialog components in use** — every list screen
   hand-rolls its own; this is the highest-leverage component work.
6. **Three advertised modules have no screens** (hostel, transport, certificates)
   — decide: build, hide, or remove from nav before calling the IA complete.
7. **Migration 023 drift** must be resolved (add the file to the branch) before
   any schema-dependent work.
8. **Cross-cutting anti-pattern:** several screens store `WidgetRef? _ref;` as a
   state field via `Consumer(builder: (ctx, ref, _) { _ref = ref; … })`
   (staff list, darja, announcements, library, super_admin screens) — works, but
   bypasses Riverpod's intended scoping.
9. **Route inconsistency:** `TenantPickerScreen` pushes `RoleHomeScreen` directly,
   bypassing `AppShell` — multi-tenant users miss AppShell chrome after picking
   a tenant.

