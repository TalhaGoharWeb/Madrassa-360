# Madrassa 360 — Visual-Symmetry Audit (lib/ screens & shared widgets)

Audit-only pass. No code was edited. Each finding was verified in its
surrounding widget tree; intentional asymmetry (chat bubbles, timelines,
RTL mirroring via `EdgeInsetsDirectional`, inter-item gaps, centered
empty/error/loading states, deliberate start/end link placement) was
excluded. Shared design-system widgets (`m360_page`, `m360_cards`,
`m360_dialog`, `m360_states`, `m360_table`, `m360_inputs`, `M360SectionHeader`,
`M360EmptyState`, `M360ErrorState`, `M360LoadingState`, `PageHeader`) were
inspected and are symmetric — no findings filed against them.

Line format: `path/to/file.dart:LINE — <widget> — <what looks asymmetric> — <suggested correction>`

---

## Auth

lib/presentation/screens/auth/forgot_password_screen.dart:134 — success-state icon Container (96×96 circle) — the success Column uses `crossAxisAlignment: CrossAxisAlignment.stretch`, so this fixed-size icon tile stretches to full card width while the icon inside it is not centered; the same screen's error icon at :183 is correctly wrapped in `Center` — wrap the success icon in `Center` (or give the Column `crossAxisAlignment: CrossAxisAlignment.center`).

## Admin lists

lib/presentation/screens/admin/student_list_screen.dart:356 — `_ChipRow` filter-strip title (`EdgeInsets.only(right: 16, left: 8)`) — outer gutters of the strip are 16px on the right (title side) but only 8px on the left (chip-list side, from each chip's own `left: 8`); the strip's two edges sit at visibly different distances from the screen edge — give the title `EdgeInsets.only(right: 16)` and the chip `ListView` a matching `EdgeInsets.only(left: 16)` (or otherwise make both outer gutters 16).

## Teacher

lib/presentation/screens/teacher/attendance_screen.dart:427 — bulk-action row — "سب کو حاضر لگائیں" is `Expanded` (full remaining width) while "تبدیلیاں صاف کریں" keeps intrinsic width; when both buttons appear side by side the row looks lopsided — make both buttons `Expanded` with equal flex (or one shared proportional flex) and identical height/spacing.

## Dashboards

lib/presentation/screens/dashboards/principal_dashboard.dart:632 — `_MiniCount` stat tiles (`margin: EdgeInsets.symmetric(horizontal: 3)`) — the three tiles sit 3px inset on each side while the progress bar directly beneath them is full-bleed, so the tile row looks slightly narrower than its sibling — remove the outer margin and use inter-item spacing only (e.g. `SizedBox(width: 6)` between tiles or `Wrap` spacing).

## Profile / common

lib/presentation/screens/common/profile_screen.dart:780 — `Divider(height: 1, indent: 70)` under the repeated settings rows — a physical one-sided indent beneath rows that themselves have symmetric horizontal padding; the divider line starts 70px in from one side and runs to the far edge — use the logical content-side inset (indent/endIndent chosen by text direction, matching the row's leading icon + padding) or symmetric horizontal insets.

## App shell

lib/presentation/shell/shell_page_body.dart:111 — `_SlimToolbar` (`EdgeInsets.fromLTRB(16, 8, 8, 0)`) — when the back chevron shows, its side has 8px padding while the actions side has 16px, so the chevron sits visibly closer to the screen edge than the actions — use symmetric horizontal padding (16/16) on the toolbar.

---

## Total confirmed findings: 6

## Top 5 worst files

1. `lib/presentation/screens/auth/forgot_password_screen.dart` — success icon stretches full width, icon off-center (most visually broken)
2. `lib/presentation/screens/teacher/attendance_screen.dart` — lopsided bulk-action button row
3. `lib/presentation/screens/admin/student_list_screen.dart` — asymmetric filter-strip outer gutters
4. `lib/presentation/screens/common/profile_screen.dart` — one-sided divider indent under symmetric rows
5. `lib/presentation/screens/dashboards/principal_dashboard.dart` — mini stat row inset 3px vs full-bleed progress bar
