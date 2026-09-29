/// ماسٹر ایڈمن مشترکہ وجیٹس
/// Shared building blocks for the Master Admin (platform operator) section.
///
/// Phase 10: every widget below is a thin compatibility wrapper over the
/// canonical m360 component language
/// (`package:madrasa_360/core/design/m360.dart`). Public classes,
/// constructors, and call semantics are unchanged — only the visuals
/// moved. In particular [MaStatusChip.colorFor] keeps its exact
/// status→color mapping (pinned by `test/unit/license_status_test.dart`).

import 'package:flutter/material.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';

export '../../../../core/widgets/empty_state_widget.dart';
export '../../../../core/widgets/loading_widget.dart';

/// A KPI stat card for the dashboard stat row.
class MaStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const MaStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = M360StatCard(
      value: value,
      label: label,
      icon: icon,
      iconBackground: color.withValues(alpha: 0.12),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(M360Radius.lg),
      child: card,
    );
  }
}

/// Section card with a title row.
class MaSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  const MaSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return M360Card(
      margin: const EdgeInsets.only(bottom: M360Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          M360SectionHeader(
            title: title,
            subtitle: subtitle,
            padding: EdgeInsets.zero,
          ),
          if (actions != null) ...[
            const SizedBox(height: M360Spacing.sm),
            Wrap(spacing: M360Spacing.sm, children: actions!),
          ],
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }
}

/// Health status for the system health panel.
enum MaHealth { ok, warning, down, unknown }

/// A single health-check row. Never renders green unless the check passed.
class MaHealthTile extends StatelessWidget {
  final String label;
  final MaHealth status;
  final String detail;

  const MaHealthTile({
    super.key,
    required this.label,
    required this.status,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    late final String statusLabel;
    switch (status) {
      case MaHealth.ok:
        color = AppColors.success;
        icon = Icons.check_circle;
        statusLabel = 'Operational';
        break;
      case MaHealth.warning:
        color = AppColors.warning;
        icon = Icons.warning_amber;
        statusLabel = 'Degraded';
        break;
      case MaHealth.down:
        color = AppColors.error;
        icon = Icons.cancel;
        statusLabel = 'Down';
        break;
      case MaHealth.unknown:
        color = AppColors.textSecondary;
        icon = Icons.help_outline;
        statusLabel = 'Unknown';
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.titleSmall),
                Text(
                  detail,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          M360Badge.custom(label: statusLabel, color: color),
        ],
      ),
    );
  }
}

/// Small colored status chip for tenant status values.
///
/// Visuals come from [M360Badge]; the [colorFor] mapping is unchanged and
/// pinned by `test/unit/license_status_test.dart`.
class MaStatusChip extends StatelessWidget {
  final String status;

  const MaStatusChip({super.key, required this.status});

  static Color colorFor(String status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      case 'trial':
        return AppColors.info;
      case 'suspended':
        return AppColors.warning;
      case 'expired':
        return AppColors.error;
      case 'archived':
      case 'cancelled':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return M360Badge.custom(
      label: status.toUpperCase(),
      color: colorFor(status),
    );
  }
}

/// Re-export conveniences so screens import one file.

/// Loading scaffold used by master admin screens.
///
/// Kept as a root [Scaffold] (pushed console route): only the chrome moved
/// to the m360 app bar and skeleton state.
class MaLoadingScaffold extends StatelessWidget {
  final String message;
  const MaLoadingScaffold({super.key, this.message = 'لوڈ ہو رہا ہے…'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const M360AppBar(title: 'پلیٹ فارم منتظم'),
      body: const M360LoadingState(),
    );
  }
}

/// Error scaffold with retry.
///
/// Kept as a root [Scaffold] (pushed console route): only the chrome moved
/// to the m360 app bar and error state.
class MaErrorScaffold extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const MaErrorScaffold({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const M360AppBar(title: 'پلیٹ فارم منتظم'),
      body: M360ErrorState(message: message, onRetry: onRetry),
    );
  }
}
