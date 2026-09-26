# Phase 2 — Permission Model Design

**Date:** 2026-09-26 · **Branch:** `feat/role-aware-ux`
**Implements:** Mission §§16–29, 50–55, 61–67, 76, 87–92

## 1. Vocabulary decision (single source of truth)

- **Canonical permission codes are the dotted DB codes** (`students.view`, `attendance.mark`, …).
  The legacy Dart underscore vocabulary (`view_students`, …) is retired: `AppPermissions`
  constants are re-valued to the dotted strings so every existing call site keeps working
  with zero dropped codes. The `_dottedToLegacy` translation map is deleted.
- **No technical term reaches normal UI.** DB carries `label_urdu` (e.g. `students.create` →
  `نئے طلبہ شامل کرنا`) and `category_urdu` (e.g. `طلبہ`). Flutter never shows raw codes.
- Role names in `tenant_memberships.role` remain the internal key; UI shows `display_urdu`.

## 2. Precedence (deterministic, §89)

```
explicit deny  >  explicit grant  >  delegation grant  >  role grant  >  default deny
```

- `user_permissions` rows carry `effect ∈ {grant, deny}`.
- A deny on a code removes it even if a role grants it. Ordinary users cannot create
  unrestricted denies/grants: only holders of `roles.assign` (or tenant_owner/tenant_admin)
  may write `user_permissions` / `tenant_role_permissions` (enforced in RPCs + RLS).

## 3. Database changes

### 3.1 Migration `019_role_ux_schema.sql`

1. **`permissions` — human labels** (new nullable-then-backfilled columns):
   - `label_urdu TEXT` — e.g. `attendance.mark` → `حاضری لگانا`
   - `category_urdu TEXT` — grouping for the permission-manager UI
     (`طلبہ`, `اساتذہ`, `عملہ`, `حاضری`, `تعلیم`, `امتحانات`, `نتائج`, `فیس`, `مالیات`,
      `کتب خانہ`, `دارالاقامہ`, `ٹرانسپورٹ`, `والدین`, `اعلانات`, `رپورٹس`, `دستاویزات`,
      `اسناد`, `صارفین`, `ذمہ داریاں`, `ترتیبات`, `شعبہ جات`, `سرگرمی`, `پلیٹ فارم`)
   - `sort_order INT` — display order inside a category
   - Backfill all 66 codes (see §7). `label_urdu NOT NULL` after backfill.

2. **`tenant_roles` — per-tenant editable roles** (mission §87: tenant records carry `tenant_id`):
   ```
   id UUID PK, tenant_id UUID NOT NULL → tenants(id) ON DELETE CASCADE,
   key TEXT NOT NULL,                       -- e.g. 'ustad', 'naib_mohtamim', custom 'deputy_nazim'
   display_name TEXT NOT NULL,              -- English admin label
   display_urdu TEXT NOT NULL,              -- e.g. 'استاد'
   template_key TEXT,                       -- which template it was cloned from (NULL = fully custom)
   is_active BOOLEAN NOT NULL DEFAULT TRUE,
   created_by UUID → auth.users, created_at, updated_at,
   UNIQUE (tenant_id, key)
   ```
   The global `roles` table stays as the **immutable template catalog** (plus platform roles).

3. **`tenant_role_permissions`**:
   ```
   tenant_role_id UUID → tenant_roles(id) ON DELETE CASCADE,
   permission_id  UUID → permissions(id)  ON DELETE CASCADE,
   PRIMARY KEY (tenant_role_id, permission_id)
   ```

4. **Backfill**: for every existing tenant, materialize one `tenant_roles` row per template
   key (§6 list) and copy the template's permission set into `tenant_role_permissions`.
   Idempotent (`ON CONFLICT DO NOTHING`).

5. **`tenant_memberships.role` — open the enum**: `ALTER TABLE … DROP CONSTRAINT`
   on the `role IN (…)` CHECK; add trigger `tenant_memberships_validate_role()` ensuring
   `NEW.role` is a key in `tenant_roles` for that tenant (after backfill the 10 legacy names
   exist there, so existing rows stay valid). `UNIQUE(user_id, tenant_id)` unchanged —
   one primary role per user per tenant; exceptions via `user_permissions`.

