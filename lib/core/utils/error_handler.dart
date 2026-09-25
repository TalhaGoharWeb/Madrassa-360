/// خرابی کا انتظام
/// Global Error Handling Utilities
///
/// Phase 7: the exception taxonomy moved to
/// `lib/core/errors/app_exceptions.dart` (sealed [AppException] +
/// subclasses with EN/UR user-safe messages). This file keeps the UI
/// helpers (dialogs, snackbars, inline error widgets) and re-exports the
/// taxonomy so existing imports keep working.
///
/// Legacy aliases ([AuthenticationException], [StorageException]) live in
/// `app_exceptions.dart` as deprecated subclasses — do not re-add the old
/// definitions here; duplicate class names will not compile.

import 'package:flutter/material.dart';

import 'package:madrasa_360/core/errors/app_exceptions.dart';
import 'package:madrasa_360/core/observability/app_logger.dart';

export 'package:madrasa_360/core/errors/app_exceptions.dart';

/// Error Handler Utility
class ErrorHandler {
  /// Handle and format error messages.
  ///
  /// Returns the user-safe message: for [AppException]s this is the Urdu
  /// user message ([AppException.message]); technical details are never
  /// returned here.
  static String getErrorMessage(dynamic error) {
    if (error is AppException) {
      return error.message;
    } else if (error is FormatException) {
      return 'غلط ڈیٹا فارمیٹ';
    } else if (error is TypeError) {
      return 'ڈیٹا ٹائپ کی خرابی';
    } else {
      return 'نامعلوم خرابی';
    }
  }

  /// Show error dialog
  static void showErrorDialog(BuildContext context, String message,
      {String? title}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title ?? 'خرابی'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ٹھیک ہے'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar
  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'بند کریں',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show success snackbar
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Log error via the centralized [AppLogger] (file logging + redaction).
  ///
  /// Kept for pre-Phase-7 call sites. New code should use
  /// `ErrorBoundary.handleError` / `logOnly`, which also classify the
  /// error into the [AppException] taxonomy and bump health counters.
  static void logError(dynamic error, StackTrace? stackTrace) {
    AppLogger().error(
      'ErrorHandler.logError',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Error Display Widget
class ErrorDisplayWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorDisplayWidget({
    super.key,
    required this.message,
    this.icon = Icons.error_outline,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('دوبارہ کوشش کریں'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
