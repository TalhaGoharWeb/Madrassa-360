/// اطلاعات — In-app notifications inbox.
///
/// Local-first: reads the on-device `notifications` table through
/// [inboxNotificationsProvider]. Works fully offline. Tapping a row marks
/// it read; the toolbar action marks everything read. Urdu-first with an
/// English toggle. Renders inside [AppShell] via [ShellPageBody].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/notifications/in_app_channel.dart';
import '../../../core/notifications/notification_models.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_provider.dart';
import '../../shell/shell_page_body.dart';

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
        showM360SnackBar(
          context,
          _isUrdu ? 'سب پڑھی ہوئی قرار دے دی گئیں' : 'All marked as read',
        );
      }
    } catch (_) {
      if (mounted) {
        showM360SnackBar(
          context,
          _isUrdu ? 'ناکام ہوا، دوبارہ کوشش کریں' : 'Failed, please retry',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxNotificationsProvider);
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return ShellPageBody(
      actions: [
        M360TertiaryButton(
          label: _isUrdu ? 'EN' : 'اردو',
          onPressed: () => setState(() => _isUrdu = !_isUrdu),
        ),
        if (unread > 0)
          M360IconButton(
            icon: Icons.done_all_outlined,
            tooltip: _isUrdu ? 'سب پڑھی ہوئی' : 'Mark all read',
            onPressed: _markAllRead,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PageHeader(
              title: _isUrdu ? 'اطلاعات' : 'Notifications',
              description: unread > 0
                  ? (_isUrdu
                      ? '$unread نئی اطلاعات'
                      : '$unread unread notifications')
                  : (_isUrdu
                      ? 'فیس، نتائج اور اعلانات کی تازہ اطلاعات'
                      : 'Latest fee, result and announcement updates'),
            ),
          ),
          Expanded(
            child: inbox.when(
              loading: () => const M360LoadingState(),
              error: (e, _) => M360ErrorState(
                message: _isUrdu
                    ? 'اطلاعات لوڈ نہیں ہو سکیں'
                    : 'Could not load notifications',
                onRetry: () => ref.invalidate(inboxNotificationsProvider),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return M360EmptyState(
                    icon: Icons.notifications_none_outlined,
                    title: _isUrdu ? 'کوئی اطلاع نہیں' : 'No notifications',
                    description: _isUrdu
                        ? 'فیس، نتائج اور اعلانات کی اطلاعات یہاں نظر آئیں گی'
                        : 'Fee, result and announcement updates will appear here',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _NotificationCard(
                    notification: rows[i],
                    isUrdu: _isUrdu,
                    timeAgo: _timeAgo(rows[i].createdAtDate, _isUrdu),
                    icon: _iconFor(rows[i].type),
                    onTap: () => _markRead(rows[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.isUrdu,
    required this.timeAgo,
    required this.icon,
    required this.onTap,
  });

  final LocalNotificationRow notification;
  final bool isUrdu;
  final String timeAgo;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final read = n.isRead;
    final titleStyle = (isUrdu
            ? AppTypography.labelNastaliq.copyWith(fontSize: 16)
            : AppTypography.bodyMedium)
        .copyWith(
      fontWeight: read ? FontWeight.normal : FontWeight.bold,
      color: read ? AppColors.textSecondary : AppColors.textPrimary,
    );

    return M360TappableCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: read
                      ? AppColors.divider.withValues(alpha: 0.4)
                      : AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: read ? AppColors.textSecondary : AppColors.primary,
                ),
              ),
              if (!read)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.titleFor(urdu: isUrdu), style: titleStyle),
                if (n.bodyFor(urdu: isUrdu).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    n.bodyFor(urdu: isUrdu),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  timeAgo,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
