# Responsive Audit — madrassa-redesign-fix (lib/)

Date: 2026-09-30. Scope: all of `lib/` (82 screens + shared widgets). Method:
4 parallel auditors + spot-verification of the severest claims by reading
surrounding code. Target: 360px phones → 1920px desktops, 1.5x text scale,
portrait + landscape.

NOT flagged (verified clean): `M360Dialog`/M360 confirm dialogs (adaptive,
maxWidth 480, Wrap actions, scrollable content), `M360ResponsiveTable`
(DataTable already in horizontal scroll), icon/avatar/logo fixed sizes,
`fee_management_screen` 220px stat cards (inside horizontal scroll),
`master_dashboard_screen` 170px stat cards (inside Wrap),
`super_admin_dashboard_screen` 2-col grid (inside `M360ConstrainedWidth`),
`admin_dashboard_screen` 2-col module grid (inside `M360ConstrainedWidth`),
login 112px logo, `ShellPageBody` (Expanded child), both wizard screens
(Expanded + SingleChildScrollView), all `core/design` components
(Expanded + ellipsis throughout).

---

## Auth

lib/presentation/screens/auth/login_screen.dart:273 — Container (login card, width: double.infinity) — no max-width constraint — stretches full viewport width (~1872px) on 1920px desktop, inputs/button span edge to edge
lib/presentation/screens/auth/forgot_password_screen.dart:84 — Form Column (crossAxisAlignment.stretch) — no max-width/centering — email field and full-width reset button stretch across a 1920px desktop
lib/presentation/screens/auth/no_access_screen.dart:41 — Column (centered, non-scrollable) — no SingleChildScrollView — overflows in landscape / at 1.5x text scale on short screens

## Parent

lib/presentation/screens/parent/parent_dashboard_screen.dart:149 — Container (height: 52) child selector — fixed height with 8px vertical padding — FilterChip labels clip at 1.5x text scale (chips need ~48px+)
lib/presentation/screens/parent/parent_dashboard_screen.dart:244 — Container badge Text ('${child.className} - رول نمبر ${child.rollNo}') — no maxLines/overflow/softWrap — long class name overflows the card at 360px or 1.5x text scale
lib/presentation/screens/parent/parent_dashboard_screen.dart:250 — Row of two _buildChildStat Rows — no Expanded/Flexible — attendance + result stat pairs overflow at 360px with 1.5x text scale
lib/presentation/screens/parent/fee_history_screen.dart:145 — summary stats Row (spaceAround: 3 _buildFeeStat columns + 2 fixed width:1/height:40 dividers) — no Expanded — overflows at 360px + 1.5x text scale with large amounts (e.g. '1250000' at titleLarge)
lib/presentation/screens/parent/fee_history_screen.dart:241 — inner Row (due-date Text + paid-date Text) — no Expanded/Flexible — overflows at 1.5x text scale when both dates render (~90–140px available once the amount column takes its share)
lib/presentation/screens/parent/fee_history_screen.dart:307 — _showFeeDetails bottom sheet Column (mainAxisSize.min) — no SingleChildScrollView — 9 detail rows + button overflow at 1.5x text scale / short screens; value Text (row.$2) has no overflow handling, long student names overflow at 360px

## Common

lib/presentation/screens/common/profile_screen.dart:420 — _showEditProfileSheet bottom sheet Column (mainAxisSize.min) — no SingleChildScrollView — photo picker + 3 text fields + save button overflow when the keyboard opens or at 1.5x text scale on 360px phones

## Finance

lib/presentation/screens/finance/finance_dashboard_tab.dart:115 — GridView (SliverGridDelegateWithFixedCrossAxisCount, mainAxisExtent: 132) — fixed cell height with 28sp stat value text — at 1.5x text scale the value wraps to 2 lines and is clipped by the fixed 132px extent
lib/presentation/screens/finance/finance_invoices_tab.dart:200 — _invoiceTile totals Row (spaceBetween, two plain Texts, no Expanded/Flexible) — overflows at 360px with 1.5x text scale
lib/presentation/screens/finance/finance_invoices_tab.dart:286 — _kv Row — value Text has no Flexible — long values overflow at 360px
lib/presentation/screens/finance/finance_payments_tab.dart:295 — _kv Row — value Text has no Flexible (compare: expenses/ledger _kv wrap the value in Flexible) — long notes overflow at 360px

## Hostel

lib/presentation/screens/hostel/hostel_screen.dart:484 — _BedsTab filter chips Row (4 chips in a non-scrollable Row, horizontal padding 16) — combined chip width (~390px) exceeds 360px even at 1.0x text scale — overflows at 360px
lib/presentation/screens/hostel/hostel_detail_screens.dart:220 — _infoRow — value Text in a Row with no Flexible/Expanded — long building notes overflow at 360px

## Shared dashboard widgets (used by every role dashboard)

lib/presentation/widgets/dashboard/quick_actions.dart:43 — QuickActionGrid (fixed crossAxisCount: 3, mainAxisExtent: 124) — at 1.5x text scale the 2-line Nastaliq label (16sp, height 2.0) + icon needs ~150px > 124px → Column overflow; no breakpoint adaptation, tiles stretch ~600px wide on a 1920px desktop (AppShell body is full-width, verified)
lib/presentation/widgets/dashboard/dashboard_section.dart:100 — DashboardSection tiles GridView (fixed crossAxisCount: 3, mainAxisExtent: 104) — at 1.5x text scale content (~122px) exceeds 104px → Column overflow; same 1920px stretch problem; labels have maxLines: 2 + ellipsis but the 2-line cap itself exceeds the fixed extent at 1.5x

