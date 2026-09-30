# Font Audit — Urdu Typography Policy Compliance

**Repo:** `~/workspace/madrassa-redesign-fix` (Flutter package `madrasa_360`)
**Date:** 2026-09-30
**Scope:** AUDIT ONLY — no code changed.
**Policy source:** `lib/core/constants/app_typography.dart`

Binding policy used for classification:
- `JameelNooriNastaleeq` — headings, titles, short labels, navigation, card titles, tabs, table headers, buttons (incl. `labelNastaliq`, `title*`, `heading*`, `navLabel`, `appBarTitle`).
- `JameelNooriKasheeda` — hero/greeting headers only.
- `NotoNaskhArabic` — body paragraphs, inputs, contact info, small readable body text.
- English/digits may use default fonts. Genuine Urdu body paragraphs / inputs / error text / snackbar content in Naskh are **not** flagged.
- The global `ThemeData.fontFamily` is `NotoNaskhArabic`, so any unstyled Urdu text renders in Naskh — acceptable for body, wrong for headings/labels/navigation/buttons/tabs/card titles/table headers.
- `pubspec.yaml` correctly declares all three families — no declaration problem.
- Kasheeda check: the only Kasheeda usage in `lib/` is the dashboard greeting header (`dashboard_scaffold.dart:180`, `greetingKasheeda`) — correct, no misuse found.

Method: automated scan of all 255 Dart files under `lib/` containing Arabic script, plus targeted structural sweeps (Text/TextSpan/RichText/SelectableText, chip/popup-menu/tab/nav destinations, drawers, FAB labels, raw `labelText`/`hintText`, dialog titles, `fontFamily:` uses), with every candidate manually verified in context. Each line below is a verified finding.

Format: `path:LINE — <widget/style> — <Urdu text> — <should be X, is Y>`

---

## Core / legacy dialogs & services

core/services/network_service_improved.dart:50 — AlertDialog title Text — 'انٹرنیٹ دستیاب نہیں' — should be Nastaleeq, is theme default (Naskh)
core/services/network_service_improved.dart:55 — TextButton child Text — 'ٹھیک ہے' — should be Nastaleeq, is theme default (Naskh)
core/sync/conflict_review_screen.dart:164 — TextButton.icon label Text — 'تفصیل چھپائیں' / 'مقامی بمقابلہ سرور دیکھیں' — should be Nastaleeq, no style (inherits Naskh)
core/sync/conflict_review_screen.dart:258 — ElevatedButton.icon label Text — 'سرور رکھیں' — should be Nastaleeq, no style
core/sync/conflict_review_screen.dart:266 — ElevatedButton.icon label Text — 'مقامی دوبارہ بھیجیں' — should be Nastaleeq, no style
core/sync/conflict_review_screen.dart:310 — ElevatedButton.icon label Text — 'سرور رکھیں (مقامی حذف کریں)' — should be Nastaleeq, no style
core/sync/conflict_review_screen.dart:325 — ElevatedButton.icon label Text — 'فنانس کھولیں' — should be Nastaleeq, no style
core/update/update_service.dart:279 — AlertDialog title Text — 'نئی اپ ڈیٹ دستیاب ہے' — should be Nastaleeq, no style
core/update/update_service.dart:299 — TextButton child Text — 'بعد میں / Later' — should be Nastaleeq, no style
core/update/update_service.dart:318 — FilledButton child Text — 'اپ ڈیٹ کریں / Update' — should be Nastaleeq, no style
core/update/update_service.dart:399 — FilledButton.icon label Text — 'اپ ڈیٹ ڈاؤن لوڈ کریں / Download update' — should be Nastaleeq, no style
core/utils/error_handler.dart:46 — AlertDialog title Text — 'خرابی' — should be Nastaleeq, no style
core/utils/error_handler.dart:51 — TextButton child Text — 'ٹھیک ہے' — should be Nastaleeq, no style
core/utils/error_handler.dart:138 — ElevatedButton.icon label Text — 'دوبارہ کوشش کریں' — should be Nastaleeq, no style
core/widgets/empty_state_widget.dart:125 — ElevatedButton.icon label Text — 'دوبارہ کوشش کریں' — should be Nastaleeq, no style

