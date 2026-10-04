/// ڈیمو ڈیٹا سکرین — one-click demo data install/remove.
///
/// Tenant admins can install a realistic Urdu-first demo dataset into their
/// own tenant to explore every module, and remove it again with one click.
/// Removal only deletes rows flagged `is_demo` — real data is never touched.
///
/// Server-side enforcement lives in the `manage-demo-data` Edge Function
/// (membership + `settings.manage` permission, rate-limited). This screen is
/// additionally gated by [AppPermissions.manageSettings].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/observability/app_logger.dart';
import '../../../core/services/tenant_context.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/demo_data_service.dart';

/// Provides a [DemoDataService] bound to the Supabase client.
final demoDataServiceProvider = Provider<DemoDataService>((ref) {
  return DemoDataService(Supabase.instance.client);
});

class DemoDataScreen extends ConsumerStatefulWidget {
  const DemoDataScreen({super.key});

  @override
  ConsumerState<DemoDataScreen> createState() => _DemoDataScreenState();
}

class _DemoDataScreenState extends ConsumerState<DemoDataScreen> {
  DemoDataStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String? get _tenantId => ref.read(currentTenantIdProvider);

  Future<void> _refresh() async {
    final tenantId = _tenantId;
    if (tenantId == null) {
      setState(() {
        _loading = false;
        _error = 'مدرسہ منتخب نہیں — پہلے لاگ اِن کریں';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status =
          await ref.read(demoDataServiceProvider).status(tenantId);
      if (mounted) {
        setState(() {
          _status = status;
          _loading = false;
        });
      }
    } on DemoDataException catch (e) {
      AppLogger().error('Demo data status failed', error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _install() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'ڈیمو ڈیٹا لگائیں؟',
      message: 'آپ کے مدرسے میں جانچ کے لیے نمونہ ڈیٹا شامل کیا جائے گا:\n'
          '• 3 درجات، 4 جماعتیں، 12 طلبہ\n'
          '• 4 عملہ، فیس اسٹرکچر، 6 انوائس\n'
          '• آمدن و اخراجات کے نمونے\n\n'
          'یہ ڈیٹا واضح طور پر "ڈیمو" نشان زد ہوگا اور ایک کلک پر '
          'مکمل حذف کیا جا سکے گا۔ آپ کا اصل ڈیٹا متاثر نہیں ہوگا۔',
      confirmLabel: 'لگائیں',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final status =
          await ref.read(demoDataServiceProvider).install(tenantId);
      if (mounted) {
        setState(() => _status = status);
        showM360SnackBar(context, 'ڈیمو ڈیٹا لگا دیا گیا');
      }
    } on DemoDataException catch (e) {
      AppLogger().error('Demo data install failed', error: e);
      if (mounted) showM360SnackBar(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'ڈیمو ڈیٹا حذف کریں؟',
      message: 'صرف ڈیمو نشان زد ڈیٹا حذف ہوگا — آپ کا اصل ڈیٹا '
          'مکمل محفوظ رہے گا۔\n\nیہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(demoDataServiceProvider).remove(tenantId);
      await _refresh();
      if (mounted) showM360SnackBar(context, 'ڈیمو ڈیٹا حذف کر دیا گیا');
    } on DemoDataException catch (e) {
      AppLogger().error('Demo data remove failed', error: e);
      if (mounted) showM360SnackBar(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.manageSettings));
    if (!canManage) {
      return const Scaffold(
        appBar: M360AppBar(title: 'ڈیمو ڈیٹا'),
        body: Center(
          child: Text(
            'آپ کو اس صفحے تک رسائی نہیں',
            style: AppTypography.bodyMedium,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const M360AppBar(title: 'ڈیمو ڈیٹا'),
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildInfoCard(),
                      const SizedBox(height: 16),
                      if (_status?.installed == true) ...[
                        _buildStatusCard(),
                        const SizedBox(height: 16),
                        _buildRemoveButton(),
                      ] else
                        _buildInstallButton(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: AppTypography.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            M360PrimaryButton(label: 'دوبارہ کوشش کریں', onPressed: _refresh),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined,
                    color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'سافٹ ویئر آزمانے کے لیے نمونہ ڈیٹا',
                    style: AppTypography.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'ایک کلک پر آپ کے مدرسے میں حقیقت نما ڈیمو ڈیٹا شامل ہوگا '
              'تاکہ آپ تمام ماڈیولز — طلبہ، عملہ، فیس، آمدن و اخراجات — '
              'آزما سکیں۔ ڈیمو ڈیٹا واضح نشان کے ساتھ آئے گا اور جب چاہیں '
              'ایک کلک پر مکمل حذف کر سکیں گے۔',
              style: AppTypography.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final status = _status!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'ڈیمو ڈیٹا فعال',
                    style: AppTypography.labelNastaliq,
                  ),
                ),
                const Spacer(),
                Text(
                  '${status.totalRows} ریکارڈ',
                  style: AppTypography.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'یہ ڈیٹا صرف جانچ کے لیے ہے۔ حذف کرنے پر صرف ڈیمو '
              'ریکارڈ ختم ہوں گے۔',
              style: AppTypography.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallButton() {
    return M360PrimaryButton(
      label: 'ڈیمو ڈیٹا لگائیں',
      icon: Icons.download_outlined,
      isLoading: _busy,
      onPressed: _busy ? null : _install,
    );
  }

  Widget _buildRemoveButton() {
    return M360DangerButton(
      label: 'ڈیمو ڈیٹا حذف کریں',
      icon: Icons.delete_outline,
      isLoading: _busy,
      onPressed: _busy ? null : _remove,
    );
  }
}
