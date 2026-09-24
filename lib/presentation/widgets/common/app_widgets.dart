import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

/// عام کارڈ ویجٹ
/// Reusable App Card Widget with consistent styling
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? elevation;
  final double borderRadius;
  final VoidCallback? onTap;
  final Border? border;
  final Gradient? gradient;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation,
    this.borderRadius = 16,
    this.onTap,
    this.border,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidget = Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: elevation ?? 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: cardWidget,
        ),
      );
    }

    return cardWidget;
  }
}

/// شماریاتی کارڈ
/// Statistics Card for Dashboard
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final String? trend;
  final bool isUp;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.trend,
    this.isUp = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isUp ? AppColors.success : AppColors.error).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUp ? Icons.trending_up : Icons.trending_down,
                        size: 14,
                        color: isUp ? AppColors.success : AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trend!,
                        style: AppTypography.labelSmall.copyWith(
                          color: isUp ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: AppTypography.headingMedium.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// خالی حالت ویجٹ
/// Empty State Widget
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.buttonText,
    this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: AppColors.primary.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (buttonText != null && onButtonPressed != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onButtonPressed,
                child: Text(buttonText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// تلاش فیلڈ
/// Search Field Widget
class SearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterTap;

  const SearchField({
    super.key,
    this.controller,
    this.hintText = 'تلاش کریں...',
    this.onChanged,
    this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTypography.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: onFilterTap != null
              ? IconButton(
                  icon: const Icon(Icons.tune, color: AppColors.primary),
                  onPressed: onFilterTap,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

/// اسٹیٹس بیج
/// Status Badge Widget
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool isLarge;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.isLarge = false,
  });

  // Predefined badge styles
  factory StatusBadge.present() => const StatusBadge(
        label: 'حاضر',
        color: AppColors.present,
        icon: Icons.check_circle,
      );

  factory StatusBadge.absent() => const StatusBadge(
        label: 'غیر حاضر',
        color: AppColors.absent,
        icon: Icons.cancel,
      );

  factory StatusBadge.leave() => const StatusBadge(
        label: 'چھٹی',
        color: AppColors.leave,
        icon: Icons.event_busy,
      );

  factory StatusBadge.paid() => const StatusBadge(
        label: 'ادا شدہ',
        color: AppColors.paid,
        icon: Icons.check_circle,
      );

  factory StatusBadge.pending() => const StatusBadge(
        label: 'زیر التواء',
        color: AppColors.pending,
        icon: Icons.schedule,
      );

  factory StatusBadge.pastDue() => const StatusBadge(
        label: 'واجب الادا',
        color: AppColors.pastDue,
        icon: Icons.warning,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLarge ? 16 : 12,
        vertical: isLarge ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isLarge ? 12 : 8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: isLarge ? 18 : 14),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: (isLarge ? AppTypography.labelLarge : AppTypography.labelSmall).copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// سیکشن ہیڈر
/// Section Header with optional action
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onActionTap;
  final IconData? actionIcon;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onActionTap,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (actionText != null || onActionTap != null)
            TextButton(
              onPressed: onActionTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionText ?? 'مزید',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  if (actionIcon != null) ...[
                    const SizedBox(width: 4),
                    Icon(actionIcon, color: AppColors.primary, size: 18),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// معلوماتی ٹائل
/// Info Tile for displaying key-value pairs
class InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const InfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.primary).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.labelSmall,
                ),
                Text(
                  value,
                  style: AppTypography.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// لوڈنگ انڈیکیٹر
/// Loading Overlay Widget
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        message!,
                        style: AppTypography.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
