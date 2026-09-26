# رپورٹنگ انجن — REPORTING.md

Phase 6 · offline-first reporting: tenant-branded PDFs, CSV & XLSX export,
preview / print / share. **Zero network access in the reporting path** —
every number comes from the local Drift database (`AppDatabase`).

> Compilation note: no Flutter toolchain exists in this environment, so
> none of this code has been compiled. It was written against the
> verified APIs of `pdf` 3.12.0, `printing` 5.14.3 and `excel` 4.0.6
> (sources downloaded from pub.dev and inspected) and follows the
> repo's existing patterns (raw-SQL via `customSelect`, Riverpod
> providers, `ConsumerStatefulWidget` screens).

---

## 1. Report catalog

### طلبہ — Student (per-student documents)

| id | اردو | English | Data sources (local tables) |
|---|---|---|---|
| `admission_form` | داخلہ فارم | Admission Form | `students` (+`classes`,`darjas` for names; `data` JSON: father_name, date_of_birth, date_of_admit, phone, address) |
| `student_id_card` | شناختی کارڈ | Student ID Card (CR80) | `students`, `classes` |
| `character_certificate` | کردار سرٹیفکیٹ | Character Certificate | `students`, `classes`. **Conduct is left blank for the principal** — the system never invents it. |
| `transfer_certificate` | منتقلی سرٹیفکیٹ | Transfer / Leaving Certificate | `students`, `invoices`, `payments` (dues = billed − paid − discounts) |
| `result_card` | رزلٹ کارڈ | Result Card | `students`, `exams`, `results` (`data`: subject, total_marks, marks_obtained); class position via dense ranking over the exam |
| `attendance_report` | حاضری رپورٹ | Attendance Report | `attendance_records` (status ∈ present/absent/leave/late) |
| `fee_statement` | فیس اسٹیٹمنٹ | Fee Statement | `invoices`, `invoice_items`, `payments`, `discounts` (via invoice `data`) |

### انتظامیہ — Admin (registers & summaries)

| id | اردو | English | Data sources |
|---|---|---|---|
| `student_register` | طلبہ رجسٹر | Student Register | `students` (+`classes`,`darjas`); filters: class, darja |
| `teacher_register` | اساتذہ رجسٹر | Teacher / Staff Register | `staff` (table `staff`; `data`: phone) |
| `attendance_summary` | حاضری خلاصہ | Attendance Summary | `attendance_records` + `students`; filters: class, date range |
| `fee_collection` | فیس وصولی رپورٹ | Fee Collection Report | `payments` (+`students`,`invoices` for names); filter: date range (payment date lives in `data` JSON → filtered in Dart) |
| `outstanding_fees` | واجب الادا فیس | Outstanding Fees | `invoices` + `payments` + `discounts`; balance > 0.5 only |
| `income_expense` | آمدن و اخراجات | Income & Expense | `income`, `expenses` tables (`data`: amount, entry_date, category, description) |
| `exam_results` | امتحانی نتائج | Exam Results | `exams`, `results`, `students`; dense-ranked positions |
| `academic_performance` | تعلیمی کارکردگی | Academic Performance | all `exams` + `results`; per-student average % |

### Filters per report

Defined in `lib/core/reports/report_catalog.dart` (`needsStudent`,
`needsClass`, `needsDarja`, `needsExam`, `needsDateRange`, `tabular`).
The hub screen only shows the relevant filter widgets.

### Export matrix

| report | PDF | CSV | XLSX |
|---|---|---|---|
| admission_form, student_id_card, character_certificate, transfer_certificate, result_card | ✅ | — | — |
| attendance_report, fee_statement, student_register, teacher_register, attendance_summary, fee_collection, outstanding_fees, income_expense, exam_results, academic_performance | ✅ | ✅ | ✅ |

---

## 2. Architecture

