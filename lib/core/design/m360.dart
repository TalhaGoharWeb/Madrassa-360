/// مدرسہ 360 — ڈیزائن سسٹم
/// The single canonical component language for the app.
///
/// Import this barrel — never individual `m360_*` files:
///
/// ```dart
/// import 'package:madrasa_360/core/design/m360.dart';
/// ```
///
/// Components are organized by concern:
///
/// * Tokens — [M360Spacing], [M360Radius], [M360Elevation], [M360Brand]
/// * Buttons — [M360PrimaryButton], [M360SecondaryButton],
///   [M360DangerButton], [M360TertiaryButton], [M360IconButton]
/// * Inputs — [M360TextField], [M360SearchField], [M360Dropdown],
///   [M360DatePicker]
/// * Cards — [M360Card], [M360StatCard], [M360SettingsTile],
///   [M360ListCard]
/// * Page chrome — [PageContainer], [PageHeader], [M360AppBar]
/// * Feedback — [showM360SnackBar], [M360Toast], [M360Dialog],
///   [showM360ConfirmDialog], [M360StatusChip]
/// * States — [M360Loading], [M360Empty], [M360Error],
///   [M360CardGridSkeleton]
/// * Data — [M360Table], [M360Badge]
/// * Text — [M360LatinText], [M360Email]
/// * Layout — responsive helpers in `responsive.dart`
library;

export 'design_tokens.dart';
export 'm360_appbar.dart';
export 'm360_badges.dart';
export 'm360_buttons.dart';
export 'm360_cards.dart';
export 'm360_date.dart';
export 'm360_dialog.dart';
export 'm360_feedback.dart';
export 'm360_inputs.dart';
export 'm360_ltr.dart';
export 'm360_page.dart';
export 'm360_search.dart';
export 'm360_select.dart';
export 'm360_states.dart';
export 'm360_status.dart';
export 'm360_table.dart';
export 'm360_navigation.dart';
export 'responsive.dart';
