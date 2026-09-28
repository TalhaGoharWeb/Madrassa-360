/// اطلاعات کے ماڈل
/// Notification models — Phase 6 / Worker 2 (notifications framework).
///
/// The canonical row type is the Drift-generated [LocalNotificationRow]
/// (see `lib/data/local/app_database.dart`, table `notifications`). This
/// file adds the shared vocabularies (channel ids, notification types,
/// dispatch outcomes) plus small extensions on the generated row so
/// channels never re-implement JSON decoding or Urdu fallback.

import 'dart:convert';

import '../../data/local/app_database.dart';

/// Well-known channel ids. 'sms' / 'whatsapp' are reserved for the future
/// extension (see sms_whatsapp_extension.md) — no implementation exists yet.
class NotificationChannelId {
  NotificationChannelId._();

  static const String inApp = 'in_app';
  static const String push = 'push';
  static const String email = 'email';

  // Reserved (documented extension point, not implemented):
  static const String sms = 'sms';
  static const String whatsapp = 'whatsapp';

  /// Channels the dispatcher can actually send through today.
  static const List<String> implemented = [inApp, push, email];

  /// Channels that need connectivity (server fan-out via Edge Function).
  static const List<String> remote = [push, email];
}

/// Well-known notification types produced by [NotificationTriggers].
/// The set is open — repositories may add types; the inbox UI renders any
/// type generically.
class NotificationType {
  NotificationType._();

  static const String feeInvoiceCreated = 'fee_invoice_created';
  static const String paymentReceived = 'payment_received';
  static const String resultPublished = 'result_published';
  static const String announcementPosted = 'announcement_posted';
  static const String backupCompleted = 'backup_completed';
}

/// Outbox row statuses (mirrors the CHECK constraint on
/// `notification_outbox.status`).
class OutboxStatus {
  OutboxStatus._();

  static const String pending = 'pending';
  static const String sending = 'sending';
  static const String sent = 'sent';
  static const String failed = 'failed';
  static const String skipped = 'skipped';
}

/// What a channel did with one notification.
enum DispatchOutcome {
  /// The channel delivered (or, for in-app, the record exists locally).
  sent,

  /// Deliberately not attempted: unsupported platform, user opted out,
  /// server reported the provider unconfigured, etc. Never retried.
  skipped,

  /// Attempted and failed: will be retried with backoff, then parked.
  failed,
}

/// Result of [NotificationChannel.send].
class ChannelDispatchResult {
  const ChannelDispatchResult._(this.outcome, this.reason);

  const ChannelDispatchResult.sent() : this._(DispatchOutcome.sent, null);

  const ChannelDispatchResult.skipped(String reason)
      : this._(DispatchOutcome.skipped, reason);

  const ChannelDispatchResult.failed(String reason)
      : this._(DispatchOutcome.failed, reason);

  final DispatchOutcome outcome;

  /// Machine-readable reason for skipped/failed (e.g.
  /// 'unsupported_platform', 'push_opted_out', 'email_unconfigured').
  final String? reason;

  bool get isSent => outcome == DispatchOutcome.sent;
  bool get isSkipped => outcome == DispatchOutcome.skipped;
  bool get isFailed => outcome == DispatchOutcome.failed;

  @override
  String toString() => 'ChannelDispatchResult($outcome, $reason)';
}

/// Convenience accessors on the generated Drift row.
extension LocalNotificationRowX on LocalNotificationRow {
  /// `true` when this row is a tenant broadcast (visible to every member).
  bool get isBroadcast => userId == null;

  /// `true` when the notification has been read on this device.
  /// Broadcast read state is local-only (server rows with
  /// user_id IS NULL freeze read_at — see 017_notifications.sql).
  bool get isRead => readAt != null;

  /// Decoded `data` JSON; `{}` on missing/corrupt payload (never throws).
  Map<String, dynamic> get dataMap {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {/* fall through */}
    return const {};
  }

  /// Urdu-first title: `title_urdu` wins when [urdu] and non-empty,
  /// otherwise the English `title`.
  String titleFor({required bool urdu}) {
    if (urdu && titleUrdu != null && titleUrdu!.trim().isNotEmpty) {
      return titleUrdu!;
    }
    return title;
  }

  /// Urdu-first body; falls back to English, then to `''`.
  String bodyFor({required bool urdu}) {
    if (urdu && bodyUrdu != null && bodyUrdu!.trim().isNotEmpty) {
      return bodyUrdu!;
    }
    return body ?? '';
  }

  DateTime get createdAtDate =>
      DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true).toLocal();
}
