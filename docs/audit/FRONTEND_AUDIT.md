# Madrassa-360 Frontend Audit — Production Readiness

- **Repo:** `~/workspace/madrassa-redesign-fix`, branch `redesign/ux-v2`, HEAD `90b41e59`
- **Date:** 2026-10-01
- **Auditor:** Frontend Auditor subagent (read-only)
- **Scope:** 262 Dart files under `lib/`

## Summary counts

| Severity | Count |
|----------|-------|
| Blocker  | 0 |
| Major    | 2 |
| Minor    | 28 |
| Clean (verified, no finding) | see notes below |

**Headline:** No blockers. No dead buttons, no "coming soon" placeholders, no fake data, no missing loading/error branches in async UI, no hardcoded widths > 340px, and the Nastaleeq font system is coherent (theme-level default + `AppTypography`, height ≥ 2.0 everywhere except one nav-label spot). The bulk of findings are **dead legacy code** (pre-shell `*_main_screen.dart` trees and duplicated widget helpers) and **lint-level** design-token/a11y items.

## Findings

### 1. Dead buttons
No findings. Verified: zero `onPressed: null` / `onTap: null`; zero empty `() {}` / `() => {}` callbacks; zero TODO/FIXME inside callbacks; zero snackbars saying "not implemented". Busy-gated `onPressed: _busy ? null : _save` patterns are legitimate.

### 2. "Coming Soon" / placeholder text / fake data
No findings. The only matches are code comments ("never a جلد آرہا ہے placeholder"). `'بعد میں / Later'` in `lib/core/update/update_service.dart:300` is a legitimate update-dialog dismiss action. No mock/fake/dummy data in UI paths.

### 3. Loading / error / empty states
No findings. Programmatically checked all 25 `.when(` call sites — every one has `data:`, `loading:`, and `error:` branches (one apparent miss at `exam_wizard_screen.dart:681` was a false positive: the branches sit ~95 lines down). All 21 `FutureBuilder`/`StreamBuilder` sites degrade gracefully. Empty-data is handled (e.g. exam wizard `_EmptyNote`, `M360EmptyState` everywhere).

### 4. Font audit (Urdu-first)
`lib/presentation/screens/master_admin/master_admin_nav.dart:268` — minor — Urdu label 'پلیٹ فارم کنسول' (19sp) uses `height: 1.6`, below the repo's own ≥ 2.0 Nastaleeq policy; nuqta-clipping risk in the tight nav header.

Clean: `app_theme.dart` sets the global default `fontFamily` to `JameelNooriNastaleeq`; every `AppTypography` style carries height 2.0–2.2 with Naskh fallback; inputs/hints/buttons all Nastaleeq. `fontFamily: 'monospace'` appears only for Latin technical strings (user IDs, module keys, crash details) — correct. Stat-card value text at `m360_cards.dart:219` (`height: 1.4`) renders only numeric strings at all call sites — no Urdu clipping risk.

### 5. Responsive (360px)
`lib/presentation/screens/teacher/attendance_screen.dart:328` — minor — `Text(classes.first.name)` in a `Row` with no `Flexible`/`Expanded`/`overflow`; a long class name can overflow at 360px.
`lib/presentation/widgets/common/app_widgets.dart:401` — minor — section-header `Row`: title `Text` has no `Expanded`/ellipsis next to the action button; long titles can squeeze the action.

Clean: no hardcoded widths > 340 anywhere; all dialogs go through `M360Dialog` (maxWidth constraints, safe at 360px) or raw `AlertDialog` with `SingleChildScrollView` content; all FilterChip/ChoiceChip strips sit in horizontal `SingleChildScrollView`s; both wizard bodies scroll inside `Expanded`.

