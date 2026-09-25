/// ای میل چینل
/// Email channel — server-side fan-out through the `send-notification`
/// Edge Function.
///
/// The app NEVER sends email directly (no SMTP credentials on device,
/// ever). [send] invokes the Edge Function with `channels: ['email']`;
/// the function resolves recipients (target user or tenant broadcast),
/// looks up their emails via the Auth admin API, and sends through the
/// configured provider (Resend via `RESEND_API_KEY` function secret).
///
/// When no email provider is configured server-side, the function
/// returns `status: 'email_unconfigured'` and this channel reports
/// `skipped` — a deliberate no-retry state, NOT a failure. The local
/// record still exists (in-app delivery), so nothing is lost.
///
/// [supportsPlatform] is true everywhere, including Windows desktop:
/// the actual sending happens on Supabase, not on the device.

import '../../data/local/app_database.dart';
import '../services/supabase_service.dart';
import 'notification_channel.dart';
import 'notification_models.dart';
import 'notification_queue.dart';

class EmailChannel extends NotificationChannel {
  @override
  String get id => NotificationChannelId.email;

  @override
  String get displayName => 'Email';

  @override
  String get displayNameUrdu => 'ای میل';

  /// True on every platform: delivery is server-side.
  @override
  bool supportsPlatform() => true;

  @override
  Future<ChannelDispatchResult> send(LocalNotificationRow notification) async {
    try {
      final res = await SupabaseService.client.functions.invoke(
        'send-notification',
        body: {
          'tenant_id': notification.tenantId,
          'notification_id': notification.id,
          'user_id': notification.userId, // null = broadcast
          'type': notification.type,
          'title': notification.title,
          'title_urdu': notification.titleUrdu,
          'body': notification.body,
          'body_urdu': notification.bodyUrdu,
          'data': notification.dataMap,
          'channels': ['email'],
        },
      );
      return _interpretFunctionResult(res.data);
    } catch (e) {
      return ChannelDispatchResult.failed('email_error: $e');
    }
  }

  @override
  Future<void> queue(AppDatabase db, LocalNotificationRow notification) {
    return NotificationOutboxStore.enqueue(
      db,
      tenantId: notification.tenantId,
      notificationId: notification.id,
      channel: id,
    );
  }

  ChannelDispatchResult _interpretFunctionResult(dynamic data) {
    try {
      final map = Map<String, dynamic>.from(data as Map);
      final channels = Map<String, dynamic>.from(map['channels'] as Map);
      final email = Map<String, dynamic>.from(channels['email'] as Map);
      if (email['sent'] == true) {
        return const ChannelDispatchResult.sent();
      }
      final status = '${email['status'] ?? 'unknown'}';
      // Config states ('email_unconfigured', 'no_recipients') are not
      // transient — skip instead of burning retries on them.
      return ChannelDispatchResult.skipped('email_$status');
    } catch (_) {
      return const ChannelDispatchResult.failed('bad_function_response');
    }
  }
}
