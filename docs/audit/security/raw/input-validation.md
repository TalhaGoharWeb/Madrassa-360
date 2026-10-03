# Input Validation Audit — Madrassa-360

**Date:** 2026-10-03 · **Branch:** `redesign/ux-v2` · **Scope:** every user-controlled input, client vs backend-boundary validation
**Method:** read-only static audit of `lib/`, `supabase/migrations/`, `supabase/functions/`
**Governing rule:** validation must exist at the backend boundary even where frontend validation exists. Every security-relevant field validated client-only is a finding.

---

## (a) Input inventory

Legend: C = client (Dart) validation · B = backend-boundary validation (Postgres CHECK/domain/trigger, RPC allow-list, Edge Function guard). Verdict: **PASS** (both layers or backend-sufficient), **CLIENT-ONLY** (backend trusts client), **NONE**.

### Edge Function JSON bodies

| Input | Entry point | C | B | Verdict |
|---|---|---|---|---|
| `provision-tenant` body: name (2–120), slug (regex ≤60), plan_id (UUID), admin{name,email,password≥6}, modules[] vs catalog, email, website (http/https) | `supabase/functions/provision-tenant/index.ts` | n/a | strict schema, length limits, allow-lists | **PASS** |
| `manage-users` actions: user_id/email/password/tenant_id/role UUID+format checks per action | `supabase/functions/manage-users/index.ts` | n/a | per-action type/format checks | **PASS** |
| `manage-tenant` / `export-tenant`: `tenant_id` UUID | `supabase/functions/manage-tenant/index.ts`, `export-tenant/index.ts` | n/a | UUID format | **PASS** |
| `send-notification`: tenant_id, notification_id, user_id UUIDs; type ≤64; title ≤200; channels allow-list | `supabase/functions/send-notification/index.ts` | n/a | present | **PARTIAL** — see F-04 |
| `send-notification`: `title_urdu`, `body`, `body_urdu` | same | n/a | **none** — no length, no type check | **NONE** — F-04 |
| `send-notification`: `data` JSONB payload → FCM | same | n/a | object-shape only; keys/values unbounded | **NONE** — F-05 |
| All Edge Function bodies: unknown JSON keys | all 5 functions | n/a | silently ignored everywhere | **NONE** — F-12 |
| All Edge Function bodies: total size | all 5 functions (`readJsonBody` / `req.json()`) | n/a | **no cap** | **NONE** — F-11 |

### RPC arguments (`supabase/migrations/`)

| Input | Entry point | C | B | Verdict |
|---|---|---|---|---|
| `sync_apply(p_entity, p_entity_id, p_base_revision, p_payload, p_op)` | `016_sync.sql` → `027` | form-level | entity/op allow-listed via CASE; id UUID-typed; table name via `%I` | **PARTIAL** — see F-01, F-02, F-03 |
| `assign_tenant_role(p_tenant_id, p_user_id, p_role_key)` | `020_role_ux_rls.sql:580` | form-level | role key validated by `tenant_memberships_validate_role` trigger | **PASS** |
| `set_user_permission(..., p_code, p_effect)` | `020_role_ux_rls.sql:677` | form-level | `p_effect IN ('grant','deny')`; code checked vs `permissions` catalog | **PASS** |
| `create_tenant_role(p_key, p_urdu, p_template_key)` | `020_role_ux_rls.sql:724` | form-level | `p_key ~ '^[a-z0-9_]+$'`; template key vs `roles` catalog | **PASS** |
| `set_role_permissions(p_codes TEXT[])` | `020_role_ux_rls.sql` | form-level | every code checked vs `permissions` catalog; last-`roles.assign` backstop | **PASS** |

### PostgREST direct writes (backend = RLS + column constraints only)

