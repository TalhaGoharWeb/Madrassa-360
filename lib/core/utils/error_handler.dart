/// خرابی کا انتظام
/// Global Error Handling Utilities

import 'package:flutter/material.dart';

/// Custom Exception Classes
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  AppException(this.message, {this.code, this.details});

  @override
  String toString() => 'AppException: $message ${code != null ? '(Code: $code)' : ''}';
}

class NetworkException extends AppException {
  NetworkException(super.message, {super.code, super.details});
}

class ValidationException extends AppException {
  ValidationException(super.message, {super.code, super.details});
}

class AuthenticationException extends AppException {
  AuthenticationException(super.message, {super.code, super.details});
}

class StorageException extends AppException {
  StorageException(super.message, {super.code, super.details});
}

/// Error Handler Utility
class ErrorHandler {
  /// Handle and format error messages
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
  static void showErrorDialog(BuildContext context, String message, {String? title}) {
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

  /// Log error (can be integrated with crash reporting services)
  static void logError(dynamic error, StackTrace? stackTrace) {
    debugPrint('❌ Error: $error');
    if (stackTrace != null) {
      debugPrint('Stack trace: $stackTrace');
    }
    // TODO: Integrate with Firebase Crashlytics or other error reporting service
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
    this.onRetry,
    this.icon = Icons.error_outline,
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
