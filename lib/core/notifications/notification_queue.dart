/// اطلاع کی قطار — offline outbox + reconnect dispatcher
/// (Phase 6 / Worker 2 — notifications framework).
///
/// OFFLINE-FIRST: [NotificationOutboxStore.enqueue] only writes SQLite —
/// it never touches the network, so triggers can record dispatch requests
/// while offline. [NotificationDispatcher.drainOutbox] runs when
/// connectivity returns and pushes each due row through its
/// [NotificationChannel].
///
/// CONNECTIVITY: the dispatcher reuses the SYNC ENGINE'S signals only —
/// it listens to [SyncEngine.events] (`pushCompleted` / `syncCompleted`).
/// The engine already watches `Connectivity().onConnectivityChanged`
/// (see lib/core/sync/sync_engine.dart `start()`) and auto-syncs on
/// regain, so its events ARE the connectivity signal for dispatch.
/// This dispatcher adds no new connectivity subscription, no polling, no
/// timers. One-shot `Connectivity().checkConnectivity()` calls are not
/// watchers — they just gate each drain.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../sync/sync_engine.dart';
import 'notification_channel.dart';
import 'notification_models.dart';
import 'notification_preferences.dart';

const _uuid = Uuid();

const int _maxAttempts = 5;
const int _baseBackoffMs = 5000; // 5s, 10s, 20s, 40s — then parked
const int _sendTimeoutSec = 30;
const int _pruneAfterMs = 7 * 24 * 60 * 60 * 1000; // 7 days
// Parked rows (attempts exhausted) get a far-future nextRetryAt so
// dueRows() never picks them up again; NULL keeps meaning "due now".
const int _parkedForMs = 10 * 365 * 24 * 60 * 60 * 1000; // ~10 years
const int _sendTimeoutSec = 30;
const int _pruneAfterMs = 7 * 24 * 60 * 60 * 1000; // 7 days
const int _staleSendingMs = 10 * 60 * 1000; // reclaim 'sending' older than this

int _nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

/// Static outbox helpers. Called by channels' [NotificationChannel.queue]
/// and by [NotificationTriggers] — always safe offline.
class NotificationOutboxStore {
  NotificationOutboxStore._();

  /// Insert a dispatch request for ([notificationId], [channel]).
  /// Idempotent: when a non-terminal row (pending/sending/failed) already
  /// exists for the pair, the call is a no-op — double-enqueue from a
  /// retried trigger can never double-send.
  static Future<void> enqueue(
    AppDatabase db, {
    required String tenantId,
    required String notificationId,
    required String channel,
  }) async {
    final existing = await db
        .customSelect(
          'SELECT 1 FROM notification_outbox '
          'WHERE notification_id = ? AND channel = ? '
          "AND status IN ('pending','sending','failed') AND attempts < 5 "
          'LIMIT 1',
          variables: [
            Variable.withString(notificationId),
            Variable.withString(channel),
          ],
        )
        .get();
    if (existing.isNotEmpty) return;
    await db.notificationOutboxDao.enqueue(
      NotificationOutboxCompanion.insert(
        id: _uuid.v4(),
        tenantId: tenantId,
        notificationId: notificationId,
        channel: channel,
        createdAt: _nowMs(),
      ),
    );
  }
}

/// Drains `notification_outbox` through the registered channels.
///
/// One instance per active tenant (see notification_providers.dart), same
/// lifecycle as the [SyncEngine]: created on tenant switch, disposed on
/// the next switch / logout.
class NotificationDispatcher {
  NotificationDispatcher({
    required AppDatabase db,
    required String tenantId,
    required String userId,
    required SyncEngine engine,
    required List<NotificationChannel> channels,
  })  : _db = db,
        _tenantId = tenantId,
        _userId = userId,
        _engine = engine,
        _channels = {for (final c in channels) c.id: c},
        _prefs = NotificationPreferences(db);

  final AppDatabase _db;
  final String _tenantId;
  final String _userId;
  final SyncEngine _engine;
  final Map<String, NotificationChannel> _channels;
  final NotificationPreferences _prefs;

  StreamSubscription<SyncEvent>? _engineSub;
  bool _started = false;
  bool _draining = false;
  bool _disposed = false;

  // ── lifecycle ──────────────────────────────────────────────

