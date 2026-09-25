/// اطلاعات فراہم کنندگان
/// Notification Riverpod providers — Phase 6 / Worker 2.
///
/// Lifecycle mirrors [syncEngineProvider]: one [NotificationDispatcher]
/// per active tenant, created on tenant switch and disposed on the next
/// switch / logout, so dispatch can never touch the wrong tenant's
/// outbox. Null when logged out / no tenant yet — repositories treat a
/// null dispatcher as "recorded locally, dispatch later".

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';
import '../services/supabase_service.dart';
import '../services/tenant_context.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_providers.dart';
import 'email_channel.dart';
import 'in_app_channel.dart';
import 'notification_models.dart';
import 'notification_preferences.dart';
import 'notification_queue.dart';
import 'push_channel.dart';

/// Current user's id, or null when logged out. Push token registration
/// and preference evaluation both need it.
final _currentUserIdProvider = Provider<String?>((ref) {
  return SupabaseService.client.auth.currentUser?.id;
});

/// One [NotificationDispatcher] per active tenant. Starts its
/// connectivity + sync-event subscriptions on creation; disposed (and
/// therefore unsubscribed) on tenant switch / logout.
final notificationDispatcherProvider =
    Provider<NotificationDispatcher?>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final String? tenantId = ref.watch(currentTenantIdProvider);
  final SyncEngine? engine = ref.watch(syncEngineProvider);
  final String? userId = ref.watch(_currentUserIdProvider);
  if (tenantId == null || engine == null || userId == null) return null;
  final dispatcher = NotificationDispatcher(
    db: db,
    tenantId: tenantId,
    userId: userId,
    engine: engine,
    channels: [
      InAppChannel(db),
      PushChannel(tenantId: tenantId, userId: userId),
      EmailChannel(),
    ],
  );
  dispatcher.start();
  ref.onDispose(dispatcher.dispose);
  return dispatcher;
});

/// Live unread badge count (own + tenant broadcasts).
final unreadNotificationsCountProvider = StreamProvider<int>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final String? tenantId = ref.watch(currentTenantIdProvider);
  final String? userId = ref.watch(_currentUserIdProvider);
  if (tenantId == null || userId == null) return Stream.value(0);
  return db.notificationsDao.watchUnreadCount(tenantId, userId);
});

/// Live inbox (own + tenant broadcasts, newest first).
final inboxNotificationsProvider =
    StreamProvider<List<LocalNotificationRow>>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final String? tenantId = ref.watch(currentTenantIdProvider);
  final String? userId = ref.watch(_currentUserIdProvider);
  if (tenantId == null || userId == null) {
    return Stream.value(const <LocalNotificationRow>[]);
  }
  return db.notificationsDao.watchInbox(tenantId, userId);
});

/// Live channel → enabled map for the preferences UI (missing = true).
final notificationPreferencesProvider =
    StreamProvider<Map<String, bool>>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final String? tenantId = ref.watch(currentTenantIdProvider);
  final String? userId = ref.watch(_currentUserIdProvider);
  if (tenantId == null || userId == null) {
    return Stream.value(
        {for (final c in NotificationChannelId.implemented) c: true});
  }
  return NotificationPreferences(db)
      .watchAll(userId: userId, tenantId: tenantId);
});
