import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// Confirmation dialog used by the data-critical fix pass.
///
/// Replaced by `M360ConfirmDialog` when the design-system components land.
/// Returns true when the user confirms, false otherwise (including dismiss).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'حذف کریں',
  String cancelLabel = 'منسوخ کریں',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTypography.titleLarge),
      content: Text(message, style: AppTypography.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel, style: AppTypography.labelNastaliq),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style:
                AppTypography.labelNastaliq.copyWith(color: Colors.white),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