  /// Subscribes to the [SyncEngine]'s events (`pushCompleted` /
  /// `syncCompleted`) — the engine owns the only connectivity watcher and
  /// auto-syncs on regain, so those events ARE the connectivity signal.
  /// Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _engineSub = _engine.events.listen((event) {
      if (event == SyncEvent.syncCompleted ||
          event == SyncEvent.pushCompleted) {
        unawaited(drainOutbox());
      }
    });
  }

  /// Hook point for app-resume: wire to
  /// `WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` next to
  /// the sync engine's `notifyAppResumed`.
  void notifyAppResumed() {
    if (!_started || _disposed) return;
    unawaited(drainOutbox());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engineSub?.cancel();
  }

  // ── public API ─────────────────────────────────────────────

  /// Record dispatch requests for [notification] on [channels]
  /// (default: every remote channel) and opportunistically drain.
  /// Fully offline-safe.
  Future<void> dispatchNow(
    LocalNotificationRow notification, {
    List<String>? channels,
  }) async {
    if (_disposed) return;
    for (final ch in channels ?? NotificationChannelId.remote) {
      await NotificationOutboxStore.enqueue(
        _db,
        tenantId: _tenantId,
        notificationId: notification.id,
        channel: ch,
      );
    }
    unawaited(drainOutbox());
  }

  /// Push every due outbox row through its channel. No-op while offline
  /// or when a drain is already running.
  Future<void> drainOutbox() async {
    if (_draining || _disposed) return;
    if (!await _isOnline()) return;
    _draining = true;
    try {
      // Crash recovery: rows stuck in 'sending' (process died mid-send)
      // go back to 'failed' with an expired backoff so they retry.
      await _db.notificationOutboxDao
          .reclaimStaleSending(_tenantId, _nowMs() - _staleSendingMs);
      final due =
          await _db.notificationOutboxDao.dueRows(_tenantId, _nowMs());
      for (final row in due) {
        await _dispatchRow(row);
        if (!await _isOnline()) return; // went offline mid-drain
      }
      // Bound table growth: drop old terminal rows.
      await _db.notificationOutboxDao
          .pruneTerminal(_tenantId, _nowMs() - _pruneAfterMs);
    } finally {
      _draining = false;
    }
  }

  // ── internals ──────────────────────────────────────────────

  Future<void> _dispatchRow(NotificationOutboxEntry row) async {
    final dao = _db.notificationOutboxDao;
    final channel = _channels[row.channel];

    // Unknown channel id or platform without an implementation:
    // skip permanently (never retried).
    if (channel == null || !channel.supportsPlatform()) {
      await dao.markSkipped(
          row.id, channel == null ? 'unknown_channel' : 'unsupported_platform');
      return;
    }

    // Per-user opt-out is evaluated at DRAIN time (not record time), so a
    // toggle takes effect immediately, even for already-queued rows.
    if (!await _prefs.isEnabled(
        userId: _userId, tenantId: _tenantId, channel: row.channel)) {
      await dao.markSkipped(row.id, 'channel_opted_out');
      return;
    }

    final notification =
        await _db.notificationsDao.getById(row.notificationId, _tenantId);
    if (notification == null) {
      await dao.markSkipped(row.id, 'notification_deleted');
      return;
    }

    await dao.markSending(row.id);
    ChannelDispatchResult result;
    try {
      result = await channel
          .send(notification)
          .timeout(const Duration(seconds: _sendTimeoutSec),
              onTimeout: () => const ChannelDispatchResult.failed(
                  'channel_timeout'));
    } catch (e) {
      // Channels must not throw (contract), but the dispatcher is the
      // last line of defence — never let one row kill the drain.
      result = ChannelDispatchResult.failed('channel_threw: $e');
    }

    switch (result.outcome) {
      case DispatchOutcome.sent:
        await dao.markSent(row.id);
        break;
      case DispatchOutcome.skipped:
        await dao.markSkipped(row.id, result.reason ?? 'skipped');
        break;
      case DispatchOutcome.failed:
        final attempts = row.attempts + 1;
        if (attempts >= _maxAttempts) {
          // Parked: a far-future nextRetryAt means "never auto-retry"
          // (dueRows only picks rows whose backoff has expired). The row
          // stays visible for debugging via the outbox table.
          await dao.markFailed(row.id, attempts,
              _nowMs() + _parkedForMs, result.reason ?? 'failed');
        } else {
          final backoffMs = _baseBackoffMs * (1 << (attempts - 1));
          await dao.markFailed(row.id, attempts,
              _nowMs() + backoffMs, result.reason ?? 'failed');
        }
        break;
    }
  }

  /// Same version-tolerant check as SyncEngine._isOnline().
  Future<bool> _isOnline() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity();
      final results = result is List ? result : [result];
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
