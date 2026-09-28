import 'package:flutter/material.dart';

/// مدرسہ 360 — ڈیزائن ٹوکنز
/// Design tokens: the single source of truth for spacing, radii, elevation,
/// motion and breakpoints used by every `m360_*` widget.
///
/// These tokens are **pure presentation values** — no business logic lives
/// here. Widgets must reference these (and [AppColors]/[AppTypography])
/// instead of hardcoding numbers.
class M360Spacing {
  M360Spacing._();

  /// 4 — hairline gaps, icon-to-text gaps inside chips.
  static const double xxs = 4;

  /// 8 — tight gaps: badge padding, list-item inner spacing.
  static const double xs = 8;

  /// 12 — default card inner padding (compact), form field gaps.
  static const double sm = 12;

  /// 16 — default screen gutter, card padding, section gaps.
  static const double md = 16;

  /// 24 — generous section separation.
  static const double lg = 24;

  /// 32 — large separation: screen sections, empty-state padding.
  static const double xl = 32;

  /// 48 — hero spacing.
  static const double xxl = 48;
}

/// Corner radii.
class M360Radius {
  M360Radius._();

  /// 8 — small controls, table cells, list tiles.
  static const double sm = 8;

  /// 12 — default: cards, buttons, text fields (matches [AppTheme]).
  static const double md = 12;

  /// 16 — large cards, dialogs, bottom sheets.
  static const double lg = 16;

  /// 24 — hero surfaces, stat cards.
  static const double xl = 24;

  /// Fully rounded: badges, pills, avatars.
  static const double pill = 999;
}

/// Elevation levels (Material 3 aligned).
class M360Elevation {
  M360Elevation._();

  static const double none = 0;
  static const double sm = 2;
  static const double md = 4;
  static const double lg = 8;
}

/// Animation durations.
class M360Duration {
  M360Duration._();

  /// 150ms — micro-interactions: ripples, badge changes.
  static const Duration fast = Duration(milliseconds: 150);

  /// 300ms — default: page transitions, expand/collapse.
  static const Duration normal = Duration(milliseconds: 300);

  /// 500ms — hero/emphasis animations.
  static const Duration slow = Duration(milliseconds: 500);
}

/// Standard easing curves.
class M360Curve {
  M360Curve._();

  static const Curve standard = Curves.easeInOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
}

/// Responsive breakpoints (logical pixels).
///
/// * `< mobile` → phone layout (single column, cards instead of tables).
/// * `< tablet` → large phone / small tablet (two columns where sensible).
/// * `>= tablet` → desktop (multi-column, full data tables).
class M360Breakpoint {
  M360Breakpoint._();

  static const double mobile = 600;
  static const double tablet = 1100;
}

/// Maximum content widths per breakpoint; content wider than this is
/// centered with gutters instead of stretching edge-to-edge.
class M360Layout {
  M360Layout._();

  static const double maxContentWidthMobile = 600;
  static const double maxContentWidthTablet = 900;
  static const double maxContentWidthDesktop = 1200;
}

/// Minimum touch-target size (48×48, Material accessibility guideline).
class M360TouchTarget {
  M360TouchTarget._();

  static const double minHeight = 48;
  static const double minWidth = 48;
}

/// Brand accent tokens.
///
/// [AppColors] carries the full product palette; the gold accent below is
/// the companion to the teal primary (app icon, premium highlights,
/// dividers). It is decorative — never use it as the sole carrier of
/// meaning, and never as small body text on light surfaces.
class M360Brand {
  M360Brand._();

  /// Muted gold accent (icon star, premium highlights, hairline dividers).
  static const Color gold = Color(0xFFC9A227);

  /// Gold for dark surfaces.
  static const Color goldLight = Color(0xFFE3C766);
}