| Input | Entry point | C | B | Verdict |
|---|---|---|---|---|
| `students.name`, `father_name` TEXT NOT NULL | any client / anon key | `Validators.required` | **no length limit, no charset check** (zero `VARCHAR` in schema) | **CLIENT-ONLY** — F-06 |
| `students.date_of_birth` DATE | date picker (client bounds) | picker `firstDate/lastDate` | **no CHECK** — future DOB, year 0001 accepted | **CLIENT-ONLY** — F-07 |
| `students.phone`, `profiles.phone`, `tenants.phone` TEXT | `Validators.phone` (PK format) | format check | **no format, no length CHECK** | **CLIENT-ONLY** — F-06 |
| `students.photo_url`, `tenants.logo_url` TEXT | file picker flow | — | **no URL/scheme validation** | **CLIENT-ONLY** — F-08 |
| `results.marks_obtained`, `total_marks` NUMERIC(6,2) | result entry forms | unknown | **no CHECK** (`marks_obtained ≤ total_marks`, `≥ 0` absent) | **CLIENT-ONLY** — F-09 |
| `announcements.title/body` TEXT | announcement composer | required-only | only `title` non-empty CHECK; body unbounded | **CLIENT-ONLY** — F-06 |
| `invoices.status` PATCH via PostgREST | fee screens | UI workflow | RLS WITH CHECK allows `issued → void/cancelled` directly | **PARTIAL** — F-10 |
| `tenant_modules.module`, `tenant_id` via upsert | `madrasa_detail_screen.dart:199` | admin UI only | RLS (tenant-isolation agent verifies) | depends on RLS |
| `permission_scopes.scope_ref` JSONB | `role_ux_repository.dart:605` | typed Dart map | `scope_type` CHECK exists; `scope_ref` schema **unvalidated** | **PARTIAL** — F-13 |

### Search / pagination / sort / filters

