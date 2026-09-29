/// دارالاقامہ تفصیل
/// Hostel detail screens (Phase 8): building detail → rooms, room
/// detail → beds. Rendered inside the single [AppShell] via
/// [ShellPageBody] (no nested Scaffolds); the shell restores the back
/// affordance for these deep-pushed routes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../data/repositories/hostel_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/hostel_provider.dart';
import '../../shell/shell_page_body.dart';
import 'hostel_forms.dart';

String _bedStatusUr(HostelBedStatus s) => switch (s) {
      HostelBedStatus.available => 'خالی',
      HostelBedStatus.occupied => 'مصروف',
      HostelBedStatus.maintenance => 'مرمت میں',
    };

Color _bedStatusColor(HostelBedStatus s) => switch (s) {
      HostelBedStatus.available => AppColors.success,
      HostelBedStatus.occupied => AppColors.primary,
      HostelBedStatus.maintenance => AppColors.warning,
    };

// ─────────────────────────────────────────────
// Building detail
// ─────────────────────────────────────────────

/// عمارت کی تفصیل — info card + its rooms, with add/edit/delete.
class HostelBuildingDetailScreen extends ConsumerWidget {
  final String buildingId;

  const HostelBuildingDetailScreen({super.key, required this.buildingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hostelProvider);
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.manageHostel));

    final building =
        state.buildings.where((b) => b.id == buildingId).firstOrNull;
    if (building == null) {
      return ShellPageBody(
        child: M360ErrorState(
          message: 'عمارت نہیں ملی۔',
          onRetry: () => Navigator.of(context).pop(),
          retryLabel: 'واپس جائیں',
        ),
      );
    }
    final rooms = state.rooms.where((r) => r.buildingId == buildingId).toList();

    return ShellPageBody(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('نیا کمرہ'),
              onPressed: () => showHostelRoomForm(
                context,
                buildings: state.buildings,
                buildingId: buildingId,
              ),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PageHeader(
            title: building.name,
            breadcrumb: 'دارالاقامہ',
            description: building.wardenName == null
                ? null
                : 'وارڈن: ${building.wardenName}',
            actions: [
              if (canManage) ...[
                M360TertiaryButton(
                  label: 'ترمیم',
                  onPressed: () => showHostelBuildingForm(
                    context,
                    existing: building,
                  ),
                ),
                const SizedBox(width: 8),
                M360TertiaryButton(
                  label: 'حذف کریں',
                  onPressed: () async {
                    final ok = await confirmHostelDelete(
                      context,
                      itemLabel: building.name,
                    );
                    if (!ok || !context.mounted) return;
                    final deleted = await ref
                        .read(hostelProvider.notifier)
                        .deleteBuilding(building.id);
                    if (!context.mounted) return;
                    if (deleted) {
                      Navigator.of(context).pop();
                      showM360SnackBar(context, 'عمارت حذف ہو گئی۔');
                    } else {
                      showM360SnackBar(
                        context,
                        ref.read(hostelProvider).error ?? 'حذف نہیں ہو سکی۔',
                        isError: true,
                      );
                    }
                  },
                ),
              ],
            ],
          ),
          M360Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('کمروں کی تعداد', '${rooms.length}'),
                if (building.notes != null) _infoRow('نوٹ', building.notes!),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const M360SectionHeader(title: 'کمرے'),
          if (rooms.isEmpty)
            const M360EmptyState(
              icon: Icons.meeting_room_outlined,
              title: 'کوئی کمرہ نہیں',
              description:
                  'اس عمارت میں ابھی کوئی کمرہ درج نہیں — اوپر بٹن سے نیا کمرہ شامل کریں۔',
            )
          else
            for (final room in rooms) ...[
              M360TappableCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HostelRoomDetailScreen(roomId: room.id),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.meeting_room_outlined,
                        color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'کمرہ ${room.roomNo}',
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'گنجائش: ${room.capacity} بستر',
                            textDirection: TextDirection.rtl,
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (canManage)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'ترمیم',
                            onPressed: () => showHostelRoomForm(
                              context,
                              buildings: state.buildings,
                              existing: room,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 20, color: AppColors.error),
                            tooltip: 'حذف کریں',
                            onPressed: () async {
                              final ok = await confirmHostelDelete(
                                context,
                                itemLabel: 'کمرہ ${room.roomNo}',
                              );
                              if (!ok || !context.mounted) return;
                              final deleted = await ref
                                  .read(hostelProvider.notifier)
                                  .deleteRoom(room.id);
                              if (!context.mounted) return;
                              showM360SnackBar(
                                context,
                                deleted
                                    ? 'کمرہ حذف ہو گیا۔'
                                    : (ref.read(hostelProvider).error ??
                                        'حذف نہیں ہو سکا۔'),
                                isError: !deleted,
                              );
                            },
                          ),
                        ],
                      )
                    else
                      const Icon(Icons.chevron_left),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Text(
            value,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Room detail
// ─────────────────────────────────────────────

/// کمرے کی تفصیل — info card + its beds, with add/edit/delete.
class HostelRoomDetailScreen extends ConsumerWidget {
  final String roomId;

  const HostelRoomDetailScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hostelProvider);
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.manageHostel));

    final room = state.rooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null) {
      return ShellPageBody(
        child: M360ErrorState(
          message: 'کمرہ نہیں ملا۔',
          onRetry: () => Navigator.of(context).pop(),
          retryLabel: 'واپس جائیں',
        ),
      );
    }
    final beds = state.beds.where((b) => b.roomId == roomId).toList();

    return ShellPageBody(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('نیا بستر'),
              onPressed: () => showHostelBedForm(
                context,
                rooms: state.rooms,
                roomId: roomId,
              ),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PageHeader(
            title: 'کمرہ ${room.roomNo}',
            breadcrumb: 'دارالاقامہ',
            description:
                'گنجائش: ${room.capacity} بستر${room.floor == null ? '' : ' — منزل: ${room.floor}'}',
          ),
          const M360SectionHeader(title: 'بستر'),
          if (beds.isEmpty)
            const M360EmptyState(
              icon: Icons.bed_outlined,
              title: 'کوئی بستر نہیں',
              description:
                  'اس کمرے میں ابھی کوئی بستر درج نہیں — اوپر بٹن سے نیا بستر شامل کریں۔',
            )
          else
            for (final bed in beds) ...[
              M360Card(
                child: Row(
                  children: [
                    const Icon(Icons.bed_outlined, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'بستر ${bed.bedNo}',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    M360StatusChip(
                      status: bed.status == HostelBedStatus.available
                          ? M360Status.active
                          : bed.status == HostelBedStatus.maintenance
                              ? M360Status.pending
                              : M360Status.inactive,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _bedStatusUr(bed.status),
                      style: TextStyle(
                        color: _bedStatusColor(bed.status),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (canManage) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'ترمیم',
                        onPressed: () => showHostelBedForm(
                          context,
                          rooms: state.rooms,
                          existing: bed,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: AppColors.error),
                        tooltip: 'حذف کریں',
                        onPressed: () async {
                          final ok = await confirmHostelDelete(
                            context,
                            itemLabel: 'بستر ${bed.bedNo}',
                          );
                          if (!ok || !context.mounted) return;
                          final deleted = await ref
                              .read(hostelProvider.notifier)
                              .deleteBed(bed.id);
                          if (!context.mounted) return;
                          showM360SnackBar(
                            context,
                            deleted
                                ? 'بستر حذف ہو گیا۔'
                                : (ref.read(hostelProvider).error ??
                                    'حذف نہیں ہو سکا۔'),
                            isError: !deleted,
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}