### 6. Navigation
Clean. Only named route is `/master` (MasterAdminGuard → MasterAdminShell, fails closed). All 63 `Navigator.push` targets resolve to existing classes; no `planned: true` destinations; `ShellPageBody` restores the back chevron whenever the route `canPop` (announcements/notifications/reports screens pushed directly still get back). `tenant_picker_screen.dart:77` deliberately disables the leading back (it's the post-login root; logout is the action) — correct.

### 7. Dead code
`lib/presentation/screens/teacher/teacher_dashboard_screen.dart:15` — major — dead legacy teacher dashboard, imported only by the dead `main_screen.dart`, AND it declares `class TeacherDashboardScreen` — the same class name as the live `lib/presentation/screens/dashboards/teacher_dashboard.dart:37`. A wrong import silently builds the dead dashboard.
`lib/presentation/screens/parent/parent_dashboard_screen.dart:21` — minor — dead island; only referenced by dead `parent_main_screen.dart`.
`lib/presentation/screens/super_admin/madrasa_management_screen.dart:21` — minor — dead island; only referenced by dead super-admin shell files (live master-admin console has its own `madrasa_list_screen.dart`).
`lib/presentation/screens/super_admin/super_admin_dashboard_screen.dart:22` — minor — dead island; only referenced by dead `super_admin_main_screen.dart`.
`lib/presentation/screens/main_screen.dart:17` — minor — legacy teacher tab shell (`MainScreen`), zero references.
`lib/presentation/screens/admin/admin_main_screen.dart:15` — minor — legacy admin tab shell, zero references.
`lib/presentation/screens/parent/parent_main_screen.dart:15` — minor — legacy parent tab shell, zero references.
`lib/presentation/screens/super_admin/super_admin_main_screen.dart:15` — minor — legacy super-admin shell, zero references.
`lib/core/widgets/loading_overlay.dart:6` — minor — duplicate `LoadingOverlay`, unused; the live one is `lib/core/widgets/loading_widget.dart:49` (used by login + forgot-password).
`lib/presentation/widgets/common/app_widgets.dart:496` — minor — a THIRD `LoadingOverlay` class, unused.
`lib/core/widgets/confirm_dialog.dart:10` — minor — `showConfirmDialog` never called (design system's `showM360ConfirmDialog` is used instead).
`lib/core/widgets/custom_buttons.dart:8` — minor — `PrimaryButton`/`SecondaryButton`/`IconButtonWidget` never used (design system's `M360PrimaryButton` etc. are used instead).

### 8. Design-system violations (hardcoded colors outside `lib/core/`)
`lib/presentation/screens/crash_screen.dart:45` — minor — `const emerald = Color(0xFF0B6E4F)` (duplicates `AppColors.primary`-adjacent token).
`lib/presentation/screens/crash_screen.dart:46` — minor — `const gold = Color(0xFFD4AF37)` (duplicates the gold token used in `app_nav_rail.dart`).
`lib/presentation/screens/crash_screen.dart:52` — minor — `backgroundColor: const Color(0xFFF6F8F7)` instead of `AppColors.background`.
`lib/presentation/shell/app_nav_rail.dart:30` — minor — `const Color _kGold = Color(0xFFC9A227)` local gold constant (third gold hex in the codebase).
`lib/presentation/screens/settings/madrassa_logo_screen.dart:312` — minor — `color: Color(0x52000000)` scrim literal.
`lib/providers/tenant_branding_provider.dart:75` — minor — hardcoded fallback brand colors (`0xFF0E7C5B`, `0xFF14532D`, `0xFFF59E0B` at lines 75–77, 102–106) instead of referencing `AppColors`.

### 9. Silent error swallowing
`lib/providers/madrasa_provider.dart:97` — minor — `update()` wraps the Supabase write in `catch (_) {}` and returns `null` (success) while optimistically updating local state: a failed write shows as succeeded with divergent local state. (Currently only reachable via the dead super-admin screens, hence minor; becomes major if the provider is reused.)
`lib/providers/madrasa_provider.dart:113` — minor — same false-success pattern in `delete()`.
`lib/data/repositories/finance_repository.dart:561` — minor — best-effort notification `catch (_) {}` with no logging (failure invisible in diagnostics; commented as intentional).
`lib/data/repositories/finance_repository.dart:643` — minor — same pattern for payment notifications.
`lib/providers/announcement_provider.dart:129` — minor — best-effort notification `catch (_) {}` with no logging.

### 10. Accessibility basics
All `IconButton`s carry tooltips — clean. Images without `semanticLabel` (minor, mostly decorative logos; the user-photo ones could take labels):
`lib/presentation/screens/auth/login_screen.dart:213` — minor — app logo `Image.asset` without `semanticLabel`.
`lib/presentation/screens/auth/tenant_picker_screen.dart:132` — minor — app logo `Image.asset` without `semanticLabel`.
`lib/presentation/shell/app_nav_rail.dart:269` — minor — logo `Image.asset` without `semanticLabel`.
`lib/presentation/shell/app_nav_rail.dart:580` — minor — logo `Image.asset` without `semanticLabel`.
`lib/presentation/shell/app_nav_rail.dart:250` — minor — tenant logo `Image.network` without `semanticLabel`.
`lib/presentation/screens/master_admin/master_admin_nav.dart:248` — minor — logo `Image.asset` without `semanticLabel`.
`lib/presentation/screens/master_admin/master_admin_nav.dart:491` — minor — logo `Image.asset` without `semanticLabel`.
`lib/presentation/screens/common/profile_screen.dart:320` — minor — user photo `Image.file` without `semanticLabel`.
`lib/presentation/screens/master_admin/console_profile_screen.dart:127` — minor — user photo `Image.file` without `semanticLabel`.
`lib/presentation/screens/settings/madrassa_logo_screen.dart:73` — minor — logo preview `Image.file` without `semanticLabel`.

## Method notes
- Every `FILE:LINE` above was read directly (grep + `sed -n` spot-checks); `.when()` branch completeness was verified programmatically across all 25 call sites; import graphs were checked by filename, class-name, and path-import matching across `lib/` and `test/`.
- Out of scope per task: test files, `supabase/` migrations, English-vs-Urdu copy completeness.