| Input | Entry point | C | B | Verdict |
|---|---|---|---|---|
| Search text → `.ilike('name', '%$q%')` | `role_ux_repository.dart:705` | — | PostgREST: `%`/`_` in `q` act as wildcards | **NONE** — F-14 (low) |
| Search text → `or` filter string interpolation | `madrasa_list_screen.dart:106` | — | `,`/parens in `q` alter filter syntax after URL-decode | **NONE** — F-14 |
| `limit`/`offset` in `manage-users` `list_users` | Edge Function | n/a | capped `1–200` | **PASS** |
| `list_users` membership pre-filter (platform admin) | `manage-users/index.ts:656` | n/a | `.in(tenantIds)` with **no limit** (up to 1000 tenants' memberships in memory) | **NONE** — F-15 |
| `.order(...)` in Dart repositories | all repositories | n/a | hardcoded column names | **PASS** |
| `?order=` / `?limit=` via raw PostgREST | anon key directly | n/a | PostgREST-inherent; RLS still applies | inherent |

### Normalization

| Input | Written as | Normalized? | Verdict |
|---|---|---|---|
| Phone (`0300…` vs `+92300…` vs `0300-…`) | raw input string (`staff.dart`, `madrasa.dart` pass through) | **No** — validator strips for the check only | **NONE** — F-16 |
| Email (`Tenants.email`, `user_accounts.email`) | trimmed only (`provision-tenant`); Auth lowercases login email but app columns not | **No lowercase** | **NONE** — F-16 |
| Names / Urdu text (Unicode NFC, bidi controls) | raw payload → `sync_apply` → column | **No** | **NONE** — F-17 |

---

## (b) Findings

### F-01 · CRITICAL — `sync_apply` enforces no per-table permission check; any tenant member can write financial tables

- **Location:** `supabase/migrations/016_sync.sql` (`public.sync_apply`), re-declared in `027_user_accounts_app_roles.sql:241`
- **Problem:** The RPC verifies authentication (`auth.uid() NOT NULL`) and tenant *membership* (`is_tenant_member`), and whitelists the entity name — but never checks *what the caller is allowed to do*. Any active member of a tenant (e.g., a `student` or `parent` role) can `insert`/`update`/`delete` rows in `invoices`, `payments`, `refunds`, `discounts`, `scholarships`, `expenses`, `income`, `transactions` — all 13 financial tables are in the whitelist.
- **Why it matters:** This is the offline-sync write path used by the mobile app. The carefully built RLS permission model (`fees.create`, `fees.collect`, …) is bypassed entirely for any client that calls the RPC directly instead of PostgREST.
- **Scenario:** A student with a valid login calls `sync_apply('payments', …, 'insert', {tenant_id, invoice_id, amount: 1, status: 'posted', …})`. Membership check passes. A `posted` payment row is created, the `finance_post_payment` trigger fires, allocates against the invoice, and writes a canonical ledger entry — fabricating a payment without `fees.collect`.
- **Fix:** Add a per-entity required-permission map inside `sync_apply` (e.g., `invoices → fees.create/fees.collect`, `payments → fees.collect`, `refunds → fees.refund`, …) checked via `public.tenant_has_permission(v_tenant, <code>)` before the write branches. This is the known-deferred hardening (migration header admits it) — it is the single highest-risk input-validation gap because it is *who-may-write* validation at the write boundary.

### F-02 · HIGH — `sync_apply` lets clients forge `created_by` (mass assignment)

- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql:356–366` (insert), `:440–455` (update)
- **Problem:** Insert excludes `('id','revision','server_version','updated_by','deleted_at')`; update excludes `('id','tenant_id','revision','server_version','updated_by','deleted_at','created_at','updated_at')`. Neither excludes **`created_by`**. Any payload key matching a real column is written.
- **Why it matters:** `created_by` is the attribution column on finance tables (used by `finance_post_payment` for the ledger's `created_by`). Forging it falsifies the audit trail: a malicious insider can make fraudulent rows appear created by someone else.
- **Scenario:** Attacker inserts a refund via `sync_apply` with `created_by = <principal's UUID>`. The row and downstream audit entries attribute the refund to the principal.
- **Fix:** Add `'created_by'` to both exclusion lists and stamp it server-side (`created_by = v_uid` on insert), mirroring the `updated_by` treatment from 027.

### F-03 · HIGH — `sync_apply` insert trusts client-supplied `tenant_id` for the membership check

- **Location:** `016_sync.sql` insert branch: `v_tenant := NULLIF(p_payload->>'tenant_id','')::UUID`
- **Problem:** For inserts, the tenant is taken from the *payload*, then `is_tenant_member(v_tenant)` is checked. Membership is verified, so cross-tenant writes are blocked — but combined with F-01, any member can write any table *within their own tenant*, including tables their role should never touch. Defense-in-depth would derive the tenant from the caller's single active tenant where unambiguous, or require the payload tenant to match *all* of the caller's memberships.
- **Fix:** Resolve with F-01's permission map; additionally reject inserts where the caller holds memberships in multiple tenants and the payload tenant is ambiguous — or simply keep the membership check (it is correct) and rely on per-table permissions.

### F-04 · MEDIUM — `send-notification` has unbounded, untyped Urdu/body fields

- **Location:** `supabase/functions/send-notification/index.ts:175–177, 251–253, 329–330`
- **Problem:** `title`, `type` have length caps (200/64) but `title_urdu`, `body`, `body_urdu` have **no length limit and no `typeof` check** — the code does `body["body"] as string` which is a lie if the client sends a number/boolean/object. These flow into the DB, FCM push (`pushTitle`/`pushBody`), and email HTML.
- **Why it matters:** Oversized payloads → FCM 4KB limit exceeded (silent push failure / 500s), DB bloat; wrong types → downstream crashes or malformed pushes. Any tenant member who can reach this function (membership check only) can do it.
- **Scenario:** Attacker sends `body_urdu` = 5MB string, or `title_urdu` = `{"$ne": null}`. The notification row stores megabytes; FCM send fails; every targeted user's device receives a broken push.
- **Fix:** In the validation block, add `typeof` checks + length caps mirroring `title` (e.g., `title_urdu ≤ 200`, `body`/`body_urdu ≤ 2000`). Reject non-strings with 400.

### F-05 · MEDIUM — `send-notification` `data` payload is unbounded (FCM abuse / breakage)

- **Location:** `supabase/functions/send-notification/index.ts:190, 337`
- **Problem:** `data` must be a non-array object, but keys and values are unbounded; values are `JSON.stringify`'d when non-string. FCM data keys must match `[a-zA-Z0-9_-]` and the total payload must fit 4KB — neither is enforced.
- **Scenario:** Attacker nests a 2MB object in `data`. The function attempts an FCM send that always fails, burning quota and error budget; or exfiltrates data through push payloads to devices.
- **Fix:** Cap `data` at ~3KB serialized, validate keys against `/^[a-zA-Z0-9_-]{1,64}$/`, cap value length, limit key count (e.g., ≤ 20).

### F-06 · MEDIUM — No length/format constraints on free-text columns anywhere in the schema

- **Location:** schema-wide; e.g. `supabase/01_schema.sql:88–114` (`students.name`, `father_name`, `phone`, `address`, `photo_url` all unbounded `TEXT`); `tenants.phone/email`; `announcements.body`; `notifications.body/body_urdu`. Zero `VARCHAR(n)` in the entire migration set.
- **Problem:** Client validators (`lib/core/utils/validators.dart`: Pakistani phone regex, CNIC, email, maxLength) are **client-only**. Via PostgREST or `sync_apply`, anyone can store a 10MB "name", a phone of `"abc"`, or an email of `"not-an-email"`. Only three `char_length` CHECKs exist in the whole schema (`017_notifications.sql`).
- **Why it matters:** Storage/DoS abuse, broken reports/PDFs (a 1MB name in an ID card), duplicate/confused contact records, downstream integrations (SMS gateways) choking on malformed phones.
- **Scenario:** Attacker PATCHes `students.phone` to a 5MB string via PostgREST (RLS allows own-tenant update). Every report rendering that student now embeds megabytes; PDF generation OOMs.
- **Fix:** Add `CHECK (char_length(col) <= N)` constraints on user-facing text columns (names ≤ 200, phones ≤ 32, addresses ≤ 500, URLs ≤ 2048, announcement body ≤ 5000), plus format CHECKs where the format is canonical: phone `~ '^\\+?[0-9]{10,15}$'`, email `~ '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'`. Keep client validators for UX.

### F-07 · MEDIUM — `date_of_birth` (and all dates) unconstrained at the DB boundary

- **Location:** `supabase/01_schema.sql:97` (`date_of_birth DATE` — nullable, no CHECK); no date CHECKs anywhere in migrations
- **Problem:** Client date pickers bound the range (`m360_date.dart`), but the backend accepts `date_of_birth = '3026-01-01'` (future birth), `'0001-01-01'`, or an admit date before birth. Age calculations, class eligibility, and reports silently corrupt.
- **Scenario:** Attacker sets a student's DOB 200 years in the future via direct API; age-gated logic (exam eligibility, fee slabs) misbehaves; reports show negative ages.
- **Fix:** `CHECK (date_of_birth IS NULL OR (date_of_birth >= '1900-01-01' AND date_of_birth <= CURRENT_DATE))`, `CHECK (date_of_admit >= date_of_birth)` where both present. Same pattern for staff joining dates.

### F-08 · MEDIUM — `photo_url` / logo URL columns accept arbitrary schemes

- **Location:** `supabase/01_schema.sql:102` (`students.photo_url TEXT`); tenants logo fields from `024_tenant_logos.sql`
- **Problem:** No URL validation at the boundary. `javascript:`, `data:text/html`, or `file://` URLs stored here become XSS vectors wherever the URL is rendered in a WebView or `<img>`/link context, and SSRF vectors if any server-side fetcher ever follows them.
- **Scenario:** Attacker sets `photo_url = 'javascript:alert(document.domain)'`; a future web-view report or admin panel rendering it unsanitized executes script.
- **Fix:** `CHECK (photo_url IS NULL OR photo_url ~ '^https://')` (or allowlist `https` + Supabase storage URLs). Validate scheme in the upload flow (file-upload agent owns the upload path; this is the stored-URL backstop).

### F-09 · HIGH — `results.marks_obtained` has no range constraint vs `total_marks`

- **Location:** `supabase/01_schema.sql` (`results`: `marks_obtained NUMERIC(6,2) NOT NULL`, `total_marks NUMERIC(6,2) NOT NULL`, unique on `(exam_id, student_id, subject)` — but no CHECK)
- **Problem:** Nothing at the backend boundary stops `marks_obtained = 999999` with `total_marks = 100`, or negative marks. Result cards, percentages (`obtained/total*100`), merit lists, and printed certificates corrupt — including values that break percentage math (>100%, negative).
- **Scenario:** A teacher's compromised session (or direct API call) posts `marks_obtained = -50`; the result card renders "-50%"; aggregate statistics skew.
- **Fix:** `CHECK (marks_obtained >= 0 AND total_marks > 0 AND marks_obtained <= total_marks)`.

### F-10 · MEDIUM — Invoice `issued → void/cancelled` allowed by direct PATCH, bypassing workflow

- **Location:** `supabase/migrations/014_finance.sql:1020–1030` (`invoices_update_tenant` WITH CHECK allows `status IN ('draft','issued','cancelled','void')`)
- **Problem:** Any holder of `fees.collect` can PATCH an `issued` invoice straight to `void`/`cancelled` via PostgREST — no reason code, no reversal entry, no approval. The immutability trigger (`finance_immutable_guard`) protects *already*-void rows but not the transition into void. (Via `sync_apply` the permission check is absent entirely — F-01.)
- **Scenario:** Insider voids issued invoices to erase fee dues, with no workflow trace beyond `updated_at`.
- **Fix:** Remove `'cancelled','void'` from the RLS WITH CHECK allow-list; expose voiding only through a dedicated RPC that requires a reason string, writes a reversal/audit entry, and enforces `finance_immutable_guard` semantics.

### F-11 · MEDIUM — No request body size limits on any Edge Function

- **Location:** `supabase/functions/_shared/guard.ts:readJsonBody` (used by provision-tenant, manage-users, manage-tenant, export-tenant); `send-notification/index.ts` uses `req.json()` directly
- **Problem:** The entire body is buffered into memory with no cap. A multi-hundred-MB JSON body OOMs the function isolate (DoS); combined with F-06's unbounded TEXT columns, large payloads flow straight into the DB.
- **Fix:** In `readJsonBody`, enforce a `Content-Length` pre-check (e.g., 1MB default, higher for export-tenant) and reject with 413; stream-guard the read.

### F-12 · LOW — Unknown JSON fields silently ignored (mass-assignment smell)

- **Location:** all 5 Edge Functions; `sync_apply` (ignores non-column keys — correct there)
- **Problem:** No function rejects unexpected keys. A client sending `{"tenant_id":…, "role": "platform_owner", …}` to `manage-users.create_user` gets the key silently dropped today — but silent-ignore means a future refactor that starts *reading* a new key can activate an attacker-controlled field with no contract change. Strict schemas fail closed.
- **Fix:** Adopt strict object schemas in the shared guard (allow-list keys per action; 400 on unknown keys).

### F-13 · LOW — `permission_scopes.scope_ref` JSONB has no schema validation

- **Location:** `supabase/migrations/019_role_ux_schema.sql:458`; written from `lib/data/role_ux_repository.dart:605`
- **Problem:** `scope_type` is CHECK-constrained but `scope_ref` (e.g., `{"class_ids": [...]}`) accepts any JSON. Malformed refs (wrong key names, non-UUID strings, huge arrays) are stored and only fail — confusingly — at enforcement time.
- **Fix:** `CHECK` constraint validating `scope_ref` shape per `scope_type` (jsonb key allow-list + array length cap), or a trigger.

### F-14 · LOW — Search inputs interpolate wildcards / filter syntax

- **Location:** `lib/data/role_ux_repository.dart:705` (`.ilike('name', '%$q%')`); `lib/presentation/screens/master_admin/madrasa_list_screen.dart:106` (`'name.ilike.%$q%,…'` inside an `or=` expression)
- **Problem:** `%`/`_` in user input act as LIKE wildcards (searching `%` matches everything — information disclosure beyond the intended substring match). In the `or=` string, `,`/parens in `q` alter the filter structure after URL-decoding (PostgREST parses them as syntax). No SQL injection (values are parameterized), but filter-structure injection is real.
- **Scenario:** In the tenant user search, typing `%` returns all users; in the admin madrasa list, `q = 'x),tenant_code.ilike.%'` reshapes the OR expression.
- **Fix:** Escape `%`→`\%`, `_`→`\_` (and `\` itself) before wrapping in `%…%`; for the `or=` string, reject/escape `,()`. Centralize in a `SearchSanitizer`.

### F-15 · LOW — `list_users` pre-filter query is unbounded for platform admins

- **Location:** `supabase/functions/manage-users/index.ts:656–664`
- **Problem:** `limit` is capped at 200 for the *output*, but the membership pre-query (`.in("tenant_id", tenantIds)` with up to 1000 tenants) has **no limit** — all memberships are loaded into memory, then `auth.admin.getUserById` is called per user (N+1). A large platform deployment exhausts function memory/time.
- **Fix:** Page the membership query (e.g., 1000-row pages) or push search/limit into the DB query.

### F-16 · MEDIUM — No canonical normalization: phones, emails, names

- **Location:** `lib/core/utils/validators.dart:36` (strips for check only); `lib/data/models/staff.dart:61`, `madrasa.dart:65` (store raw); `provision-tenant/index.ts` (trim, no lowercase)
- **Problem:** The same phone stored as `03001234567`, `0300-1234567`, `0300 1234567`, `+923001234567` = 4 different identities → duplicate students/staff, failed phone lookups, SMS sent to malformed numbers. Same for email case variants (`Ali@x.com` vs `ali@x.com`) in app-level columns.
- **Fix:** Normalize at write: phones → E.164-ish canonical (`+92…`, strip separators, validate); emails → lowercase(trim()); names → trim + collapse whitespace. Enforce in a shared Dart value object *and* a DB trigger/normalization function so direct API writes are normalized too.

### F-17 · LOW — No Unicode normalization on Urdu/Arabic text

- **Location:** all TEXT writes via PostgREST / `sync_apply`
- **Problem:** Visually identical names with different codepoints (e.g., Arabic Yeh `ي` vs Farsi Yeh `ی`, NFC vs NFD) bypass `UNIQUE (roll_no, class_id)` dedup and break search matching. Zero-width / bidi-control characters can be stored in names and rendered in reports/ID cards.
- **Scenario:** Two "محمد" records that look identical but differ in Yeh codepoints; duplicate detection fails; ID cards render bidi-reordered text oddly.
- **Fix:** Normalize to NFC on write (DB trigger using `normalize()` where available, or Edge Function/Dart layer), strip zero-width chars (`\u200B`–`\u200D`, `\uFEFF`) and bidi controls from name fields, canonicalize Yeh/Kaf variants for Urdu.

### F-18 · MEDIUM — CSV/Excel exports have no formula-injection protection

- **Location:** `lib/core/reports/export/csv_export.dart:27–36` (`_esc` handles only `,"` and newlines); `lib/core/reports/export/excel_export.dart` (no escaping found)
- **Problem:** Any attacker-controlled string (student name, guardian note, address) starting with `=`, `+`, `-`, `@` becomes a live spreadsheet formula when the exported file is opened. Names/notes have no charset validation (F-06), so planting `=cmd|'/c calc'!A0` is trivial via the app's own forms.
- **Scenario:** Attacker enrolls a student named `=HYPERLINK("https://evil.example","Click")`; the accountant exports the fee report and opens it — the link renders as clickable; `=cmd|` variants execute on Windows Excel with macros/DDE.
- **Fix:** Prefix-escape cells beginning with `=`, `+`, `-`, `@` (prepend `'` or a space) in both exporters; centralize in `tabular_data.dart`.

### Positive controls observed (do not regress)

- `provision-tenant`: strict lengths, email/slug/website validators, modules validated against live `modules_catalog`, unknown modules rejected.
- RPC enum discipline: `set_user_permission` (`grant`/`deny` + catalog check), `create_tenant_role` (key regex), `set_role_permissions` (catalog check + last-`roles.assign` backstop), `assign_tenant_role` (trigger-validated role key).
- `sync_apply`: entity/op allow-lists, `%I` parameterization, tenant-from-existing-row on update/delete, `GET DIAGNOSTICS` instead of `FOUND`, `updated_by` excluded (027).
- `manage-users`: per-action UUID/email/password checks, `typeof b.active === "boolean"` strictness, last-owner backstops, passwords never logged/returned.
- `handle_new_user` hardcodes `role='student'` — never trusts client metadata.
- Finance: amount `CHECK (amount > 0 / >= 0)`, status allow-lists, `finance_immutable_guard` on final rows, doc-number triggers per-table (028).
- `send-notification`: UUID/type/title/channels validation, cross-tenant target check, `escHtml` in email rendering.
- Dart `.order()` uses hardcoded columns everywhere — no order-by injection from the app.

---

## (c) Centralized validation plan (prioritized)

### Phase 1 — backend boundary, highest risk (migrations)

1. **029: `sync_apply` permission map + `created_by` hardening** (F-01, F-02, F-03). Per-entity required permission checked via `tenant_has_permission`; stamp `created_by = auth.uid()` server-side; exclude from writable columns.
2. **030: domain + CHECK hardening** (F-06, F-07, F-08, F-09):
   - `CREATE DOMAIN phone_e164 TEXT CHECK (value ~ '^\+?[0-9]{10,15}$')` (after a data-cleanup pass) and apply to phone columns; or `CHECK (char_length(phone) <= 32)` minimum.
   - `CHECK (char_length(name) <= 200)` on person/tenant name columns; `char_length(body) <= 5000` on announcement/notification bodies.
   - `results`: `CHECK (marks_obtained >= 0 AND total_marks > 0 AND marks_obtained <= total_marks)`.
   - `students`: `CHECK (date_of_birth IS NULL OR (date_of_birth BETWEEN '1900-01-01' AND CURRENT_DATE))`.
   - URL columns: `CHECK (value ~ '^https://')`.
3. **Invoice void workflow** (F-10): remove `void`/`cancelled` from the RLS WITH CHECK; add `void_invoice(p_id, p_reason)` RPC.

### Phase 2 — Edge Functions (extend `supabase/functions/_shared/guard.ts`)

4. Strict schema validator: `validateBody(body, schema)` with per-action key allow-lists → 400 on unknown keys (F-12); shared `isPhone`, `isDateString`, `isBoundedNumber`, `isEnum` helpers.
5. `readJsonBody` size cap → 413 (F-11); apply length caps to `title_urdu`/`body`/`body_urdu` and `data` key/value rules in `send-notification` (F-04, F-05); page the `list_users` pre-query (F-15).

### Phase 3 — Flutter (shared, testable)

6. Value objects in `lib/core/validation/`: `PhoneNumber` (parse → canonical `+92…`), `EmailAddress` (lowercase+trim), `PersonName` (trim, collapse spaces, strip zero-width/bidi controls, NFC) — used by every form and repository write path, so normalization happens even where backend triggers don't exist yet (F-16, F-17).
7. `SearchSanitizer.escapeLike(q)` used by every `.ilike` / `or=` construction (F-14).
8. Formula-escape in `CsvExport`/`ExcelExport` (centralize in `tabular_data.dart`) (F-18).

### Phase 4 — verification

9. Adversarial test suite: for each finding, a test that submits the malicious/malformed input **directly at the backend boundary** (PostgREST/RPC/Edge Function with crafted HTTP, not through the UI) and asserts rejection — including: oversized strings, negative/overflow marks, future DOB, forged `created_by`, cross-permission `sync_apply` writes, `=cmd` export cells, `%`-wildcard search, 5MB notification body.
10. Add a CI "validation-matrix" check: every new `TEXT` column in migrations must carry a length CHECK (lint rule), every new Edge Function action must use `validateBody`.

**Effort order:** Phase 1 is one migration (029) + one RPC-adjacent change — highest risk reduction per line. Phases 2–3 are mechanical. Phase 4 locks it in.
