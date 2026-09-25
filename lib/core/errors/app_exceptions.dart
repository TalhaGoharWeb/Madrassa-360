/// مرکزی خرابی کی درجہ بندی
/// Centralized exception taxonomy for Madrasa-360 (Phase 7, mission §§46–47).
///
/// Rules:
/// * Every exception carries a SAFE user-facing message in English + Urdu
///   ([userMessageEn] / [userMessageUr]). UI code must ONLY ever show these —
///   never [technicalDetails].
/// * [technicalDetails] is for the log file / diagnostics ONLY. It is never
///   rendered in any widget, snackbar, or dialog.
/// * No passwords, tokens, keys, CNIC numbers, or full row payloads may be
///   placed in either the user message or the technical details — the
///   [AppLogger] redaction layer is the last line of defence, not the first.
///
/// Usage:
/// ```dart
/// try {
///   await repo.signIn(email: email, password: password);
/// } catch (e, st) {
///   final message = ErrorBoundary.handleError(e, st, ref, tag: 'auth/login');
///   state = AuthState.error(message); // safe Urdu string
/// }
/// ```

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Base of the taxonomy. Sealed: every subtype lives in this file so the
/// classifier in [ErrorBoundary] (and `fromSupabase`) is exhaustive.
sealed class AppException implements Exception {
  /// Safe message for English-locale UI.
  final String userMessageEn;

  /// Safe message for Urdu-locale UI (the app's default).
  final String userMessageUr;

  /// Machine-readable code, e.g. `auth`, `network`, `rls_denied`,
  /// `unique_violation`, `http_404`. Safe to log; never shown to users.
  final String? code;

  /// Diagnostics for the log file ONLY (server messages, SQL states,
  /// provider codes). NEVER shown in UI.
  final String? technicalDetails;

  /// The original thrown object, if any. Logged, never shown.
  final Object? cause;

  const AppException({
    required this.userMessageEn,
    required this.userMessageUr,
    this.code,
    this.technicalDetails,
    this.cause,
  });

  /// The user-safe message in the requested locale. Defaults to Urdu —
  /// Madrasa-360 is an Urdu-first app.
  String userMessage({String localeCode = 'ur'}) =>
      localeCode.toLowerCase().startsWith('en')
          ? userMessageEn
          : userMessageUr;

  /// Legacy accessor kept for pre-Phase-7 call sites (`e.message`).
  /// Returns the Urdu safe message — never the technical details.
  String get message => userMessageUr;

  @override
  String toString() => 'AppException(${code ?? 'unknown'}): $userMessageEn';

  // ── Factories ────────────────────────────────────────────────

  /// Classify any thrown object into the taxonomy. Never throws itself:
  /// unrecognised errors become [_UnknownException] with a generic safe
  /// message, so UI code can always rely on getting an [AppException].
  factory AppException.fromSupabase(dynamic error) {
    if (error is AppException) return error;
    try {
      return _classify(error);
    } catch (_) {
      return _UnknownException(cause: error);
    }
  }

  /// Classify an `http` package failure. Maps [http.ClientException] to
  /// [NetworkException]; everything else falls back to [fromSupabase].
  factory AppException.fromHttpError(dynamic error) {
    if (error is AppException) return error;
    if (error is http.ClientException) {
      return NetworkException(
        code: 'http_client',
        technicalDetails: 'http.ClientException: ${error.message}',
        cause: error,
      );
    }
    return AppException.fromSupabase(error);
  }

