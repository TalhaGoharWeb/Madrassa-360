/// مشترکہ چھوٹے ویجٹس — صارف انتظام (Phase 8a)
/// Shared small widgets for the 8a user-management screens: badges,
/// section titles, empty states, confirm dialogs, snackbars.
/// Plain Urdu everywhere; no IDs, codes, or jargon surface here.
///
/// Phase 10: every widget below is a thin compatibility wrapper over the
/// canonical m360 component language
/// (`package:madrasa_360/core/design/m360.dart`). Public classes,
/// constructors, and call semantics are unchanged — only the visuals
/// moved. New code should import m360 directly instead of these.

import 'package:flutter/material.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

/// فعال / غیر فعال badge.
class ActiveBadge extends StatelessWidget {
  const ActiveBadge({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return M360Badge.custom(
      label: active ? 'فعال' : 'غیر فعال',
      color: active ? AppColors.success : AppColors.error,
    );
  }
}

/// Urdu role label chip.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return M360Badge.custom(label: label, color: AppColors.primary);
  }
}

/// Section heading used across the 8a screens.
///
/// Kept as a local row (instead of [M360SectionHeader]) because the 8a
/// screens pass an icon and the canonical header has no icon slot; the
/// typography and colors are the same m360 tokens.
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
    return M360EmptyState(
      icon: icon,
      title: title,
      description: hint ?? '',
    );
  }
}

/// Plain-Urdu snackbar. When there is no Scaffold ancestor (standalone /
// test usage — the shell refactor stripped nested Scaffolds), falls back
/// to a floating overlay banner so the message is never lost and never
/// throws. The overlay is tap-to-dismiss; it carries no timer so it cannot
/// race widget-test pumpAndSettle.
void showUxSnack(BuildContext context, String message, {bool isError = false}) {
  if (Scaffold.maybeOf(context) != null) {
    showM360SnackBar(context, message, isError: isError);
    return;
  }
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: GestureDetector(
        onTap: () => entry.remove(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? AppColors.error : AppColors.success,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
}

/// Destructive-action confirmation in plain Urdu. Returns true when the
/// user confirms.
///
/// Backed by the canonical [showM360ConfirmDialog]; copy and defaults
/// are preserved exactly.
Future<bool> confirmUxAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'جی ہاں',
  String cancelLabel = 'منسوخ',
  bool isDestructive = true,
}) {
  return showM360ConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    danger: isDestructive,
  );
}

/// Card container shared by the 8a screens.
class UxCard extends StatelessWidget {
  const UxCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? const EdgeInsets.all(M360Spacing.md);
    if (onTap == null) {
      return M360Card(padding: effectivePadding, child: child);
    }
    return M360TappableCard(
        onTap: onTap!, padding: effectivePadding, child: child);
  }
}
