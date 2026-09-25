# Madrasa 360 — UI/UX + Localization Audit

**Date:** 2026-09-25 · **Scope:** presentation layer only (`lib/presentation/**`, `lib/core/theme/`, `lib/core/widgets/`, `lib/core/constants/`, `lib/core/config/`, `lib/main.dart`, fonts/pubspec)
**Method:** full read of theme/config/widgets + 23 screens; every claim cites `file:line` with the exact string/widget.

---

## 1. Executive summary

- **Bottom nav everywhere, no drawer, no sidebar, no named routes.** Three separate hand-rolled `InkWell`-row bottom bars (`main_screen.dart`, `admin_main_screen.dart`, `parent_main_screen.dart`) plus one Material 3 `NavigationBar` in `super_admin_main_screen.dart`. `AppDrawer` (`presentation/widgets/app_drawer.dart:15`) is defined but **used zero times**. All navigation is imperative `Navigator.push(MaterialPageRoute(...))` — no route table, no deep links.
- **Brand name is dynamic (✓), brand logo and colors are not (✗).** The name flows from `MadrassaConfig.nameUrdu` → `AppConfig.appName` → login/about/result screens. But there is **no logo asset** (`AppConfig.logoImage` points to a non-existent `assets/images/logo.png`), colors are hard-coded static consts in `app_colors.dart`, and `"Developed by HijaziApps"` / `"HijaziApps Production"` are hard-coded vendor strings in user-visible UI (`login_screen.dart:386`, `profile_screen.dart:149`, `about_screen.dart:17`).
- **There is no real l10n — it's an Urdu-only app with an `AppStrings` veneer.** 0 `.arb` files, 0 `AppLocalizations`, `locale` is hard-pinned to `Locale('ur','PK')` (`main.dart:86`) and RTL is force-wrapped globally (`main.dart:98-101`). `AppStrings` defines 67 keys but is referenced at only ~27 sites; **~157 inline `Text('...')` literals** live directly in screens, and the only English support in the entire app is a local toggle inside `AboutScreen`. Mission requires Urdu/English/Arabic switching — this is ~1% of that.
- **Dashboards range from genuinely good to static mock.** Admin dashboard (`admin_dashboard_screen.dart`) and super-admin dashboard are permission-aware and provider-backed (grade B) but ship **hard-coded demo data** (`todayPresent: 142`, fake activity feed, hard-coded `'3,80,000'` fee figures). Teacher and parent dashboards are fully static placeholders with invented names/numbers (`teacher_dashboard_screen.dart:112 '25'`, `parent_dashboard_screen.dart:105 'محمد احمد'`) — grade D. One module card on the admin dashboard pushes `const Placeholder()` (`admin_dashboard_screen.dart:388`) — a dead tap.
- **Desktop/Windows is structurally unsupported today.** `main.dart:42-45` locks orientation to portrait only; zero `LayoutBuilder`/`isDesktop`/`NavigationRail` usage in any screen (`responsive.dart` ships a full breakpoint toolkit that nothing uses); grids are fixed `crossAxisCount: 2` everywhere. "Windows desktop first-class" would need the nav-shell rework.

---

## 2. Screen inventory

