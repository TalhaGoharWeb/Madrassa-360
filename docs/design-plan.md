# Madrassa 360 — Design System Plan (Redesign Phase 3)

**Branch:** `redesign/ux-v2` · **Date:** 2026-09-29
**Status:** Plan. No code changed. Implementation follows this document.

Principle: **"Everything important should be visible, understandable, and
reachable without unnecessary navigation."**

---

## 1. Color system — strict 60/30/10

Centralized in `AppColors` + `M360Brand` (dedupe `gold`). No other hex literals
in presentation code.

| Token | Hex | Share | Used for |
|---|---|---|---|
| `background` | `#F1FAF7` | 60% | main background |
| `surface` | `#FFFFFF` | 60% | cards, forms, tables, dialogs, inputs |
| `primary` | `#0F6B63` | 30% | sidebar, nav, headers, section titles, selected states, branding |
| `primaryDark` | `#094742` | 30% | sidebar depth, strong anchors |
| `primaryLight` | `#4DB6AC` | — | teal tint (sparingly) |
| `accent` | `#F28C28` | 10% | **only** meaningful CTAs: + نیا طالب علم، حاضری محفوظ کریں، فیس جمع کریں، نیا امتحان |
| `accentDark` | `#D97706` | — | pressed state |
| `gold` | `#C9A227` | — | brand accent (logo contexts, subtle) |

Semantics (restrained, never overpowering 60/30/10):
`success #4CAF50` · `warning #FF9800` · `error #F44336` · `info #2196F3`.
Domain: attendance present/absent/leave/late (green/red/amber/blue);
fee paid/pending/pastDue (green/orange/red). Every color documented; no random
introductions.

**Purge list:** `app_nav_rail.dart:271` `#009688` · `role_config.dart` rainbow
gradients · all `Colors.red/green/grey/amber` literals → tokens · finance
indigo `0xFF1A237E` · `₹` → PKR.

## 2. Typography (RTL-first, Urdu-first)

- **Urdu display/nav/labels:** Jameel Noori Nastaleeq (bundled v4 + Kasheeda
  subset), `height ≥ 2.0` anti-clipping, ≥15sp legibility floor. Never via
  `fontFamily` literals — always `AppTypography` (fallback chain:
  Nastaleeq → Naskh → never system font).
- **Inputs/body/numbers/technical:** Noto Naskh Arabic; **standard numerals
  0–9** for money, dates, roll numbers.
- **Latin/technical:** documented `M360LatinText` LTR helper (replaces scattered
  `TextDirection.ltr` overrides).
- Hierarchy: Display · H1 · H2 · H3 · Section title · Card title · Body ·
  Secondary · Caption (`bodySmall` until a real caption exists) · Button ·
  Navigation · Table · Metric. 93 hardcoded `fontSize` literals → scale.

## 3. Spacing / radius / elevation / motion

`M360Spacing`: 4/8/12/16/20/24/32/40/48 · `M360Radius`: 8/12/16/20(pill 999) —
avoid pill overload · `M360Elevation`: 0/2/4/8 (minimal shadows; 42 current
`boxShadow` usages reduced) · `M360Duration`: 150/300/500ms (subtle motion only).
Breakpoints: mobile 600 · tablet 1100. Touch target 48×48.

## 4. Component library (canonical: `lib/core/design/` + `m360.dart` barrel)

### 4.1 Keep / refactor (per design audit)

- KEEP: `design_tokens.dart` (dedupe gold), `m360_badges.dart`, `m360_inputs.dart`,
  `m360_states.dart`, `responsive.dart`.
- REFACTOR: `m360_buttons.dart` (fix "filled teal" docstring; **add tertiary/text
  variant** — 52 ad-hoc `TextButton`s prove demand), `m360_cards.dart` (**unify
  3 StatCards → one horizontal** icon-circle + label/value, per reference),
  `m360_table.dart` (**add pagination + bulk selection**; `Alignment.centerLeft`
  → `AlignmentDirectional.centerEnd`).

### 4.2 New components to build (gaps proven by usage counts)

| Component | Why |
|---|---|
| `M360Dialog` + `M360ConfirmDialog` | 73 ad-hoc dialogs; destructive actions need one standard confirm |
| `showM360SnackBar` / `M360Toast` | 126 raw SnackBars, inconsistent wording/duration |
| `M360Dropdown` (select) | no shared select; every filter hand-rolled |
| `M360SearchField` | promote from `app_widgets.dart`, standardize |
| `M360AppBar` | consistent deep-screen app bars with back nav |
| `M360DatePicker` | one Urdu date-picking UX |
| `M360LatinText` | documented LTR helper |
| Skeleton variants | card-grid skeleton alongside existing shimmer |

### 4.3 Delete after migration

`core/widgets/` duplicates · `app_widgets.dart` (migrate consumers first) ·
`dashboard/` widget duplicates · 2 `LoadingOverlay`s → 1 · 3 `StatCard`s → 1.

### 4.4 Rules

- No new raw `Card(`/`ElevatedButton(`/`TextButton(`/`SnackBar(`/`showDialog(`
  in presentation code — use m360_\*.
- Buttons: primary = orange (icon + label + loading/disabled/hover/pressed);
  secondary = white/mint + teal border/text; tertiary = transparent teal text;
  danger = semantic red.
- Forms: `M360TextField`/`M360Dropdown`, sectioned with `SectionDivider`,
  required indicators, inline validation inside real `Form`s, RTL alignment.
