/// اطلاع کی ترجیحات
/// Per-user, per-channel notification toggles.
///
/// Contract: a MISSING row means ENABLED (default-on). The preferences
/// screen therefore only ever writes rows for channels the user touched.
/// The dispatcher evaluates [isEnabled] at DRAIN time, so toggling a
/// channel takes effect immediately — even for rows already queued.
///
/// The local table mirrors `public.notification_preferences` (017).
/// DEFERRED: server sync of preferences (so one user's choice follows
/// them across devices). The server table + RLS already exist; the
/// client write path is intentionally not built yet — preferences are
/// per-device until then.

import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import 'notification_models.dart';

int _nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

class NotificationPreferences {
  NotificationPreferences(this._db);

  final AppDatabase _db;

  /// Whether [channel] is enabled for this user. Missing row → true.
  Future<bool> isEnabled({
    required String userId,
    required String tenantId,
    required String channel,
  }) async {
    final row =
        await _db.notificationPreferencesDao.get(userId, tenantId, channel);
    if (row == null) return true;
    return row.enabled == 1;
  }

  /// Persist the user's choice for one channel.
  Future<void> setEnabled({
    required String userId,
    required String tenantId,
    required String channel,
    required bool enabled,
  }) async {
    await _db.notificationPreferencesDao.set(
      NotificationPreferencesCompanion.insert(
        userId: userId,
        tenantId: tenantId,
        channel: channel,
        enabled: Value(enabled ? 1 : 0),
        updatedAt: _nowMs(),
      ),
    );
  }

  /// Live map of channel → enabled for the preferences UI. Channels the
  /// user never touched report `true` (default-on contract).
  Stream<Map<String, bool>> watchAll({
    required String userId,
    required String tenantId,
  }) {
    return _db.notificationPreferencesDao.watchAll(userId, tenantId).map(
      (rows) {
        final map = {
          for (final c in NotificationChannelId.implemented) c: true,
        };
        for (final r in rows) {
          map[r.channel] = r.enabled == 1;
        }
        return map;
      },
    );
  }
}
