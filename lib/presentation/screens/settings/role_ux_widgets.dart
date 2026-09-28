/// مشترکہ چھوٹے ویجٹس — صارف انتظام (Phase 8a)
/// Shared small widgets for the 8a user-management screens: badges,
/// section titles, empty states, confirm dialogs, snackbars.
/// Plain Urdu everywhere; no IDs, codes, or jargon surface here.

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

/// فعال / غیر فعال badge.
class ActiveBadge extends StatelessWidget {
  const ActiveBadge({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (active ? AppColors.success : AppColors.error)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'فعال' : 'غیر فعال',
        style: AppTypography.labelSmall.copyWith(
          color: active ? AppColors.success : AppColors.error,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Urdu role label chip.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Section heading used across the 8a screens.
class UxSectionTitle extends StatelessWidget {
  const UxSectionTitle(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
        ],
        // Long Urdu titles must wrap instead of overflowing narrow
        // screens (Phase 13 responsiveness).
        Expanded(
          child: Text(
            text,
            style: AppTypography.titleSmall.copyWith(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

/// Honest empty state (icon + title + optional hint).
class UxEmptyState extends StatelessWidget {
  const UxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56, color: AppColors.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              title,
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plain-Urdu snackbar.
void showUxSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(color: Colors.white),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

/// Destructive-action confirmation in plain Urdu. Returns true when the
/// user confirms.
Future<bool> confirmUxAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'جی ہاں',
  String cancelLabel = 'منسوخ',
  bool isDestructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            isDestructive ? Icons.warning_amber_rounded : Icons.help_outline,
            color: isDestructive ? AppColors.warning : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: AppTypography.titleMedium)),
        ],
      ),
      content: Text(message, style: AppTypography.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isDestructive ? AppColors.error : AppColors.primary,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Card container shared by the 8a screens.
class UxCard extends StatelessWidget {
  const UxCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: body,
    );
  }
}