- Tables: `M360ResponsiveTable` everywhere (search/filter/sort/pagination/row
  actions/bulk actions; card fallback on mobile; `M360EmptyState` on empty).
- Feedback: every important action → `showM360SnackBar` (success/error) or
  `M360ConfirmDialog` (destructive). Copy: success "کامیابی سے محفوظ ہوگیا",
  error human-readable + retry, loading "محفوظ کیا جا رہا ہے...".
- Empty states: WHAT/WHY/NEXT ACTION + action button (never bare `Text('کوئی…')`).
- Loading: skeletons, not full-screen spinners.
- Icons: single consistent set, consistent stroke/size; tooltips on all icon buttons.

## 5. Application shell (target) — ONE SHELL, NO NESTING

```
MaterialApp
  └── AppShell                    ← the ONLY Scaffold / top-level header
        ├── Sidebar (right, RTL)
        ├── TopBar (search ⌘K · notifications · tenant · profile)
        └── ContentArea
              └── PageContainer   ← pages provide ONLY this
                    ├── PageHeader (breadcrumb · title · description · actions)
                    └── PageContent
```

**Hard rules:**
- ONE global shell. Pages NEVER create their own Scaffold/AppBar/sidebar/
  global search — they render `PageContainer` + `PageHeader` + content.
- NO nested Scaffolds, NO duplicate AppBars, NO card-headers pretending to be
  AppBars. Hierarchy: GLOBAL SHELL → PAGE HEADER → SECTION HEADER → CONTENT.
- Dialogs/sheets for confirmations, quick edits, small forms. Full pages for
  complex forms, multi-step workflows (exam wizard, user wizard), detailed
  records, reports, large datasets. Bottom sheets on mobile where appropriate.
- Navigation belongs to the shell: sidebar, top bar, global search,
  notifications, profile, tenant switcher, responsive behavior.

- **Rail (desktop ≥1100, 264px):** deep teal `#0F6B63→#094742`, tenant logo/name
  header, collapsible groups (مرکزی، طلبہ، تعلیمی نظام، حاضری، **مالی نظام**
  (unified: ڈیش بورڈ، فیس، واجبات، انوائسز، ادائیگیاں، لیجر، اخراجات، رپورٹس),
  **ہاسٹل**، **ٹرانسپورٹ**، **اسناد** (real screens, §8 plan), ادارہ، ترتیبات),
  permission-filtered, badges, selected = subtle mint/orange accent (never
  full-orange fill), smooth expand/collapse, keyboard accessible.
- **Tablet:** rail in drawer. **Mobile:** bottom nav (4 primaries + "مزید").
- **Top header:** global command search (Ctrl+K → students/teachers/classes/
  subjects/exams/fees/pages/commands), notification bell + badge, tenant
  switcher, institution logo/name (right), user profile + role (right).
  Breadcrumb `group › destination`.

## 6. Dashboard hierarchy (all 10 role dashboards)

1. **Welcome/context:** السلام علیکم ورحمۃ اللہ / خوش آمدید! + institution,
   user, Gregorian + Islamic date. Subtle Islamic geometric motif (arch/star),
   never oversized, never decorative-poster.
2. **Key metrics:** 4–6 horizontal stat cards (icon · label · value · context).
   Restrained color — not one color per card.
3. **Quick actions:** primary orange CTA (e.g. + نیا طالب علم) + secondary
   mint/teal actions (حاضری محفوظ کریں، فیس جمع کریں، نیا امتحان، اعلان جاری کریں).
4. **Info area (3-col):** آج کی حاضری (donut + حاضر/غائب/کل) · اہم اعلانات ·
   آج کے اہم کام (checklist).
5. **Bottom:** recent students/payments, upcoming exams, department shortcuts —
   only where data exists.
- Sections, lists, tables, timelines — **not** a card for every fact.
- Dense but readable; no giant empty spaces.

## 7. Visual language

Modern Islamic institutional — subtle geometric pattern, arch-inspired shapes,
paper-like mint surfaces. NOT: banking/CRM/ERP template, rainbow cards,
excessive gradients/glassmorphism/shadows, decorative religious poster.
Teal = identity · mint/white = surface · orange ≈10% = action.

## 8. Implementation order (gated)

1. Barrel export + component gaps (dialog/confirm/snackbar/dropdown/search/appbar) + refactors (buttons/cards/table).
2. Data-critical fixes (student class IDs, PKR, confirmations, exam duplicates, postedByName, migration 023, silent-catch hygiene on dashboard providers).
3. Dead-code removal + route fixes (TenantPicker→AppShell, _backToApp→AppShell, legacy user-mgmt deep-push, hide planned placeholders, relocate BackupScreen → settings).
4. Shell (rail/header/mobile nav) on the component library.
5. Dashboards (principal first as the template, then role variants).
6. Shared components migration (forms → tables → dialogs per module).
7. Module screens (students → attendance → fees → finance → exams/results → staff → darjas → announcements → library → reports → users/roles → settings → about/profile).
8. Master admin (`/master`) visual pass.
9. Responsive pass (3 breakpoints, real device sizes).
10. Accessibility pass (contrast, focus, targets, semantics).
11. Regression: every route × role matrix × CRUD × states × RTL × breakpoints.

**Gate:** no phase starts until the previous is CI-green (`flutter analyze`,
`flutter test`, `dart format`, migration validation, no-mock-data guard).
