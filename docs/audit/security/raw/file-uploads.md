# File Upload/Download Security Audit — Madrassa-360

**Date:** 2026-10-03 · **Branch:** `redesign/ux-v2` · **Scope:** every upload/download path, read-only audit
**Auditor stance:** adversarial — attacker holds a valid low-privilege tenant account + the anon key and can bypass all client code.

---

## 1. Inventory — every upload/download feature

| # | Feature | Bucket / path | Upload entry point | Validation (where) | Auth (server-side) | Serving / download |
|---|---------|---------------|--------------------|--------------------|--------------------|--------------------|
| 1 | Tenant logo upload | `tenant-logos` (**PUBLIC**), `<tenant_id>/logo.png` (fixed name, upsert) | `TenantLogoService.uploadLogo` → direct `uploadBinary` | non-empty + ≤5 MB — **Dart client only**; content-type hardcoded `image/png` regardless of bytes | RLS: platform admin OR tenant member + `settings.update`, path tenant = first segment (migration 024) | Public URL, no auth; rendered via `cached_network_image`; cached to `<app-support>/Madrassa360/branding/<tenantId>/logo.png`; **drawn into every generated PDF/report** |
| 2 | Student photo upload | `student-photos` (**PRIVATE**), `<tenant_id>/students/<studentId>.<ext>` | `StudentProvider.uploadPhoto` → `PendingUploadQueue` → sync engine `uploadBinary` (online later) | **none** — extension taken from picked filename (`photo.name.split('.').last`); no size check; no content check | RLS: platform admin OR tenant member + `students.update`, path tenant = first segment (migration 008) | `getPublicUrl` stored as `photo_url`, rendered with plain `NetworkImage` (**no auth headers — see M6**) |
| 3 | Staff photo upload | `staff-photos` (**PRIVATE**), `<tenant_id>/staff/<staffId>.<ext>` | `StaffProvider.uploadPhoto` → same queue/engine path | **none** — same extension-from-filename pattern; no size/content check | RLS: platform admin OR tenant member + `staff.update`, path tenant = first segment (migration 008) | Same `NetworkImage`-with-no-auth pattern |
| 4 | `documents` bucket | `documents` (**PRIVATE**) | **none found in `lib/`** — dead surface | n/a | RLS policies exist (`documents.manage`) | n/a |
| 5 | Tenant data export | `tenant-exports` (**visibility UNKNOWN — no migration creates it**) `exports/<tenant_id>/<ts>.jsonl` | `export-tenant` Edge Function (service role) | platform-admin gate in function | service role bypasses RLS; **no storage policies exist for this bucket** | **No download flow in the app** — function returns only `storage_path`; never invoked from `lib/` |
| 6 | Report/certificate/audit PDF & XLSX | local only | generated on-device (`pdf_kit.dart`, `Printing.sharePdf`) | n/a (generated, not uploaded) | n/a | OS share sheet — leaves the device via user action |
| 7 | Local DB backup / restore | app-private dirs | `BackupService` — local file copy | SHA-256 manifest integrity + `PRAGMA integrity_check` + cross-tenant block + pre-restore copy + rollback | device-local (no server) | local only |
| 8 | Logo/branding cache refresh | device cache | `TenantLogoService.refreshLogoCache`, `report_branding.dart` | **none** — downloads whatever URL is in `tenants.logo_url` | n/a (client fetch) | written to app-private cache, decoded into PDFs |

**Positives (verified, keep):** `storage_path_tenant()` returns NULL on malformed paths and every write policy denies on NULL (fail-closed); logo destination filename is fixed (`logo.png`, no user filename); backup restore blocks cross-tenant restores, snapshots a pre-restore copy, runs `integrity_check`, and rolls back; `export-tenant` is platform-admin-only and never echoes row data; Edge Functions never leak stack traces.

---

## 2. Findings

### CRITICAL