## Certificates

presentation/screens/certificates/certificates_screen.dart:366 — Text w600 (student picker) — student name `_student!.name` — should be Nastaleeq, is default w600 (Naskh)
presentation/screens/certificates/certificates_screen.dart:378 — TextButton child Text — 'تبدیل کریں' — should be Nastaleeq, no style
presentation/screens/certificates/certificates_screen.dart:488 — Text w600 (type card) — `type.labelUr` (certificate-type card title) — should be Nastaleeq, is default w600
presentation/screens/certificates/certificates_screen.dart:575 — Text w600 (history row) — `h.studentName` — should be Nastaleeq, is default w600

## Exam wizard

presentation/screens/dashboards/exam_wizard_screen.dart:360 — raw InputDecoration labelText — 'امتحان کا نام' — should be Nastaleeq (labelNastaliq), is theme labelStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:361 — raw InputDecoration hintText — 'مثلاً: سہ ماہی امتحان' — should be Nastaleeq (m360 hint policy), is theme hintStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:378 — raw InputDecoration labelText — 'امتحان کی تاریخ' — should be Nastaleeq, is theme labelStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:395 — raw InputDecoration labelText — 'درجہ / جماعت (اختیاری)' — should be Nastaleeq, is theme labelStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:419 — raw InputDecoration labelText — 'کل نمبر' — should be Nastaleeq, is theme labelStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:448 — raw InputDecoration labelText — 'مضمون ${i + 1}' — should be Nastaleeq, is theme labelStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:460 — raw InputDecoration labelText — 'کل نمبر' — should be Nastaleeq, is theme labelStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:589 — ChoiceChip label Text — subject name `e.value.name` — should be Nastaleeq, no style
presentation/screens/dashboards/exam_wizard_screen.dart:626 — raw InputDecoration labelText — 'نمبر' — should be Nastaleeq, is theme labelStyle (Naskh)
presentation/screens/dashboards/exam_wizard_screen.dart:653 — ElevatedButton.icon label Text — '«<subject>» کے نمبر محفوظ کریں' — should be Nastaleeq, no style (rest of file already uses labelNastaliq on button labels)

## Finance hub

