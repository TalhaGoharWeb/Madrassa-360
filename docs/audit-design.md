# Design System & UI Component Audit — Madrassa 360

**Date:** 2026-09-29
**Branch:** `redesign/ux-v2`
**Scope:** `lib/core/design/` (8 files), `lib/core/constants/app_colors.dart`, `lib/core/constants/app_typography.dart`, `lib/core/theme/app_theme.dart`, and usage sampling across 25+ screens in `lib/presentation/`.
**Method:** Static code reading + grep inventory. No code was changed.

---

## 1. Executive summary

The repository contains **four parallel widget/styling systems**, of which exactly **one** (the `m360_*` design system) is the documented standard — and it has **zero usages** anywhere outside `lib/core/design/`. Every one of the 85 files under `lib/presentation/` styles itself ad hoc (275 raw `Card(`, 37 `ElevatedButton(`, 52 `TextButton(`, 50 `IconButton(`, 14 `FloatingActionButton`, 71 raw `TextField`/`TextFormField`, 69 raw `CircularProgressIndicator`).

The token layer underneath is in good shape: `AppColors` implements the 60/30/10 palette correctly, `AppTypography` wires Jameel Noori Nastaleeq with sane fallbacks and anti-clipping line heights, and `design_tokens.dart` matches the mission's spacing/radius spec. The problem is **adoption: 0%**, plus three competing legacy component libraries and stale leftovers (old `#009688` teal, per-role rainbow gradients).

---

## 2. Design tokens audit

### 2.1 Color palette — 60/30/10 compliance

Source: `lib/core/constants/app_colors.dart`

| Token | Value | Role | Compliant |
|---|---|---|---|
| `background` | `0xFFF1FAF7` | 60% mint surface | ✅ |
| `surface` | `0xFFFFFFFF` | 60% white surface | ✅ |
| `primary` | `0xFF0F6B63` | 30% deep teal | ✅ |
| `primaryDark` | `0xFF094742` | 30% dark teal | ✅ |
| `primaryLight` | `0xFF4DB6AC` | teal tint | ✅ |
| `accent` | `0xFFF28C28` | 10% warm orange CTA | ✅ |
| `accentDark` | `0xFFD97706` | orange pressed | ✅ |
| `gold` | `0xFFC9A227` | brand accent | ✅ |
| semantic `success/warning/error/info` | `4CAF50/FF9800/F44336/2196F3` | restrained | ✅ |
| attendance `present/absent/leave/late` | green/red/amber/blue | domain statuses | ✅ |
| fee `paid/pending/pastDue` | green/orange/red | domain statuses | ✅ |

**Verdict: the token definitions are 60/30/10-compliant.** Violations exist only at usage sites (see §5).

`M360Brand` (`lib/core/design/design_tokens.dart:100-113`) duplicates `gold`/`goldLight` already present in `AppColors` — minor duplication, same hex values.

### 2.2 Typography — is Jameel Noori Nastaleeq wired?

Source: `lib/core/constants/app_typography.dart`, `pubspec.yaml:111-122`

- ✅ Font files bundled: `assets/fonts/JameelNooriNastaleeq-v4.ttf`, `JameelNooriNastaleeqKasheeda-subset.ttf`, `NotoNaskhArabic-Regular.ttf`, `NotoNaskhArabic-Bold.ttf` — all present on disk and declared in pubspec.
- ✅ Family names: `nastaliqFamily='JameelNooriNastaleeq'`, `kasheedaFamily='JameelNooriKasheeda'`, `naskhFamily='NotoNaskhArabic'`.
- ✅ Fallback chains: display → `[naskhFamily]`; body → `[nastaliqFamily]`; kasheeda → `[nastaliqFamily, 'NotoNastaliqUrdu']`. Never falls back to platform system font.
- ✅ Anti-clipping: every Nastaleeq style enforces `height >= 2.0` (docstring at `app_typography.dart:10-13`); `labelNastaliq` documents the ≥15sp legibility floor.
- ✅ `AppTheme.lightTheme` (`lib/core/theme/app_theme.dart:20`) sets `fontFamily: AppTypography.naskhFamily` globally, so undecorated text inherits Naskh.
- ✅ `isUrduText()` helper (`app_typography.dart:127`) exists for bilingual label switching.
- ⚠️ **Gap: no `caption` style exists.** (This caused CI failure on commit `16ec2a2d`; fixed by using `bodySmall`.) Smallest styles are `labelSmall` (12sp) and `bodySmall` (14sp).
- ⚠️ `buttonText` (18sp Naskh) is defined but `m360_buttons.dart` uses `labelNastaliq` for button labels instead — two competing button-text conventions.