#### C1 — Tenant logo: arbitrary attacker bytes into a PUBLIC bucket, auto-rendered by every device and baked into PDFs
- **Location:** `lib/services/tenant_logo_service.dart:60-90` (`uploadLogo`); bucket policy `supabase/migrations/024_tenant_logos.sql`
- **Problem:** The only checks are client-side (`bytes.isEmpty`, `bytes.length > 5MB`). There is **no magic-byte / content sniffing, no allowlist, no server-side size cap**. The upload hardcodes `contentType: 'image/png'` regardless of actual bytes. The bucket is **public** by design and the object is served at the predictable URL `tenant-logos/<tenant_id>/logo.png`. The same bytes are cached on every device and **drawn into every generated report/certificate** via the image decoder.
- **Why it matters:** A public bucket + attacker-controlled bytes + automatic consumption on all devices is a stored-content distribution channel. The 5 MB cap is Dart-only — a direct Storage API call (RLS permits any `settings.update` holder) uploads any size.
- **Exploit scenario:**
  1. Attacker is a tenant admin (or any role with `settings.update`) of madrassa X.
  2. Attacker crafts a PNG decompression bomb (a few MB that decodes to gigapixels) or a polyglot PNG/HTML, and uploads it via a raw `POST /storage/v1/object/tenant-logos/<tenantX>/logo.png` with their JWT — bypassing the app's 5 MB check entirely.
  3. Every device in the madrassa refreshes branding / generates any report → the image decoder attempts to decode the bomb → **OOM crash, repeatedly** (denial of service for the whole tenant). A polyglot served as `image/png` is less directly exploitable in browsers (content-type is fixed), but the decode path is the real weapon, and the public URL makes the bytes fetchable by anyone for further analysis/reuse.
- **Recommended fix:** Route logo uploads through a dedicated Edge Function (service role): verify JWT + `settings.update`, **sniff magic bytes** (allow PNG/JPEG/WebP only), **enforce size server-side**, **re-encode the image** (strips polyglots, metadata, bombs — decode with pixel-dimension caps), then store with fixed `image/png` + `cache-control`. Clients keep picker UX checks only. Additionally set a pixel-dimension cap before PDF embedding.

---

### HIGH

#### H1 — Student/staff photos: attacker-controlled extension, no content validation, content-type inferred from extension
- **Location:** `lib/providers/student_provider.dart:118-122`, `lib/providers/staff_provider.dart:83-88`, `lib/core/sync/sync_engine.dart:906-910`
- **Problem:** `final ext = photo.name.split('.').last.toLowerCase()` — the extension comes straight from the picked filename, and `destPath = '$tenantId/students/$studentId.$ext'`. The sync engine uploads with `FileOptions(upsert: true)` and **no `contentType`**, so Supabase Storage **infers the served content-type from the extension**. There is no size cap on this path at all (`pickImage(imageQuality: 70)` only affects the gallery picker UI, not the queued bytes).
- **Why it matters:** "Never trust the filename" is violated at the storage layer. The filename *is* the content-type decision.
- **Exploit scenario:**
  1. Attacker (any user with `students.update`, e.g. a clerk) crafts `x.svg` containing `<svg xmlns=...><script>/* session/cookie theft, origin = storage host */</script></svg>` and picks it as a student photo (or calls the upload path directly).
  2. Object stored as `<tenant>/students/<uuid>.svg`, served as `image/svg+xml`.
  3. The buckets are currently private (mitigating factor — see H4/M6), but any tenant member who opens the photo URL in a browser/WebView context with their session executes the script in the storage origin. If the buckets are ever made public to "fix" photo display (see M6), this becomes **stored XSS against the whole internet**.
  4. Separately: no size cap → a hostile client queues multi-GB "photos" → storage fill / cost abuse, all RLS-permitted.
- **Recommended fix:** Same upload-via-Edge-Function pattern: allowlist `{jpg, jpeg, png, webp}`, magic-byte sniff, server-generated filename (`<tenant>/students/<uuid>.jpg` — never derive the name or extension from user input), explicit `contentType`, server-side size cap (e.g. 2 MB after re-encode). Reject SVG/BMP/TIFF outright.