presentation/screens/finance/finance_dashboard_tab.dart:140 — empty-state Text — 'کوئی بقایا نہیں — تمام فیس وصول ہو چکی ہے۔' — should be titleSmall (Nastaleeq), no style
presentation/screens/finance/finance_dashboard_tab.dart:176 — Text w600 — student name `o.topDues[i].studentName` — should be Nastaleeq, is default w600
presentation/screens/finance/finance_dashboard_tab.dart:218 — empty-state Text — 'مالیاتی نظام میں ابھی کوئی ادائیگی درج نہیں۔' — should be titleSmall (Nastaleeq), no style
presentation/screens/finance/finance_dashboard_tab.dart:256 — Text w600 — student name `p.studentLabel` — should be Nastaleeq, is default w600
presentation/screens/finance/finance_dues_tab.dart:165 — Text 11px secondary — 'روپے بقایا' (metric label) — should be Nastaleeq, is default (Naskh)
presentation/screens/finance/finance_dues_tab.dart:214 — Text w600 — `view.monthLabel` (month card title) — should be Nastaleeq, is default w600
presentation/screens/finance/finance_expenses_tab.dart:116 — FilterChip label Text — 'سب' / `s.urduLabel` — should be Nastaleeq, no style
presentation/screens/finance/finance_expenses_tab.dart:309 — _kv key Text — 'مد' / 'رقم' / 'وصول کنندہ' / 'تاریخ' / 'تفصیل' — should be Nastaleeq, is default (Naskh)
presentation/screens/finance/finance_expenses_tab.dart:311 — _kv value Text w600 — category/amount/recipient/date/description values — should be Nastaleeq, is default w600
presentation/screens/finance/finance_invoices_tab.dart:122 — FilterChip label Text — 'سب' / `s.urduLabel` — should be Nastaleeq, no style
presentation/screens/finance/finance_invoices_tab.dart:292 — _kv key Text — 'طالب علم' / 'بلنگ ماہ' / 'تاریخ اجراء' / 'آخری تاریخ' / 'ذیلی کل' / 'رعایت' / 'کل رقم' / 'ادا شدہ' / 'بقایا' / 'نوٹس' — should be Nastaleeq, is default (Naskh)
presentation/screens/finance/finance_invoices_tab.dart:295 — _kv value Text w600 — student/month/date/amount values — should be Nastaleeq, is default w600
presentation/screens/finance/finance_invoices_tab.dart:441 — Text bold — 'مدات' (section heading) — should be Nastaleeq, is default bold (Naskh)
presentation/screens/finance/finance_invoices_tab.dart:538 — Text 11px secondary — date-field label — should be Nastaleeq, is default (Naskh)
presentation/screens/finance/finance_ledger_tab.dart:309 — _kv key Text — 'قسم' / 'زمرہ' / 'رقم' / 'تاریخ' / 'تفصیل' — should be Nastaleeq, is default (Naskh)
presentation/screens/finance/finance_ledger_tab.dart:311 — _kv value Text w600 — kind/category/amount/date/title values — should be Nastaleeq, is default w600
presentation/screens/finance/finance_payments_tab.dart:301 — _kv key Text — 'طالب علم' / 'رقم' / 'طریقہ' / 'تاریخ' / 'نوٹس' — should be Nastaleeq, is default (Naskh)
presentation/screens/finance/finance_payments_tab.dart:304 — _kv value Text w600 — student/amount/method/date/notes values — should be Nastaleeq, is default w600

## Hostel

presentation/screens/hostel/hostel_screen.dart:170 — FloatingActionButton.extended label Text(label) — 'نئی عمارت' / 'نیا کمرہ' / 'نیا بستر' / 'بستر الاٹ کریں' — should be Nastaleeq, no style
presentation/screens/hostel/hostel_screen.dart:263 — Text w600 — `b.name` (building card title) — should be Nastaleeq, is default w600
presentation/screens/hostel/hostel_screen.dart:383 — Text w600 — 'کمرہ ${r.roomNo}' (room card title) — should be Nastaleeq, is default w600
presentation/screens/hostel/hostel_screen.dart:540 — Text w600 — 'بستر ${bed.bedNo}' (bed card title) — should be Nastaleeq, is default w600
presentation/screens/hostel/hostel_screen.dart:635 — _FilterChip ChoiceChip label Text(label) — 'سب' / 'خالی' / 'مصروف' / 'مرمت میں' — should be Nastaleeq, no style
presentation/screens/hostel/hostel_screen.dart:693 — Text w600 — `a.studentName` (allocation row title) — should be Nastaleeq, is default w600
presentation/screens/hostel/hostel_screen.dart:734 — TextButton child Text — 'ختم کریں' — should be Nastaleeq, no style
presentation/screens/hostel/hostel_detail_screens.dart:66 — FloatingActionButton.extended label Text — 'نیا کمرہ' — should be Nastaleeq, no style
presentation/screens/hostel/hostel_detail_screens.dart:155 — Text w600 — 'کمرہ ${room.roomNo}' (detail title) — should be Nastaleeq, is default w600
presentation/screens/hostel/hostel_detail_screens.dart:226 — _detailRow label Text — detail labels — should be Nastaleeq, is default (Naskh)
presentation/screens/hostel/hostel_detail_screens.dart:232 — _detailRow value Text w600 — detail values — should be Nastaleeq, is default w600
presentation/screens/hostel/hostel_detail_screens.dart:277 — FloatingActionButton.extended label Text — 'نیا بستر' — should be Nastaleeq, no style
presentation/screens/hostel/hostel_detail_screens.dart:310 — Text w600 — 'بستر ${bed.bedNo}' (bed card title) — should be Nastaleeq, is default w600
presentation/screens/hostel/hostel_detail_screens.dart:324 — status Text w600 — `_bedStatusUr(bed.status)` — should be Nastaleeq, is default w600

