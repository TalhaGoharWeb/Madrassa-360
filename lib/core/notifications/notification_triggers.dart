/// اطلاع کے محرکات — local-first trigger API
/// (Phase 6 / Worker 2 — notifications framework).
///
/// LOCAL-FIRST CONTRACT: every trigger below writes the notification
/// record into the local SQLite `notifications` table AND enqueues
/// per-channel outbox rows in the SAME [AppDatabase.transaction] as the
/// caller's business write. Nothing here touches the network, so
/// recording a notification NEVER requires connectivity — offline-created
/// invoices/payments/results/announcements still produce their
/// notifications, which the [NotificationDispatcher] fans out when
/// connectivity returns.
///
/// CALL PATTERN (for repository authors):
/// ```dart
/// await db.transaction(() async {
///   await db.invoicesDao.upsert(...);          // the business write
///   await NotificationTriggers.onFeeInvoiceCreated(
///     db, tenantId: tenantId, invoiceId: ..., ...);  // same txn
/// });
/// unawaited(engine.syncNow()); // → syncCompleted → dispatcher drains
/// ```
/// The dispatcher drains on (a) connectivity regain, (b) the sync
/// engine's `syncCompleted` event, and (c) app resume — so the
/// opportunistic `syncNow()` repositories already perform after a write
/// is what carries queued push/email rows out.
///
/// DO NOT call these from a background isolate: they use the caller's
/// [AppDatabase] instance.
///
/// CALL SITES — wiring status as of Phase 6 merge:
/// * fee invoice created  → WIRED in LocalFinanceRepository.createInvoice
///   (lib/data/repositories/finance_repository.dart)
/// * payment received     → WIRED in LocalFinanceRepository.recordPayment
///   (lib/data/repositories/finance_repository.dart)
/// * result published     → NOT WIRED: no exam-publish flow exists yet
///   (results entry save is honestly stubbed — see TODO(phase-8)). Call
///   [onResultPublished] ONCE per exam from the future publish entry
///   point, never once per result row.
/// * announcement posted  → WIRED in AnnouncementNotifier.create
///   (lib/providers/announcement_provider.dart)
/// * backup completed     → WIRED in BackupService.createBackup, after the
///   manifest is written and before the [BackupResult] is returned
///   (lib/core/backup/backup_service.dart).
/// All call sites treat trigger failures as best-effort (try/catch): a
/// notification failure must never fail the business write.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import 'notification_models.dart';
import 'notification_queue.dart';

const _uuid = Uuid();

int _nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

String _formatAmount(double amount, String currency) =>
    '$currency ${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}';

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// One-line trigger API for business events. See the file header for the
/// call pattern and the exact call sites.
class NotificationTriggers {
  NotificationTriggers._();

  // ── shared record helper ───────────────────────────────────

  /// Inserts the local record + one outbox row per remote channel, in a
  /// single transaction. Returns the notification id.
  static Future<String> _record(
    AppDatabase db, {
    required String tenantId,
    String? recipientUserId, // null = tenant broadcast
    required String type,
    required String title,
    String? titleUrdu,
    String? body,
    String? bodyUrdu,
    Map<String, dynamic> data = const {},
  }) async {
    final id = _uuid.v4();
    final now = _nowMs();
    await db.transaction(() async {
      await db.notificationsDao.insert(
        NotificationsCompanion.insert(
          id: id,
          tenantId: tenantId,
          userId: Value(recipientUserId),
          type: type,
          title: title,
          titleUrdu: Value(titleUrdu),
          body: Value(body),
          bodyUrdu: Value(bodyUrdu),
          data: Value(jsonEncode(data)),
          createdAt: now,
        ),
      );
      // Remote fan-out is queued per channel; the dispatcher evaluates
      // preferences + platform support at drain time.
      for (final channel in NotificationChannelId.remote) {
        await NotificationOutboxStore.enqueue(
          db,
          tenantId: tenantId,
          notificationId: id,
          channel: channel,
        );
      }
    });
    return id;
  }

  // ── triggers ───────────────────────────────────────────────

  /// A fee invoice was issued. [recipientUserId] is the parent/student
  /// app user when known, else null (tenant broadcast for staff).
  /// Call inside the same transaction as the invoice write, from
  /// `FinanceRepository.createInvoice`.
  static Future<String> onFeeInvoiceCreated(
    AppDatabase db, {
    required String tenantId,
    required String invoiceId,
    required String studentId,
    String? studentName,
    String? recipientUserId,
    required double amount,
    String currency = 'Rs',
  }) {
    final who = (studentName != null && studentName.trim().isNotEmpty)
        ? studentName
        : 'طالب علم';
    final amt = _formatAmount(amount, currency);
    return _record(
      db,
      tenantId: tenantId,
      recipientUserId: recipientUserId,
      type: NotificationType.feeInvoiceCreated,
      title: 'New fee invoice',
      titleUrdu: 'نئی فیس کا بل',
      body: 'Invoice of $amt issued for $who.',
      bodyUrdu: '$who کے لیے $amt کا بل جاری کیا گیا۔',
      data: {'invoice_id': invoiceId, 'student_id': studentId},
    );
  }