6. **`user_permissions` — per-user overrides**:
   ```
   id UUID PK, tenant_id UUID NOT NULL → tenants CASCADE, user_id UUID NOT NULL → auth.users CASCADE,
   permission_id UUID NOT NULL → permissions CASCADE, effect TEXT NOT NULL CHECK (effect IN ('grant','deny')),
   reason TEXT, created_by UUID, created_at,
   UNIQUE (tenant_id, user_id, permission_id)
   ```

7. **`permission_scopes` — plain-language data scope** (§23–25, §67):
   ```
   id UUID PK, tenant_id, user_id, permission_id → permissions,
   scope_type TEXT NOT NULL CHECK (scope_type IN ('all','department','classes','students')),
   scope_ref JSONB NOT NULL DEFAULT '{}',
     -- 'department' → {"department": "بنات"} ; 'classes' → {"class_ids": ["uuid",…]} ;
     -- 'students' → {"student_ids": ["uuid",…]} ; 'all' → {}
   created_by, created_at, UNIQUE (tenant_id, user_id, permission_id)
   ```
   UI language: `all` → `پورا مدرسہ`, `department` → `صرف میرے شعبے کے افراد`,
   `classes` → `صرف میری مقرر کردہ جماعتوں کے طلبہ`, `students` → `صرف میرے طلبہ`.

8. **`permission_delegations` — delegation with ceilings** (§26–27):
   ```
   id UUID PK, tenant_id, delegator_id → auth.users, delegatee_id → auth.users,
   permission_id → permissions, scope_type TEXT (same CHECK), scope_ref JSONB DEFAULT '{}',
   starts_at TIMESTAMPTZ DEFAULT now(), expires_at TIMESTAMPTZ,
   created_by, created_at,
   UNIQUE (tenant_id, delegatee_id, permission_id),
   CHECK (delegator_id <> delegatee_id), CHECK (expires_at IS NULL OR expires_at > starts_at)
   ```
   Trigger `delegation_ceiling_check()`: the delegator must (a) hold `roles.assign` or be
   tenant_owner/tenant_admin in that tenant, AND (b) effectively hold the delegated permission
   code themselves (role + user grants, minus denies; delegations do **not** chain).

9. **Auto-audit triggers** (§83): AFTER INSERT/UPDATE/DELETE on `tenant_memberships`,
   `tenant_roles`, `tenant_role_permissions`, `user_permissions`, `permission_delegations`
   → `public.log_audit()` row with structured `action`/`entity`/`old_data`/`new_data`
   (human-readable rendering happens in Flutter from `label_urdu` + user names).

10. **Principal safety** (§28): trigger `protect_last_owner()` on `tenant_memberships`
    (UPDATE/DELETE): refuse to remove/deactivate/re-role the last active `tenant_owner`
    of a tenant. Destructive tenant actions require the Flutter danger-zone confirmation;
    the trigger is the backstop.

### 3.2 Migration `020_role_ux_rls.sql`

1. **RLS on all new tables** (`tenant_roles`, `tenant_role_permissions`, `user_permissions`,
   `permission_scopes`, `permission_delegations`): SELECT for tenant members; write policies
   require `tenant_has_permission(tid, 'roles.assign')` (or owner/admin) — the DB never trusts
   client-sent roles.
2. **Rewrite `tenant_has_permission(p_tenant_id, p_code)`** to resolve through
   `tenant_roles`/`tenant_role_permissions` (+ `user_permissions` with deny>grant precedence,
   + active `permission_delegations`). Platform-admin short-circuit retained.
3. **Rewrite `get_my_permissions(p_tenant_id)`**: `p_tenant_id` is now **honored**
   (NULL = all tenants, as today). Same precedence. Keep `RETURNS TABLE(code TEXT)` so
   `has_permission()` keeps working. Add `get_my_permissions_detailed(p_tenant_id)`
   → `(code, tenant_id, source)` where source ∈ {role, override, delegation} for the new client.
4. **Scope enforcement helper**:
   `scope_allows(p_tenant_id, p_user_id, p_code, p_class_id UUID DEFAULT NULL)` —
   FALSE when no scope row exists (fail-closed since migration 022; see §3.4),
   TRUE when scope is `all`, when the class is in the user's assigned classes
   (`teacher_class_assignments`, active) for `classes` scope, etc. Used by RLS on
   `attendance` and `results` write policies so a class-scoped teacher cannot
   mark/enter outside their classes even via raw API.
   Every effective grant gets a `permission_scopes` row: migration 022 backfills
   `all` rows for existing grants and adds insert-only provisioning triggers
   (membership / role-grant / explicit-grant / delegation), so "no row" only
   ever means "no grant". A narrower-than-`all` default is seeded only for
   teachers (`classes` from their active `teacher_class_assignments`).