  /// Classify an HTTP response by status code. [bodyPreview] must already
  /// be redacted/truncated by the caller — never pass raw bodies here.
  factory AppException.fromHttpResponse(
    http.Response response, {
    String? bodyPreview,
  }) {
    final status = response.statusCode;
    final tech =
        'HTTP $status${bodyPreview == null || bodyPreview.isEmpty ? '' : ' — $bodyPreview'}';
    if (status == 401) {
      return AuthException(
        userMessageEn: 'Your session has expired. Please sign in again.',
        userMessageUr: 'آپ کا سیشن ختم ہو گیا ہے۔ برا کرم دوبارہ سائن ان کریں۔',
        code: 'http_401',
        technicalDetails: tech,
      );
    }
    if (status == 403) {
      return PermissionException(
        code: 'http_403',
        technicalDetails: tech,
      );
    }
    if (status == 404) {
      return DatabaseException(
        userMessageUr: 'مطلوبہ ریکارڈ نہیں ملا۔',
        userMessageEn: 'The requested record was not found.',
        code: 'http_404',
      );
    }
    if (status == 409) {
      return DatabaseException(
        userMessageUr: 'یہ ریکارڈ پہلے سے موجود ہے۔',
        userMessageEn: 'This record already exists.',
        code: 'http_409',
        technicalDetails: tech,
      );
    }
    if (status == 422) {
      return ValidationException(
        userMessageUr: 'درج کی گئی کچھ معلومات درست نہیں ہیں۔',
        userMessageEn: 'Some of the entered information is invalid.',
        code: 'http_422',
      );
    }
    if (status == 429) {
      return NetworkException(
        userMessageEn: 'Too many requests. Please wait a moment and try again.',
        userMessageUr: 'بہت زیادہ درخواستیں۔ تھوڑا انتظار کر کے دوبارہ کوشش کریں۔',
        code: 'http_429',
        technicalDetails: tech,
      );
    }
    if (status >= 500) {
      return NetworkException(
        userMessageEn:
            'The server is temporarily unavailable. Please try again later.',
        userMessageUr:
            'سرور عارضی طور پر دستیاب نہیں ہے۔ برا کرم بعد میں دوبارہ کوشش کریں۔',
        code: 'http_$status',
        technicalDetails: tech,
      );
    }
    return DatabaseException(
      code: 'http_$status',
      technicalDetails: tech,
    );
  }
}

// ── Concrete taxonomy ────────────────────────────────────────────
//
// Constructor shape (all subclasses): an optional POSITIONAL first argument
// is a custom Urdu user message (keeps pre-Phase-7 call sites such as
// `NetworkException('انٹرنیٹ دستیاب نہیں ہے')` compiling); everything else
// is named.

