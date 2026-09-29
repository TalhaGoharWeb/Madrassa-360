/// ٹرانسپورٹ تفصیل
/// Transport detail screens (Phase 8): route detail → ordered stops.
/// Rendered inside the single [AppShell] via [ShellPageBody] (no nested
/// Scaffolds); the shell restores the back affordance for these
/// deep-pushed routes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../data/repositories/transport_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/transport_provider.dart';
import '../../shell/shell_page_body.dart';
import 'transport_forms.dart';

/// راستے کی تفصیل — info card + ordered stops, with add/edit/delete.
class TransportRouteDetailScreen extends ConsumerStatefulWidget {
  final String routeId;

  const TransportRouteDetailScreen({super.key, required this.routeId});

  @override
  ConsumerState<TransportRouteDetailScreen> createState() =>
      _TransportRouteDetailScreenState();
}

class _TransportRouteDetailScreenState
    extends ConsumerState<TransportRouteDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(transportProvider.notifier).loadStops(widget.routeId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transportProvider);
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.manageTransport));

    final route = state.routes.where((r) => r.id == widget.routeId).firstOrNull;
    if (route == null) {
      return ShellPageBody(
        child: M360ErrorState(
          message: 'راستہ نہیں ملا۔',
          onRetry: () => Navigator.of(context).pop(),
          retryLabel: 'واپس جائیں',
        ),
      );
    }
    final stops = state.stops
        .where((s) => s.routeId == widget.routeId)
        .toList(growable: false)
      ..sort((a, b) => a.sequence.compareTo(b.sequence));

    return ShellPageBody(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accentDark,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('نیا اسٹاپ'),
              onPressed: () => showTransportStopForm(
                context,
                ref,
                routeId: route.id,
                nextSequence: stops.isEmpty
                    ? 0
                    : stops
                            .map((s) => s.sequence)
                            .reduce((a, b) => a > b ? a : b) +
                        1,
              ),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PageHeader(
            title: route.name,
            breadcrumb: 'ٹرانسپورٹ',
            description: [
              if (route.startPoint != null) 'آغاز: ${route.startPoint}',
              if (route.endPoint != null) 'اختتام: ${route.endPoint}',
            ].join(' — '),
            actions: [
              if (canManage) ...[
                M360TertiaryButton(
                  label: 'ترمیم',
                  onPressed: () => showTransportRouteForm(
                    context,
                    ref,
                    existing: route,
                  ),
                ),
                const SizedBox(width: 8),
                M360TertiaryButton(
                  label: 'حذف کریں',
                  onPressed: () async {
                    final ok = await confirmTransportDelete(
                      context,
                      itemLabel: route.name,
                    );
                    if (!ok || !context.mounted) return;
                    final deleted = await ref
                        .read(transportProvider.notifier)
                        .deleteRoute(route.id);
                    if (!context.mounted) return;
                    if (deleted) {
                      Navigator.of(context).pop();
                      showM360SnackBar(context, 'راستہ حذف ہو گیا۔');
                    } else {
                      showM360SnackBar(
                        context,
                        ref.read(transportProvider).error ?? 'حذف نہیں ہو سکا۔',
                        isError: true,
                      );
                    }
                  },
                ),
              ],
            ],
          ),
          const M360SectionHeader(
            title: 'اسٹاپ',
            subtitle: 'راستے کی ترتیب کے مطابق',
          ),
          if (state.backendUnavailable)
            const M360EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'ٹرانسپورٹ کا ریکارڈ دستیاب نہیں',
              description:
                  'راستے اور اسٹاپ کا ڈیٹا ابھی بیک اینڈ سے منسلک نہیں ہے۔',
            )
          else if (stops.isEmpty)
            const M360EmptyState(
              icon: Icons.location_on_outlined,
              title: 'کوئی اسٹاپ نہیں',
              description:
                  'اس راستے میں ابھی کوئی اسٹاپ درج نہیں — اوپر بٹن سے پہلا اسٹاپ شامل کریں۔',
            )
          else
            for (var i = 0; i < stops.length; i++) ...[
              _stopRow(context, ref, stops[i], i + 1, canManage),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _stopRow(BuildContext context, WidgetRef ref, TransportStop stop,
      int number, bool canManage) {
    return M360Card(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              stop.name,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (canManage)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'ترمیم',
                  onPressed: () => showTransportStopForm(
                    context,
                    ref,
                    routeId: stop.routeId,
                    existing: stop,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.error),
                  tooltip: 'حذف کریں',
                  onPressed: () async {
                    final ok = await confirmTransportDelete(
                      context,
                      itemLabel: stop.name,
                    );
                    if (!ok || !context.mounted) return;
                    final deleted = await ref
                        .read(transportProvider.notifier)
                        .deleteStop(stop.id);
                    if (!context.mounted) return;
                    showM360SnackBar(
                      context,
                      deleted
                          ? 'اسٹاپ حذف ہو گیا۔'
                          : (ref.read(transportProvider).error ??
                              'حذف نہیں ہو سکا۔'),
                      isError: !deleted,
                    );
                    if (deleted) {
                      await ref
                          .read(transportProvider.notifier)
                          .loadStops(stop.routeId);
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