## Transport

presentation/screens/transport/transport_screen.dart:168 — FloatingActionButton.extended label Text(label) — 'نئی گاڑی' / 'نیا ڈرائیور' / 'نیا راستہ' / 'نئی اسائنمنٹ' — should be Nastaleeq, no style
presentation/screens/transport/transport_screen.dart:374 — Text w600 — `d.name` (driver card title) — should be Nastaleeq, is default w600
presentation/screens/transport/transport_screen.dart:478 — Text w600 — `r.name` (route card title) — should be Nastaleeq, is default w600
presentation/screens/transport/transport_screen.dart:597 — Text w600 — route name (assignment row title) — should be Nastaleeq, is default w600
presentation/screens/transport/transport_detail_screens.dart:66 — FloatingActionButton.extended label Text — 'نیا اسٹاپ' — should be Nastaleeq, no style
presentation/screens/transport/transport_detail_screens.dart:180 — Text w600 — `stop.name` (stop row title) — should be Nastaleeq, is default w600

## Settings

presentation/screens/settings/delegation_screen.dart:59 — FloatingActionButton.extended label Text — 'اختیار سونپیں' — should be Nastaleeq, no style
presentation/screens/settings/scope_manager_screen.dart:73 — FloatingActionButton.extended label Text — 'دائرہ کار مقرر کریں' — should be Nastaleeq, no style
presentation/screens/settings/user_management_hub.dart:110 — FloatingActionButton.extended label Text — 'نیا صارف' — should be Nastaleeq, no style
presentation/screens/settings/user_management_hub.dart:320 — PopupMenuItem child Text — 'فعال کریں' — should be Nastaleeq, no style
presentation/screens/settings/user_management_hub.dart:321 — PopupMenuItem child Text — 'غیر فعال کریں' — should be Nastaleeq, no style
presentation/screens/settings/delegation_create_screen.dart:127 — CheckboxListTile title Text — `p.labelUrdu` (permission label) — should be Nastaleeq, is bodyMedium (Naskh)

## Master admin / super admin

presentation/screens/master_admin/licenses_screen.dart:113 — ChoiceChip label Text — 'تمام' / `licenseStatusUrdu(s)` — should be Nastaleeq, no style
presentation/screens/master_admin/plans_screen.dart:191 — PopupMenuItem child Text — 'ترمیم' — should be Nastaleeq, no style
presentation/screens/master_admin/plans_screen.dart:195 — PopupMenuItem child Text — 'فعال کریں' / 'غیر فعال کریں' — should be Nastaleeq, no style
presentation/screens/master_admin/plans_screen.dart:197 — PopupMenuItem child Text — 'حذف کریں' — should be Nastaleeq, no style
presentation/screens/master_admin/plans_screen.dart:372 — SwitchListTile title Text — 'فعال / Active' — should be Nastaleeq, no style
presentation/screens/super_admin/madrasa_management_screen.dart:162 — Text labelMedium — 'فعال' / 'غیرفعال' (status label) — should be Nastaleeq, is labelMedium (Naskh)
presentation/screens/super_admin/super_admin_main_screen.dart:45 — NavigationDestination label — 'ڈیش بورڈ' — should be Nastaleeq, is M3 NavigationBar default label (Naskh; theme has no navigationBarTheme)
presentation/screens/super_admin/super_admin_main_screen.dart:51 — NavigationDestination label — 'مدارس' — should be Nastaleeq, is M3 NavigationBar default label (Naskh)
presentation/screens/super_admin/super_admin_main_screen.dart:57 — NavigationDestination label — 'صارفین' — should be Nastaleeq, is M3 NavigationBar default label (Naskh)
presentation/screens/super_admin/super_admin_main_screen.dart:62 — NavigationDestination label — 'بارے میں' — should be Nastaleeq, is M3 NavigationBar default label (Naskh)
presentation/screens/super_admin/super_admin_dashboard_screen.dart:178 — ListTile title Text — `m.nameUrdu` (madrasa card title) — should be Nastaleeq, is bodyLarge (Naskh)

