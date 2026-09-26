/// ڈیوائس صحت کے اشاریے
/// Client-side health metrics (Phase 7, mission §§46–47).
///
/// Lightweight in-memory counters persisted to SharedPreferences, surfaced
/// on the Master Admin dashboard ("Client health (this device)" card).
///
/// What each counter means — honestly:
/// * [crashFreeSessions]: sessions counted as crash-free because the
///   PREVIOUS session wrote a clean-exit marker before terminating. This
///   is a proxy, not a crash reporter: a kill -9, power loss, or an
///   unflushed marker all count as "not clean". Fleet-wide crash
///   reporting needs a real reporter (Crashlytics/Sentry) — out of scope.
/// * [syncFailures24h] / [authFailures24h] / [apiErrors24h]: rolling 24-hour
///   counts of classified failures seen on THIS device (bumped by
///   [ErrorBoundary] from the [AppException] taxonomy).
///
/// Fleet-wide aggregation is a FUTURE Edge Function: devices would POST
/// `toMap()` summaries and a platform table would roll them up. Until
/// then these counters are per-device only.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class HealthMetrics {
  HealthMetrics._();
  static final HealthMetrics instance = HealthMetrics._();

  static const _kCrashFree = 'health.crash_free_sessions';
  static const _kCleanExit = 'health.clean_exit_marker';
  static const _kSync = 'health.sync_failures_ts';
  static const _kAuth = 'health.auth_failures_ts';
  static const _kApi = 'health.api_errors_ts';

  static const _window = Duration(hours: 24);

  int crashFreeSessions = 0;
  final List<int> _syncFailures = [];
  final List<int> _authFailures = [];
  final List<int> _apiErrors = [];

  bool _loaded = false;

  int get syncFailures24h => _count24h(_syncFailures);
  int get authFailures24h => _count24h(_authFailures);
  int get apiErrors24h => _count24h(_apiErrors);

  /// Load persisted state. Idempotent; safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      crashFreeSessions = prefs.getInt(_kCrashFree) ?? 0;
      _readList(prefs, _kSync, _syncFailures);
      _readList(prefs, _kAuth, _authFailures);
      _readList(prefs, _kApi, _apiErrors);
    } catch (_) {
      // Metrics must never break the app; start from zero.
    }
  }

  /// Call once at app startup. If the previous session wrote a clean-exit
  /// marker, this session's start counts it as crash-free.
  ///
  /// NOTE: wire this in `main.dart` bootstrap (owned by the Phase-7 crash
  /// wiring worker) — `await HealthMetrics.instance.markSessionStarted();`
  /// before `runApp`, and `HealthMetrics.instance.markCleanShutdown()` on
  /// a graceful detach.
  Future<void> markSessionStarted() async {
    await load();
    try {
      final prefs = await SharedPreferences.getInstance();
      final cleanExit = prefs.getBool(_kCleanExit) ?? false;
      if (cleanExit) {
        crashFreeSessions++;
        await prefs.setInt(_kCrashFree, crashFreeSessions);
      }
      await prefs.setBool(_kCleanExit, false);
    } catch (_) {
      // Best effort only.
    }
  }

  /// Call on graceful shutdown so the NEXT session counts this one as
  /// crash-free. Best effort; never throws.
  Future<void> markCleanShutdown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCleanExit, true);
    } catch (_) {
      // Best effort only.
    }
  }

  /// A sync-cycle failure was classified (called by [ErrorBoundary]).
  void recordSyncFailure() => _record(_syncFailures, _kSync);

  /// An auth failure was classified (called by [ErrorBoundary]).
  void recordAuthFailure() => _record(_authFailures, _kAuth);

  /// A network/database API error was classified (called by [ErrorBoundary]).
  void recordApiError() => _record(_apiErrors, _kApi);

  /// Summary for the dashboard card / future fleet upload.
  Map<String, Object> toMap() => <String, Object>{
        'crash_free_sessions': crashFreeSessions,
        'sync_failures_24h': syncFailures24h,
        'auth_failures_24h': authFailures24h,
        'api_errors_24h': apiErrors24h,
      };

  // ── Internals ──────────────────────────────────────────────

  void _record(List<int> buffer, String key) {
    buffer.add(DateTime.now().millisecondsSinceEpoch);
    _prune(buffer);
    unawaited(_persistList(key, buffer));
  }

  int _count24h(List<int> buffer) {
    _prune(buffer);
    return buffer.length;
  }

  void _prune(List<int> buffer) {
    final cutoff = DateTime.now().subtract(_window).millisecondsSinceEpoch;
    buffer.removeWhere((ts) => ts < cutoff);
  }

  void _readList(SharedPreferences prefs, String key, List<int> buffer) {
    final raw = prefs.getStringList(key);
    if (raw == null) return;
    for (final s in raw) {
      final ts = int.tryParse(s);
      if (ts != null) buffer.add(ts);
    }
    _prune(buffer);
  }

  Future<void> _persistList(String key, List<int> buffer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          key, buffer.map((ts) => ts.toString()).toList());
    } catch (_) {
      // Best effort only.
    }
  }
}