#### H2 — `tenants_member_update` RLS has no column allowlist: tenant admin can flip `status` (suspension/billing bypass)
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql:186-196`
- **Problem:** The UPDATE policy's `USING`/`WITH CHECK` only verify membership + `settings.update`. **Any column** on the tenant row is writable, including `status` (`trial|active|suspended|expired|cancelled|archived`), `tenant_code`, `slug`, `registration_number`.
- **Why it matters:** If `check_tenant_access()` (or any gate) enforces suspension/expiry via `tenants.status`, a suspended tenant's own admin can set `status='active'` and un-suspend themselves — platform-level enforcement becomes advisory. `tenant_code`/`slug` rewrites can break routing/derived-tenant logic.
- **Exploit scenario:** Platform suspends madrassa X for non-payment (`status='suspended'`). X's admin (holds `settings.update`) issues `PATCH /rest/v1/tenants?id=eq.<X> {status:'active'}` with their JWT — RLS allows it. Suspension lifted without platform action.
- **Recommended fix:** Add a `BEFORE UPDATE` trigger on `public.tenants` that rejects changes to `status`, `tenant_code`, `slug`, `registration_number` unless `public.is_platform_admin()`; or split into column-granular policies. `logo_url`/`favicon_url`/`name`/contact fields stay tenant-writable (but see H3).

#### H3 — `tenants.logo_url` is freely writable → cache poisoning + unbounded download OOM on every device
- **Location:** `supabase/migrations/027_user_accounts_app_roles.sql:186-196` (no column guard) + `lib/services/tenant_logo_service.dart:144-162` (`refreshLogoCache`) + `lib/core/reports/report_branding.dart:195-236`
- **Problem:** Because of H2's missing column guard, any `settings.update` holder can set `logo_url` to **any arbitrary URL** (not just the uploaded logo's). Both refresh paths do `HttpClient().getUrl(Uri.parse(logoUrl))` and accumulate the response with **no size cap** (`fold` into a growable list), then write it to the logo cache that gets decoded into PDFs.
- **Why it matters:** One writable DB field becomes remote-code-bytes distribution to every device in the tenant, plus a trivial OOM vector.
- **Exploit scenario:**
  1. Attacker sets `tenants.logo_url = 'https://attacker.example/20gb.bin'` (or a `http://192.168.x.x/...` LAN URL — client-side SSRF on each device).
  2. Every device refreshing branding downloads unbounded bytes into memory → OOM crash. The cached file then breaks/fails all report generation until manually cleared.
