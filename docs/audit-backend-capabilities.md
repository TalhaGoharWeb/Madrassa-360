# Backend Capability Audit — Missing Modules, License Ops, Audit Export

**Branch:** `redesign/ux-v2` · **Working copy:** `~/workspace/madrassa-redesign-fix`
**Date:** 2026-09-29 · **Method:** read-only grep + file reads. No code changed.

Question answered: for hostel, transport, certificates, master-admin license
operations, and audit-log export — what backend **actually exists**?

---

## 1. Hostel (دارالاقامہ)

| Check | Result |
|---|---|
| Supabase tables | **NONE.** Full table list across migrations 001–022 (40 tables): `accounts, audit_logs, device_sessions, devices, discounts, expenses, fee_items, fee_structures, income, invoice_items, invoices, license_plans, licenses, modules_catalog, notification_device_tokens, notification_preferences, notifications, payment_allocations, payments, permission_delegations, permission_scopes, permissions, platform_admins, platform_config, refunds, role_permissions, roles, schema_migrations, scholarships, student_guardians, teacher_class_assignments, tenant_memberships, tenant_modules, tenant_role_permissions, tenant_roles, tenant_settings, tenant_subscriptions, tenants, transactions, user_permissions`. No `hostel_*`, `rooms`, `beds`, or allocation tables. |
| Local Drift tables | None (`lib/data/local/app_database.dart` — 22 tables, no hostel) |
| Dart models | None |
| Providers/repositories | None |
| Permissions | `hostel.view`, `hostel.manage` exist — `005_rbac.sql:125-127`, Urdu labels in `019_role_ux_schema.sql:120-121`, legacy `manage_hostel`/`view_hostel` in 019:181/197, role templates seed hostel roles (`019:334-361`). Referenced in code only by `app_permissions.dart` constants, `nav_destinations.dart` visibility, and `HostelDashboardScreen` gating. |
| Existing UI | `HostelDashboardScreen` (`lib/presentation/screens/dashboards/hostel_dashboard.dart:1-11`): doc comment states explicitly — *"HONEST EMPTY STATE: there is no hostel data source in the app yet (no hostel tables, no residents, no rooms)."* Stat cards render '—' + 'ابھی دستیاب نہیں'; quick actions point only at real screens (attendance, reports). |
| Module plumbing | `modules_catalog` entry `('hostel','Hostel','ہاسٹل','Hostel rooms and boarders')` — `003_tenant_modules.sql:33`; included in full-plan module list — `011_licensing.sql:165`; role keys `hostel_manager`, `warden`, `nazim_darul_iqama` exist with template permission seeds. |

**Verdict: BACKEND MISSING.** To build for real needs: new migration(s) with
`hostel_buildings`, `hostel_rooms`, `hostel_beds`, `hostel_allocations`
(student↔bed, dates), RLS via `is_tenant_member` pattern, indexes, seed module
enablement; Dart models; repository + providers; sync-queue entries if offline
is required. UI can be built now against isolated repository interfaces, but
every data call must surface honest "backend not connected" states — no fake
numbers.

## 2. Transport (ٹرانسپورٹ)

| Check | Result |
|---|---|
| Supabase tables | **NONE** (see table list above). No `vehicles`, `drivers`, `routes`, `stops`, `transport_assignments`. |
| Local Drift tables | None |
| Dart models | None |
| Providers/repositories | None |
| Permissions | `transport.view`, `transport.manage` exist — `005_rbac.sql:128-130`, Urdu labels `019:122-123`. Code references: `app_permissions.dart` constants + `nav_destinations.dart` only. |
| Existing UI | None — only the `PlannedScreen` ("جلد آرہا ہے") placeholder in nav. |
| Module plumbing | `modules_catalog` entry `('transport','Transport','ٹرانسپورٹ','Routes, vehicles and drivers')` — `003:34`; in full-plan module list — `011:165`. |

**Verdict: BACKEND MISSING.** Needs: `vehicles`, `drivers`, `transport_routes`,
`route_stops`, `transport_assignments` (student↔route/vehicle), optional
transport attendance/fee linkage; RLS; models; repositories; providers. Same
UI-isolation rule as hostel.

## 3. Certificates (اسناد)

