/// ماسٹر ایڈمن مشترکہ وجیٹس
/// Shared building blocks for the Master Admin (platform operator) section.

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/loading_widget.dart';

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
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: AppTypography.headingMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(12), child: card);
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
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            )),
                      ],
                    ],
                  ),
                ),
                if (actions != null) ...actions!,
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: AppTypography.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small colored status chip for tenant status values.
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
    final color = colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Re-export conveniences so screens import one file.

/// Loading scaffold used by master admin screens.
class MaLoadingScaffold extends StatelessWidget {
  final String message;
  const MaLoadingScaffold({super.key, this.message = 'لوڈ ہو رہا ہے…'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform Admin')),
      body: LoadingWidget(message: message),
    );
  }
}

/// Error scaffold with retry.
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
      appBar: AppBar(title: const Text('Platform Admin')),
      body: EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'خرابی / Error',
        message: message,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: onRetry,
      ),
    );
  }
}
