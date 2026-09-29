/// ٹرانسپورٹ
/// Transport module hub (Phase 8) — vehicles, drivers, routes, assignments.
///
/// Renders inside the single [AppShell] via [ShellPageBody] (no nested
/// Scaffold). Tabs: گاڑیاں، ڈرائیور، راستے، اسائنمنٹس — each with list,
/// search, view (detail), create, edit and delete (m360 destructive
/// confirmation).
///
/// BACKEND STATUS: no transport tables exist yet
/// (docs/audit-backend-capabilities.md). The provider lands in
/// [TransportLoadStatus.unavailable] and every tab shows the honest
/// backend-unavailable state — what the data WILL look like once the
/// backend is connected, never invented rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../data/repositories/transport_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/transport_provider.dart';
import '../../shell/shell_page_body.dart';
import 'transport_detail_screens.dart';
import 'transport_forms.dart';

/// ٹرانسپورٹ — the transport module entry screen (nav destination).
class TransportScreen extends ConsumerStatefulWidget {
  const TransportScreen({super.key});

  @override
  ConsumerState<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends ConsumerState<TransportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(_onTabChanged);
    Future.microtask(() => ref.read(transportProvider.notifier).load());
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
    final state = ref.watch(transportProvider);
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.manageTransport));

    return ShellPageBody(
      tabBar: TabBar(
        controller: _tabs,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textSecondary,
        tabs: const [
          Tab(text: 'گاڑیاں'),
          Tab(text: 'ڈرائیور'),
          Tab(text: 'راستے'),
          Tab(text: 'اسائنمنٹس'),
        ],
      ),
      floatingActionButton: canManage ? _fabForTab(context, ref, state) : null,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PageHeader(
              title: 'ٹرانسپورٹ',
              description: 'گاڑیاں، ڈرائیور، راستے اور اسائنمنٹس کا انتظام',
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
            child:
                state.isLoading || state.status == TransportLoadStatus.initial
                    ? const M360LoadingState()
                    : state.backendUnavailable
                        ? _unavailableBody(context, ref)
                        : state.status == TransportLoadStatus.error
                            ? M360ErrorState(
                                message: state.error ?? 'خرابی ہوئی۔',
                                onRetry: () =>
                                    ref.read(transportProvider.notifier).load(),
                              )
                            : TabBarView(
                                controller: _tabs,
                                children: [
                                  _VehiclesTab(
                                      state: state,
                                      search: _search,
                                      canManage: canManage),
                                  _DriversTab(
                                      state: state,
                                      search: _search,
                                      canManage: canManage),
                                  _RoutesTab(
                                      state: state,
                                      search: _search,
                                      canManage: canManage),
                                  _AssignmentsTab(
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
  Widget? _fabForTab(
      BuildContext context, WidgetRef ref, TransportState state) {
    Future<void> Function() action;
    String label;
    switch (_tabs.index) {
      case 0:
        label = 'نئی گاڑی';
        action = () async => showTransportVehicleForm(context, ref);
        break;
      case 1:
        label = 'نیا ڈرائیور';
        action = () async => showTransportDriverForm(context, ref);
        break;
      case 2:
        label = 'نیا راستہ';
        action = () async => showTransportRouteForm(context, ref);
        break;
      default:
        label = 'نئی اسائنمنٹ';
        action = () async => showTransportAssignmentForm(
              context,
              ref,
              vehicles: state.vehicles,
              drivers: state.drivers,
              routes: state.routes,
            );
    }
    return FloatingActionButton.extended(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: Text(label),
      onPressed: () {
        action();
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
          title: 'ٹرانسپورٹ کا ریکارڈ دستیاب نہیں',
          description:
              'گاڑیوں، ڈرائیوروں، راستوں اور اسائنمنٹس کا ڈیٹا ابھی بیک اینڈ سے منسلک نہیں ہے۔ '
              'بیک اینڈ دستیاب ہوتے ہی یہاں گاڑیوں کی فہرست، ہر راستے کے اسٹاپ، '
              'اور گاڑی و ڈرائیور کی اسائنمنٹس نظر آئیں گی۔',
        ),
        const SizedBox(height: 8),
        Center(
          child: M360SecondaryButton(
            label: 'دوبارہ کوشش کریں',
            icon: Icons.refresh,
            onPressed: () => ref.read(transportProvider.notifier).load(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Shared row helpers
// ─────────────────────────────────────────────

Future<void> _deleteWithConfirm({
  required BuildContext context,
  required WidgetRef ref,
  required String itemLabel,
  required Future<bool> Function() delete,
}) async {
  final ok = await confirmTransportDelete(context, itemLabel: itemLabel);
  if (!ok || !context.mounted) return;
  final deleted = await delete();
  if (!context.mounted) return;
  showM360SnackBar(
    context,
    deleted
        ? 'حذف ہو گیا۔'
        : (ref.read(transportProvider).error ?? 'حذف نہیں ہو سکا۔'),
    isError: !deleted,
  );
}

// ─────────────────────────────────────────────
// Tab: vehicles
// ─────────────────────────────────────────────

class _VehiclesTab extends ConsumerWidget {
  final TransportState state;
  final String search;
  final bool canManage;

  const _VehiclesTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = state.vehicles
        .where((v) =>
            search.isEmpty ||
            v.plateNumber.contains(search) ||
            v.vehicleType.contains(search))
        .toList(growable: false);
    if (items.isEmpty) {
      return M360EmptyState(
        icon: Icons.directions_bus_outlined,
        title: search.isEmpty ? 'کوئی گاڑی نہیں' : 'کوئی نتیجہ نہیں',
        description: search.isEmpty
            ? 'ابھی کوئی گاڑی درج نہیں — نیچے بٹن سے پہلی گاڑی شامل کریں۔'
            : 'تلاش کے مطابق کوئی گاڑی نہیں ملی۔',
        actionLabel: search.isEmpty && canManage ? 'نئی گاڑی' : null,
        onAction: search.isEmpty && canManage
            ? () => showTransportVehicleForm(context, ref)
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final v = items[i];
        return M360Card(
          child: Row(
            children: [
              const Icon(Icons.directions_bus_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    M360LatinText(v.plateNumber),
                    Text(
                      '${v.vehicleType} — گنجائش: ${v.capacity}',
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
                      onPressed: () => showTransportVehicleForm(
                        context,
                        ref,
                        existing: v,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                      tooltip: 'حذف کریں',
                      onPressed: () => _deleteWithConfirm(
                        context: context,
                        ref: ref,
                        itemLabel: v.plateNumber,
                        delete: () => ref
                            .read(transportProvider.notifier)
                            .deleteVehicle(v.id),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Tab: drivers
// ─────────────────────────────────────────────

class _DriversTab extends ConsumerWidget {
  final TransportState state;
  final String search;
  final bool canManage;

  const _DriversTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = state.drivers
        .where((d) =>
            search.isEmpty ||
            d.name.contains(search) ||
            (d.phone ?? '').contains(search))
        .toList(growable: false);
    if (items.isEmpty) {
      return M360EmptyState(
        icon: Icons.person_outline,
        title: search.isEmpty ? 'کوئی ڈرائیور نہیں' : 'کوئی نتیجہ نہیں',
        description: search.isEmpty
            ? 'ابھی کوئی ڈرائیور درج نہیں — نیچے بٹن سے پہلا ڈرائیور شامل کریں۔'
            : 'تلاش کے مطابق کوئی ڈرائیور نہیں ملا۔',
        actionLabel: search.isEmpty && canManage ? 'نیا ڈرائیور' : null,
        onAction: search.isEmpty && canManage
            ? () => showTransportDriverForm(context, ref)
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = items[i];
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
                      d.name,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (d.phone != null) M360LatinText(d.phone!),
                    if (d.licenseNumber != null)
                      Text(
                        'لائسنس: ${d.licenseNumber}',
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
                      onPressed: () => showTransportDriverForm(
                        context,
                        ref,
                        existing: d,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                      tooltip: 'حذف کریں',
                      onPressed: () => _deleteWithConfirm(
                        context: context,
                        ref: ref,
                        itemLabel: d.name,
                        delete: () => ref
                            .read(transportProvider.notifier)
                            .deleteDriver(d.id),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Tab: routes
// ─────────────────────────────────────────────

class _RoutesTab extends ConsumerWidget {
  final TransportState state;
  final String search;
  final bool canManage;

  const _RoutesTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = state.routes
        .where((r) => search.isEmpty || r.name.contains(search))
        .toList(growable: false);
    if (items.isEmpty) {
      return M360EmptyState(
        icon: Icons.route_outlined,
        title: search.isEmpty ? 'کوئی راستہ نہیں' : 'کوئی نتیجہ نہیں',
        description: search.isEmpty
            ? 'ابھی کوئی راستہ درج نہیں — نیچے بٹن سے پہلا راستہ شامل کریں۔'
            : 'تلاش کے مطابق کوئی راستہ نہیں ملا۔',
        actionLabel: search.isEmpty && canManage ? 'نیا راستہ' : null,
        onAction: search.isEmpty && canManage
            ? () => showTransportRouteForm(context, ref)
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = items[i];
        return M360TappableCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransportRouteDetailScreen(routeId: r.id),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.route_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (r.startPoint != null) r.startPoint!,
                        if (r.endPoint != null) r.endPoint!,
                      ].join(' ← '),
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
                      onPressed: () => showTransportRouteForm(
                        context,
                        ref,
                        existing: r,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                      tooltip: 'حذف کریں',
                      onPressed: () => _deleteWithConfirm(
                        context: context,
                        ref: ref,
                        itemLabel: r.name,
                        delete: () => ref
                            .read(transportProvider.notifier)
                            .deleteRoute(r.id),
                      ),
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
// Tab: assignments
// ─────────────────────────────────────────────

class _AssignmentsTab extends ConsumerWidget {
  final TransportState state;
  final String search;
  final bool canManage;

  const _AssignmentsTab({
    required this.state,
    required this.search,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = state.assignments.where((a) {
      if (search.isEmpty) return true;
      final vehicle =
          state.vehicles.where((v) => v.id == a.vehicleId).firstOrNull;
      final route = state.routes.where((r) => r.id == a.routeId).firstOrNull;
      return (vehicle?.plateNumber ?? '').contains(search) ||
          (route?.name ?? '').contains(search);
    }).toList(growable: false);

    if (items.isEmpty) {
      return M360EmptyState(
        icon: Icons.assignment_outlined,
        title: search.isEmpty ? 'کوئی اسائنمنٹ نہیں' : 'کوئی نتیجہ نہیں',
        description: search.isEmpty
            ? 'ابھی کوئی اسائنمنٹ درج نہیں — نیچے بٹن سے پہلی اسائنمنٹ بنائیں۔'
            : 'تلاش کے مطابق کوئی اسائنمنٹ نہیں ملی۔',
        actionLabel: search.isEmpty && canManage ? 'نئی اسائنمنٹ' : null,
        onAction: search.isEmpty && canManage
            ? () => showTransportAssignmentForm(
                  context,
                  ref,
                  vehicles: state.vehicles,
                  drivers: state.drivers,
                  routes: state.routes,
                )
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a = items[i];
        final vehicle =
            state.vehicles.where((v) => v.id == a.vehicleId).firstOrNull;
        final driver =
            state.drivers.where((d) => d.id == a.driverId).firstOrNull;
        final route = state.routes.where((r) => r.id == a.routeId).firstOrNull;
        return M360Card(
          child: Row(
            children: [
              const Icon(Icons.assignment_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route?.name ?? '—',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (vehicle != null) M360LatinText(vehicle.plateNumber),
                    if (driver != null)
                      Text(
                        'ڈرائیور: ${driver.name}',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              M360StatusChip(
                status: a.active ? M360Status.active : M360Status.inactive,
              ),
              if (canManage)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'ترمیم',
                      onPressed: () => showTransportAssignmentForm(
                        context,
                        ref,
                        vehicles: state.vehicles,
                        drivers: state.drivers,
                        routes: state.routes,
                        existing: a,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                      tooltip: 'حذف کریں',
                      onPressed: () => _deleteWithConfirm(
                        context: context,
                        ref: ref,
                        itemLabel: route?.name ?? 'اسائنمنٹ',
                        delete: () => ref
                            .read(transportProvider.notifier)
                            .deleteAssignment(a.id),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