| Check | Result |
|---|---|
| Supabase tables | **NONE.** No `certificates` table, no issuance log, no reference/verification numbers. |
| Local Drift tables | None |
| Dart models | None |
| Providers/repositories | None |
| Permissions | `certificates.view`, `certificates.issue` exist — `005_rbac.sql:142-144`, Urdu labels `019:131-132`; `daftar_dar` role template includes `certificates.issue` — `019:314`. Code references: `app_permissions.dart` + `nav_destinations.dart` only. |
| Existing UI — **generation works** | `lib/core/reports/report_catalog.dart:37-51`: two real report definitions — `character_certificate` (کردار سرٹیفکیٹ; conduct left blank for principal to fill by hand) and `transfer_certificate` (منتقلی سرٹیفکیٹ; dues computed from local invoices/payments). Implemented in `lib/core/reports/documents/student_documents.dart:179-271` (`characterCertificate`, `transferCertificate`) with Nastaleeq PDF rendering. Reachable today via ReportsHub → generate/print/share PDF. |
| Missing | Issuance tracking: no table for who was issued what, when, by whom; no reference/serial numbers; no verification flow; no template management UI. |
| Module plumbing | `modules_catalog` entry `('certificates','Certificates','اسناد','Generated certificates')` — `003:39`; in both license-plan module lists — `011:158,165`. |

**Verdict: PARTIAL — generation is buildable now, issuance tracking is not.**
A production Certificates screen can be built today that (a) lists students,
(b) generates the two existing certificate PDFs through the **real** report
pipeline (genuine backend operations: PDF bytes produced, printed, shared), and
(c) shows issuance history as an honest "not tracked yet" state behind an
isolated `CertificateRepository` interface. Needs for full tracking: a
`certificates` table (id, tenant_id, student_id, type, serial/reference no,
issued_by, issued_at, status, payload JSONB), RLS, and a serial-number scheme.

## 4. Master Admin — license operations

**`licenses` table** (`011_licensing.sql:41-62`):
```
id UUID PK, tenant_id UUID NOT NULL (FK tenants, cascade),
plan_id UUID (FK license_plans, set null),
issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
expires_at TIMESTAMPTZ NULLABLE,
status TEXT NOT NULL DEFAULT 'trial'
  CHECK (status IN ('trial','active','grace_period','expired','suspended','cancelled')),
max_users INTEGER, max_students INTEGER,
enabled_modules TEXT[] NOT NULL DEFAULT '{}',
created_at TIMESTAMPTZ
```
**No `revoked_at` column. No `'revoked'` status value** — the CHECK constraint
forbids it.

**RPCs for license revoke/extend/renew: NONE** (grep over all migrations).

**Edge Functions:**
- `manage-tenant/index.ts:4,18-24` — actions are exactly `suspend | reactivate | archive`,
  mapped onto **`tenants.status`**. Writes an audit entry `tenant.${action}` (`:119`).
  **No license actions.**
- `provision-tenant/index.ts:280-299` — the **only** license issuance path:
  inserts a `licenses` row (trial, 30 days) during tenant provisioning.
- No renewal/extension flow exists anywhere.

**RLS** (`011_licensing.sql:96-106`): `"platform admins manage licenses" FOR ALL
USING (is_platform_admin()) WITH CHECK (is_platform_admin())`. Tenant admins
get SELECT on their own rows only.

**Current UI** (`lib/presentation/screens/master_admin/licenses_screen.dart`):
read-only list with status filter. Two problems found:
1. Line 3 doc comment claims *"issue/revoke are server-side actions"* — **no
   such server-side actions exist** for licenses.
2. Line 13: `_licenseStatuses = ['all','active','expired','revoked','suspended']`
   — `'revoked'` **cannot exist** per the CHECK constraint, so that filter chip
   always returns zero rows. (The `'revoked'` status found at `014_finance.sql:262`
   belongs to the **`scholarships`** table, not licenses.)

**Verdict: BACKEND PARTIAL — no new backend needed for real revoke/extend.**
Because RLS grants platform admins `FOR ALL` on `licenses`, genuine
revoke/extend/renew can be implemented **today via direct table updates** (real
operations, no faking):
- Revoke → `status = 'cancelled'` (or `'suspended'`), confirmed dialog, `log_audit` entry.
- Extend/renew → `expires_at = new date` (+ optionally `status = 'active'`).
- Each action must be a confirmed dialog + write the audit log via the existing
  `log_audit()` RPC (`012:65-90`, SECURITY DEFINER, platform-admin path when
  `p_tenant_id IS NULL`).
