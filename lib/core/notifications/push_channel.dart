/// پش اطلاعات (FCM)
/// Push channel via Firebase Cloud Messaging.
///
/// ARCHITECTURE (why the client doesn't "send" FCM directly): a device
/// cannot fan out push to OTHER users' devices — that needs the Firebase
/// Admin SDK + service-account key, which must never ship in the app.
/// So [send] does the two client-side jobs and delegates fan-out:
///   1. registers this device's FCM token in `notification_device_tokens`
///      (RLS: users write only their own tokens), and
///   2. invokes the `send-notification` Edge Function with
///      `channels: ['push']`, which inserts the server row and fans out
///      via the FCM HTTP v1 API (server-side, key in function secrets).
///
/// PLATFORM SUPPORT — verified 2026-09-25 against pub.dev:
/// firebase_messaging declares support for Android, iOS, macOS and Web
/// ONLY. It has NO Windows or Linux implementation, so ANY call into it
/// on Windows throws MissingPluginException at runtime. The Windows
/// desktop build itself is unaffected (Flutter simply doesn't register
/// the plugin), but this channel reports [supportsPlatform] == false
/// there and the dispatcher marks push rows 'skipped' — a documented
/// no-op, never a crash. Web is also disabled for now: FCM on web needs
/// a firebase-messaging-sw.js service worker + VAPID key, which is
/// app-bootstrap work deferred to the push-enablement task.
///
/// SDK COMPATIBILITY (verified 2026-09-25 via the pub.dev API):
/// * firebase_messaging 15.2.10 (latest 15.x, pin `^15.2.0`) documents
///   Dart >= 3.2.0 (< 4.0.0) — intersects this app's `sdk: ^3.5.0`
///   (>= 3.5.0 < 4.0.0) and the team's resolved toolchain
///   (pubspec.lock: Dart >= 3.7.0). It depends on
///   `firebase_core: ^3.15.2`, pinned to match.
/// * The current 16.x line (firebase_core ^4.14.0, analysed with Dart
///   3.13.3) was deliberately NOT pinned: its exact Dart lower bound is
///   unverified and may exceed the team's Dart 3.7.
/// * `flutter pub get` / `flutter analyze` could NOT be run here (no
///   Flutter toolchain in this environment) — version resolution must be
///   confirmed on a dev machine before merge.
///
/// BOOTSTRAP CONTRACT (for whoever wires this into main.dart):
/// call `Firebase.initializeApp()` ONLY on supported platforms
/// (i.e. behind `PushChannel.supportsPlatform()`), and call
/// [requestPermission] once on first launch. Never initialize Firebase
/// on Windows — it throws there.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;

import '../../data/local/app_database.dart';
import '../services/supabase_service.dart';
import 'notification_channel.dart';
import 'notification_models.dart';
import 'notification_queue.dart';

class PushChannel extends NotificationChannel {
  PushChannel({
    required String tenantId,
    required String userId,
  })  : _tenantId = tenantId,
        _userId = userId;

  final String _tenantId;
  final String _userId;

  @override
  String get id => NotificationChannelId.push;

  @override
  String get displayName => 'Push notifications';

  @override
  String get displayNameUrdu => 'پش اطلاعات';

  /// False on Windows/Linux (no firebase_messaging implementation —
  /// documented no-op) and on Web (service-worker setup deferred).
  @override
  bool supportsPlatform() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Ask the OS for notification permission. Call once from app
  /// bootstrap (on supported platforms only); safe to call repeatedly.
  Future<bool> requestPermission() async {
    if (!supportsPlatform()) return false;
    try {
      if (Firebase.apps.isEmpty) return false;
      final settings = await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus ==
          AuthorizationStatus.authorized;
    } on MissingPluginException {
      return false; // defensive: unreachable behind supportsPlatform()
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ChannelDispatchResult> send(
      LocalNotificationRow notification) async {
    if (!supportsPlatform()) {
      return const ChannelDispatchResult.skipped('unsupported_platform');
    }
    try {
      if (Firebase.apps.isEmpty) {
        return const ChannelDispatchResult.failed(
            'firebase_not_initialized');
      }
      final messaging = FirebaseMessaging.instance;

      // 1. This device's token → server registry (own row; RLS write_own).
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        return const ChannelDispatchResult.failed('no_fcm_token');
      }
      await SupabaseService.client
          .from('notification_device_tokens')
          .upsert(
        {
          'user_id': _userId,
          'tenant_id': _tenantId,
          'token': token,
          'platform': _platformName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );

      // 2. Server-side fan-out through the Edge Function. The local
      // notification id doubles as the server row id (idempotent upsert).
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
          'channels': ['push'],
        },
      );
      return _interpretFunctionResult(res.data);
    } on MissingPluginException {
      // Defensive: supportsPlatform() already excludes platforms without
      // the plugin. Never retried — would fail identically next time.
      return const ChannelDispatchResult.skipped('unsupported_platform');
    } catch (e) {
      return ChannelDispatchResult.failed('push_error: $e');
    }
  }

  @override
  Future<void> queue(
      AppDatabase db, LocalNotificationRow notification) {
    return NotificationOutboxStore.enqueue(
      db,
      tenantId: notification.tenantId,
      notificationId: notification.id,
      channel: id,
    );
  }

  String get _platformName {
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    return 'android';
  }

  ChannelDispatchResult _interpretFunctionResult(dynamic data) {
    try {
      final map = Map<String, dynamic>.from(data as Map);
      final channels = Map<String, dynamic>.from(map['channels'] as Map);
      final push = Map<String, dynamic>.from(channels['push'] as Map);
      if (push['sent'] == true) {
        return const ChannelDispatchResult.sent();
      }
      final status = '${push['status'] ?? 'unknown'}';
      // 'no_fcm_configured' / 'no_recipients' are config states, not
      // transient errors — skip rather than burn retries on them.
      return ChannelDispatchResult.skipped('push_$status');
    } catch (_) {
      return const ChannelDispatchResult.failed('bad_function_response');
    }
  }
}