### 3.4 Migration `022_scope_failclosed.sql` — the fail-closed flip

Before 022, `scope_allows()` returned TRUE when no `permission_scopes` row
existed — a fail-open default. 022 flips the contract:

1. **New columns** on `permission_scopes`: `starts_at` / `expires_at`
   (nullable; a grant outside its window denies), `name_ur` / `name_en`
   (nullable display labels).
2. **Backfill** of explicit `all` rows for every effective grant (active
   memberships × effective codes, minus denies; active delegations, minus
   denies) — run BEFORE the behavior change, so no live grant is revoked.
3. **`scope_allows()` rewritten**: missing row → FALSE; future `starts_at`
   → FALSE; expired `expires_at` → FALSE. `all` / `classes` / `students`
   evaluation and the `department`-is-unevaluatable fail-closed rule are
   unchanged.
4. **Provisioning triggers** (insert-only, `ON CONFLICT DO NOTHING` so they
   never widen a narrowed row): new/reactivated/re-roled memberships, new
   role-permission grants, explicit user grants, and new delegations each
   create the corresponding `all` row. Delegations provision as `all` to
   preserve the pre-022 effective behavior of delegated codes.
5. **Client contract** (`ScopeService`): a missing scope row or a scope-load
   error is FAIL-CLOSED (deny / hide / filter to nothing) — never read as
   "unrestricted". `ScopeGuard` hides its child in the same situations.

Executable proof: `supabase/tests/phase11_authorization.sql` (68 assertions:
precedence, tenant isolation, delegation ceilings, last-owner safety, the
022 fail-closed behavior incl. provisioning triggers, RPC interplay).
5. **Management RPCs** (SECURITY DEFINER, authorization checked inside — §62):
   - `assign_tenant_role(p_tenant_id, p_user_id, p_role_key)` — requires `roles.assign`.
   - `set_role_permissions(p_tenant_role_id, p_codes TEXT[])` — requires `roles.assign`;
     refuses to strip the last owner-capable role's `roles.assign` (safety).
   - `set_user_permission(p_tenant_id, p_user_id, p_code, p_effect)` — requires `roles.assign`.
   - `create_tenant_role(p_tenant_id, p_key, p_urdu, p_template_key)` — requires `roles.assign`.
   - `delegate_permission(p_tenant_id, p_delegatee, p_code, p_scope_type, p_scope_ref, p_expires_at)`
     — ceiling enforced in trigger; RPC checks the delegator's own grant.
   All RPCs write audit rows (via the triggers, which fire under the definer).

### 3.3 What deliberately does NOT change

- `007`/`014` business-table policies keep working: they call `tenant_has_permission()`,
  whose internals are replaced but contract kept.
- Legacy `user_roles`/`profiles.role` branches: left as-is (deprecated) until the 02/06
  policies they serve are retired (noted in audit §C13 — out of scope for this mission).
- `platform_admins` / `/master` console untouched.

## 4. Flutter architecture (Phase 5)

- **Single vocabulary**: `AppPermissions` constants re-valued to dotted codes
  (e.g. `viewStudents = 'students.view'`); `_dottedToLegacy` deleted; `normalizeServerCodes`
  becomes a pass-through validator (unknown codes → warning, dropped).
- `PermissionService.loadForUser` → per-tenant: `get_my_permissions_detailed(p_tenant_id)`
  for the **active** tenant; reload on tenant switch (fix audit §C3).
- New `AuthorizationService` (facade): `can(code)`, `canAll`, `canAny`, `scopeFor(code)`,
  `canDelegate(code)`, `roleKeys`, plus Urdu label lookup `labelFor(code)`.
- `ScopeService`: loads `permission_scopes`; exposes plain-language scope text and
  class/student id filters for list screens.
- `RoleService`: tenant role CRUD via the §3.2 RPCs (never raw table writes from UI).
- `DashboardService`: maps role key → dashboard config (cards, alerts, quick actions).
- Guards: `PermissionGuard(required: '…', child:…, fallback:…)`,
  `RoleGuard(roles:{…})`, `ScopeGuard` — centralized, no duplicated logic.
- `AppUser.role` resolved from `tenant_memberships` (active tenant), not app_metadata.
- Offline fallbacks re-keyed to the new role keys with the template permission sets.

