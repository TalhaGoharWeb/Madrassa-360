/// دارالاقامہ
/// Hostel module hub (Phase 8) — buildings → rooms → beds → allocations.
///
/// Renders inside the single [AppShell] via [ShellPageBody] (no nested
/// Scaffold). Tabs: عمارتیں، کمرے، بستر، رہائشی — each with list, search,
/// filter, view (detail), create, edit and delete (m360 destructive
/// confirmation).
///
/// BACKEND STATUS: no hostel tables exist yet
/// (docs/audit-backend-capabilities.md). The provider lands in
/// [HostelLoadStatus.unavailable] and every tab shows the honest
/// backend-unavailable state — what the data WILL look like once the
/// backend is connected, never invented rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../data/repositories/hostel_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/hostel_provider.dart';
import '../../shell/shell_page_body.dart';
import 'hostel_detail_screens.dart';
import 'hostel_forms.dart';

/// دارالاقامہ — the hostel module entry screen (nav destination).
class HostelScreen extends ConsumerStatefulWidget {
  const HostelScreen({super.key});

  @override
  ConsumerState<HostelScreen> createState() => _HostelScreenState();
}

class _HostelScreenState extends ConsumerState<HostelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_onTabChanged);
    Future.microtask(() => ref.read(hostelProvider.notifier).load());
  }

  void _onTabChanged() {
    // Refresh the orange primary CTA so its label follows the active tab.
    if (_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hostelProvider);
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.manageHostel));

    return ShellPageBody(
      tabBar: TabBar(
        controller: _tabs,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textSecondary,
        tabs: const [
          Tab(text: 'عمارتیں'),
          Tab(text: 'کمرے'),
          Tab(text: 'بستر'),
          Tab(text: 'رہائشی'),
        ],
      ),
      floatingActionButton: canManage ? _fabForTab(context, ref, state) : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PageHeader(
              title: 'دارالاقامہ',
              description: 'عمارتیں، کمرے، بستر اور رہائش کا انتظام',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: M360SearchField(
              hint: 'تلاش کریں...',
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.isLoading || state.status == HostelLoadStatus.initial
                ? const M360LoadingState()
                : state.backendUnavailable
                    ? _unavailableBody(context, ref)
                    : state.status == HostelLoadStatus.error
                        ? M360ErrorState(
                            message: state.error ?? 'خرابی ہوئی۔',
                            onRetry: () =>
                                ref.read(hostelProvider.notifier).load(),
                          )
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              _BuildingsTab(
                                  state: state,
                                  search: _search,
                                  canManage: canManage),
                              _RoomsTab(
                                  state: state,
                                  search: _search,
                                  canManage: canManage),
                              _BedsTab(
                                  state: state,
                                  search: _search,
                                  canManage: canManage),
                              _AllocationsTab(
                                  state: state,
                                  search: _search,
                                  canManage: canManage),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  /// Orange primary CTA per active tab — the single primary action.
  Widget? _fabForTab(BuildContext context, WidgetRef ref, HostelState state) {
    Future<void> Function() action;
    String label;
    switch (_tabs.index) {
      case 0:
        label = 'نئی عمارت';
        action = () async => showHostelBuildingForm(context);
        break;
      case 1:
        label = 'نیا کمرہ';
        action = () async => showHostelRoomForm(
              context,
              buildings: state.buildings,
            );
        break;
      case 2:
        label = 'نیا بستر';
        action = () async => showHostelBedForm(
              context,
              rooms: state.rooms,
            );
        break;
      default:
        label = 'بستر الاٹ کریں';
        action = () async => showHostelAllocationForm(
              context,
              beds: state.beds,
            );
    }
    return FloatingActionButton.extended(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: Text(label),
      onPressed: () {
        action();
        // Refresh the tab index listener so the FAB label follows tabs.
        setState(() {});
      },
    );
  }

  /// Honest backend-unavailable body — explains what WILL appear here
  /// once the backend is connected. Never a "جلد آرہا ہے" placeholder.
  Widget _unavailableBody(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const M360EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'دارالاقامہ کا ریکارڈ دستیاب نہیں',
          description:
              'عمارتوں، کمروں، بستروں اور رہائش کا ڈیٹا ابھی بیک اینڈ سے منسلک نہیں ہے۔ '
              'بیک اینڈ دستیاب ہوتے ہی یہاں عمارتوں کی فہرست، ہر کمرے کے بستر، '
              'اور ہر طالب علم کی رہائش نظر آئے گی۔',
        ),
        const SizedBox(height: 8),
        Center(
          child: M360SecondaryButton(
            label: 'دوبارہ کوشش کریں',
            icon: Icons.refresh,
            onPressed: () => ref.read(hostelProvider.notifier).load(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Tab: buildings
// ─────────────────────────────────────────────

class _BuildingsTab extends ConsumerWidget {
  final HostelState state;
  final String search;
  final bool canManage;

  const _BuildingsTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = state.buildings
        .where((b) =>
            search.isEmpty ||
            b.name.contains(search) ||
            (b.wardenName ?? '').contains(search))
        .toList(growable: false);
    if (items.isEmpty) {
      return M360EmptyState(
        icon: Icons.apartment_outlined,
        title: search.isEmpty ? 'کوئی عمارت نہیں' : 'کوئی نتیجہ نہیں',
        description: search.isEmpty
            ? 'ابھی کوئی عمارت درج نہیں — نیچے بٹن سے پہلی عمارت شامل کریں۔'
            : 'تلاش کے مطابق کوئی عمارت نہیں ملی۔',
        actionLabel: search.isEmpty && canManage ? 'نئی عمارت' : null,
        onAction: search.isEmpty && canManage
            ? () => showHostelBuildingForm(context)
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final b = items[i];
        final roomCount = state.rooms.where((r) => r.buildingId == b.id).length;
        return M360TappableCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HostelBuildingDetailScreen(buildingId: b.id),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.apartment_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      b.wardenName == null
                          ? '$roomCount کمرے'
                          : 'وارڈن: ${b.wardenName} — $roomCount کمرے',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(color: AppColors.textSecondary),
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
                      onPressed: () => showHostelBuildingForm(
                        context,
                        existing: b,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                      tooltip: 'حذف کریں',
                      onPressed: () => _deleteBuilding(context, ref, b),
                    ),
                  ],
                )
              else
                const Icon(Icons.chevron_left),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteBuilding(
      BuildContext context, WidgetRef ref, HostelBuilding b) async {
    final ok = await confirmHostelDelete(context, itemLabel: b.name);
    if (!ok || !context.mounted) return;
    final deleted =
        await ref.read(hostelProvider.notifier).deleteBuilding(b.id);
    if (!context.mounted) return;
    showM360SnackBar(
      context,
      deleted
          ? 'عمارت حذف ہو گئی۔'
          : (ref.read(hostelProvider).error ?? 'حذف نہیں ہو سکی۔'),
      isError: !deleted,
    );
  }
}

// ─────────────────────────────────────────────
// Tab: rooms
// ─────────────────────────────────────────────

class _RoomsTab extends ConsumerWidget {
  final HostelState state;
  final String search;
  final bool canManage;

  const _RoomsTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = state.rooms
        .where((r) =>
            search.isEmpty ||
            r.roomNo.contains(search) ||
            (r.floor ?? '').contains(search))
        .toList(growable: false);
    if (items.isEmpty) {
      return M360EmptyState(
        icon: Icons.meeting_room_outlined,
        title: search.isEmpty ? 'کوئی کمرہ نہیں' : 'کوئی نتیجہ نہیں',
        description: search.isEmpty
            ? 'ابھی کوئی کمرہ درج نہیں — نیچے بٹن سے پہلا کمرہ شامل کریں۔'
            : 'تلاش کے مطابق کوئی کمرہ نہیں ملا۔',
        actionLabel: search.isEmpty && canManage ? 'نیا کمرہ' : null,
        onAction: search.isEmpty && canManage
            ? () => showHostelRoomForm(context, buildings: state.buildings)
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = items[i];
        final building =
            state.buildings.where((b) => b.id == r.buildingId).firstOrNull;
        final bedCount = state.beds.where((b) => b.roomId == r.id).length;
        return M360TappableCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HostelRoomDetailScreen(roomId: r.id),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.meeting_room_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'کمرہ ${r.roomNo}',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${building?.name ?? ''} — $bedCount بستر',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(color: AppColors.textSecondary),
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
                        existing: r,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                      tooltip: 'حذف کریں',
                      onPressed: () async {
                        final ok = await confirmHostelDelete(
                          context,
                          itemLabel: 'کمرہ ${r.roomNo}',
                        );
                        if (!ok || !context.mounted) return;
                        final deleted = await ref
                            .read(hostelProvider.notifier)
                            .deleteRoom(r.id);
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
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Tab: beds
// ─────────────────────────────────────────────

class _BedsTab extends StatefulWidget {
  final HostelState state;
  final String search;
  final bool canManage;

  const _BedsTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  State<_BedsTab> createState() => _BedsTabState();
}

class _BedsTabState extends State<_BedsTab> {
  HostelBedStatus? _filter;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        var items = widget.state.beds
            .where(
                (b) => widget.search.isEmpty || b.bedNo.contains(widget.search))
            .toList(growable: false);
        if (_filter != null) {
          items = items.where((b) => b.status == _filter).toList();
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'سب',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'خالی',
                    selected: _filter == HostelBedStatus.available,
                    onTap: () =>
                        setState(() => _filter = HostelBedStatus.available),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'مصروف',
                    selected: _filter == HostelBedStatus.occupied,
                    onTap: () =>
                        setState(() => _filter = HostelBedStatus.occupied),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'مرمت میں',
                    selected: _filter == HostelBedStatus.maintenance,
                    onTap: () =>
                        setState(() => _filter = HostelBedStatus.maintenance),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const M360EmptyState(
                      icon: Icons.bed_outlined,
                      title: 'کوئی بستر نہیں',
                      description: 'اس فلٹر کے مطابق کوئی بستر درج نہیں۔',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final bed = items[i];
                        final room = widget.state.rooms
                            .where((r) => r.id == bed.roomId)
                            .firstOrNull;
                        return M360Card(
                          child: Row(
                            children: [
                              const Icon(Icons.bed_outlined,
                                  color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'بستر ${bed.bedNo}',
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      room == null ? '' : 'کمرہ ${room.roomNo}',
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              M360StatusChip(
                                status: bed.status == HostelBedStatus.available
                                    ? M360Status.active
                                    : bed.status == HostelBedStatus.maintenance
                                        ? M360Status.pending
                                        : M360Status.inactive,
                              ),
                              if (widget.canManage)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 20),
                                      tooltip: 'ترمیم',
                                      onPressed: () => showHostelBedForm(
                                        context,
                                        rooms: widget.state.rooms,
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
                                        if (!ok || !context.mounted) {
                                          return;
                                        }
                                        final deleted = await ref
                                            .read(hostelProvider.notifier)
                                            .deleteBed(bed.id);
                                        if (!context.mounted) {
                                          return;
                                        }
                                        showM360SnackBar(
                                          context,
                                          deleted
                                              ? 'بستر حذف ہو گیا۔'
                                              : (ref
                                                      .read(hostelProvider)
                                                      .error ??
                                                  'حذف نہیں ہو سکا۔'),
                                          isError: !deleted,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
    );
  }
}

// ─────────────────────────────────────────────
// Tab: allocations
// ─────────────────────────────────────────────

class _AllocationsTab extends ConsumerWidget {
  final HostelState state;
  final String search;
  final bool canManage;

  const _AllocationsTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = state.allocations
        .where((a) => search.isEmpty || a.studentName.contains(search))
        .toList(growable: false);
    if (items.isEmpty) {
      return M360EmptyState(
        icon: Icons.hotel_outlined,
        title: search.isEmpty ? 'کوئی رہائش نہیں' : 'کوئی نتیجہ نہیں',
        description: search.isEmpty
            ? 'ابھی کوئی بستر الاٹ نہیں ہوا — نیچے بٹن سے پہلی الاٹمنٹ کریں۔'
            : 'تلاش کے مطابق کوئی رہائش نہیں ملی۔',
        actionLabel: search.isEmpty && canManage ? 'بستر الاٹ کریں' : null,
        onAction: search.isEmpty && canManage
            ? () => showHostelAllocationForm(context, beds: state.beds)
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a = items[i];
        final bed = state.beds.where((b) => b.id == a.bedId).firstOrNull;
        final active = a.status == HostelAllocationStatus.active;
        return M360Card(
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.studentName,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      bed == null ? '' : 'بستر ${bed.bedNo}',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              M360StatusChip(
                status: active ? M360Status.active : M360Status.inactive,
              ),
              if (canManage && active)
                TextButton(
                  onPressed: () async {
                    final ok = await showM360ConfirmDialog(
                      context,
                      title: 'رہائش ختم کریں',
                      message:
                          'کیا آپ ${a.studentName} کی رہائش ختم کرنا چاہتے ہیں؟ بستر دوبارہ خالی ہو جائے گا۔',
                      confirmLabel: 'ختم کریں',
                      danger: true,
                    );
                    if (!ok || !context.mounted) return;
                    final done = await ref
                        .read(hostelProvider.notifier)
                        .endAllocation(a.id);
                    if (!context.mounted) return;
                    showM360SnackBar(
                      context,
                      done
                          ? 'رہائش ختم ہو گئی۔'
                          : (ref.read(hostelProvider).error ??
                              'عمل نہیں ہو سکا۔'),
                      isError: !done,
                    );
                  },
                  child: const Text('ختم کریں'),
                ),
            ],
          ),
        );
      },
    );
  }
}