  /// A payment was recorded against an invoice (or on account).
  /// Call inside the same transaction as the payment write, from
  /// `FinanceRepository.recordPayment`.
  static Future<String> onPaymentReceived(
    AppDatabase db, {
    required String tenantId,
    required String paymentId,
    String? invoiceId,
    required String studentId,
    String? studentName,
    String? recipientUserId,
    required double amount,
    String currency = 'Rs',
  }) {
    final who = (studentName != null && studentName.trim().isNotEmpty)
        ? studentName
        : 'طالب علم';
    final amt = _formatAmount(amount, currency);
    return _record(
      db,
      tenantId: tenantId,
      recipientUserId: recipientUserId,
      type: NotificationType.paymentReceived,
      title: 'Payment received',
      titleUrdu: 'ادائیگی موصول ہو گئی',
      body: '$amt received from $who.',
      bodyUrdu: '$who سے $amt کی ادائیگی موصول ہو گئی۔',
      data: {
        'payment_id': paymentId,
        if (invoiceId != null) 'invoice_id': invoiceId,
        'student_id': studentId,
      },
    );
  }

  /// An exam's results were published. This is an EXAM-level event: call
  /// it ONCE per publish (not once per result row) from the results
  /// publish flow. Null [recipientUserId] = tenant broadcast (parents /
  /// students see it in their inbox; per-recipient fan-out is deferred).
  static Future<String> onResultPublished(
    AppDatabase db, {
    required String tenantId,
    required String examId,
    String? examName,
    String? classId,
    String? recipientUserId,
  }) {
    final exam = (examName != null && examName.trim().isNotEmpty)
        ? examName
        : 'امتحان';
    return _record(
      db,
      tenantId: tenantId,
      recipientUserId: recipientUserId,
      type: NotificationType.resultPublished,
      title: 'Results published',
      titleUrdu: 'نتائج جاری',
      body: 'Results for "$exam" are now available.',
      bodyUrdu: '"$exam" کے نتائج جاری کر دیے گئے ہیں۔',
      data: {
        'exam_id': examId,
        if (classId != null) 'class_id': classId,
      },
    );
  }

  /// An announcement was posted. Broadcast to the tenant (null
  /// [recipientUserId]); pass a user id to target one recipient.
  /// Call from `AnnouncementNotifier.create` after the local write.
  static Future<String> onAnnouncementPosted(
    AppDatabase db, {
    required String tenantId,
    required String announcementId,
    required String title,
    String? titleUrdu,
    String? body,
    String? bodyUrdu,
    String? audience,
    String? recipientUserId,
  }) {
    return _record(
      db,
      tenantId: tenantId,
      recipientUserId: recipientUserId,
      type: NotificationType.announcementPosted,
      title: title,
      titleUrdu: titleUrdu,
      body: body,
      bodyUrdu: bodyUrdu,
      data: {
        'announcement_id': announcementId,
        if (audience != null) 'audience': audience,
      },
    );
  }

  /// A local backup finished. AGREED SIGNATURE with the backup worker
  /// (they own lib/core/backup/ — do not write their files): call this
  /// at the end of `BackupService.createBackup`, after the manifest is
  /// written, passing fields from the returned [BackupResult]-equivalent
  /// (`file.path`, `sizeBytes`, `cloudUploadId`). Broadcast (null
  /// [recipientUserId]) so tenant admins see it in their inbox.
  static Future<String> onBackupCompleted(
    AppDatabase db, {
    required String tenantId,
    required String filePath,
    required int sizeBytes,
    String? cloudUploadId,
    String? recipientUserId,
  }) {
    final size = _formatBytes(sizeBytes);
    final fileName = filePath.split('/').last;
    return _record(
      db,
      tenantId: tenantId,
      recipientUserId: recipientUserId,
      type: NotificationType.backupCompleted,
      title: 'Backup completed',
      titleUrdu: 'بیک اپ مکمل',
      body: 'Backup saved: $fileName ($size).',
      bodyUrdu: 'بیک اپ محفوظ ہو گیا: $fileName ($size)۔',
      data: {
        'file_path': filePath,
        'size_bytes': sizeBytes,
        if (cloudUploadId != null) 'cloud_upload_id': cloudUploadId,
      },
    );
  }
}