| # | Screen | Role | File | Nav type | Grade |
|---|--------|------|------|----------|-------|
| 1 | Login | auth | `presentation/screens/auth/login_screen.dart` | entry screen (no nav) | **B+** — polished: animated entry, gradient header, form validation via `Validators`, `LoadingOverlay`, brand name from config |
| 2 | MainScreen | teacher (legacy) / student fallback | `presentation/screens/main_screen.dart` | hand-rolled bottom bar (InkWell row, 4 tabs) | **C+** — duplicates `AdminMainScreen` nav logic; kept only as `student:`/`default:` fallback in login router |
| 3 | AdminMainScreen | 11 staff roles | `presentation/screens/admin/admin_main_screen.dart` | permission-driven bottom bar (`buildNavTabs`), IndexedStack | **B** — best gating: tabs built from `userPermissionsProvider` (`role_config.dart`) |
| 4 | AdminDashboardScreen | staff | `presentation/screens/admin/admin_dashboard_screen.dart` | dashboard (pushed module screens) | **B** — permission-filtered stats/modules, role-aware gradient header; **docked points for hard-coded demo data** (§6) |
| 5 | StudentListScreen | staff | `presentation/screens/admin/student_list_screen.dart` | tab in AdminMain | **B-** — search + EmptyState + add/edit dialogs; inline per-field validators instead of `Validators` helper |
| 6 | StaffListScreen | staff | `presentation/screens/admin/staff_list_screen.dart` | tab in AdminMain | **B-** — same pattern as student list |
| 7 | FeeManagementScreen | staff | `presentation/screens/admin/fee_management_screen.dart` | tab in AdminMain | **B-** — loading/empty/error branches present; error branch is bare text, no retry (`fee_management_screen.dart:76-81`) |
| 8 | FinanceScreen | staff | `presentation/screens/admin/finance_screen.dart` | module push | **B-** — income/expense dialogs, summary tiles |
| 9 | LibraryScreen | staff | `presentation/screens/admin/library_screen.dart` | module push | **B-** — issue/return dialogs |
| 10 | DarjaScreen | staff | `presentation/screens/admin/darja_screen.dart` | module push | **C+** — add/edit/delete dialogs; per-field `textDirection` set manually |
| 11 | UserManagementScreen | staff | `presentation/screens/admin/user_management_screen.dart` | module push / tab | **B** — proper delete-confirmation dialogs (`user_management_screen.dart:408`, `:766`) |
| 12 | TeacherDashboardScreen | teacher | `presentation/screens/teacher/teacher_dashboard_screen.dart` | tab in MainScreen | **D** — header comment says "Placeholder for Phase 1"; stats `'25'`/`'23'`/`'3'` and 3 fake schedule rows hard-coded |
| 13 | AttendanceScreen | teacher/staff | `presentation/screens/teacher/attendance_screen.dart` | tab / module | **B+** — live `attendanceProvider`, "management by exception" (all present by default), reset tooltip, save FAB |
| 14 | ResultsScreen | teacher/staff | `presentation/screens/teacher/results_screen.dart` | tab / module | **B-** — provider-backed, EmptyState used; result card shows `AppConfig.appName` (`results_screen.dart:342`) |
| 15 | ParentMainScreen | parent | `presentation/screens/parent/parent_main_screen.dart` | hand-rolled bottom bar (3 tabs) | **C+** — third copy of the same custom bottom-bar pattern |
| 16 | ParentDashboardScreen | parent | `presentation/screens/parent/parent_dashboard_screen.dart` | tab in ParentMain | **D** — entirely static: child `'محمد احمد'`, `'حاضری 95%'`, fake timeline, fake exam dates (`parent_dashboard_screen.dart:105-160`) |
| 17 | FeeHistoryScreen | parent | `presentation/screens/parent/fee_history_screen.dart` | tab in ParentMain | **C+** — Riverpod `loading:`/`error:` handled, EmptyState used |
| 18 | SuperAdminMainScreen | super_admin | `presentation/screens/super_admin/super_admin_main_screen.dart` | **Material 3 NavigationBar** (4 tabs) | **B** — the only M3-standard nav; inline Urdu labels instead of `AppStrings` |
| 19 | SuperAdminDashboardScreen | super_admin | `presentation/screens/super_admin/super_admin_dashboard_screen.dart` | tab in SuperAdminMain | **B** — live `madrasaProvider` data, loading + empty states with CTA (`super_admin_dashboard_screen.dart:141-163`) |
| 20 | MadrasaManagementScreen | super_admin | `presentation/screens/super_admin/madrasa_management_screen.dart` | tab in SuperAdminMain | **B-** — multi-tenant CRUD exists here (provider-backed) |
| 21 | ProfileScreen | common | `presentation/screens/common/profile_screen.dart` | tab / push | **C** — info rows fine; hard-coded `'Developed by HijaziApps'` footer (`profile_screen.dart:149`) |
| 22 | AnnouncementsScreen | common | `presentation/screens/common/announcements_screen.dart` | module push | **C+** — provider list, add dialog |
| 23 | AboutScreen | common | `presentation/screens/common/about_screen.dart` | tab in SuperAdminMain | **B** — SliverAppBar, **Urdu/English toggle (only screen with one)**, reads `AppConfig`/`MadrassaConfig`; dev contact constants hard-coded |

