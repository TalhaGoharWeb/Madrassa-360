/// اطلاع کا چینل (بنیادی تعریف)
/// NotificationChannel — the abstract delivery channel contract.
///
/// A channel is one way a notification reaches a user: in-app inbox,
/// push (FCM), email (server-side), and later sms / whatsapp (see
/// sms_whatsapp_extension.md). The [NotificationDispatcher] drives every
/// channel through this interface; adding a channel never touches the
/// dispatcher.

import '../../data/local/app_database.dart';
import 'notification_models.dart';

/// Delivery contract for one notification channel.
///
/// OFFLINE-FIRST contract:
/// * [queue] must NEVER require connectivity — it only persists an
///   outbox row. (The in-app channel's [queue] is a documented no-op:
///   the local record IS the delivery.)
/// * [send] performs the actual delivery attempt. It may require
///   connectivity; failures are reported as [ChannelDispatchResult.failed]
///   so the dispatcher can back off and retry.
/// * [supportsPlatform] gates everything: the dispatcher never calls
///   [send] on a channel that reports false (e.g. push on Windows, where
///   firebase_messaging has no implementation).
abstract class NotificationChannel {
  /// Stable id: 'in_app' | 'push' | 'email' (+ future 'sms'/'whatsapp').
  /// Matches [NotificationChannelId] and the `notification_outbox.channel`
  /// column / server `notification_preferences.channel` values.
  String get id;

  /// English display name for the preferences UI.
  String get displayName;

  /// Urdu display name for the preferences UI.
  String get displayNameUrdu;

  /// Whether this channel can deliver on the current platform.
  /// Checked before every [send]; false → the outbox row is marked
  /// 'skipped' (never retried).
  bool supportsPlatform();

  /// Attempt delivery of one notification. Must not throw — every
  /// failure mode is a [ChannelDispatchResult].
  Future<ChannelDispatchResult> send(LocalNotificationRow notification);

  /// Persist a dispatch request for later (offline-safe).
  ///
  /// Default implementation is a no-op; remote channels override it to
  /// insert a `notification_outbox` row. The in-app channel keeps the
  /// default: its record in the local `notifications` table IS the
  /// delivery, so there is nothing to queue.
  Future<void> queue(AppDatabase db, LocalNotificationRow notification) async {}
}