## Admin

lib/presentation/screens/admin/admin_dashboard_screen.dart:560 — Row (spaceBetween) of three _buildFeeStatItem columns with money values, no Expanded/Flexible — overflows at 360px (a 14-char value like '3,80,000 روپے' at 19px titleMedium ≈ 147px × 3 = 441px vs ~264px available; breaks even at 1x text scale with realistic amounts)
lib/presentation/screens/admin/admin_dashboard_screen.dart:483 — _moduleCard subtitle Text — fixed childAspectRatio: 1.5 grid cells give ~63px inner height at 360px but icon (38px) + label (30.6px) + subtitle (≥19.2px) need ≥88px — overflows at 360px even at 1x text scale, worse at 1.5x
lib/presentation/screens/admin/admin_main_screen.dart:105 — bottom-nav Row (spaceAround) — up to 5 tabs (ڈیش بورڈ/طلباء/حاضری/نتائج/پروفائل) with fixed 24px horizontal padding per item, no scroll or Expanded — intrinsic width ≈ 408px vs 344px available at 360px — horizontal RenderFlex overflow at 1x text scale, worse at 1.5x
lib/presentation/screens/admin/fee_management_screen.dart:312 — Row (spaceBetween) — 'ادا شدہ: …' and 'بقایا: … روپے' Texts with no Flexible — overflows at 360px with large amounts (≈ 265px needed vs ~202px available at 1x; definite at 1.5x)
lib/presentation/screens/admin/staff_list_screen.dart:123 — SizedBox (height: 50) — horizontal FilterChip list — chip + list padding needs ~60px at 1.5x text scale — clips filter chips at 1.5x
lib/presentation/screens/admin/staff_list_screen.dart:241 — Row of two _infoChip (icon + Text, no overflow/ellipsis) — needs ~210px at 1.5x text scale vs ~157px available at 360px — overflows at 1.5x

## Teacher

lib/presentation/screens/teacher/results_screen.dart:211 — SizedBox (height: 50) — horizontal FilterChip list — clips filter chips at 1.5x text scale
lib/presentation/screens/teacher/results_screen.dart:339 — SizedBox (width: 64) — marks M360LatinText ('100/100') — text needs ~80px at 1.5x text scale vs fixed 64px — overflows (or wraps mid-number after '/') at 1.5x

## Master admin

lib/presentation/screens/master_admin/modules_screen.dart:78 — GridView.builder (fixed crossAxisCount: 2, childAspectRatio: 1.25) — returned directly as a shell destination with no PageContainer/M360ConstrainedWidth ancestor (verified) — at 1920px renders two ~950px-wide cards instead of adapting column count
lib/presentation/screens/master_admin/madrasa_list_screen.dart:165 — SizedBox (height: 44) around a horizontal ListView of ChoiceChips with no vertical padding — at 1.5x text scale the chip labels grow taller than the 44px box and clip vertically
lib/presentation/screens/master_admin/licenses_screen.dart:103 — SizedBox (height: 52) around a horizontal ListView of ChoiceChips with vertical: 8 padding (36px of content room) — at 1.5x text scale the chips exceed the available height and clip vertically
lib/presentation/screens/master_admin/subscriptions_screen.dart:74 — SizedBox (height: 52) around a horizontal ListView of ChoiceChips with vertical: 8 padding — same vertical clip at 1.5x text scale as licenses_screen
lib/presentation/screens/master_admin/create_madrasa_wizard.dart:763 — _successRow Row (spaceBetween) — plain Text label + SelectableText value, no Flexible/Expanded — a long admin email value crowds out the label and overflows at 360px

## Super admin

lib/presentation/screens/super_admin/madrasa_management_screen.dart:137 — city/branch Row — two icon+text pairs with Text/M360LatinText, no Expanded/Flexible or overflow handling — long city or branch-code strings overflow at 360px, especially at 1.5x text scale

## Settings

lib/presentation/screens/settings/user_wizard_screen.dart:286 — stepper Row — five step Columns sized by intrinsic label width (no Expanded/Flexible); step labels (Text at :322) have no maxLines/overflow — at 1.5x text scale the Urdu labels ('بنیادی معلومات', 'دائرۂ کار', …) exceed the 328px available and the row overflows
lib/presentation/screens/settings/user_management_hub.dart:307 — _bulkBar Row — Text('${_selected.length} منتخب') + Spacer + M360TertiaryButton('ذمہ داری تبدیل کریں') + PopupMenuButton with no Flexible — at 360px with 1.5x text scale the button label overflows the bar

---

**Total: 34 responsiveness defects** across 21 files.
Pattern summary: (a) fixed-height chip/filter strips clipping at 1.5x text scale — 6 hits; (b) Row texts without Expanded/Flexible overflowing at 360px — 14 hits; (c) fixed-column grids with no breakpoint adaptation (stretch at 1920px / cramped or clipping at 360px+1.5x) — 4 hits; (d) non-scrollable bottom sheets / screens — 3 hits; (e) full-bleed desktop cards with no max-width — 2 hits; (f) fixed-size grid tiles clipping at 1.5x — 3 hits; (g) bottom-nav Row overflow — 1 hit; (h) fixed-width marks field — 1 hit.