**Role gating in UI:** `login_screen.dart:112-145` routes by `UserRole` → 4 shells (SuperAdmin / AdminMain / ParentMain / MainScreen fallback). Inside `AdminMainScreen`, tabs are built from the permission set (`admin_main_screen.dart:36-44` → `buildNavTabs` in `role_config.dart:150-238`, capped at 5). Dashboard modules/stats/cards are individually permission-filtered (`admin_dashboard_screen.dart:192-262`). This part is genuinely well done.

---

## 3. Branding hard-code inventory (UI-layer)

What IS dynamic (single source of truth, works):

| Usage | File:line |
|---|---|
| App/institution name on login header | `login_screen.dart:202` → `AppStrings.appName` → `AppConfig.appName` → `MadrassaConfig.nameUrdu` (`'خواجہ ایجوکیشنل سسٹم'`) |
| App name + version in About | `about_screen.dart:96,100,225,229` → `AppConfig.appName`, `'v${MadrassaConfig.appVersion}'` |
| Institution + city (Urdu/English per toggle) in About | `about_screen.dart:234-241` → `MadrassaConfig.nameUrdu/nameEnglish/cityUrdu/cityEnglish` |
| Institution name on result card | `results_screen.dart:342` → `AppConfig.appName` |
| `MaterialApp.title` | `main.dart:72` → `AppStrings.appName` |

What is hard-coded in user-visible UI:

| String | File:line | Notes |
|---|---|---|
| `'Developed by HijaziApps'` | `auth/login_screen.dart:386` (footer) | English, vendor brand, not tenant-configurable |
| `'Developed by HijaziApps'` | `common/profile_screen.dart:149` (footer) | same, duplicated |
| `const _production = 'HijaziApps Production'` | `common/about_screen.dart:17` | shown in Developer Credentials card + footer |
| `const _devName = 'Muhammad Talha Farid'` | `common/about_screen.dart:15` | hard-coded person; fine for a dev-credit screen, but it's a const, not config |
| `const _devEmail = 'goharenaqshband@gmail.com'` | `common/about_screen.dart:16` | hard-coded |
| `const _devPhone = '03287819000'` | `common/about_screen.dart:16` | hard-coded |
| `'January 2026'` (Released date) | `common/about_screen.dart:249` | hard-coded English date |
| Stale brand in doc comments only (not user-visible): `/// المرکز الاسلامی قصور` | `core/constants/app_colors.dart:3-4`, `app_strings.dart:1-2`, `app_typography.dart:4`, `core/theme/app_theme.dart:5` | comments; harmless but confusing next to `MadrassaConfig` |
| Stale brand in metadata: `name: al_markaz_al_islami`, `description: "Al Markaz al Islami Kasur - ..."` | `pubspec.yaml:1-2` | ships in build metadata |

What is **missing** (mission §37-39 requires dynamic tenant branding):

