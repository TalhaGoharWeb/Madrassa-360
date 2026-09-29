import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';

/// مدرسہ 360 — اسٹیٹس بیجز
/// Status pills with accessible contrast.
///
/// Contrast strategy: a 15% tint of the status color behind **darkened**
/// status-color text. White-on-bright-status (e.g. white on
/// [AppColors.present]) fails WCAG AA for small text, so the badge derives
/// its foreground by darkening the token color instead of hardcoding one —
/// no new color literals are introduced.
///
/// Every badge kind carries its canonical Urdu label:
///
/// | Kind | Label | Token color |
/// |---|---|---|
/// | [M360BadgeKind.present] | حاضر | [AppColors.present] |
/// | [M360BadgeKind.leave] | رخصت | [AppColors.leave] |
/// | [M360BadgeKind.absent] | غیر حاضر | [AppColors.absent] |
/// | [M360BadgeKind.paid] | ادا شدہ | [AppColors.paid] |
/// | [M360BadgeKind.due] | بقایا | [AppColors.pastDue] |
/// | [M360BadgeKind.partial] | جزوی | [AppColors.pending] |
/// | [M360BadgeKind.active] | فعال | [AppColors.primary] |
/// | [M360BadgeKind.suspended] | معطل | [AppColors.textSecondary] |
enum M360BadgeKind {
  /// حاضر — present (green).
  present,

  /// رخصت — on leave (amber).
  leave,

  /// غیر حاضر — absent (red).
  absent,

  /// ادا شدہ — fee paid (green).
  paid,

  /// بقایا — fee overdue (red).
  due,

  /// جزوی — partially paid (orange).
  partial,

  /// فعال — active (teal).
  active,

  /// معطل — suspended (grey).
  suspended,
}

/// Extension mapping each badge kind to its label and token color.
extension M360BadgeKindX on M360BadgeKind {
  /// Canonical Urdu label.
  String get label {
    switch (this) {
      case M360BadgeKind.present:
        return 'حاضر';
      case M360BadgeKind.leave:
        return 'رخصت';
      case M360BadgeKind.absent:
        return 'غیر حاضر';
      case M360BadgeKind.paid:
        return 'ادا شدہ';
      case M360BadgeKind.due:
        return 'بقایا';
      case M360BadgeKind.partial:
        return 'جزوی';
      case M360BadgeKind.active:
        return 'فعال';
      case M360BadgeKind.suspended:
        return 'معطل';
    }
  }

  /// The [AppColors] status color this badge is derived from.
  Color get color {
    switch (this) {
      case M360BadgeKind.present:
        return AppColors.present;
      case M360BadgeKind.leave:
        return AppColors.leave;
      case M360BadgeKind.absent:
        return AppColors.absent;
      case M360BadgeKind.paid:
        return AppColors.paid;
      case M360BadgeKind.due:
        return AppColors.pastDue;
      case M360BadgeKind.partial:
        return AppColors.pending;
      case M360BadgeKind.active:
        return AppColors.primary;
      case M360BadgeKind.suspended:
        return AppColors.textSecondary;
    }
  }
}

/// A status pill: tinted background + darkened status-color Nastaleeq label.
///
/// Use [M360Badge.kind] for the canonical statuses, or [M360Badge.custom]
/// for one-off labels (still tinted from an [AppColors] token color).
class M360Badge extends StatelessWidget {
  /// Creates a badge for a canonical status kind.
  const M360Badge.kind({
    super.key,
    required M360BadgeKind kind,
    this.icon,
  })  : _kind = kind,
        _label = null,
        _color = null;

  /// Creates a badge with a custom Urdu label tinted from [color].
  ///
  /// Prefer [M360Badge.kind]; custom badges are for statuses the design
  /// system does not canonically cover yet.
  const M360Badge.custom({
    super.key,
    required String label,
    required Color color,
    this.icon,
  })  : _kind = null,
        _label = label,
        _color = color;

  final M360BadgeKind? _kind;
  final String? _label;
  final Color? _color;

  /// Optional small icon before the label.
  final IconData? icon;

  String get _resolvedLabel => _label ?? _kind!.label;
  Color get _resolvedColor => _color ?? _kind!.color;

  /// Darkens [color] for AA-safe small text on a light tint.
  ///
  /// Derived from the token at build time — no hardcoded foregrounds.
  static Color _accessibleForeground(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - 0.28).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final base = _resolvedColor;
    final foreground = _accessibleForeground(base);
    return Semantics(
      label: _resolvedLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: M360Spacing.sm,
          vertical: M360Spacing.xxs,
        ),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(M360Radius.pill),
          border: Border.all(color: base.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: base,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: M360Spacing.xxs),
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: M360Spacing.xxs),
            ],
            Flexible(
              child: Text(
                _resolvedLabel,
                textDirection: TextDirection.rtl,
                // Flexible + ellipsis: long labels (e.g. expiry dates) must
                // truncate inside narrow parents instead of overflowing the
                // badge Row on 360px phones.
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: AppTypography.labelNastaliq.copyWith(
                  color: foreground,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
