import 'dart:async';

import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';

/// مدرسہ 360 — فیڈبیک
/// Central user feedback. Every snackbar in the app goes through
/// [showM360SnackBar]; [M360Toast] covers lightweight overlay toasts.
///
/// Styling is fixed by the design system (never per-screen): floating
/// snackbar, radius 12, teal-dark success / red error, white Naskh text,
/// 3s success / 4s error.

/// Shows the single canonical snackbar.
///
/// [isError] renders the error style and a longer duration. The [message]
/// must be human-readable Urdu — never a raw exception or error code.
void showM360SnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection: TextDirection.rtl,
          style: AppTypography.bodyMedium.copyWith(color: Colors.white),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
        ),
        margin: const EdgeInsets.all(M360Spacing.md),
        duration: duration ?? Duration(seconds: isError ? 4 : 3),
        action: isError
            ? SnackBarAction(
                label: 'ٹھیک ہے',
                textColor: Colors.white,
                onPressed: () => messenger.hideCurrentSnackBar(),
              )
            : null,
      ),
    );
}

/// Lightweight overlay toast for non-critical confirmations
/// («محفوظ ہو گیا»). Auto-dismisses; does not block interaction.
class M360Toast {
  M360Toast._();

  /// Shows a toast; safe to call without awaiting.
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => _ToastView(
        message: message,
        isError: isError,
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: M360Spacing.xl,
      left: M360Spacing.lg,
      right: M360Spacing.lg,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: M360Spacing.md,
                vertical: M360Spacing.sm,
              ),
              decoration: BoxDecoration(
                color: isError ? AppColors.error : AppColors.textPrimary,
                borderRadius: BorderRadius.circular(M360Radius.pill),
              ),
              child: Text(
                message,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style:
                    AppTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