## 5. Role templates (§6, mission §§17/51–53)

Global `roles` rows (template catalog, `is_system=TRUE`) — key / Urdu / scope:

| key | Urdu | base permissions (curated) | default scope |
|---|---|---|---|
| tenant_owner | مالک | all tenant codes | all |
| tenant_admin | ناظم اعلیٰ | all tenant codes | all |
| mohtamim | مہتمم | all tenant codes | all |
| naib_mohtamim | نائب مہتمم | all except `roles.assign` mgmt? no — all tenant codes | all |
| nazim_aala | ناظم اعلیٰ | students/teachers/staff/attendance/academics/reports/users.view, announcements | all |
| nazim_taleem | ناظم تعلیم | academics.*, exams.*, results.*, attendance.view, teachers.view, reports.* | all |
| nazim_intizamia | ناظم انتظامیہ | staff.*, documents.*, notifications.send, users.view | all |
| nazim_maliyat | ناظم مالیات | fees.*, finance.* | all |
| daftar_dar | دفتر دار | students.view/create/update, fees.view/collect, documents.*, certificates.issue, notifications.view | all |
| principal | پرنسپل | (legacy) academics/exams/results full, reports, attendance.view, staff.view, fees.view | all |
| teacher | استاد | students.view, attendance.view/mark/edit, exams.view, results.view/enter/edit, notifications.view | **classes** |
| ustad | استاد | = teacher | classes |
| ustad_hifz | مدرس حفظ | = teacher + hostel.view | classes |
| nazim_hifz | ناظم حفظ | academics.view, exams.view/create, results.view/enter/edit, attendance.view | department (حفظ) |
| nazim_darul_iqama | ناظم دارالاقامہ | hostel.*, students.view, attendance.view | department (دارالاقامہ) |
| warden | وارڈن | hostel.view, attendance.view/mark, students.view | department (دارالاقامہ) |
| mumtahin | ممتحن | exams.view/create/update, results.view/enter/edit, students.view | all |
| accountant | اکاؤنٹنٹ | (legacy) fees.*, finance.*, reports.* | all |
| librarian | لائبریرین | library.* | all |
| hostel_manager | ہاسٹل مینیجر | hostel.* | all |
| store_incharge | اسٹور انچارج | documents.*, reports.view | all |
| hr_incharge | عملہ انچارج | staff.*, users.view, attendance.view, reports.view | all |
| staff | عملہ | attendance.view/mark | all |
| parent | والدین | notifications.view (+ student-scoped reads via existing fallbacks) | students (own) |
| student | طالب علم | notifications.view | students (own) |

Legacy 10 keys keep their 005 permission sets (unchanged behavior for existing tenants);
new keys get the curated sets above. All are **editable per tenant** via `tenant_roles`
(the backfill in 019 materializes every key for every tenant).

## 6. Delegation ceilings (§27)

- Only `roles.assign` holders (or tenant_owner/tenant_admin) may delegate, and only codes
  they effectively hold. Enforced in the `delegation_ceiling_check()` trigger — the UI
  simply won't offer codes outside the ceiling (computed via `canDelegate`).
- Delegations never chain (a delegated code cannot itself be re-delegated).
- Expiry is honored in `tenant_has_permission`/`get_my_permissions` (`expires_at IS NULL
  OR expires_at > now()`).

## 7. Urdu permission labels (019 backfill — full list)

