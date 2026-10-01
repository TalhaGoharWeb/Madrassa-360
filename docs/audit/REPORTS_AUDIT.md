# REPORTS AUDIT — Madrassa-360 production readiness

**Scope:** `lib/core/reports/` + the screens/routes that trigger report generation.
**Repo:** `~/workspace/madrassa-redesign-fix`, branch `redesign/ux-v2`, HEAD `90b41e59` (CI-green).
**Date:** 2026-10-01. **Mode:** read-only (no source edits).

Severity: blocker = crash on generate, tofu Urdu in output, missing logo on official documents, cross-tenant data leak; major = no pagination (clipped pages), missing signature on certificates, dead report menu entry; minor = polish/inconsistency. Uncertain items are marked minor per audit rules.

**Counts: 1 blocker, 0 major, 8 minor.**

---

## 1. Generator inventory + trigger map

19 generator functions, all with live triggers. No dead generators, no dead menu entries.

| # | Generator | Trigger (verified call site) |
|---|-----------|------------------------------|
| 1 | `StudentDocuments.admissionForm` | Reports hub (`reports_hub_screen.dart:312` via `ReportsService.generatePdf`) |
| 2 | `StudentDocuments.idCard` | Reports hub (same path) |
| 3 | `StudentDocuments.characterCertificate` | Reports hub + Certificates screen (`certificates_screen.dart:182` → `generatePdf(_type.reportId)`, type `character`) |
| 4 | `StudentDocuments.transferCertificate` | Reports hub + Certificates screen (type `transfer`) |
| 5 | `StudentReports.resultCard` | Reports hub |
| 6 | `StudentReports.attendanceReport` | Reports hub |
| 7 | `StudentReports.feeStatement` | Reports hub |
| 8–15 | `AdminReports.studentRegister / teacherRegister / attendanceSummary / feeCollection / outstandingFees / incomeExpense / examResults / academicPerformance` | Reports hub |
| 16 | `ResultDocuments.resultCard` | Results screen share button (`teacher/results_screen.dart:1123`, `_shareResult`) |
| 17 | `ResultDocuments.resultsSummary` | Results screen print button (`teacher/results_screen.dart:1174`, `_printResults`) |
| 18 | `FeeReceiptPdf.build` | Collect-fee screen print (`finance/collect_fee_screen.dart:151`) |
| 19 | `AuditLogReport.build` | Audit-logs screen export (`master_admin/audit_logs_screen.dart:432`) |

Hub reachability: `finance_reports` nav destination → `FinanceHubScreen(Section.reports)` → `ReportsHubScreen`; also linked from 6 dashboards (admin, accountant, exam, library, hostel, principal) and the student profile screen. All 15 `ReportCatalog` entries render via `ReportCatalog.byCategory` in the hub tabs (`reports_hub_screen.dart:104`), with student/exam/class/darja/date filters honoring each definition's `needs*` flags (lines 241–273, 399–467).

---

## 2. Branding pipeline verification — PASSES

- `loadReportBranding` (`report_branding.dart:117`) reads `tenant_settings_cache` (offline-only, never network) → logo from tenant-scoped file `Madrassa360/branding/<tenantId>/logo.png` via the single `tenantLogoCacheFile` definition (line 171) shared by writer and reader. No hard-coded duplicate path. **No cross-tenant leak** (path is tenant-scoped; comment at line 163–164 states the invariant).
- Fallback chain: corrupt/missing cache → `ReportBranding.fallback()` (neutral name + colors); missing logo → product logo `assets/images/app_logo.png` via `rootBundle` in `PdfBuildScope.create` (`pdf_kit.dart:131–150`); asset missing → vector `_emblem()`. Never a broken image.
- **Product-logo fallback verified on every header path**: standard header (`buildHeader`, `pdf_kit.dart:241`) uses `_logo ?? _emblem()` where `_logo` already carries the product fallback; the bare ID-card path uses `s.logoOrEmblem()` (`student_documents.dart:113`), which wraps the same `_logo` (fallback included). `AuditLogReport` (platform-level branding, `hasLogo=false`) also resolves through the same `create()` → product logo. The f7914dcb fixes hold.
- Header/footer consistent across all generators: logo + Nastaleeq name + Latin name + address + contact + title, divider; footer "Page X of Y" + generated timestamp (`pdf_kit.dart:264–291`). The bare ID card builds its own equivalent brand band (logo, name, address, contact).

## 3. Urdu rendering check — PASSES (one conditional caveat)