- **No logo mechanism.** `AppConfig.logoImage = 'assets/images/logo.png'` (`app_config.dart:102`) but `assets/images/` does not exist; zero `Image.asset` calls in `lib/`. Login shows a generic `Icons.mosque` (`login_screen.dart:175-181`); About shows a mosque icon (`about_screen.dart:80-88`). A new tenant cannot set a logo without editing code.
- **No dynamic colors.** `AppColors` is all `static const` (`app_colors.dart:9-10`: `primary = Color(0xFF009688)` "Islamic Teal"); nothing reads color from tenant config. Per-tenant theming requires a code change.
- Role gradients in `role_config.dart` are hard-coded hex per role — fine as design tokens, but they bypass the tenant palette.

---

## 4. Localization verdict

**Verdict: Urdu-only app with a strings file, not a localized app. No l10n infrastructure.**

| Measure | Value | Evidence |
|---|---|---|
| `.arb` / `l10n/` files | **0** | `find` returned none |
| `AppLocalizations` / intl codegen references | **0** | grep count 0 |
| Keys defined in `AppStrings` | **67** | `static const String` count in `core/constants/app_strings.dart` |
| `AppStrings.x` usage sites (screens) | **~27** | grep; e.g. dashboards use `AppStrings.dashboard` but most labels are inline |
| Inline user-visible `Text('...')` literals in `lib/presentation` | **~157** | regex count of `Text('literal')`; total `Text(` usages 459 |
| Screens with any English UI | **1 of 23** | only `AboutScreen` (`about_screen.dart:116-141` `_LanguageToggle`) |
| Runtime locale switching | **none** | `locale: const Locale('ur','PK')` hard-pinned, `main.dart:86`; `supportedLocales` lists en_US but it can never be selected |
| Arabic support | **none** | no ar locale, no Arabic strings anywhere |

Additional notes:
- `flutter_localizations` + `intl` are in pubspec but only provide Material widget translations (date pickers etc.); app content strings bypass the intl pipeline entirely.
- English support is a one-off: `AboutScreen` carries its own `_isUrdu` bool and duplicate `_descUrdu`/`_descEnglish` paragraphs plus per-label ternaries (`about_screen.dart:163-260`) — this pattern was not extended anywhere else.
- Mixed-language debt: `'Developed by HijaziApps'` footers, `'v1.0.0'`, `'January 2026'`, dev email/phone are English/Latin inside an otherwise Urdu UI with no directionality handling (see §5).

---

## 5. RTL audit

- **Global force-RTL: correct for the Urdu-only reality.** `main.dart:98-101` wraps the app in `Directionality(textDirection: TextDirection.rtl)` and pins `locale: Locale('ur','PK')` (`main.dart:86`). Urdu text renders RTL throughout; the header comment claims "RTL (Right-to-Left) Support for Urdu" — accurate as far as it goes.
- **Per-field direction overrides exist where needed:** `darja_screen.dart:170,275`, `finance_screen.dart:183`, `library_screen.dart:138,264`, `announcements_screen.dart:174`, `madrasa_management_screen.dart:63,309` set `textDirection: TextDirection.rtl` on fields; `profile_screen.dart:367,380` and `user_management_screen.dart:266` set `.ltr` (phone/email inputs) — good practice, correct.
- **Gaps:** English/Latin content under forced RTL has no isolation: `'Developed by HijaziApps'` footers (`login_screen.dart:386`, `profile_screen.dart:149`), the dev email `_devEmail` row in About, and `'v1.0.0'` version strings render inside RTL paragraphs — Latin runs will display but can mis-order around adjacent Urdu/punctuation (e.g. `'+92 $_devPhone'` in `about_screen.dart:204`). No `Directionality`/`Text` with explicit handling around these.
- RTL is **forced, not adaptive**: because direction is hard-wrapped rather than derived from locale, the "English mode" the mission wants would require removing the `builder` override in `main.dart:96-102` and switching to locale-driven direction.

---

## 6. Font audit — Jameel Noori Nastaleeq

**Bundled and declared: YES. Applied consistently: mostly, with leaks.**

