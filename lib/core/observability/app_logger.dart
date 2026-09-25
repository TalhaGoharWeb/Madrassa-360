/// File-based application logger with rotation and secret redaction.
///
/// Log files live under the per-OS application-support directory, inside a
/// `Madrassa360/logs` folder — on Windows this resolves under `%APPDATA%`,
/// next to the Drift database (see `lib/data/local/database_provider.dart`).
/// Business data and logs NEVER go under Program Files.
///
/// Rotation: at most 5 files × 2 MiB (`madrassa360.log`,
/// `madrassa360.1.log` … `madrassa360.4.log`); oldest is dropped.
/// Crash reports go to `logs/crashes/crash_<timestamp>.log`.
///
/// REDACTION: every logged message / context / error / stack trace passes
/// through [redact], which masks values for keys matching
/// password|token|secret|api[_-]?key|authorization|bearer — including inline
/// `key=value` fragments inside free-form strings. Never log raw
/// exceptions with stack traces containing tokens.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Log severity, ascending.
enum LogLevel { debug, info, warning, error, fatal }

class AppLogger {
  AppLogger._();
  static final AppLogger _instance = AppLogger._();

  /// Singleton accessor: `AppLogger().info('…')`.
  factory AppLogger() => _instance;

  // ── rotation policy ──────────────────────────────────────────────
  static const int maxFiles = 5;
  static const int maxBytesPerFile = 2 * 1024 * 1024;

  static final RegExp _sensitiveKey = RegExp(
    r'password|passwd|pwd|token|secret|api[_-]?key|authorization|bearer|private[_-]?key',
    caseSensitive: false,
  );

  /// Matches inline `key=value` / `key: value` / `"key": "value"` fragments
  /// inside free-form strings (error messages, stack traces, URLs).
  static final RegExp _inlineSecret = RegExp(
    r'''(password|passwd|pwd|token|secret|api[_-]?key|authorization|bearer|private[_-]?key)\s*['"]?\s*[:=]\s*['"]?([^\s'",;}\]]+)''',
    caseSensitive: false,
  );

  static const String mask = '***REDACTED***';

  bool _initialized = false;
  bool _initializing = false;
  File? _file;
  IOSink? _sink;
  Directory? _logDir;
  String _version = 'unknown';
  String? _tenantId;
  final List<String> _pending = [];

  // ── lifecycle ────────────────────────────────────────────────────