- Python scan of `lib/core/reports/**/*.dart`: **zero `pw.Text(...)` calls with Arabic-script string literals**. All Urdu routes through `UrduPdf` rasterisation (`s.u`, `s.auto`, `urdu.text`).
- Header name routing (the f7914dcb tofu fix) holds: `pdf_kit.dart:165–173` — `UrduPdf.isUrdu(branding.name)` decides raster vs `pw.Text`.
- Dynamic data: `dataTable` cells route via `auto()` (`pdf_kit.dart:421`), `fieldRow` via `s.auto()` (`document_helpers.dart:43`), stat labels via `u()`. Values like `fmtMoney` output are Latin-safe.
- Caveat (minor finding #4 below): `StatBox.subEn` is rendered Latin-only (`pdf_kit.dart:511–512`); the fee-collection "by method" breakdown feeds payment-method values into it, which are Urdu labels in the app (`نقد`, `بینک ٹرانسفر` — `lib/data/models/finance.dart:119–133`).

## 4. Pagination

- `PdfKit.build` assembles everything into a single `pw.MultiPage` (`pdf_kit.dart:585`) — no fixed `pw.Page` anywhere in reports. Long `pw.Table`s (`dataTable`) are `SpanningWidget`s and break across pages correctly (verified against pdf 3.12.0 `multi_page.dart`).
- **Blocker:** `AdminReports.incomeExpense` wraps each section's table in `pw.Column` (`admin_reports.dart:270`), and `pw.Column` is NOT a spanning widget — pdf 3.12.0 `MultiPage` **throws** `Exception('Widget won't fit into the page...')` for any non-spanning child taller than one page (`multi_page.dart:383–389`). A madrassa with enough income/expense rows to exceed one page **crashes generation**. All other generators place `dataTable` directly in the `MultiPage` build list and paginate fine.

## 5. Empty states — all honest

Every generator renders a bilingual `emptyNotice` instead of blank pages, zeros-as-data, or crashes: `_missingStudent` (student_documents.dart:303), `_missing`/`_empty` (student_reports.dart:318–338), `_tabular` (admin_reports.dart:63–69), `incomeExpense` with an honest "records exist but no usable amounts" variant (admin_reports.dart:222–234), `resultsSummary` (result_documents.dart:78–82), `AuditLogReport` (audit_log_report.dart:44–49). `feeStatement`'s `tables![0]` (student_reports.dart:220) is safe — `_feeStatement` returns non-nullable `List<ReportTable>` (tabular_data.dart:339).

## 6. Signatures

Present: admission form (student_documents.dart:78), character certificate (:228), transfer certificate (:296), result cards (student_reports.dart:159; result_documents.dart:58), fee receipt (fee_receipt.dart:55). Missing (minor, grouped): student attendance report, fee statement, all 8 admin tabular reports, results summary. ID card has none by design.

---

## Findings

`lib/core/reports/documents/admin_reports.dart:270` — blocker — incomeExpense `section()` wraps the income/expense `dataTable` in `pw.Column`; MultiPage throws on any non-SpanningWidget child taller than one page, so long income/expense lists crash generation instead of paginating

`lib/core/reports/documents/admin_reports.dart:198-216` — minor — fee-collection "طریقے" StatBox `subEn` renders payment-method values via Latin-only `e()` (pdf_kit.dart:511); app method labels are Urdu (`نقد`, `بینک ٹرانسفر`, finance.dart:119-133), so Urdu method values would render as tofu (the table cells for the same values correctly route via `auto()`)

`lib/core/reports/documents/student_documents.dart:156` — minor — `pw.Spacer()` is a direct child of the MultiPage build list (not inside a Row/Column), so it's a spacing no-op: the contact band is not bottom-pinned on the CR80 card as intended (no crash — Flexible is a pass-through SingleChildWidget outside Flex)

`lib/core/reports/documents/student_documents.dart:117` — minor — ID-card brand-band madrassa name rendered via `s.u()` with no maxWidth (single-line raster); a long institution name overflows the 226pt card width instead of wrapping

`lib/core/reports/documents/student_documents.dart:320` — minor — ID-card `_idLine` values via `s.auto()` with no maxWidth; long student/father names can overflow the CR80 card width

`lib/core/reports/documents/student_documents.dart:173` — minor — ID-card contact line assumes Latin-only phone/email (`replaceAll('فون: ', 'Ph: ')` then `s.e()`); a phone stored with Urdu digits would render as tofu

`lib/core/reports/documents/student_reports.dart:132-166` — minor — attendance report has no signature block (certificates/result cards/fee receipt all have `signatureRow`)

`lib/core/reports/documents/student_reports.dart:190-261` — minor — fee statement has no signature block

`lib/core/reports/documents/admin_reports.dart` — minor — none of the 8 admin tabular reports include a signature/verification block (no `signatureRow` anywhere in the file)

`lib/core/reports/documents/result_documents.dart:35-58` — minor — share-path `resultCard` renders a headers-only table when `result.subjects` is empty, with no `emptyNotice` (inconsistent with sibling `resultsSummary`)

**Totals: 1 blocker, 0 major, 8 minor. No dead generators, no dead menu entries, no cross-tenant leaks, no `pw.Text` Urdu tofu in literals.**