**Verdict: typography system is well-designed and correctly bundled; adoption is partial** (see §5.4 for `fontFamily` literals bypassing it).

### 2.3 Spacing / radius / elevation

Source: `lib/core/design/design_tokens.dart`

| Token set | Values | Matches mission spec (§18) |
|---|---|---|
| `M360Spacing` | xxs 4, xs 8, sm 12, md 16, lg 24, xl 32, xxl 48 | ✅ exact |
| `M360Radius` | sm 8, md 12, lg 16, xl 24, pill 999 | ✅ exact |
| `M360Elevation` | none 0, sm 2, md 4, lg 8 | ✅ |
| `M360Duration` | 150/300/500 ms | ✅ subtle-motion |
| `M360Breakpoint` | mobile 600, tablet 1100 | ✅ |
| `M360TouchTarget` | 48×48 | ✅ a11y |

**Verdict: keep as-is.** The one concern is that nothing references these tokens (0 usages).

### 2.4 `responsive.dart`

`Responsive.isMobile/isTablet/isDesktop`, `ResponsiveLayout`, `M360ConstrainedWidth` — clean, breakpoint-consistent with `M360Breakpoint`. **0 usages** outside the file itself. Screens hand-roll `MediaQuery` checks instead (spot-check: dashboards use inline width checks).

---

## 3. Component inventory — four parallel systems

