# Modules — per-module tenant behavior & permission codes

**Status (2026-09-25, Phase 4):** the permission catalog (66 codes, 005) and
the tenant-bound RLS policies (007) are written and parse-validated but
**never applied to a live database**. Module gating in the client is
contract-only (see `MULTI_TENANCY.md` §§32–33 section). This doc is the
authoritative map of what each module touches and which permission codes
guard it — nothing here is production-true until staging runs green.

## Reading this table

- **Tables** — business tables the module reads/writes (all carry
  `tenant_id`, immutable after insert).
- **RLS** — the 007 policy name stem (`<stem>_select_tenant` etc.);
  SELECT = `is_platform_admin() OR (is_tenant_member(tenant_id) AND
  (tenant_has_permission(tenant_id,'<code>') OR <ownership fallback>))`.
- **Permission codes** — real codes from `005_rbac.sql` (verified). Note
  the asymmetries 007's header documents: `results` has no `.delete`
  (`edit` is the strongest mutation code); `fees` has no `.update`/`.delete`
  (`collect` covers payment mutation); `attendance` uses `.mark`/`.edit`
  instead of `.create`/`.update`.
- **Portal scoping** — how the parent/teacher portals restrict the module
  (migration 015 link tables + scoped providers, Phase 4).

| Module (اردو) | Tables | Tenant behavior | Permission codes | Portal scoping |
|---|---|---|---|---|
| students (طلبہ) | `students` | `tenant_id` FK→tenants, immutable; `idx_students_tenant_class` hot path | `students.view` / `.create` / `.update` / `.delete` | Parent: only linked children (`parentChildrenProvider`). Teacher: only students of assigned classes (`teacherClassStudentsProvider`) |
| staff (عملہ) | `staff` | same as students; salary/CNIC columns exist — teacher/parent reads blocked by RLS | `staff.view` / `.create` / `.update` / `.delete` | Not exposed in parent/teacher portals |
| teachers (اساتذہ) | `staff` (+ `teacher_class_assignments`) | teacher records live in `staff`; assignments are the separate link table (015) | `teachers.view` / `.create` / `.update` / `.delete` | Teacher portal is scoped *by* the assignment table, not *to* it |
| attendance (حاضری) | `attendance` | `tenant_id` + `(tenant_id, class_id, date)` index | `attendance.view` / `.mark` / `.edit` / `.delete` | Parent: own children's records (`parentAttendanceProvider`, re-checks link). Teacher: `classAttendanceProvider` for assigned classes only |
| academics (تعلیمیات) | `darjas`, `classes`, `darja_sections` | structural tables; all members read, only `academics.manage` mutates | `academics.view` / `academics.manage` | Teacher: assigned classes only (`teacherAssignedClassesProvider`) |
| exams (امتحانات) | `exams` | schedules per tenant | `exams.view` / `.create` / `.update` / `.delete` / `.publish` | Not yet in portals (Phase 5) |
| results (نتائج) | `results` | per-student subject rows; `idx_results_tenant_student` | `results.view` / `.enter` / `.edit` / `.publish` (no `.delete` — `edit` is strongest) | Parent: own children (`parentResultsProvider`). Teacher: results of assigned-class students only |
| fees (فیس) | `fees` | per-student monthly dues; `idx_fees_tenant_student`; status is DB-generated | `fees.view` / `.create` / `.collect` / `.refund` (no `.update`/`.delete`) | Parent: own children (`parentFeesProvider`, drives fee-history screen) |
| finance (مالیات) | `finance_transactions` | tenant ledger; sensitive — narrow role grants | `finance.view` / `.create` / `.update` / `.delete` / `.approve` | Not exposed in parent/teacher portals |
| library (لائبریری) | `library_books`, `book_issues` | catalogue + issuance per tenant | `library.view` / `library.manage` | Not yet in portals (Phase 5) |
| hostel (ہاسٹل) | *(legacy tables)* | no 007 RLS rewrite yet — **unscoped until covered** | `hostel.view` / `hostel.manage` | Not exposed in portals |
| transport (ٹرانسپورٹ) | *(legacy tables)* | no 007 RLS rewrite yet — **unscoped until covered** | `transport.view` / `transport.manage` | Not exposed in portals |
| parents (والدین) | `student_guardians` (015) | link table; guardians SELECT own rows in own tenants; tenant admins manage | `parents.view` (link management is tenant-admin via RLS, no separate mutation code) | The parent portal's identity source |
| notifications (اطلاعات) | `announcements` | tenant announcements; `target` ∈ all/teachers/parents/students/specific | `notifications.view` / `notifications.send` | Parent: `target` ∈ {all, parents} (`parentAnnouncementsProvider`); parent role holds only `notifications.view` |
| reports (رپورٹس) | views (`attendance_summary`, `fee_summary`) | `security_invoker = true` (Postgres 15+) so caller RLS applies | `reports.view` / `reports.export` | Not yet in portals (Phase 5) |
| documents (دستاویزات) | `documents` bucket | storage path `{tenant_id}/…`, membership-checked (008) | `documents.view` / `documents.manage` | Not yet in portals (Phase 5) |
| certificates (اسناد) | *(no dedicated table in 001–013)* | — | `certificates.view` / `certificates.issue` | Not yet in portals (Phase 5) |

## Cross-cutting rules (apply to every module)

1. **DB is the enforcement point.** Client-side scoping (`.eq('tenant_id', …)`,
   link-table filters) is a companion; a forged client can never widen
   access past RLS.
2. **Null tenant = no query.** `currentTenantIdProvider == null` (logged
   out / memberships loading) → every portal provider returns [].
3. **Tenant admins manage links.** `student_guardians` and
   `teacher_class_assignments` are writable only by tenant admins
   (`is_tenant_admin()`) and platform admins — teachers cannot assign
   themselves classes, parents cannot link themselves to children.
4. **Legacy `parent_user_id` is deprecated.** 007's ownership fallbacks
   still reference `students.parent_user_id` for compatibility; all new
   portal code joins `student_guardians`. The column is backfilled into
   the link table once (015) and must not be written by new code.
5. **Module gating is UX-only for now.** A disabled module is hidden in
   the client, but RLS does not consult `tenant_modules` (documented
   Phase-8 hardening item).

## Role → module grants (005, condensed)

- `tenant_owner` / `tenant_admin`: all 61 tenant-scoped codes.
- `principal`: academics (view+manage), exams (all), results (view/enter/edit/publish), reports, attendance.view, staff.view, fees.view.
- `teacher`: students.view, attendance (view/mark/edit), exams.view, results (view/enter/edit), notifications.view.
- `accountant`: fees (view/create/collect/refund), finance (all), reports.
- `librarian`: library (view/manage). `hostel_manager`: hostel (view/manage).
- `parent` / `student`: `notifications.view` only — everything else in
  their portals arrives via link-table scoping + 007 ownership fallbacks.
- `staff`: attendance (view/mark).
- `platform_owner`: all 66 codes. `platform_support`: tenants.view,
  users.view, audit.view, reports.view.