| Check | Evidence |
|---|---|
| TTF files present | `assets/Jameel Noori Nastaleeq Regular - [UrduFonts.com].ttf`, `... Kasheeda - [UrduFonts.com].ttf` |
| Declared in pubspec | `pubspec.yaml` fonts section: `family: JameelNooriNastaleeq`, weights 400/700 mapped to the two files |
| Base style | `app_typography.dart:10-13`: `fontFamily: 'JameelNooriNastaleeq'`, `fontFamilyFallback: ['NotoNastaliqUrdu']`, generous `height: 1.6-2.0` for Nastaliq line spacing |
| Wired into Material theme | `app_theme.dart:151-166`: full `textTheme` mapped from `AppTypography`; `appBarTitle`, `inputDecorationTheme`, `bottomNavigationBarTheme`, `snackBarTheme` all reference it |

Leaks and issues:
- **`fontFamilyFallback: ['NotoNastaliqUrdu']` is dead.** The font is not bundled and `google_fonts` (in pubspec) is **never imported anywhere in `lib/`** — if a glyph is missing from Jameel Noori, the fallback silently fails to system font.
- **`PrimaryButton` bypasses the typography system**: `custom_buttons.dart:58-62` uses a raw `const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)` — buttons would not render in Nastaleeq even if the widget were used (it isn't — see §10).
- **Nastaleeq is applied to everything, including Latin digits.** Fee figures like `'3,80,000'` (`admin_dashboard_screen.dart`), phone numbers, and `'January 2026'` all render in the Nastaleeq family. Mission says "Jameel Noori Nastaleeq preserved" for Urdu — consider a Latin/digit font pairing for numbers to avoid odd glyph rendering.
- `main.dart`'s own doc comment says "Noto Nastaliq Urdu Font" — stale; the actual font is Jameel Noori.

---

## 7. Responsive audit — desktop/Windows

**Verdict: one stretched mobile layout. Windows is not first-class today.**

| Check | Evidence |
|---|---|
| Breakpoint/layout widgets in screens | **0** — no `LayoutBuilder`, no `NavigationRail`, no drawer in any of 23 screens |
| `responsive.dart` toolkit usage | **0** — `isMobile/isTablet/isDesktop`, `ResponsiveGrid`, `ResponsiveLayout`, `ResponsiveBuilder` are defined (`core/utils/responsive.dart`) and **never used** in `lib/presentation` |
| Grid columns | fixed `crossAxisCount: 2` in both dashboards (`admin_dashboard_screen.dart:361`, `super_admin_dashboard_screen.dart:93`) — a 1920px Windows window gets the same 2-column phone grid |
| Nav adaptation | none — bottom bars on all widths; no sidebar/rail ≥900px |
| Orientation | `main.dart:42-45`: `SystemChrome.setPreferredOrientations([portraitUp, portraitDown])` — **explicitly locks out landscape/desktop window shapes**; directly contradicts "Windows desktop first-class" |
| What exists (unused) | `ResponsiveGrid.crossAxisCount(context, mobile:2, tablet:3, desktop:4)`, `Breakpoints`, `ResponsiveLayout(mobile/tablet/desktop)` — a complete, tested-looking toolkit with zero call sites |

Net: the responsive story is "infrastructure written, integration not started."

---

## 8. States audit (loading / empty / error)

| State | Coverage | Evidence |
|---|---|---|
| Loading spinners | **Universal** — 18 `CircularProgressIndicator` sites across screens | e.g. `student_list_screen.dart:51`, `attendance_screen.dart:51`, `fee_management_screen.dart:75`; `LoadingOverlay` (`app_widgets.dart:474`) used on login (`login_screen.dart:116`) and 1 other site |
| Shimmer/skeleton | **Built, never used** — `ShimmerLoading` + `ListShimmerLoading` defined in `core/widgets/loading_widget.dart:140-243`; **0 usages** in `lib/presentation` |
| Empty states | **Good where wired** — shared `EmptyState` (`app_widgets.dart:165`) used in 5 screens: `fee_management_screen.dart:226`, `staff_list_screen.dart:201`, `student_list_screen.dart:203`, `fee_history_screen.dart:164`, `results_screen.dart:86`; super-admin dashboard has a custom inline empty state with CTA (`super_admin_dashboard_screen.dart:146-163`) |
| Error states | **Inconsistent, no retry** — `fee_management_screen.dart:76-81`: `hasError` → bare `Text('فیس لوڈ کرنے میں خطا')`, no retry button; `ErrorStateWidget` exists in `core/widgets/empty_state_widget.dart` but is **never used**; `ErrorHandler.showErrorSnackBar` used on login failures |
| Try/catch in UI | 2 files (`student_list_screen.dart`, `staff_list_screen.dart`) | most screens rely on provider-level error propagation |
| Success feedback | SnackBars on save (`attendance_screen.dart:240`, `user_management_screen.dart:425`) | adequate |

---

## 9. Widget reuse audit

**Shared widgets that ARE used (good):** `AppCard`, `StatCard`, `EmptyState`, `SearchField`, `StatusBadge` (+ factories `StatusBadge.present()/absent()/leave()/paid()/pending()/pastDue()`), `SectionHeader`, `InfoTile`, `LoadingOverlay` — all in `presentation/widgets/common/app_widgets.dart`, used across dashboards and list screens.

**Dead widgets (defined, 0 usages):**

| Widget | File | Claim vs reality |
|---|---|---|
| `PrimaryButton` / `SecondaryButton` (+ IconButton) | `core/widgets/custom_buttons.dart` | IMPROVEMENTS.md §4 claims "Consistent styling across app" — **0 usages**; screens build `ElevatedButton` inline instead (e.g. `login_screen.dart:349-377`) |
| `EmptyStateWidget` / `ErrorStateWidget` / `LoadingStateWidget` | `core/widgets/empty_state_widget.dart` | IMPROVEMENTS.md §4 claims "Consistent user feedback" — **0 imports**; screens use the *different* `EmptyState` from `app_widgets.dart` — two parallel empty-state systems |
| `AppDrawer` | `presentation/widgets/app_drawer.dart:15` | "available for use in any role screen" — **0 usages**; nav is bottom-bar-only |

**Duplicated inline code (should be shared):**
- Stat-card builders: `_buildStatCard` re-implemented in both `teacher_dashboard_screen.dart:109-145` and `parent_dashboard_screen.dart:207-247` (instead of using shared `StatCard`).
- Bottom nav item builders: near-identical `_buildNavItem` InkWell/AnimatedContainer rows in `main_screen.dart:93-127`, `parent_main_screen.dart:93-127`, `admin_main_screen.dart:124-158`.
- Gradient welcome headers: re-implemented in `admin_dashboard_screen.dart:130-200`, `teacher_dashboard_screen.dart:63-108`, `parent_dashboard_screen.dart:70-137`.
- `super_admin_dashboard_screen.dart` defines its own private `_StatCard` (`:207-240`) — a third stat-card variant.

---

## 10. Forms, dialogs, confirmations

- **Login form: good.** `Form` + `GlobalKey`, `Validators.email` / `Validators.required` (`login_screen.dart:303,338`), password `obscureText`, inline-styled but consistent inputs.
- **CRUD dialogs (student/staff/darja/library/finance/fee): good structure, weak validation reuse.** Dialogs use `showDialog` + `AlertDialog` + `TextFormField` with **inline per-field validators** (e.g. `student_list_screen.dart:607-613`: `if (value == null || value.isEmpty) return 'نام درج کریں';`) — the `Validators` helper class exists but only login uses it. No shared form-field widget; each dialog re-declares `InputDecoration` by hand.
- **Destructive confirmations: good where they exist.** `user_management_screen.dart:408-431` ("صارف حذف کریں؟" with irreversible-warning copy + red confirm) and `:766-789` (role delete). Delete icon buttons elsewhere (darja/library/finance) — confirm presence not verified on all; spot-check recommended.
- **Attendance save has no confirmation** — FAB → direct `_saveAttendance` (`attendance_screen.dart:59,236`) with success SnackBar. Reasonable for the use case (with offline queue), acceptable.

---

## 11. Accessibility quick-pass

| Check | Result |
|---|---|
| `Semantics` widgets | **0 in presentation + core widgets** |
| Touch targets | bottom-nav items are `InkWell` rows with padding (`main_screen.dart:101-109`) — adequate; icon-only `IconButton`s (notifications, overflow menus) rely on default 48px |
| Tooltips | present on some icon buttons (`attendance_screen.dart:37` `'سب کو حاضر کریں'`, `about_screen.dart` copy buttons) — inconsistent |
| Contrast | white-on-teal gradient headers fine; `AppColors.textSecondary` on `background` for `bodySmall`/`labelSmall` — likely passes but unverified; `labelSmall` at **fontSize 10** (`app_typography.dart:77-82`) is below comfortable minimum for Urdu Nastaliq, which needs size to stay legible |
| Focus/keyboard | no `FocusNode` management, no focus traversal order — Windows keyboard navigation unaddressed |
| Text scaling | fixed font sizes everywhere; Nastaleq `height` multipliers are fixed — large system text settings may clip in fixed-height containers (e.g. `super_admin_dashboard_screen.dart` stat cards) |

---

## 12. Docs-vs-reality mismatches

| # | Doc claim | Reality | Location |
|---|---|---|---|
| 1 | README:1,22 — "Al Markaz al Islami Kasur" as the institution | Code rebranded to `MadrassaConfig` ('خواجہ ایجوکیشنل سسٹم'); README + pubspec still carry the old brand | `README.md:1,22`, `pubspec.yaml:1-2` |
| 2 | README:22 — "multi-tenant capabilities" | `MadrassaConfig` is a **static compile-time class** — one tenant per build, no runtime tenant switching. True multi-tenancy exists only partially via `MadrasaManagementScreen` data model (super-admin), not in the app shell/branding | `core/config/madrassa_config.dart`, `README.md:22` |
| 3 | README:57 — "Custom Google Fonts" | `google_fonts` in pubspec but **never imported** in `lib/`; typography is bundled TTF only | `README.md` features list, `pubspec.yaml` |
| 4 | README:180 — "Desktop: Windows 10/11…" platform support | `main.dart:42-45` locks to portrait; no desktop layout exists (§7) | `README.md:180` vs `lib/main.dart:42-45` |
| 5 | IMPROVEMENTS.md §4 — "Custom Buttons… Consistent styling across app" | `PrimaryButton` has **0 usages** | `IMPROVEMENTS.md:59-63` |
| 6 | IMPROVEMENTS.md §4 — "Empty/Error States… Consistent user feedback" | `empty_state_widget.dart` has **0 usages**; `ErrorStateWidget` never used | `IMPROVEMENTS.md:65-70` |
| 7 | `main.dart` doc comment — "Noto Nastaliq Urdu Font" | Actual font is **Jameel Noori Nastaleeq** | `lib/main.dart` header comment |
| 8 | `admin_dashboard_screen.dart:388` comment — "StaffListScreen imported in outer scope" | **False** — the 'عملہ' module pushes `const Placeholder()`; tapping it shows a blank placeholder. `staff_list_screen.dart` is not imported in that file | `admin_dashboard_screen.dart:381-389` |
| 9 | Hard-coded demo data presented as live | Admin dashboard: `'totalClasses': 8`, `'todayPresent': 142`, `'todayAbsent': 10`, `'monthlyTarget': 468000` (`admin_dashboard_screen.dart:53-62`); fee card figures `'3,80,000'`/`'45,000'`/`'4,68,000'` hard-coded even though `feeSummaryProvider` is watched (`admin_dashboard_screen.dart:519-541`); `_activities` feed is 4 fake rows (`admin_dashboard_screen.dart:38-43`); `'جنوری 2026'` hard-coded (`admin_dashboard_screen.dart:493`) | `admin_dashboard_screen.dart` |
| 10 | Teacher/parent dashboards imply live data | Teacher stats `'25'/'23'/'3'` + fixed schedule (`teacher_dashboard_screen.dart:96-145, 171-175`); parent child `'محمد احمد'`, `'حاضری 95%'`, fake timeline/exams (`parent_dashboard_screen.dart:105-160, 246-330, 333-420`) | both dashboard files |

---

## 13. Prioritized remediation list

**P0 — correctness / honesty**
1. Replace hard-coded demo data: wire admin dashboard stats to providers (remove `todayPresent: 142` etc., `_activities` mock feed, hard-coded fee figures at `admin_dashboard_screen.dart:519-541`); replace teacher/parent dashboard statics with provider data or explicit "demo" empty states.
2. Fix the dead 'عملہ' module card pushing `const Placeholder()` (`admin_dashboard_screen.dart:381-389`) — route to `StaffListScreen` (already exists) or remove the card.
3. Branding: add a real logo mechanism (tenant logo asset/URL in `MadrassaConfig` + `Image` widget in login/about headers; `assets/images/` doesn't exist today) and move `'Developed by HijaziApps'` footers (`login_screen.dart:386`, `profile_screen.dart:149`) and `'HijaziApps Production'` (`about_screen.dart:17`) into tenant config or remove from UI.

**P1 — mission-critical (localization, desktop)**
4. Localization: introduce real l10n (`.arb` + codegen) or, at minimum, expand `AppStrings` to 100% coverage and add an app-wide Urdu/English toggle (the `AboutScreen`-only toggle proves the pattern); unpin `locale` in `main.dart:86` and make the forced-RTL builder (`main.dart:96-102`) locale-driven so Arabic/English modes are possible.
5. Desktop: remove the portrait lock (`main.dart:42-45`); build a ≥900px shell using the already-written `responsive.dart` toolkit (`ResponsiveLayout`, `ResponsiveGrid.crossAxisCount`) — NavigationRail/sidebar for admin/super-admin, responsive grids (replace fixed `crossAxisCount: 2`); add keyboard/focus support.
6. Tenant colors: read primary palette from `MadrassaConfig` (or per-madrasa record) instead of hard-coded `AppColors` consts, so rebranding doesn't require code edits.

**P2 — consistency / reuse**
7. Delete or adopt dead widgets: either use `PrimaryButton`/`AppDrawer`/`empty_state_widget.dart` everywhere or delete them (and correct IMPROVEMENTS.md §4 claims); unify the three stat-card implementations and three bottom-nav builders into the shared set.
8. States: adopt `ShimmerLoading` for list screens, use `ErrorStateWidget` with retry actions instead of bare error `Text` (`fee_management_screen.dart:76-81`), keep `EmptyState` usage consistent.
9. Forms: route all dialog validators through the `Validators` helper; extract a shared `AppTextField` (label + validation + direction) to replace per-dialog `InputDecoration` duplication.

**P3 — polish / a11y**
10. Accessibility: add `Semantics` labels to icon-only buttons and stat cards; raise `labelSmall` above 10px for Nastaliq legibility; verify `textSecondary`-on-background contrast; test with large system text sizes.
11. Typography: bundle the `NotoNastaliqUrdu` fallback (or drop the dead `fontFamilyFallback`); consider a Latin/digit companion font so numbers/phone/version strings don't render in Nastaleeq; fix `PrimaryButton`'s raw `TextStyle` to use `AppTypography`.
12. Docs: update README brand (Al Markaz → current), qualify "multi-tenant" and "Desktop" claims, remove "Custom Google Fonts"; fix the stale `main.dart` font comment and the false `admin_dashboard_screen.dart:388` comment.