- Fix: remove the bogus `'revoked'` filter chip (or map it to `'cancelled'`).

## 5. Audit-log export

**`audit_logs` table** (`012_audit_logs.sql:17-30`):
```
id UUID PK, tenant_id UUID NULLABLE (FK tenants, cascade),
user_id UUID NULLABLE (FK auth.users, set null),
action TEXT NOT NULL, entity TEXT, entity_id TEXT,
old_data JSONB, new_data JSONB, metadata JSONB,
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
```
**No IP/device columns** — IP/device metadata is possible only inside `metadata`
JSONB (writer-dependent; `log_audit` accepts `p_metadata JSONB`).

**Existing export code: NONE.** `export-tenant` Edge Function exports tenant
*datasets* to JSONL for offboarding — it does not touch `audit_logs`.
`audit_logs_screen.dart` (604 lines) has filters + list + detail, **no export
buttons** of any kind (verified by grep for export/share/csv/pdf/print).

**Read access:** the master-admin screen already SELECTs `audit_logs` with
filters as a platform admin, so the data the user sees is already authorized.

**Verdict: BUILDABLE NOW — no new backend required.** Client-side export from
already-fetched, already-authorized rows:
- CSV: same UTF-8-BOM pattern the reports module already uses (`lib/core/reports/export/`).
- PDF: existing Nastaleeq PDF pipeline (`urdu_pdf.dart`, `pdf_kit.dart`).
- Include applied filters, date range, institution, export timestamp (per spec §57).
- Do not add the button until the generator is wired — no dead export buttons.

---

## Verdict table

| Module | Tables exist? | Models? | Providers? | Permissions? | Verdict |
|---|---|---|---|---|---|
| Hostel (دارالاقامہ) | No | No | No | `hostel.view/manage` (nav + dashboard gating only) | **BACKEND MISSING** — needs `hostel_buildings/rooms/beds/allocations` tables + RLS + models + providers. Build UI against isolated repository interfaces with honest empty states. |
| Transport (ٹرانسپورٹ) | No | No | No | `transport.view/manage` (nav only) | **BACKEND MISSING** — needs `vehicles/drivers/routes/stops/assignments` tables + RLS + models + providers. Same isolation rule. |
| Certificates (اسناد) | No | No | No | `certificates.view/issue` (nav only; `daftar_dar` seeded with issue) | **PARTIAL** — PDF *generation* (character + transfer certificates) works today via the real report pipeline; *issuance tracking* (log, serial numbers, verification) needs a new `certificates` table. Build generation UI now; isolate tracking behind a repository interface. |
| License revoke/extend/renew | `licenses` table exists (statuses: trial/active/grace_period/expired/suspended/cancelled — **no 'revoked'**) | n/a | n/a | platform-admin RLS `FOR ALL` | **BUILDABLE NOW** — no RPC/Edge Function exists, but none is needed: direct platform-admin table updates are real operations. Add confirmed dialogs + `log_audit` entries. Fix bogus 'revoked' filter chip in `licenses_screen.dart:13`. |
| Audit-log export | `audit_logs` table exists (no IP/device cols; metadata JSONB only) | n/a | n/a | platform-admin read (screen already queries) | **BUILDABLE NOW** — no backend needed; client-side CSV (reports export pattern) / PDF (existing pipeline) from already-authorized rows. No dead buttons. |

## Notes / traps for implementers

1. `licenses_screen.dart:13` — the `'revoked'` status filter is impossible data; fix during redesign.
2. `licenses_screen.dart:3` — the "issue/revoke are server-side actions" comment is false; issuance is `provision-tenant`-only, revoke does not exist yet.
3. `manage-tenant` actions (`suspend/reactivate/archive`) operate on **tenants**, not licenses — do not conflate tenant suspension with license revocation in the UI.
4. `HostelDashboardScreen` already models the honest-empty-state pattern the missing modules should copy.
5. Certificate generation must go through `report_catalog`/`reports_service` (the real pipeline), never a parallel PDF reimplementation.
