import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_typography.dart';
import '../../../core/notifications/in_app_channel.dart';
import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_provider.dart';

/// اطلاعات — In-app notifications inbox (Phase 6).
///
/// Local-first: reads the on-device `notifications` table through
/// [inboxNotificationsProvider]. Works fully offline. Tapping a row marks
/// it read; the header action marks everything read. Urdu-first with an
/// English toggle, following the app-wide pattern.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _isUrdu = true;

  IconData _iconFor(String type) {
    switch (type) {
      case NotificationType.feeInvoiceCreated:
        return Icons.receipt_long_outlined;
      case NotificationType.paymentReceived:
        return Icons.payments_outlined;
      case NotificationType.resultPublished:
        return Icons.emoji_events_outlined;
      case NotificationType.announcementPosted:
        return Icons.campaign_outlined;
      case NotificationType.backupCompleted:
        return Icons.backup_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _timeAgo(DateTime dt, bool urdu) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return urdu ? 'ابھی' : 'now';
    if (d.inMinutes < 60) {
      return urdu ? '${d.inMinutes} منٹ قبل' : '${d.inMinutes}m ago';
    }
    if (d.inHours < 24) {
      return urdu ? '${d.inHours} گھنٹے قبل' : '${d.inHours}h ago';
    }
    final days = d.inDays;
    return urdu ? '$days دن قبل' : '${days}d ago';
  }

  Future<void> _markRead(LocalNotificationRow n) async {
    if (n.isRead) return;
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return;
    final db = ref.read(appDatabaseProvider);
    try {
      await InAppChannel(db).markRead(n.id, tenantId);
    } catch (_) {
      // Local write failed — the row simply stays unread; never crash the UI.
    }
  }

  Future<void> _markAllRead() async {
    final tenantId = ref.read(currentTenantIdProvider);
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (tenantId == null || userId == null) return;
    final db = ref.read(appDatabaseProvider);
    try {
      await InAppChannel(db).markAllRead(tenantId, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isUrdu
                ? 'سب پڑھی ہوئی قرار دے دی گئیں'
                : 'All marked as read'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isUrdu
                ? 'ناکام ہوا، دوبارہ کوشش کریں'
                : 'Failed, please retry'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxNotificationsProvider);
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isUrdu ? 'اطلاعات' : 'Notifications'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _isUrdu = !_isUrdu),
            child: Text(_isUrdu ? 'EN' : 'اردو'),
          ),
          if (unread > 0)
            IconButton(
              tooltip: _isUrdu ? 'سب پڑھی ہوئی' : 'Mark all read',
              icon: const Icon(Icons.done_all_outlined),
              onPressed: _markAllRead,
            ),
        ],
      ),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            _isUrdu
                ? 'اطلاعات لوڈ نہیں ہو سکیں'
                : 'Could not load notifications',
            style: AppTypography.bodyMedium,
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_outlined,
                      size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    _isUrdu ? 'کوئی اطلاع نہیں' : 'No notifications',
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isUrdu
                        ? 'فیس، نتائج اور اعلانات کی اطلاعات یہاں نظر آئیں گی'
                        : 'Fee, result and announcement updates will appear here',
                    style: AppTypography.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = rows[i];
              final read = n.isRead;
              return ListTile(
                leading: Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: read
                          ? Colors.grey.shade200
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        _iconFor(n.type),
                        color: read
                            ? Colors.grey.shade600
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (!read)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  n.titleFor(urdu: _isUrdu),
                  style: (read
                          ? AppTypography.bodyMedium
                          : AppTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.bold))
                      .copyWith(
                    fontFamily: _isUrdu ? 'JameelNooriNastaleeq' : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (n.bodyFor(urdu: _isUrdu).isNotEmpty)
                      Text(
                        n.bodyFor(urdu: _isUrdu),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          fontFamily: _isUrdu ? 'JameelNooriNastaleeq' : null,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      _timeAgo(n.createdAtDate, _isUrdu),
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.grey.shade600,
                        fontFamily: null,
                      ),
                    ),
                  ],
                ),
                onTap: () => _markRead(n),
              );
            },
          );
        },
      ),
    );
  }
}