  /// Opens (and rotates) the log file and writes the session-start marker.
  /// Safe to call repeatedly; the second call while initializing waits.
  Future<void> init({String? version}) async {
    if (_initialized) return;
    if (_initializing) {
      while (_initializing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _initializing = true;
    try {
      if (version != null) _version = version;
      final support = await getApplicationSupportDirectory();
      _logDir = Directory(p.join(support.path, 'Madrassa360', 'logs'));
      await _logDir!.create(recursive: true);
      _file = File(p.join(_logDir!.path, 'madrassa360.log'));
      await _rotateIfNeeded();
      _sink = _file!.openWrite(mode: FileMode.append);
      _initialized = true;
      _writeLine(_sessionMarker('SESSION START'));
      for (final line in _pending) {
        _sink!.writeln(line);
      }
      _pending.clear();
      await _sink!.flush();
    } catch (_) {
      // Logging must never crash the app; file logging stays disabled.
      _initialized = false;
    } finally {
      _initializing = false;
    }
  }

  /// Records the active tenant id for subsequent log lines.
  /// Tenant ids are organisation identifiers, NOT user PII.
  void setTenantId(String? tenantId) {
    if (tenantId == _tenantId) return;
    _tenantId = tenantId;
    if (_initialized) {
      _writeLine(_format(LogLevel.info, 'tenant context: ${_tenantId ?? 'unknown'}'));
    }
  }

  Future<void> close() async {
    try {
      if (_initialized) _writeLine(_sessionMarker('SESSION END'));
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {
      // ignore — logger shutdown is best-effort
    } finally {
      _sink = null;
      _initialized = false;
    }
  }

  // ── public API ───────────────────────────────────────────────────

  void debug(String message, {Map<String, Object?>? context}) =>
      _log(LogLevel.debug, message, context: context);

  void info(String message, {Map<String, Object?>? context}) =>
      _log(LogLevel.info, message, context: context);

  void warning(String message,
          {Map<String, Object?>? context, Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.warning, message,
          context: context, error: error, stackTrace: stackTrace);

  void error(String message,
          {Map<String, Object?>? context, Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.error, message,
          context: context, error: error, stackTrace: stackTrace);

  void fatal(String message,
          {Map<String, Object?>? context, Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.fatal, message,
          context: context, error: error, stackTrace: stackTrace);

  /// Writes a timestamped crash report under `logs/crashes/`.
  /// Also appends a one-line pointer to the main log.
  Future<void> logCrash(String source, Object error, StackTrace? stack) async {
    final ts = DateTime.now();
    final stamp = _stamp(ts);
    try {
      final dir = _logDir ??
          Directory(p.join((await getApplicationSupportDirectory()).path,
              'Madrassa360', 'logs'));
      final crashDir = Directory(p.join(dir.path, 'crashes'));
      await crashDir.create(recursive: true);
      final report = File(p.join(crashDir.path, 'crash_$stamp.log'));
      final buf = StringBuffer()
        ..writeln('═' * 72)
        ..writeln('CRASH REPORT — Madrassa 360 $_version')
        ..writeln('source   : $source')
        ..writeln('time     : ${ts.toIso8601String()}')
        ..writeln('tenant   : ${_tenantId ?? 'unknown'}')
        ..writeln('─' * 72)
        ..writeln(redact('error: $error'))
        ..writeln('─' * 72)
        ..writeln(redact('stack:\n${stack ?? StackTrace.current}'))
        ..writeln('═' * 72);
      await report.writeAsString(buf.toString());
      _log(LogLevel.fatal, 'crash report written: ${report.path}',
          context: {'source': source});
    } catch (_) {
      // best-effort; never throw from crash reporting
    }
  }

  // ── redaction (pure, unit-testable) ──────────────────────────────

  /// Recursively masks values whose keys look like secrets.
  ///
  /// Handles nested [Map]s and [Iterable]s; free-form strings are scanned
  /// for inline `key=value`-style fragments. Everything else passes
  /// through untouched. Pure function — safe to unit test.
  static Object? redact(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(
          k, _sensitiveKey.hasMatch('$k') ? mask : redact(v)));
    }
    if (value is Iterable) {
      return value.map(redact).toList();
    }
    if (value is String) {
      return _inlineSecret.hasMatch(value)
          ? value.replaceAllMapped(
              _inlineSecret, (m) => '${m.group(1)}=$mask')
          : value;
    }
    return value;
  }

  // ── internals ────────────────────────────────────────────────────

  void _log(LogLevel level, String message,
      {Map<String, Object?>? context, Object? error, StackTrace? stackTrace}) {
    try {
      final buf = StringBuffer(_format(level, message));
      if (context != null && context.isNotEmpty) {
        buf.write(' | ctx=${redact(context)}');
      }
      if (error != null) {
        buf.write(' | err=${redact('$error')}');
      }
      if (stackTrace != null) {
        buf.write('\n${redact('$stackTrace')}');
      }
      _writeLine(buf.toString());
    } catch (_) {
      // never throw from the logger
    }
  }

  String _format(LogLevel level, String message) {
    final ts = DateTime.now().toIso8601String();
    final redacted = redact('$message');
    return '[$ts] [${level.name.toUpperCase()}] [tenant=${_tenantId ?? 'unknown'}] $redacted';
  }

  String _sessionMarker(String kind) {
    final ts = DateTime.now().toIso8601String();
    return '═' * 24 +
        ' $kind $ts | Madrassa 360 $_version | tenant=${_tenantId ?? 'unknown'} ' +
        '═' * 24;
  }

  void _writeLine(String line) {
    try {
      if (_initialized && _sink != null) {
        _sink!.writeln(line);
        _maybeRotateAsync();
      } else {
        // Buffer early-startup lines (bounded) until init() opens the file.
        if (_pending.length < 500) _pending.add(line);
      }
    } catch (_) {
      // never throw from the logger
    }
  }

  String _stamp(DateTime ts) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${ts.year}${two(ts.month)}${two(ts.day)}_'
        '${two(ts.hour)}${two(ts.minute)}${two(ts.second)}';
  }

  Future<void> _rotateIfNeeded() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    if (await file.length() < maxBytesPerFile) return;
    await _rotate();
  }

  void _maybeRotateAsync() {
    // Cheap periodic check: only stat the file every ~50 lines.
    _lineCount++;
    if (_lineCount % 50 == 0) {
      unawaited(_rotateIfNeeded());
    }
  }

  int _lineCount = 0;

  /// madrassa360.log → .1 → .2 → .3 → .4 (oldest dropped).
  Future<void> _rotate() async {
    try {
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      final dir = _logDir!;
      final oldest = File(p.join(dir.path, 'madrassa360.${maxFiles - 1}.log'));
      if (await oldest.exists()) await oldest.delete();
      for (var i = maxFiles - 2; i >= 1; i--) {
        final src = File(p.join(dir.path, 'madrassa360.$i.log'));
        if (await src.exists()) {
          await src.rename(p.join(dir.path, 'madrassa360.${i + 1}.log'));
        }
      }
      if (await _file!.exists()) {
        await _file!.rename(p.join(dir.path, 'madrassa360.1.log'));
      }
      _sink = _file!.openWrite(mode: FileMode.append);
    } catch (_) {
      try {
        _sink ??= _file?.openWrite(mode: FileMode.append);
      } catch (_) {}
    }
  }
}