## Admin

presentation/screens/admin/user_management_screen.dart:934 — ListTile title Text — 'حذف کریں' (menu label) — should be Nastaleeq, is bodyMedium (Naskh)
presentation/screens/admin/darja_screen.dart:187 — ListTile title Text — `darja.nameUrdu` — should be Nastaleeq, is bodyLarge (Naskh)
presentation/screens/admin/darja_screen.dart:219 — ListTile title Text — `sec.nameUrdu` — should be Nastaleeq, is bodyMedium (Naskh)
presentation/screens/crash_screen.dart:142 — ElevatedButton label Text — 'دوبارہ شروع کریں • Restart' — should be Nastaleeq, is labelLarge (Naskh)

## Parent

presentation/screens/parent/parent_dashboard_screen.dart:471 — ListTile title Text — 'فیس کی ہسٹری' (drawer nav item) — should be Nastaleeq, is bodyLarge (Naskh)
presentation/screens/parent/parent_dashboard_screen.dart:483 — ListTile title Text — 'اعلانات' (drawer nav item) — should be Nastaleeq, is bodyLarge (Naskh)
presentation/screens/parent/fee_history_screen.dart:362 — OutlinedButton child Text — 'بند کریں' — should be Nastaleeq, no style

## Common / shell

presentation/screens/common/announcements_screen.dart:56 — FloatingActionButton.extended label Text — 'نیا اعلان' — should be Nastaleeq, no style
presentation/shell/app_shell.dart:132 — failsafe Center Text — 'رسائی دستیاب نہیں' — should be Nastaleeq, no style (unreachable failsafe path)

---

## Total: 93 findings across 34 files

## Top 5 worst files

1. `presentation/screens/dashboards/exam_wizard_screen.dart` — 10
2. `presentation/screens/hostel/hostel_screen.dart` — 7
3. `presentation/screens/hostel/hostel_detail_screens.dart` — 7
4. `presentation/screens/finance/finance_invoices_tab.dart` — 5
5. `core/sync/conflict_review_screen.dart` — 5

---

## Verified non-findings (checked, deliberately excluded)

- `core/design/m360_table.dart:333` — bare `Text('کارروائی')` in `DataColumn` is **not** a violation: `DataTable(headingTextStyle: AppTypography.labelNastaliq)` is set and Flutter wraps column labels in that style automatically.
- All `M360*` design-system components (buttons, text fields, dropdowns, chips, badges, empty/loading states, page headers, app bar) apply `labelNastaliq`/title styles internally — their Urdu `label:`/`title:`/`hint:` params are compliant.
- Theme-covered text: AppBar titles (`appBarTitle`), bottom-nav labels (`navLabel`), `ListTile` titles via `listTileTheme.titleTextStyle = titleMedium`, `DataTable` headers/cells — not flagged.
- Urdu body paragraphs, long notices, inline form/snackbar error text, and empty-state descriptions in Naskh — policy-correct, not flagged.
- Dropdown menu items / `M360Dropdown` options in Naskh — sanctioned by the design system's own `bodyLarge` item style, not flagged.
- `M360FieldDecoration` labels and hints explicitly use `labelNastaliq` — login/forgot-password/user-wizard/create-madrasa-wizard fields are compliant.
- Digits-only or Latin-only text (badge counts, 'Ctrl+K', 'Back to app', module keys, UUIDs, crash details in monospace) — not flagged.
- Kasheeda is used only for the dashboard greeting header — no misuse.
- `tenant_branding_provider.dart:100` uses a tenant-selected dynamic font family — a policy decision, not a static violation; left out of scope.
- `app_shell.dart:132` failsafe is documented unreachable in practice (kept as a finding for completeness).