```
lib/core/reports/
├── report_params.dart      # ReportParams (tenant + filters), ReportDefinition
├── report_catalog.dart     # the 15 static definitions
├── report_context.dart     # ReportContext handed to every builder
├── report_branding.dart    # offline branding loader (cache → fallback)
├── urdu_pdf.dart           # Urdu rasteriser (Flutter engine → PNG)
├── pdf_kit.dart            # PdfKit.build: header/footer, tables, forms
├── reports_service.dart    # facade: generatePdf / generateCsv / generateXlsx
├── data/
│   ├── report_models.dart  # plain data holders + gradeFor + fmtMoney
│   └── report_data.dart    # local-DB fetchers (customSelect, tenant-scoped)
├── documents/
│   ├── document_helpers.dart
│   ├── student_documents.dart  # 4 builders
│   ├── student_reports.dart    # 3 builders
│   └── admin_reports.dart      # 8 builders
└── export/
    ├── tabular_data.dart   # SINGLE source of headers+rows (PDF+CSV+XLSX)
    ├── csv_export.dart
    └── excel_export.dart

lib/presentation/screens/reports/
└── reports_hub_screen.dart # catalog tabs, filter sheet, preview/save/share/print
```

**Data flow:** hub screen → `ReportsService` → `loadReportBranding` (offline
cache) + `ReportData` (local Drift) → document builder → `PdfKit.build`
(pre-renders all Urdu images, then assembles `pw.MultiPage`) → bytes →
`printing` (preview/print/share) or `path_provider` (save).

**Why `TabularData` is the single source:** the PDF tables for tabular
reports AND the CSV/XLSX exporters consume the same `ReportTable`
(headers + rows), so a number can never disagree between formats.

---

## 3. Urdu / RTL — the shaping decision (READ THIS)

### The problem

