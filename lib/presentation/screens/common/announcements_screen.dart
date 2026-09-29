/// اعلانات
/// Announcements inbox + admin publishing.
///
/// Renders inside [AppShell] via [ShellPageBody] (no nested Scaffold).
/// Admins get the single orange «نیا اعلان» FAB; publishing opens an
/// [M360Dialog] form; unpin/delete use the design-system confirm + snackbar
/// feedback. All data flows through [announcementProvider] unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/models.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../shell/shell_page_body.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  final String? madrasaId;
  const AnnouncementsScreen({super.key, this.madrasaId});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref
        .read(announcementProvider.notifier)
        .load(madrasaId: widget.madrasaId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(announcementProvider);
    final user = ref.watch(authProvider).user;
    final isAdmin =
        user?.role.name == 'admin' || user?.role.name == 'superAdmin';

    final pinned = state.announcements.where((a) => a.isPinned).toList();
    final rest = state.announcements.where((a) => !a.isPinned).toList();

    return ShellPageBody(
      backgroundColor: AppColors.background,
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('نیا اعلان'),
              onPressed: () => _showCreateDialog(context, user),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PageHeader(
              title: 'اعلانات',
              description: 'مدرسے کے تازہ اعلانات اور اہم اطلاعات',
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const M360LoadingState()
                : state.announcements.isEmpty
                    ? M360EmptyState(
                        icon: Icons.campaign_outlined,
                        title: 'کوئی اعلان نہیں',
                        description: 'ابھی تک کوئی اعلان شائع نہیں ہوا۔',
                        actionLabel: isAdmin ? 'نیا اعلان' : null,
                        onAction: isAdmin
                            ? () => _showCreateDialog(context, user)
                            : null,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          if (pinned.isNotEmpty) ...[
                            const M360SectionHeader(title: 'اہم اعلانات'),
                            ...pinned.map((a) => _AnnouncementCard(
                                  announcement: a,
                                  isAdmin: isAdmin,
                                  ref: ref,
                                )),
                            const SizedBox(height: 8),
                          ],
                          if (rest.isNotEmpty) ...[
                            const M360SectionHeader(title: 'تمام اعلانات'),
                            ...rest.map((a) => _AnnouncementCard(
                                  announcement: a,
                                  isAdmin: isAdmin,
                                  ref: ref,
                                )),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, dynamic user) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String target = 'all';
    bool pinned = false;

    await showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setS) => M360Dialog(
          title: 'نیا اعلان',
          icon: Icons.campaign_outlined,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              M360TextField(
                label: 'عنوان',
                hint: 'اعلان کا عنوان لکھیں',
                controller: titleCtrl,
              ),
              const SizedBox(height: 12),
              M360TextField(
                label: 'تفصیل',
                hint: 'اعلان کی تفصیل لکھیں',
                controller: bodyCtrl,
                maxLines: 4,
                minLines: 3,
              ),
              const SizedBox(height: 12),
              M360Dropdown<String>(
                label: 'ہدف',
                value: target,
                items: const [
                  M360DropdownItem(value: 'all', label: 'سب'),
                  M360DropdownItem(value: 'teachers', label: 'اساتذہ'),
                  M360DropdownItem(value: 'parents', label: 'والدین'),
                  M360DropdownItem(value: 'students', label: 'طلباء'),
                ],
                onChanged: (v) => setS(() => target = v ?? 'all'),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    Text('اہم — پن کریں', style: AppTypography.labelNastaliq),
                value: pinned,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setS(() => pinned = v),
              ),
            ],
          ),
          actions: [
            M360TertiaryButton(
              label: 'منسوخ کریں',
              onPressed: () => Navigator.of(dCtx).pop(),
            ),
            M360PrimaryButton(
              label: 'شائع کریں',
              icon: Icons.send_outlined,
              onPressed: () async {
                Navigator.of(dCtx).pop();
                // Display the poster's real name; fall back to email only
                // when no name is on the auth profile.
                final posterName = user?.name as String?;
                final error =
                    await ref.read(announcementProvider.notifier).create(
                          Announcement(
                            title: titleCtrl.text,
                            body: bodyCtrl.text,
                            target: _targetFromString(target),
                            postedByUserId: user?.id ?? '',
                            postedByName:
                                (posterName != null && posterName.isNotEmpty)
                                    ? posterName
                                    : (user?.email as String? ?? ''),
                            tenantId: ref.read(currentTenantIdProvider) ?? '',
                            madrasaId: widget.madrasaId,
                            isPinned: pinned,
                          ),
                        );
                if (!context.mounted) return;
                if (error != null) {
                  showM360SnackBar(context, 'اعلان شائع نہیں ہو سکا',
                      isError: true);
                } else {
                  showM360SnackBar(context, 'اعلان شائع کر دیا گیا');
                }
              },
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    bodyCtrl.dispose();
  }

  AnnouncementTarget _targetFromString(String s) {
    switch (s) {
      case 'teachers':
        return AnnouncementTarget.teachers;
      case 'parents':
        return AnnouncementTarget.parents;
      case 'students':
        return AnnouncementTarget.students;
      default:
        return AnnouncementTarget.all;
    }
  }
}

// ─────────────────────────────────────────────────────────────────
class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.isAdmin,
    required this.ref,
  });

  final Announcement announcement;
  final bool isAdmin;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final targetColors = {
      AnnouncementTarget.all: AppColors.primary,
      AnnouncementTarget.teachers: AppColors.info,
      AnnouncementTarget.parents: AppColors.warning,
      AnnouncementTarget.students: AppColors.success,
    };
    final color = targetColors[a.target] ?? AppColors.primary;

    return M360Card(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: a.isPinned ? AppColors.accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (a.isPinned)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.push_pin, size: 18, color: AppColors.error),
                ),
              Expanded(
                child: Text(
                  a.title,
                  style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              M360Badge.custom(label: a.target.urduLabel, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            a.body,
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  a.postedByName ?? '',
                  style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAdmin) ...[
                M360IconButton(
                  icon: a.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  tooltip: a.isPinned ? 'پن ہٹائیں' : 'پن کریں',
                  color: a.isPinned ? AppColors.error : AppColors.textSecondary,
                  onPressed: () =>
                      ref.read(announcementProvider.notifier).togglePin(a),
                ),
                M360IconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'اعلان حذف کریں',
                  color: AppColors.error,
                  onPressed: () => _confirmDelete(context, a),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Announcement a) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'اعلان حذف کریں؟',
      message:
          '«${a.title}» مستقل طور پر حذف ہو جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(announcementProvider.notifier).delete(a.id ?? '');
    if (!context.mounted) return;
    final error = ref.read(announcementProvider).error;
    final failed = error != null && error.isNotEmpty;
    showM360SnackBar(
      context,
      failed ? 'اعلان حذف نہیں ہو سکا' : 'اعلان حذف کر دیا گیا',
      isError: failed,
    );
  }
}
