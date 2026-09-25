/// ان ایپ اطلاعاتی چینل
/// In-app channel — the local-Drfit-table-driven channel.
///
/// Delivery model: the notification RECORD in the local `notifications`
/// table IS the delivery. [send] is therefore an immediate success (the
/// trigger already wrote the row); [queue] keeps the interface default
/// no-op. Works on every platform, online or offline — this is what makes
/// the framework offline-first even when push/email are unavailable.
///
/// Also owns the inbox read helpers the UI needs: unread badge counts and
/// mark-read operations.

import '../../data/local/app_database.dart';
import 'notification_channel.dart';
import 'notification_models.dart';

int _nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

class InAppChannel extends NotificationChannel {
  InAppChannel(this._db);

  final AppDatabase _db;

  @override
  String get id => NotificationChannelId.inApp;

  @override
  String get displayName => 'In-app';

  @override
  String get displayNameUrdu => 'ایپ میں';

  /// Always supported: pure local SQLite, no platform services involved.
  @override
  bool supportsPlatform() => true;

  /// The record already exists locally (written by the trigger) — the
  /// notification is, by definition, delivered to the inbox.
  @override
  Future<ChannelDispatchResult> send(LocalNotificationRow notification) async {
    final row =
        await _db.notificationsDao.getById(notification.id, notification.tenantId);
    if (row == null) {
      return const ChannelDispatchResult.failed('notification_missing');
    }
    return const ChannelDispatchResult.sent();
  }

  // queue() intentionally keeps the default no-op: nothing to persist
  // beyond the record itself.

  // ── inbox helpers (used by the UI + badge providers) ──────────

  /// Live unread count for the badge (own + tenant broadcasts).
  Stream<int> watchUnreadCount(String tenantId, String userId) =>
      _db.notificationsDao.watchUnreadCount(tenantId, userId);

  /// Live inbox stream (own + tenant broadcasts, newest first).
  Stream<List<LocalNotificationRow>> watchInbox(
          String tenantId, String userId) =>
      _db.notificationsDao.watchInbox(tenantId, userId);

  Future<List<LocalNotificationRow>> listInbox(
          String tenantId, String userId) =>
      _db.notificationsDao.listInbox(tenantId, userId);

  Future<void> markRead(String id, String tenantId) =>
      _db.notificationsDao.markRead(id, tenantId, _nowMs());

  Future<void> markAllRead(String tenantId, String userId) =>
      _db.notificationsDao.markAllRead(tenantId, userId, _nowMs());
}