The `pdf` package (3.12.0, source inspected) shapes Arabic script by
mapping each character to a Unicode **presentation form**
(`U+FB50–FDFF` / `U+FE70–FEFF`) in `lib/src/pdf/font/arabic.dart`, and it
performs **no OpenType GSUB/GPOS shaping** (upstream
DavBfr/dart_pdf#1907 confirms: "the library currently maps Unicode →
glyphs directly without applying GSUB/GPOS shaping").

The bundled Jameel Noori Nastaleeq TTFs were inspected with fontTools:

| block | coverage |
|---|---|
| Arabic base U+0600–06FF | 127 glyphs ✓ |
| Presentation Forms-A U+FB50–FDFF | **4 of 688** ✗ |
| Presentation Forms-B U+FE70–FEFF | **0 of 144** ✗ |
| GSUB / GPOS | present ✓ |

Feeding Urdu strings to `pw.Text` with this font would address
presentation-form codepoints the font **does not have** → tofu/broken
glyphs. Even with a font that had them, the result would be Naskh-style
joining, not Nastaleeq's cascading layout, which fundamentally requires
HarfBuzz-level GSUB/GPOS.

### The solution: `UrduPdf` (`urdu_pdf.dart`)

Every Urdu string is shaped by the **Flutter engine** (Skia/HarfBuzz —
the same pipeline that renders the app's own UI correctly) via
`TextPainter` (`fontFamily: 'JameelNooriNastaleeq'`, `TextDirection.rtl`),
rasterised to PNG at 3×, and embedded as `pw.MemoryImage`. Latin text
keeps using the pdf engine's native text (searchable/selectable);
`PdfBuildScope.auto()` routes each string by script detection
(`UrduPdf.isUrdu`).

Confidence: **high that glyphs are correct** (identical shaper to the
on-screen UI the user already sees). Known trade-off: Urdu text in PDFs
is raster, not selectable. If a future `pdf` release gains HarfBuzz
shaping, `UrduPdf` is the single seam to replace.

### RTL rules applied

- All Urdu runs are laid out `TextDirection.rtl`, right-aligned.
- `dataTable(rtl: auto)`: when every header is Urdu, column order is
  mirrored so the first logical column appears at the right.
- Mixed-direction strings (e.g. "جماعت: 10th") go through `TextPainter`,
  whose bidi algorithm orders runs correctly.
- Numbers/dates stay Latin digits (standard in Pakistani documents).

---

## 4. Tenant branding (offline)

`loadReportBranding(db, tenantId)`:

1. Reads `tenant_settings_cache.payload` for the tenant. Expected shape —
   the two maps `TenantBranding.fromRows` already understands:
   ```json
   {"tenant": {"name": "...", "name_urdu": "...", "logo_url": "...",
               "phone": "...", "email": "...", "address": "...", "city": "..."},
    "settings": {"primary_color": "#0E7C5B", "secondary_color": "#14532D",
                 "accent_color": "#F59E0B"}}
   ```
   A flat map (tenant keys at top level) is also tolerated.
2. Logo: `<app-support>/Madrassa360/branding/<tenantId>/logo.png` when a
   previous sync cached it there (tenant-scoped so logos never leak
   across tenants); otherwise a neutral vector emblem in the
   tenant's primary colour. A remote `logo_url` is never fetched here
   (offline rule).
3. Anything missing/corrupt → `ReportBranding.fallback()` (neutral
   product defaults, same values as `TenantBranding.fallback()`).

> **Contract for the sync layer:** whoever writes `tenant_settings_cache`
> should cache the `tenants` + `tenant_settings` rows in the shape above
> and drop the logo bytes at the path above. Until then, reports render
> with neutral branding — never another tenant's identity, never a
> broken image.

Every PDF carries the branded header (logo/emblem, Urdu + English name,
address, phone) and footer (page X of Y, generation timestamp) on each
page. The ID card uses `bare: true` (no header/footer — it draws its own).

---

## 5. Empty states & honesty rules

- No data → the PDF shows a clean notice box
  ("منتقلی… / …not found in the local database"), never zeros presented
  as real data.
- Percentages are `null` (rendered `—`) when there is nothing to divide
  by; `gradeFor(null)` → `—`.
- Attendance % = (present + late) ÷ marked days × 100, footnoted on the
  report. Statuses outside present/absent/leave/late are counted in a
  separate نامعلوم column and included in the denominator — they are
  never silently counted as present.
- Result rows with missing marks or totals are kept null end-to-end:
  per-subject cells show —, totals/percentages/rankings use only usable
  rows, students with no usable marks are left unranked, and a
  partially-marked result card carries an explicit footnote instead of
  synthetic zeroes.
- Grading scale: A+ ≥90, A ≥80, B ≥70, C ≥60, D ≥50, F <50.
- Class positions use dense ranking by obtained marks.
- Dues: invoices − (invoice `amount_paid` + discounts) − payments;
  only balances > 0.5 are listed (float dust).
- Income/expense entries whose `data` JSON has no parseable `amount`
  are excluded from totals and counted in a footnote — never silently
  treated as 0 in a total.
- Payment/income dates live inside the `data` JSON blob, so date-range
  filtering for those happens in Dart after the fetch (documented in
  `report_data.dart`).
- Character certificate: conduct is a **blank hand-filled line** —
  the DB has no conduct field and the system must not invent one.

---

## 6. Packages added (SDK-compat evidence)

App floor: `sdk: ^3.5.0` (Dart ≥3.5.0 <4.0.0). Checked per-version SDK
constraints via the pub.dev API (`/api/packages/<name>`) on 2026-09-25:

| package | pinned | SDK constraint | why this version |
|---|---|---|---|
| `pdf` | `^3.12.0` | `>=2.19.0 <4.0.0` | highest 3.x line fitting 3.5.0; ≥3.13 needs Dart ≥3.12 |
| `printing` | `^5.14.3` | `>=3.3.0 <4.0.0` (Flutter ≥3.22.0) | highest line fitting 3.5.0; ≥5.15 needs Dart ≥3.12. Depends on `pdf ^3.10.0` ✓ |
| `excel` | `^4.0.6` | `>=3.0.0 <4.0.0` | latest line; pure Dart, fits directly |

Dependency intersections are clean: `pdf`↔`excel` share `archive`
(`>=3.4.0 <4.1.0` ∩ `^3.6.1`) and `xml` (`>=6.3.0 <7.0.0` ∩
`>=5.0.0 <7.0.0`).

**`share_plus` was checked and deliberately NOT added**: 12.0.2
(`>=3.4.0 <4.0.0`) is compatible, but `printing` already covers preview,
print **and** system share (`Printing.sharePdf`), so an extra dependency
buys nothing.

---

## 7. How to add a new report

1. Add a `ReportDefinition` in `report_catalog.dart` (id, titles,
   category, which `needs*` filters, `tabular` if CSV/XLSX makes sense).
2. Write the builder:
   - single/student document → `documents/` (follow `StudentDocuments`);
   - tabular admin/student report → add a `ReportTable` builder in
     `export/tabular_data.dart` + a thin PDF wrapper in
     `documents/admin_reports.dart` via `_tabular(...)`.
3. Add the `case` in `ReportsService.generatePdf` (and nothing else —
   CSV/XLSX flow through `TabularData` automatically).
4. It appears in the hub automatically (catalog-driven filters/buttons).

Rules for new builders:

- Read **only** via `ReportData` (local DB). No Supabase, no HTTP.
- Urdu strings → `s.u(...)` / `s.auto(...)`; never `pw.Text` with Urdu.
- Numbers from the DB only; missing → empty notice, not zeros.
- Keep every `pw` widget tree delimiter-balanced; builders are async —
  pre-render Urdu before `PdfKit.build` returns (the kit handles this).

---

## 8. Validation performed

- **Urdu shaping**: `pdf` 3.12.0 source inspected (`arabic.dart`,
  `options.dart`, `text.dart`); Jameel Noori Nastaleeq cmap inspected
  with fontTools → presentation-form path proven broken for this font →
  `UrduPdf` engine-rasterisation implemented. (Visual proof requires a
  device/Flutter run — not available here.)
- **Package APIs**: `pdf` 3.12.0, `printing` 5.14.3, `excel` 4.0.6
  sources downloaded; every API used (`pw.MultiPage` header/footer,
  `pw.MemoryImage`, `PdfPageFormat`, `Printing.sharePdf/layoutPdf`,
  `PdfPreview`, `Excel.createExcel`, `sheet.appendRow`,
  `CellIndex.indexByColumnRow`, `CellStyle`, `ExcelColor.fromHexString`,
  `sheet.setColumnWidth`, `excel.rename`, `excel.encode`) verified
  against the actual sources.
- **Schema**: every table/column name copied from
  `lib/data/local/app_database.dart`; JSON keys from the model
  `fromJson`/`toJson` methods (`father_name`, `date_of_birth`,
  `amount_paid`, `payment_date`, `entry_date`, …).
- **Delimiter balance**: automated brace/paren/bracket scan over all new
  files (see worker report).
- **Not done**: `flutter analyze` / compilation / on-device run — no
  Flutter toolchain in this environment. Stated honestly wherever
  relevant.

## 9. Deferred / known limits

- Urdu in PDFs is raster (not selectable). Revisit if `pdf` gains
  HarfBuzz shaping.
- Branding cache (`tenant_settings_cache` + logo file) has no writer
  yet — reports fall back to neutral branding until the sync layer (or
  a sibling worker) populates it; the payload contract is specified
  above.
- `printing`'s `PdfPreview` renders via the platform print pipeline;
  complex-script raster images preview fine.
- Photo support (student photos on ID cards/admission forms): the DB
  has no local photo bytes path; placeholders are drawn instead.
- `result_card` without an explicit exam picks the student's latest
  exam by `exam_date` (may be imprecise if dates are missing).
