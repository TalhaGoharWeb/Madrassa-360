import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/models.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/auth_provider.dart';

class AnnouncementsScreen extends StatefulWidget {
  final String? madrasaId;
  const AnnouncementsScreen({super.key, this.madrasaId});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  WidgetRef? _ref;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        _ref?.read(announcementProvider.notifier).load(
            madrasaId: widget.madrasaId));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      _ref = ref;
      final state = ref.watch(announcementProvider);
      final user = ref.watch(authProvider).user;
      final isAdmin = user?.role.name == 'admin' ||
          user?.role.name == 'superAdmin';

      final pinned = state.announcements.where((a) => a.isPinned).toList();
      final rest = state.announcements.where((a) => !a.isPinned).toList();

      return Scaffold(
        appBar: AppBar(
          title: Text('اعلانات', style: AppTypography.appBarTitle),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('نیا اعلان'),
                onPressed: () => _showCreateDialog(context, ref, user),
              )
            : null,
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.announcements.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.campaign_outlined,
                        size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text('کوئی اعلان نہیں',
                        style: AppTypography.bodyLarge
                            .copyWith(color: AppColors.textSecondary)),
                  ]))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _sectionHeader('📌 اہم اعلانات'),
                        const SizedBox(height: 8),
                        ...pinned
                            .map((a) => _AnnouncementCard(a, ref, isAdmin)),
                        const SizedBox(height: 16),
                      ],
                      if (rest.isNotEmpty) ...[
                        _sectionHeader('📋 تمام اعلانات'),
                        const SizedBox(height: 8),
                        ...rest
                            .map((a) => _AnnouncementCard(a, ref, isAdmin)),
                      ],
                    ],
                  ),
      );
    });
  }

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: AppTypography.titleSmall),
      );

  Future<void> _showCreateDialog(
      BuildContext context, WidgetRef ref, dynamic user) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String target = 'all';
    bool pinned = false;

    await showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
        return AlertDialog(
          title: Text('نیا اعلان', style: AppTypography.titleMedium),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(titleCtrl, 'عنوان'),
            _field(bodyCtrl, 'تفصیل', maxLines: 4),
            DropdownButtonFormField<String>(
              value: target,
              decoration: const InputDecoration(
                  labelText: 'ہدف', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('سب')),
                DropdownMenuItem(value: 'teachers', child: Text('اساتذہ')),
                DropdownMenuItem(value: 'parents', child: Text('والدین')),
                DropdownMenuItem(value: 'students', child: Text('طلباء')),
              ],
              onChanged: (v) => setS(() => target = v!),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: pinned,
              title: const Text('اہم — پِن کریں'),
              onChanged: (v) => setS(() => pinned = v!),
            ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('منسوخ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(dCtx);
                await ref.read(announcementProvider.notifier).create(
                      Announcement(
                        title: titleCtrl.text,
                        body: bodyCtrl.text,
                        target: _targetFromString(target),
                        postedByUserId: user?.id ?? '',
                        postedByName: user?.email ?? '',
                        madrasaId: widget.madrasaId,
                        isPinned: pinned,
                      ),
                    );
              },
              child: const Text('شائع'),
            ),
          ],
        );
      }),
    );
  }

  AnnouncementTarget _targetFromString(String s) {
    switch (s) {
      case 'teachers': return AnnouncementTarget.teachers;
      case 'parents': return AnnouncementTarget.parents;
      case 'students': return AnnouncementTarget.students;
      default: return AnnouncementTarget.all;
    }
  }

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────
class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard(this.a, this.ref, this.isAdmin);
  final Announcement a;
  final WidgetRef ref;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final targetColors = {
      AnnouncementTarget.all: AppColors.primary,
      AnnouncementTarget.teachers: AppColors.info,
      AnnouncementTarget.parents: AppColors.warning,
      AnnouncementTarget.students: AppColors.success,
    };
    final color = targetColors[a.target] ?? AppColors.primary;

    return Card(
      elevation: a.isPinned ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (a.isPinned)
              const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.push_pin, size: 16, color: Colors.red)),
            Expanded(
                child: Text(a.title,
                    style: AppTypography.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(a.target.urduLabel,
                  style:
                      AppTypography.labelSmall.copyWith(color: color)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(a.body,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.person_outline,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Expanded(
                child: Text(a.postedByName ?? '',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textSecondary))),
            if (isAdmin) ...[
              IconButton(
                icon: Icon(
                    a.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                    color: a.isPinned ? Colors.red : AppColors.textSecondary),
                onPressed: () =>
                    ref.read(announcementProvider.notifier).togglePin(a),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                onPressed: () =>
                    ref.read(announcementProvider.notifier).delete(a.id ?? ''),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