| code | label_urdu | category_urdu |
|---|---|---|
| students.view | طلبہ دیکھنا | طلبہ |
| students.create | نئے طلبہ شامل کرنا | طلبہ |
| students.update | طلبہ کی معلومات درست کرنا | طلبہ |
| students.delete | طلبہ کا ریکارڈ ختم کرنا | طلبہ |
| teachers.view | اساتذہ کو دیکھنا | اساتذہ |
| teachers.create | نئے اساتذہ شامل کرنا | اساتذہ |
| teachers.update | اساتذہ کی معلومات درست کرنا | اساتذہ |
| teachers.delete | اساتذہ کا ریکارڈ ختم کرنا | اساتذہ |
| staff.view | عملے کو دیکھنا | عملہ |
| staff.create | نیا عملہ شامل کرنا | عملہ |
| staff.update | عملے کی معلومات درست کرنا | عملہ |
| staff.delete | عملے کا ریکارڈ ختم کرنا | عملہ |
| attendance.view | حاضری دیکھنا | حاضری |
| attendance.mark | حاضری لگانا | حاضری |
| attendance.edit | حاضری درست کرنا | حاضری |
| attendance.delete | حاضری کا ریکارڈ ختم کرنا | حاضری |
| academics.view | تعلیمی نظام دیکھنا | تعلیم |
| academics.manage | تعلیمی نظام ترتیب دینا | تعلیم |
| exams.view | امتحانات دیکھنا | امتحانات |
| exams.create | امتحان بنانا | امتحانات |
| exams.update | امتحان میں تبدیلی کرنا | امتحانات |
| exams.delete | امتحان ختم کرنا | امتحانات |
| exams.publish | امتحان کا اعلان کرنا | امتحانات |
| results.view | نتائج دیکھنا | نتائج |
| results.enter | نمبر درج کرنا | نتائج |
| results.edit | نمبر درست کرنا | نتائج |
| results.publish | نتائج شائع کرنا | نتائج |
| fees.view | فیس کا حساب دیکھنا | فیس |
| fees.create | فیس مقرر کرنا | فیس |
| fees.collect | فیس وصول کرنا | فیس |
| fees.refund | فیس واپس کرنا | فیس |
| finance.view | مالی حساب دیکھنا | مالیات |
| finance.create | مالی لین دین درج کرنا | مالیات |
| finance.update | مالی ریکارڈ درست کرنا | مالیات |
| finance.delete | مالی ریکارڈ ختم کرنا | مالیات |
| finance.approve | مالی لین دین کی منظوری دینا | مالیات |
| library.view | کتب خانہ دیکھنا | کتب خانہ |
| library.manage | کتب خانے کا انتظام کرنا | کتب خانہ |
| hostel.view | دارالاقامہ دیکھنا | دارالاقامہ |
| hostel.manage | دارالاقامہ کا انتظام کرنا | دارالاقامہ |
| transport.view | ٹرانسپورٹ دیکھنا | ٹرانسپورٹ |
| transport.manage | ٹرانسپورٹ کا انتظام کرنا | ٹرانسپورٹ |
| parents.view | والدین کی معلومات دیکھنا | والدین |
| notifications.view | اعلانات دیکھنا | اعلانات |
| notifications.send | اعلان بھیجنا | اعلانات |
| reports.view | رپورٹس دیکھنا | رپورٹس |
| reports.export | رپورٹس محفوظ کرنا | رپورٹس |
| documents.view | دستاویزات دیکھنا | دستاویزات |
| documents.manage | دستاویزات کا انتظام کرنا | دستاویزات |
| certificates.view | اسناد دیکھنا | اسناد |
| certificates.issue | سند جاری کرنا | اسناد |
| users.view | صارفین دیکھنا | صارفین |
| users.create | نیا صارف بنانا | صارفین |
| users.update | صارف کی معلومات درست کرنا | صارفین |
| users.deactivate | صارف غیر فعال کرنا | صارفین |
| roles.view | ذمہ داریاں دیکھنا | ذمہ داریاں |
| roles.assign | ذمہ داریاں سونپنا | ذمہ داریاں |
| settings.view | ترتیبات دیکھنا | ترتیبات |
| settings.update | ترتیبات تبدیل کرنا | ترتیبات |
| modules.view | شعبے دیکھنا | شعبہ جات |
| modules.manage | شعبے فعال یا غیر فعال کرنا | شعبہ جات |
| audit.view | سرگرمی کا ریکارڈ دیکھنا | سرگرمی |
| tenants.view | مدارس دیکھنا | پلیٹ فارم |
| tenants.create | نیا مدرسہ بنانا | پلیٹ فارم |
| tenants.update | مدرسے کی معلومات درست کرنا | پلیٹ فارم |
| tenants.suspend | مدرسہ معطل یا بحال کرنا | پلیٹ فارم |

## 8. Phase sequencing from here

- **P3a** `019_role_ux_schema.sql` — §3.1 (tables, labels, backfill, triggers for validation/safety/audit).
- **P3b** `020_role_ux_rls.sql` — §3.2 (RLS, rewritten helpers, scope helper, RPCs).
- Apply via Management API; verify with real queries (tenant isolation spot-checks).
- **P5** Flutter services + guards + vocabulary unification (one child, big).
- **P6** provision-tenant seeds tenant_roles for new tenants; role template rows in `roles`.
- **P7/P8** dashboards + permission manager (split children).
- **P12** permission matrix tests (SQL-level + Dart unit + widget).