- **Recommended fix:** (a) Column-guard `logo_url` so it is only ever written by the logo-upload flow (trigger: new value must start with the storage public URL prefix for this tenant's logo path — or better, have the Edge Function from C1 write it with service role and revoke client write entirely). (b) Cap downloads: read at most ~5 MB (`take` on the stream), enforce `https` scheme, reject private/loopback IP hosts. (c) Validate the URL host allowlist (the Supabase storage host).

#### H4 — No server-side file-size cap on ANY storage upload (client checks are bypassable)
- **Location:** `lib/services/tenant_logo_service.dart:66-68` (5 MB, Dart-only); student/staff photo path (no cap at all); `supabase/migrations/008_tenant_storage.sql`, `024_tenant_logos.sql` (no size conditions possible in policies)
- **Problem:** Supabase storage RLS policies cannot inspect object size; all size enforcement lives in the Flutter client. Any user with the relevant `*.update` permission can `POST` multi-GB objects with a raw HTTP client and valid JWT.
- **Why it matters:** Storage-fill / cost-exhaustion DoS by a low-privilege insider; also amplifies C1/H1/H3.
- **Exploit scenario:** Disgruntled clerk with `students.update` loops `uploadBinary` of 4 GB random blobs to `student-photos/<tenant>/students/fake-<i>.bin` (RLS: path tenant matches, permission held → allowed). Storage quota/cost consumed; no alert.
- **Recommended fix:** Proxy uploads through the Edge Function (C1/H1) with a hard cap; add monitoring/alerting on bucket growth; consider a `storage.objects` INSERT trigger that deletes/quarantines objects whose `metadata->>'size'` exceeds the cap (metadata is client-controlled, so this is backstop-only — the function is the real fix).

---

### MEDIUM

#### M1 — Private photo buckets rendered with `NetworkImage` and no auth (broken-or-dangerous)
- **Location:** `lib/presentation/screens/students/student_widgets.dart:31-32`; buckets private per `008_tenant_storage.sql:29-33`
- **Problem:** `student-photos`/`staff-photos` are **private**, but the app renders `photo_url` (a `getPublicUrl` URL) via plain `NetworkImage` with no `Authorization` header. An unauthenticated GET on a private bucket object is rejected → **photos silently never load** (functional bug), OR the first "fix" someone tries is flipping the buckets public → **photos of minors become world-readable at predictable URLs** (privacy disaster).
- **Recommended fix:** Do not make the buckets public. Serve via short-lived **signed URLs** (`createSignedUrl`, e.g. 15-min expiry, minted per view or via a thin Edge Function), or a custom `ImageProvider` that attaches the user's JWT as `Authorization: Bearer` header (RLS then enforces tenant membership).

#### M2 — `tenant-exports` bucket has no migration: visibility and policies unknown, full-tenant PII at predictable paths
- **Location:** `supabase/functions/export-tenant/index.ts` (writes `exports/<tenant_id>/<ts>.jsonl` via service role); **no `INSERT INTO storage.buckets` / policies anywhere in `supabase/migrations/`**; never invoked from `lib/`
- **Problem:** The export contains the **entire tenant dataset** (students, staff, finance, results). The bucket's public/private flag and its storage policies are undefined in code — if the bucket was created public (manually or by default), exports are world-readable at guessable paths. There is also no in-app download flow (function returns only `storage_path`), so retrieval presumably happens via dashboard — unaudited.
- **Recommended fix:** Add a migration creating `tenant-exports` as **private** with platform-admin-only SELECT/INSERT/DELETE policies; serve downloads exclusively via short-lived signed URLs minted after re-checking platform-admin; add an in-app download flow or document the retrieval procedure; verify the live bucket's current `public` flag immediately.

#### M3 — Public logo bucket: instant global overwrite, no versioning
- **Location:** `supabase/migrations/024_tenant_logos.sql` (public read, upsert writes)
- **Problem:** Writes are correctly tenant-bound, but `upsert: true` on a fixed path means a compromised `settings.update` account (or platform admin) can **instantly replace every public rendering of a madrassa's identity** (documents, PDFs, app UI) with attacker content, served from the project's own trusted domain. No versioning/quarantine.
- **Recommended fix:** Keep a versioned history (write new objects `<tenant>/<uuid>.png`, update `logo_url` pointer) so a malicious overwrite is revertible; the C1 Edge Function re-encode already neuters malicious content.

#### M4 — Edge Functions accept unbounded JSON bodies (payload-size DoS)
- **Location:** `supabase/functions/_shared/guard.ts:190-202` (`readJsonBody` → `await req.json()` with no size limit), used by `manage-users`, `provision-tenant`, `export-tenant`, etc.
- **Problem:** No `Content-Length` / byte cap before parsing. A caller can POST a multi-GB JSON body; Deno buffers it → memory exhaustion per invocation (cost + availability).
- **Recommended fix:** Wrap `req.body` with a byte-counting reader; reject > 1 MB (these endpoints take small JSON) with 413 before `req.json()`.

#### M5 — Path/filename handling is ad-hoc (defense-in-depth gap)
- **Location:** `student_provider.dart:118`, `staff_provider.dart:83` (`photo.name.split('.').last`); `storage_repository.dart:stageFile` (`p.join` with caller filename)
- **Problem:** Extension parsing breaks on extensionless names (`photo.name` with no `.` → ext = whole name, producing `id.<wholename>`); no normalization of Unicode/RTL-override characters in staged filenames. `..` is not reachable via the gallery picker on-device, but the pattern is fragile if any future picker returns crafted names.
- **Recommended fix:** Stop deriving anything from the filename (server-generated names per H1/C1); sanitize staged filenames to `[a-z0-9-]` if a filename must be kept.

---

### LOW

#### L1 — `documents` bucket is dead surface
- **Location:** `supabase/migrations/008_tenant_storage.sql` (policies for `documents.manage`); zero references in `lib/`
- **Problem:** Policies and a private bucket exist for a feature nothing uses. Unused attack surface that will confuse future auditors.
- **Recommended fix:** Either wire the intended document feature through the H1 upload function or drop the bucket + policies.

#### L2 — Logo/branding download errors are swallowed (`catch (_)`)
- **Location:** `lib/core/reports/report_branding.dart` (bare `catch (_)`)
- **Problem:** Poisoned-cache states (H3) are silent; operators get no signal.
- **Recommended fix:** Log branding-fetch failures with the URL host (never the full URL if it contains secrets — it shouldn't) to the observability pipeline once H3's allowlist is in place.

#### L3 — Backup manifest is integrity-only, not authenticity
- **Location:** `lib/core/backup/backup_service.dart:350-378` (SHA-256 `data_sha256`)
- **Problem:** SHA-256 detects corruption, not a maliciously crafted backup. Threat model is the device owner attacking themselves, so this is acceptable — recorded for completeness. Cross-tenant restore is correctly blocked and rollback is implemented (verified good).

---

## 3. Consolidated remediation (ordered by risk)

**Phase 1 — stop the bleeding (server-side, no client redesign):**
1. Migration: `BEFORE UPDATE` trigger on `public.tenants` — only platform admins may change `status`, `tenant_code`, `slug`, `registration_number`; `logo_url`/`favicon_url` only writable when the new value matches the tenant's storage logo prefix (fixes H2, H3).
2. Migration: create `tenant-exports` as private + platform-admin-only storage policies (fixes M2); verify live bucket flag.
3. New Edge Function `upload-image` (service role): JWT auth → permission check (`settings.update` / `students.update` / `staff.update` per target) → magic-byte sniff (PNG/JPEG/WebP) → size cap → pixel-dimension cap → re-encode → server-generated filename → fixed `contentType` → write `logo_url`/`photo_url` itself. Switch logo + photo flows to it (fixes C1, H1, H4).
4. Signed-URL (or authed-header) photo rendering; never make photo buckets public (fixes M1).

**Phase 2 — hardening:**
5. Byte-cap `readJsonBody` in `_shared/guard.ts` (M4).
6. Cap + allowlist branding/logo downloads (https only, ≤5 MB, no private IPs) (H3).
7. Versioned logo objects instead of fixed-path upsert (M3).

**Phase 3 — hygiene:**
8. Decide the fate of the `documents` bucket (L1); add bucket-growth alerting (H4); structured logging for branding failures (L2).

## 4. Adversarial test checklist (for the fix-verification phase)
- [ ] Upload `.svg`/`.html`/polyglot as logo via raw Storage API with `settings.update` JWT → must be rejected (or neutralized by re-encode), never publicly served as-is.
- [ ] Upload 50 MB "photo" via raw API → rejected.
- [ ] `PATCH tenants {status:'active'}` as suspended tenant's admin → rejected.
- [ ] `PATCH tenants {logo_url:'https://evil.example/x'}` → rejected.
- [ ] Fetch `student-photos` object URL with no auth → denied; with another tenant's JWT → denied.
- [ ] Open `tenant-exports` object URL unauthenticated → denied; confirm bucket private.
- [ ] Set `logo_url` to a 2 GB URL → branding refresh caps at 5 MB, no OOM.
- [ ] Student photo with `x.svg` name → stored as `.jpg` (or rejected), served as `image/jpeg`.
- [ ] 10 MB JSON POST to `manage-users` → 413.