/// Sign-in / session / token failures.
final class AuthException extends AppException {
  const AuthException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn: userMessageEn ??
              'Sign-in failed. Please check your credentials and try again.',
          userMessageUr: userMessageUr ??
              'سائن ان ناکام ہوا۔ برا کرم اپنی معلومات چیک کر کے دوبارہ کوشش کریں۔',
          code: code ?? 'auth',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// No connectivity, timeouts, DNS/TLS failures, unreachable hosts.
final class NetworkException extends AppException {
  const NetworkException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn: userMessageEn ?? 'No internet connection.',
          userMessageUr: userMessageUr ?? 'انٹرنیٹ دستیاب نہیں ہے۔',
          code: code ?? 'network',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// PostgREST / local-database failures (query errors, constraint
/// violations, missing rows). RLS denials map to [PermissionException].
final class DatabaseException extends AppException {
  const DatabaseException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn:
              userMessageEn ?? 'Could not save or load data. Please try again.',
          userMessageUr:
              userMessageUr ?? 'ڈیٹا محفوظ یا لوڈ نہیں ہو سکا۔ برا کرم دوبارہ کوشش کریں۔',
          code: code ?? 'database',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// Offline-sync pipeline failures (push/pull/apply). Local data is kept;
/// the user message must always say the retry story.
final class SyncException extends AppException {
  const SyncException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn: userMessageEn ??
              'Sync failed. Your data is saved on this device and will be retried.',
          userMessageUr: userMessageUr ??
              'ہم آہنگی ناکام ہوئی۔ آپ کا ڈیٹا اس ڈیوائس میں محفوظ ہے، دوبارہ کوشش کی جائے گی۔',
          code: code ?? 'sync',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// RLS denials and permission-check failures.
final class PermissionException extends AppException {
  const PermissionException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn:
              userMessageEn ?? 'You do not have permission to do this.',
          userMessageUr: userMessageUr ?? 'آپ کو یہ عمل کرنے کی اجازت نہیں ہے۔',
          code: code ?? 'permission',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// Cross-tenant access attempts and tenant-context problems.
final class TenantException extends AppException {
  const TenantException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn: userMessageEn ??
              'This action is not allowed for your institution.',
          userMessageUr:
              userMessageUr ?? 'آپ کے ادارے کے لیے یہ عمل مجاز نہیں ہے۔',
          code: code ?? 'tenant',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// Client-side input validation failures.
final class ValidationException extends AppException {
  const ValidationException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn:
              userMessageEn ?? 'Please check the entered information.',
          userMessageUr: userMessageUr ?? 'برا کرم درج کی گئی معلومات چیک کریں۔',
          code: code ?? 'validation',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// Server demands a minimum app version (forced-upgrade path).
final class UpdateRequiredException extends AppException {
  const UpdateRequiredException([
    String? userMessageUr, {
    String? userMessageEn,
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          userMessageEn: userMessageEn ?? 'Please update the app to continue.',
          userMessageUr:
              userMessageUr ?? 'جاری رکھنے کے لیے برا کرم ایپ اپ ڈیٹ کریں۔',
          code: code ?? 'update_required',
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// Fallback for anything the classifier does not recognise. Private to
/// this library — callers only ever see it as [AppException].
final class _UnknownException extends AppException {
  const _UnknownException({super.technicalDetails, super.cause})
      : super(
          userMessageEn: 'Something went wrong. Please try again.',
          userMessageUr: 'کچھ غلط ہو گیا۔ برا کرم دوبارہ کوشش کریں۔',
          code: 'unknown',
        );
}

// ── Legacy aliases (pre-Phase-7 names) ───────────────────────────
// Kept so existing throw/catch sites compile unchanged. New code must use
// the canonical names above.

/// Legacy alias — use [AuthException].
@Deprecated('Use AuthException from core/errors/app_exceptions.dart')
class AuthenticationException extends AuthException {
  const AuthenticationException([
    String? message, {
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          message,
          code: code,
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

/// Legacy alias — use [DatabaseException].
@Deprecated('Use DatabaseException from core/errors/app_exceptions.dart')
class StorageException extends DatabaseException {
  const StorageException([
    String? message, {
    String? code,
    String? technicalDetails,
    Object? cause,
  }]) : super(
          message,
          code: code,
          technicalDetails: technicalDetails,
          cause: cause,
        );
}

// ── Classifier ───────────────────────────────────────────────────

AppException _classify(dynamic e) {
  // PostgREST errors — the bulk of data-layer failures.
  if (e is sb.PostgrestException) {
    final code = e.code ?? '';
    final tech =
        'PostgrestException code=$code message=${e.message} details=${e.details} hint=${e.hint}';
    switch (code) {
      case '42501': // insufficient_privilege — RLS denial
      case '42502':
        return PermissionException(
          'آپ کو اس ڈیٹا تک رسائی کی اجازت نہیں ہے۔',
          userMessageEn: 'You do not have access to this data.',
          code: 'rls_denied',
          technicalDetails: tech,
          cause: e,
        );
      case '23505': // unique_violation
        return DatabaseException(
          'یہ ریکارڈ پہلے سے موجود ہے۔',
          userMessageEn: 'This record already exists.',
          code: 'unique_violation',
          technicalDetails: tech,
          cause: e,
        );
      case '23503': // foreign_key_violation
        return DatabaseException(
          'یہ ریکارڈ کہیں اور استعمال ہو رہا ہے، اس لیے عمل مکمل نہیں ہو سکا۔',
          userMessageEn:
              'This record is referenced elsewhere and cannot be changed.',
          code: 'fk_violation',
          technicalDetails: tech,
          cause: e,
        );
      case '23502': // not_null_violation
      case '23514': // check_violation
      case '22P02': // invalid_text_representation
        return ValidationException(
          code: 'db_$code',
          technicalDetails: tech,
          cause: e,
        );
      case 'PGRST116': // 0 rows (or >1) for single()
        return DatabaseException(
          'مطلوبہ ریکارڈ نہیں ملا۔',
          userMessageEn: 'The requested record was not found.',
          code: 'not_found',
          technicalDetails: tech,
          cause: e,
        );
      default:
        return DatabaseException(
          code: code.isEmpty ? 'postgrest' : 'pg_$code',
          technicalDetails: tech,
          cause: e,
        );
    }
  }

  // Supabase Auth (GoTrue) errors.
  if (e is sb.AuthException) {
    final msg = e.message.toLowerCase();
    final tech = 'AuthException status=${e.statusCode} message=${e.message}';
    if (msg.contains('invalid login credentials')) {
      return AuthException(
        'ای میل یا پاس ورڈ غلط ہے۔',
        userMessageEn: 'The email or password is incorrect.',
        code: 'invalid_credentials',
        technicalDetails: tech,
        cause: e,
      );
    }
    if (msg.contains('email not confirmed')) {
      return AuthException(
        'ای میل کی تصدیق نہیں ہوئی۔ برا کرم اپنا ان باکس چیک کریں۔',
        userMessageEn: 'Your email is not confirmed. Please check your inbox.',
        code: 'email_not_confirmed',
        technicalDetails: tech,
        cause: e,
      );
    }
    if (msg.contains('user not found') ||
        msg.contains('user already registered')) {
      return AuthException(
        code: 'auth_user',
        technicalDetails: tech,
        cause: e,
      );
    }
    if (msg.contains('too many requests') || e.statusCode == '429') {
      return AuthException(
        'بہت زیادہ کوششیں۔ تھوڑا انتظار کر کے دوبارہ کوشش کریں۔',
        userMessageEn: 'Too many attempts. Please wait a moment and try again.',
        code: 'rate_limited',
        technicalDetails: tech,
        cause: e,
      );
    }
    return AuthException(
      code: 'auth',
      technicalDetails: tech,
      cause: e,
    );
  }

  // Supabase Storage errors.
  if (e is sb.StorageException) {
    return DatabaseException(
      'فائل اپ لوڈ/ڈاؤن لوڈ نہیں ہو سکی۔',
      userMessageEn: 'The file could not be uploaded or downloaded.',
      code: 'storage',
      technicalDetails: 'StorageException status=${e.statusCode} message=${e.message}',
      cause: e,
    );
  }

  // Transport-level failures — never show raw socket text to users.
  if (e is SocketException) {
    return NetworkException(
      code: 'socket',
      technicalDetails: 'SocketException: ${e.message} (osError=${e.osError})',
      cause: e,
    );
  }
  if (e is TimeoutException) {
    return NetworkException(
      'درخواست کا وقت ختم ہو گیا۔ برا کرم دوبارہ کوشش کریں۔',
      userMessageEn: 'The request timed out. Please try again.',
      code: 'timeout',
      technicalDetails: 'TimeoutException after ${e.duration}',
      cause: e,
    );
  }
  if (e is http.ClientException) {
    return NetworkException(
      code: 'http_client',
      technicalDetails: 'http.ClientException: ${e.message}',
      cause: e,
    );
  }
  if (e is HandshakeException) {
    return NetworkException(
      'محفوظ کنکشن قائم نہیں ہو سکا۔',
      userMessageEn: 'A secure connection could not be established.',
      code: 'tls',
      technicalDetails: 'HandshakeException: ${e.message}',
      cause: e,
    );
  }
  if (e is TlsException) {
    return NetworkException(
      'محفوظ کنکشن قائم نہیں ہو سکا۔',
      userMessageEn: 'A secure connection could not be established.',
      code: 'tls',
      technicalDetails: 'TlsException: ${e.message}',
      cause: e,
    );
  }

  // Data-shape problems (parity with the pre-Phase-7 ErrorHandler).
  if (e is FormatException) {
    return ValidationException(
      'غلط ڈیٹا فارمیٹ۔',
      userMessageEn: 'Invalid data format.',
      code: 'format',
      technicalDetails: 'FormatException: ${e.message}',
      cause: e,
    );
  }
  if (e is TypeError) {
    return DatabaseException(
      'ڈیٹا ٹائپ کی خرابی۔',
      userMessageEn: 'A data-type error occurred.',
      code: 'type',
      technicalDetails: 'TypeError: $e',
      cause: e,
    );
  }

  return _UnknownException(
    technicalDetails: 'Unclassified ${e.runtimeType}: $e',
    cause: e,
  );
}
