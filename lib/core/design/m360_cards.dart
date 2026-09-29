import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';
import 'm360_buttons.dart';

/// مدرسہ 360 — کارڈز
/// Card surfaces. Titles in Nastaleeq, body text in Naskh.
///
/// * [M360Card] — static content surface.
/// * [M360TappableCard] — card with an ink ripple and tap handler.
/// * [M360StatCard] — metric + Urdu label + optional trend and an optional
///   action button (stats are never wallpaper: the action slot is the norm).
/// * [M360SectionHeader] — screen-section title row with optional action.
class M360Card extends StatelessWidget {
  /// Creates a static content card.
  const M360Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(M360Spacing.md),
    this.margin = EdgeInsets.zero,
    this.elevation = M360Elevation.sm,
    this.borderColor,
    this.borderRadius = M360Radius.md,
    this.semanticLabel,
  });

  /// Card content.
  final Widget child;

  /// Inner padding; defaults to 16 all around.
  final EdgeInsetsGeometry padding;

  /// Outer margin; defaults to none (parents own the gutters).
  final EdgeInsetsGeometry margin;

  /// Material elevation.
  final double elevation;

  /// Optional hairline border color (e.g. [AppColors.gold] for highlights).
  final Color? borderColor;

  /// Corner radius; defaults to [M360Radius.md].
  final double borderRadius;

  /// Accessibility label for the card region.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: margin,
      elevation: elevation,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!, width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (semanticLabel == null) return card;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: card,
    );
  }
}

/// Card with a Material ink ripple; use for rows/tiles that navigate.
class M360TappableCard extends StatelessWidget {
  /// Creates a tappable card.
  const M360TappableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.all(M360Spacing.md),
    this.margin = EdgeInsets.zero,
    this.elevation = M360Elevation.sm,
    this.semanticLabel,
  });

  /// Card content.
  final Widget child;

  /// Null disables the ripple.
  final VoidCallback? onTap;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  /// Outer margin.
  final EdgeInsetsGeometry margin;

  /// Material elevation.
  final double elevation;

  /// Accessibility label; defaults to none (content should self-describe).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(M360Radius.md),
    );
    final card = Card(
      margin: margin,
      elevation: elevation,
      color: AppColors.surface,
      shape: shape,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(M360Radius.md),
        child: Padding(padding: padding, child: child),
      ),
    );
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: semanticLabel,
      child: card,
    );
  }
}

/// Metric card: big value, Urdu label, optional trend line and action.
///
/// Horizontal layout: tinted icon circle, then a label/value column. Radius
/// 16 ([M360Radius.lg]) — not the generic card radius — with an optional
/// subtitle/trend/action slot.
/// The value renders in Naskh (digits/amounts), the label in Nastaleeq.
/// [actionLabel]/[onAction] render a text button — prefer wiring a real
/// action («تفصیل دیکھیں») over a decorative stat.
class M360StatCard extends StatelessWidget {
  /// Creates a stat card.
  const M360StatCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.iconBackground,
    this.trendText,
    this.trendUp,
    this.actionLabel,
    this.onAction,
    this.valueColor = AppColors.textPrimary,
    this.semanticLabel,
  });

  /// The metric itself, e.g. «1,250» or «₨ 45,000».
  final String value;

  /// Urdu label under the metric, e.g. «کل طلبہ».
  final String label;

  /// Optional leading icon in a tinted circle.
  final IconData? icon;

  /// Tint behind [icon]; defaults to a light teal.
  final Color? iconBackground;

  /// Optional trend caption, e.g. «+5% اس ماہ».
  final String? trendText;

  /// Trend direction; null hides the trend arrow.
  final bool? trendUp;

  /// Optional action label, e.g. «تفصیل دیکھیں».
  final String? actionLabel;

  /// Action handler; the button only renders when both this and
  /// [actionLabel] are provided.
  final VoidCallback? onAction;

  /// Metric color; defaults to primary text.
  final Color valueColor;

  /// Accessibility label; defaults to «label: value».
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return M360Card(
      semanticLabel: semanticLabel ?? '$label: $value',
      borderRadius: M360Radius.lg,
      padding: const EdgeInsets.all(M360Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null)
                Container(
                  width: M360TouchTarget.minHeight,
                  height: M360TouchTarget.minHeight,
                  decoration: BoxDecoration(
                    color: iconBackground ??
                        AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 24),
                ),
              if (icon != null) const SizedBox(width: M360Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      textDirection: TextDirection.rtl,
                      style: AppTypography.bodyLarge.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                        height: 1.4,
                      ),
                    ),
                    Text(
                      label,
                      textDirection: TextDirection.rtl,
                      style: AppTypography.labelNastaliq,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (trendText != null || hasAction) ...[
            const SizedBox(height: M360Spacing.sm),
            Row(
              children: [
                if (trendText != null)
                  Expanded(child: _TrendLine(text: trendText!, up: trendUp)),
                if (hasAction)
                  M360TertiaryButton(
                    label: actionLabel!,
                    onPressed: onAction,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.text, required this.up});

  final String text;
  final bool? up;

  @override
  Widget build(BuildContext context) {
    final color = up == null
        ? AppColors.textSecondary
        : up!
            ? AppColors.success
            : AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (up != null)
          Icon(
            up! ? Icons.trending_up : Icons.trending_down,
            size: 18,
            color: color,
          ),
        if (up != null) const SizedBox(width: M360Spacing.xxs),
        Flexible(
          child: Text(
            text,
            textDirection: TextDirection.rtl,
            style: AppTypography.bodySmall.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Section title row: Nastaleeq title, optional Naskh subtitle, optional
/// trailing action («سب دیکھیں»).
class M360SectionHeader extends StatelessWidget {
  /// Creates a section header.
  const M360SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(
      horizontal: M360Spacing.md,
      vertical: M360Spacing.sm,
    ),
  });

  /// Urdu section title, e.g. «آج کی حاضری».
  final String title;

  /// Optional longer explanation in Naskh.
  final String? subtitle;

  /// Optional trailing action label, e.g. «سب دیکھیں».
  final String? actionLabel;

  /// Trailing action handler; renders only with [actionLabel].
  final VoidCallback? onAction;

  /// Outer padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.titleMedium,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    textDirection: TextDirection.rtl,
                    style: AppTypography.bodySmall,
                  ),
              ],
            ),
          ),
          if (hasAction)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: AppTypography.labelNastaliq
                    .copyWith(color: AppColors.primary),
                minimumSize: const Size(64, M360TouchTarget.minHeight),
              ),
              child: Text(actionLabel!, textDirection: TextDirection.rtl),
            ),
        ],
      ),
    );
  }
}
