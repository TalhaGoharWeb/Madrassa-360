/// عالمی خرابی کی حد
/// Global error boundary (Phase 7, mission §§46–47).
///
/// The single choke point for failure handling: every caught error is
/// classified into the [AppException] taxonomy, its technical details are
/// logged through [AppLogger] (never shown to users), the relevant
/// [HealthMetrics] counter is bumped, and the caller gets back ONLY the
/// user-safe Urdu/English message.
///
/// Contract with `core/observability/app_logger.dart` (parallel worker):
/// singleton with instance methods —
/// `AppLogger().error(message, {context, error, stackTrace})`,
/// `AppLogger().warning(...)`, `AppLogger().info(...)`, `AppLogger().debug(...)`,
/// plus `AppLogger.redact(...)`. If the landed AppLogger API changes, this
/// file is the only place that needs reconciling.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/errors/app_exceptions.dart';
import 'package:madrasa_360/core/observability/app_logger.dart';
import 'package:madrasa_360/core/observability/health_metrics.dart';

/// Central error-handling entry point. All methods are static and never
/// throw — the boundary itself must not become a failure source.
class ErrorBoundary {
  ErrorBoundary._();

  /// Classify [error], log technical details, bump health counters, and
  /// return the user-safe message. For widget-layer code with a [WidgetRef].
  ///
  /// [tag] identifies the failure site in logs (e.g. `'auth/login'`).
  /// [localeCode] selects the message language; defaults to Urdu.
  /// The [ref] parameter is reserved for future locale/theme resolution;
  /// it is currently unused beyond keeping the call sites uniform.
  static String handleError(
    Object error,
    StackTrace stackTrace,
    WidgetRef ref, {
    String? tag,
    String localeCode = 'ur',
  }) {
    try {
      return _report(error, stackTrace, tag: tag, localeCode: localeCode);
    } catch (_) {
      return _fallbackMessage(localeCode);
    }
  }

  /// Same as [handleError] for non-widget code (sync engine, backup
  /// service, repositories) that has no [WidgetRef]/[BuildContext].
  static String handleErrorSimple(
    Object error,
    StackTrace stackTrace, {
    String? tag,
    String localeCode = 'ur',
  }) {
    try {
      return _report(error, stackTrace, tag: tag, localeCode: localeCode);
    } catch (_) {
      return _fallbackMessage(localeCode);
    }
  }

  /// Log-only variant: classify + log + bump counters, discard the
  /// message. For catch sites that already produce their own UX.
  static void logOnly(
    Object error,
    StackTrace stackTrace, {
    String? tag,
  }) {
    try {
      _report(error, stackTrace, tag: tag, localeCode: 'ur');
    } catch (_) {
      // The boundary never throws.
    }
  }

  // ── UI helpers ───────────────────────────────────────────────

  /// Show the user-safe message for [error] in a snackbar. Classifies and
  /// logs first; never shows raw errors or stack traces.
  static void showErrorSnackBar(
    BuildContext context,
    Object error, {
    StackTrace? stackTrace,
    WidgetRef? ref,
    String localeCode = 'ur',
  }) {
    final message = ref != null && stackTrace != null
        ? handleError(error, stackTrace, ref, localeCode: localeCode)
        : handleErrorSimple(error, stackTrace ?? StackTrace.current,
            localeCode: localeCode);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show the user-safe message for [error] in a dialog. Classifies and
  /// logs first; never shows raw errors or stack traces.
  static Future<void> showErrorDialog(
    BuildContext context,
    Object error, {
    StackTrace? stackTrace,
    WidgetRef? ref,
    String? title,
    String localeCode = 'ur',
  }) {
    final message = ref != null && stackTrace != null
        ? handleError(error, stackTrace, ref, localeCode: localeCode)
        : handleErrorSimple(error, stackTrace ?? StackTrace.current,
            localeCode: localeCode);
    final dialogTitle = title ??
        (localeCode.toLowerCase().startsWith('en') ? 'Error' : 'خرابی');
    final okLabel =
        localeCode.toLowerCase().startsWith('en') ? 'OK' : 'ٹھیک ہے';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dialogTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  // ── Internals ──────────────────────────────────────────────

  static String _report(
    Object error,
    StackTrace stackTrace, {
    String? tag,
    required String localeCode,
  }) {
    final ex = error is AppException ? error : AppException.fromSupabase(error);

    // Technical details go ONLY to the log. The user message returned
    // below contains no diagnostics.
    AppLogger().error(
      'Handled error${tag != null ? ' [$tag]' : ''} (${ex.code ?? 'unknown'})',
      error: error,
      stackTrace: stackTrace,
      context: <String, Object?>{
        'code': ex.code,
        'technical': ex.technicalDetails,
        if (tag != null) 'tag': tag,
      },
    );

    // Observability counters (fire-and-forget; HealthMetrics persists).
    final metrics = HealthMetrics.instance;
    if (ex is SyncException) {
      metrics.recordSyncFailure();
    } else if (ex is AuthException) {
      metrics.recordAuthFailure();
    } else if (ex is NetworkException || ex is DatabaseException) {
      metrics.recordApiError();
    }

    return ex.userMessage(localeCode: localeCode);
  }

  static String _fallbackMessage(String localeCode) =>
      localeCode.toLowerCase().startsWith('en')
          ? 'Something went wrong. Please try again.'
          : 'کچھ غلط ہو گیا۔ برا کرم دوبارہ کوشش کریں۔';
}