| # | System | Location | Components | Usage |
|---|---|---|---|---|
| 1 | **m360_\* design system** | `lib/core/design/` (8 files) | M360Primary/Secondary/Danger/IconButton, M360Card, M360TappableCard, M360StatCard, M360SectionHeader, M360TextField, M360PickerField, M360Badge(+8 kinds), M360EmptyState, M360LoadingState, M360ErrorState, M360ResponsiveTable, tokens, responsive helpers | **0 files** import it |
| 2 | Legacy core widgets | `lib/core/widgets/` | `PrimaryButton`, `SecondaryButton`, `IconButtonWidget` (`custom_buttons.dart`); `EmptyStateWidget`, `ErrorStateWidget`, `LoadingStateWidget` (`empty_state_widget.dart`); `LoadingWidget`, `LoadingOverlay`, `ShimmerLoading`, `ListShimmerLoading` (`loading_widget.dart`) | used (e.g. `login_screen.dart:10` imports `loading_widget.dart`) |
| 3 | Presentation widgets | `lib/presentation/widgets/common/app_widgets.dart` | `AppCard`, `StatCard`, `EmptyState`, `SearchField`, `StatusBadge`, `SectionHeader`, `InfoTile`, `LoadingOverlay` (duplicate of #2's) | used by 8+ screens |
| 4 | Dashboard widgets | `lib/presentation/widgets/dashboard/` | `stat_card.dart` (`StatCard` #3), `dashboard_scaffold.dart`, `dashboard_section.dart`, `quick_actions.dart`, `alert_card.dart`, `today_tasks.dart`, `pattern_background.dart`, … | used by all dashboards |

**Three different `StatCard` implementations exist:**
- `M360StatCard` — `lib/core/design/m360_cards.dart:137` — vertical (icon row → value → label), 0 usages.
- `StatCard` — `lib/presentation/widgets/common/app_widgets.dart:74` — vertical with trend row, used by admin/fee/student/parent screens (8 importers).
- `StatCard` — `lib/presentation/widgets/dashboard/stat_card.dart:14` — **horizontal** (icon circle + label/value column, radius 16, custom `BoxShadow`), used by all 10 dashboards.

**Two `LoadingOverlay` implementations:** `lib/core/widgets/loading_widget.dart:49` and `lib/presentation/widgets/common/app_widgets.dart:495`.

**No barrel export** exists for `lib/core/design/` — there is not even a discoverable import path; every screen would have to guess the file name.

---

## 4. Component usage analysis (m360_\* adoption)

Grep over all of `lib/` excluding `lib/core/design/` itself:

- Files importing anything from `lib/core/design/`: **0**
- Files referencing any `M360*` symbol: **0**
- `M360Spacing` / `M360Radius` / `M360Elevation` / `Responsive` / `M360ConstrainedWidth` references outside design/: **0**

Screens instead import `app_colors.dart` + `app_typography.dart` directly (universal) and hand-build every control. Sampled import blocks: `principal_dashboard.dart:33-35`, `student_profile_screen.dart:4-5`, `login_screen.dart:4-6`, `user_management_hub.dart:14-15`, `app_shell.dart:24-25`, `app_nav_rail.dart:17-18`.

**Adoption rate of the m360_\* system: 0%.**

---

## 5. Inconsistencies (with file:line citations)

### 5.1 Stale / wrong colors

- `lib/presentation/shell/app_nav_rail.dart:271` — `color: Color(0xFF009688)` — **the old bright teal** the 60/30/10 migration removed; a leftover violating the palette.
- `lib/presentation/shell/app_nav_rail.dart:31` — `const Color _kGold = Color(0xFFC9A227)` — duplicates `AppColors.gold` / `M360Brand.gold`.
- `lib/presentation/shell/app_nav_rail.dart:438` — `color: const Color(0xFF8a6d1c)` — hardcoded dark gold.
- `lib/core/config/role_config.dart:40-163` — **per-role rainbow gradients**: purple `#4527A0/#7C4DFF` (superAdmin), blue `#448AFF/#2979FF` (franchise/accountant), brown `#4E342E` (clerk), deep-orange `#E65100/#FF6D00` (teacher) — directly violate 60/30/10 and the "no rainbow" rule.
- `lib/presentation/screens/teacher/attendance_screen.dart:259` — offline banner uses `Colors.orange.shade700` instead of `AppColors.warning` (`#FF9800`).
- `lib/presentation/screens/admin/backup_screen.dart:171,205,225,352,356,375` — `Colors.red` / `Colors.grey` literals instead of `AppColors.error` / `textSecondary`.
- `lib/presentation/screens/admin/staff_list_screen.dart:718,726,907,915` — `backgroundColor: Colors.green` / `Colors.red` instead of `AppColors.success` / `error`.
- `lib/presentation/screens/admin/fee_management_screen.dart:848` — `backgroundColor: Colors.green`.
- `lib/presentation/screens/students/student_dialogs.dart:242,250,400,408,615` — `Colors.green` / `Colors.red` literals.
- `lib/presentation/screens/common/notifications_screen.dart:141,172,177,231` — `Colors.grey.shade400/200/600` literals.
- `lib/presentation/screens/common/announcements_screen.dart:222,255` — `Colors.red` for pin icon.
- `lib/presentation/screens/super_admin/madrasa_management_screen.dart:113`, `super_admin_dashboard_screen.dart:123` — `Colors.amber[700]!` literals.
- `lib/presentation/screens/auth/forgot_password_screen.dart:160,164` — `Colors.green` literals.
- `lib/presentation/screens/parent/parent_dashboard_screen.dart:468,480` — `Colors.green`, `Colors.blue` icon literals.
- `lib/core/errors/error_boundary.dart:98`, `lib/core/utils/error_handler.dart:63,81,125`, `lib/core/services/network_service_improved.dart:145` — `Colors.red`/`Colors.green` snackbar colors instead of tokens.
- `lib/core/reports/documents/*.dart` — `Color(0xFF9E9E9E)`, `Color(0xFF424242)`, `Color(0xFF616161)` literals (PDF docs; lower priority but still untokenized).

### 5.2 Mixed button styles

- 37 raw `ElevatedButton(`, 52 `TextButton(`, 9 `OutlinedButton(`, 50 `IconButton(`, 14 `FloatingActionButton` across presentation — **zero** use `M360PrimaryButton`/`M360SecondaryButton`/`M360IconButton`.
- `lib/presentation/screens/auth/login_screen.dart:459-462` — the **login CTA overrides** the theme to `backgroundColor: AppColors.primary` (teal), while `AppTheme.elevatedButtonTheme` (`app_theme.dart:71-73`) defines orange `#F28C28` for primary CTAs. The most-seen button in the app contradicts the theme.
- `lib/core/design/m360_buttons.dart:18` — docstring says "Creates a primary (**filled teal**) button" but the code uses `AppColors.accent` (orange). **Stale doc; code is correct per 60/30/10.**
- `M360IconButton` requires a `tooltip`; the 50 ad-hoc `IconButton(` usages were not audited for tooltips — likely gaps.
- Missing from m360_\*: **no tertiary/text-button variant** (52 ad-hoc `TextButton(` prove the need), no FAB variant (14 ad-hoc), no dropdown/select component.

### 5.3 Inconsistent card styles

- 275 raw `Card(` in presentation; 0 use `M360Card`/`M360TappableCard`.
- `lib/presentation/widgets/dashboard/stat_card.dart:36-46` — custom `Container` + `BoxShadow(black 5%, blur 10)` + `BorderRadius.circular(16)` instead of design-system card.
- `AppTheme.cardTheme` (`app_theme.dart:60-67`) sets `elevation: 2, margin: EdgeInsets.all(8), radius 12`; `M360Card` defaults to `M360Elevation.sm` (= 2), radius 12, margin zero — **two competing card defaults** (theme margin 8 vs M360 margin 0).
- `BorderRadius.circular` literals in presentation: 173× in the 10–19 range, 42× in the 20s, 26× `8`, plus `4`/`6`/`3`/`9` — no single radius language.

### 5.4 Typography misuse

- 93 hardcoded `fontSize:` literals in `TextStyle` across presentation.
- `fontFamily` literals bypassing `AppTypography`:
  - `lib/presentation/screens/reports/reports_hub_screen.dart:59,66,73,533` — `TextStyle(fontFamily: 'JameelNooriNastaleeq')` (no fallback chain, no line-height guard → clipping risk).
  - `lib/presentation/shell/app_nav_rail.dart:269` — same literal.
  - `lib/presentation/screens/common/notifications_screen.dart:208,220` — conditional `fontFamily: _isUrdu ? 'JameelNooriNastaleeq' : null` with manual bold overrides; line 232 sets `fontFamily: null` (falls to theme Naskh — inconsistent within one list tile).
  - `lib/presentation/screens/crash_screen.dart:127`, `lib/presentation/screens/master_admin/modules_screen.dart:127`, `platform_users_screen.dart:335` — `fontFamily: 'monospace'`.
- `lib/providers/tenant_branding_provider.dart:71,100` — tenant branding fontFamily plumbing (by design, but another font path to audit).

### 5.5 Spacing violations

- Hard `EdgeInsets` literals everywhere instead of `M360Spacing`; e.g. `fee_management_screen.dart:641` (`all(10)`), `:1197,1373` (`all(20)`); `stat_card.dart:37` (`all(16)`), `:49` (`all(12)`).
- `SizedBox(width: 8/12)` / `height: 4` literals instead of spacing tokens (e.g. `stat_card.dart:55,72`).

### 5.6 Shadows / gradients / decoration

- 42 `boxShadow` usages in presentation (mission: avoid excessive shadows).
- 17 `LinearGradient` usages in presentation (mission: avoid excessive gradients) — plus the per-role gradient system in `role_config.dart`.
- `M360EmptyState`/`M360ErrorState` themselves are shadow-free; the product is not.

### 5.7 Dialogs / feedback — no system component

- 73 `showDialog`/`AlertDialog` and 126 `SnackBar(` / 68 `ScaffoldMessenger` — **all ad hoc**. The m360_\* system has **no dialog, no snackbar/toast, no confirmation-dialog** component. This is the largest component gap.
- `M360TextField` covers text inputs; there is **no m360 dropdown/select, radio, checkbox, switch, date-picker, or search-field** component (a `SearchField` exists only in `app_widgets.dart:232`).

### 5.8 Tables

- `M360ResponsiveTable` (sortable, RTL `Directionality`, mobile card fallback, `M360EmptyState` on empty): 0 usages. Screens hand-roll `DataTable` (e.g. `student_list_screen.dart:402`).
- Gaps vs mission: no pagination, no bulk-action/selection support, no column filters in `M360ResponsiveTable`.
- Minor: card-fallback actions use `Align(alignment: Alignment.centerLeft)` (`m360_table.dart:398`) — works in RTL (inline-end) but is direction-fragile; prefer `AlignmentDirectional.centerEnd`.

---

## 6. RTL audit

- ✅ **App-level RTL is forced**: `lib/main.dart:253-259` wraps the app in `Directionality(textDirection: TextDirection.rtl)`; `supportedLocales` lists `ur_PK` first.
- ✅ `M360ResponsiveTable` wraps its table in explicit RTL `Directionality` (`m360_table.dart:196`); all m360_\* text sets `textDirection: TextDirection.rtl` explicitly.
- ✅ `M360TextField` is RTL-native (`textDirection: rtl`, `textAlign: right`, `hintTextDirection: rtl`) — `m360_inputs.dart:160-166`.
- ✅ `M360StatCard` uses `CrossAxisAlignment.start` (direction-aware); dashboard `StatCard` `Row` lays out icon-first = right side in RTL, matching the reference image.
- ⚠️ Explicit `TextDirection.ltr` overrides (mostly legitimate — Latin technical content):
  - `lib/core/sync/conflict_review_screen.dart:144,222` — diff/data views.
  - `lib/presentation/screens/admin/user_management_screen.dart:281` — likely email/ID.
  - `lib/presentation/screens/auth/no_access_screen.dart:70` — email display next to `mohtamim@madrassa.com`.
  - `lib/presentation/screens/common/profile_screen.dart:497,511` — contact fields.
  - `lib/presentation/screens/crash_screen.dart:130` — monospace stack trace.
  - **Recommendation:** keep, but centralize into a documented `M360LatinText`/`LtrText` helper so the intent is explicit.
- ⚠️ `app_nav_rail.dart:94` wraps the rail in `Directionality` — redundant given the app-level forcing, but harmless.
- ❌ **No RTL issue found in tables/forms/navigation themselves** — the risk is not broken RTL but *bypassed* RTL: hardcoded `EdgeInsets.only(left:/right:)` (non-directional) would break mirroring; a full grep for those is recommended in implementation phase.

---

## 7. Loading / empty / error states

- `M360EmptyState` / `M360LoadingState` (skeleton shimmer) / `M360ErrorState`: **0 usages**.
- Legacy state widgets exist but are inconsistently used: `EmptyStateWidget`, `ErrorStateWidget`, `LoadingStateWidget` (`core/widgets/empty_state_widget.dart`), `LoadingWidget`, `ShimmerLoading`, `ListShimmerLoading` (`core/widgets/loading_widget.dart`), plus `EmptyState` (`app_widgets.dart:164`).
- **Screens with poor/missing empty states** (bare `Text('کوئی …')`, no icon, no action):
  - `lib/presentation/screens/admin/darja_screen.dart:70,252`
  - `lib/presentation/screens/admin/finance_screen.dart:92`
  - `lib/presentation/screens/admin/library_screen.dart:158,332`
  - `lib/presentation/screens/admin/user_management_screen.dart:192,491`
  - `lib/presentation/screens/common/announcements_screen.dart:67`
- 69 ad-hoc `CircularProgressIndicator` in presentation (full-screen spinners, not skeletons).
- `no_access_screen.dart` and `crash_screen.dart` hand-roll their own error layouts (acceptable as special cases, but they duplicate `M360ErrorState`'s pattern).

---

## 8. Keep / refactor / replace verdicts

| File | Verdict | Reason |
|---|---|---|
| `design_tokens.dart` | **KEEP** | Clean, complete, matches mission spec (spacing 4–48, radius 8/12/16/24/pill, elevation, motion, breakpoints, 48px touch target). Only fix: dedupe `M360Brand.gold` vs `AppColors.gold`. |
| `m360_buttons.dart` | **REFACTOR** | Solid a11y (48px, Semantics, tooltips) and correct orange primary; fix stale "filled teal" docstring (`:18`); add missing tertiary/text variant and dropdown-adjacent needs before migration. |
| `m360_cards.dart` | **REFACTOR** | `M360Card`/`M360TappableCard`/`M360SectionHeader` are good; `M360StatCard` is vertical while the product standardized on the horizontal stat card — unify the 3 `StatCard` implementations into one horizontal component. |
| `m360_badges.dart` | **KEEP** | Best-in-repo contrast strategy (darkened foreground on tint, no new literals); 8 canonical kinds cover attendance/fee/active/suspended. |
| `m360_inputs.dart` | **KEEP** | RTL-native field with correct Nastaleeq-label/Naskh-input policy; needs only adoption. |
| `m360_states.dart` | **KEEP** | Good empty/loading-shimmer/error trio with Urdu copy; consider adding a card-grid skeleton variant. |
| `m360_table.dart` | **REFACTOR** | Good responsive table→card fallback and RTL handling; add pagination + bulk selection (mission §21) and replace `Alignment.centerLeft` with `AlignmentDirectional.centerEnd` before rollout. |
| `responsive.dart` | **KEEP** | Clean breakpoint helpers; needs only adoption (screens currently hand-roll `MediaQuery`). |

### System-level recommendations (for the plan phase)

1. **Add a barrel export** (`lib/core/design/m360.dart`) — the system is currently undiscoverable.
2. **Consolidate 4 systems → 1**: migrate `core/widgets/*`, `app_widgets.dart`, and `dashboard/` widgets onto m360_\*; delete the duplicates (`LoadingOverlay` ×2, `StatCard` ×3).
3. **Fill component gaps before migration**: dialog/confirmation, snackbar/toast, dropdown/select, search field, app bar — the 73 dialogs and 126 snackbars prove demand.
4. **Purge palette violators**: `app_nav_rail.dart:271` (`#009688`), `role_config.dart` rainbow gradients, all `Colors.red/green/grey/amber` literals → `AppColors` tokens.
5. **Reconcile card defaults**: `AppTheme.cardTheme` (margin 8) vs `M360Card` (margin 0) — pick one.
6. **Adopt `M360ResponsiveTable`** as the single table path; extend with pagination/bulk actions.
7. **Adopt `M360EmptyState`** on the 6+ screens currently showing bare "کوئی …" text.
