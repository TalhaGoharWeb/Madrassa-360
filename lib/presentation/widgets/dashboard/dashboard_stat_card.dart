/// ڈیش بورڈ اعداد و شمار کارڈ (m360 اڈاپٹر)
/// Dashboard stat card — Phase 7 adapter.
///
/// Renders the canonical [M360StatCard] (horizontal: tinted icon circle +
/// label/value column, radius 16) while preserving the dashboard
/// framework's tap-to-navigate contract: when [onTap] is given the whole
/// card gets a Material ink ripple.
///
/// [subtitle] maps to the stat card's caption line ([M360StatCard.trendText]).
/// [color] drives both the icon tint and the value color.

import 'package:flutter/material.dart';

import '../../../core/design/m360.dart';

/// A single dashboard metric on the m360 system.
class DashboardStatCard extends StatelessWidget {
  /// Metric icon in the tinted circle.
  final IconData icon;

  /// Urdu label under the metric.
  final String label;

  /// The metric itself, e.g. «1,250» or «Rs 45,000».
  final String value;

  /// Optional caption line under the label.
  final String? subtitle;

  /// Icon tint + value color.
  final Color color;

  /// Tap handler; null renders a static card.
  final VoidCallback? onTap;

  const DashboardStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.color = AppColors.primary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = M360StatCard(
      value: value,
      label: label,
      icon: icon,
      iconBackground: color.withValues(alpha: 0.12),
      valueColor: color,
      trendText: subtitle,
      semanticLabel: '$label: $value',
    );
    final tap = onTap;
    if (tap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(M360Radius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(M360Radius.lg),
        onTap: tap,
        child: card,
      ),
    );
  }
}
