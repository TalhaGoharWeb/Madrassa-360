/// بیک اپ اسکرین — m360 redesign (Phase 10)
///
/// One-file offline backup & restore UI (admin). Visual layer only: every
/// operation keeps its real behavior — backup now, verify, restore (with
/// typed confirmation), backup list, delete, and the best-effort cloud
/// copy via the existing `pending_uploads` sync machinery. The local file
/// is always the source of truth.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:madrasa_360/core/design/m360.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/local/database_provider.dart';

/// بیک اپ اور ریسٹور
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  List<BackupMetadata> _backups = [];
  bool _loading = true;
  bool _working = false;
  String? _status;

  BackupService get _service {
    final tenantId = ref.read(activeTenantIdProvider) ?? '';
    return BackupService(
      db: ref.read(appDatabaseProvider),
      tenantId: tenantId,
    );
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Back affordance for deep-pushed routes. Shell destinations get the
  /// shell's own back chevron, so this renders nothing for them.
  List<Widget> _withBack(BuildContext context, List<Widget> actions) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return [
      if (canPop)
        M360IconButton(
          icon: Icons.arrow_back,
          tooltip: 'واپس',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ...actions,
    ];
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final list = await _service.listBackups();
      if (!mounted) return;
      setState(() {
        _backups = list;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'فہرست لوڈ نہیں ہو سکی');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() op) async {
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      await op();
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'خرابی ہوئی — دوبارہ کوشش کریں');
      if (mounted) {
        showM360SnackBar(context, 'خرابی ہوئی — دوبارہ کوشش کریں',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _backupNow() => _run(() async {
        final result = await _service.createBackup();
        if (!mounted) return;
        setState(
            () => _status = 'بیک اپ مکمل: ${result.file.path.split('/').last} '
                '(${BackupService.formatBytes(result.sizeBytes)}, '
                '${result.manifest.totalRows} ریکارڈ)');
        showM360SnackBar(context, 'بیک اپ کامیابی سے بن گیا');
        await _refresh();
      });

  Future<void> _verify(BackupMetadata meta) => _run(() async {
        final v = await _service.verifyBackup(meta.file.path);
        if (!mounted) return;
        await showM360Dialog<void>(
          context,
          title: v.valid ? 'بیک اپ درست ہے' : 'بیک اپ ناقص ہے',
          icon:
              v.valid ? Icons.verified_outlined : Icons.warning_amber_outlined,
          content: v.valid
              ? Text(
                  'ریکارڈ: ${v.manifest!.totalRows}\n'
                  'تاریخ: ${_fmtDate(v.manifest!.exportedAt)}\n'
                  'چیک سم: درست',
                  textDirection: TextDirection.rtl,
                  style: AppTypography.bodyMedium,
                )
              : Text(
                  'وجوہات:\n${v.reasons.join('\n')}',
                  textDirection: TextDirection.rtl,
                  style: AppTypography.bodyMedium,
                ),
          actions: [
            M360TertiaryButton(
              label: 'بند کریں',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      });

  Future<void> _restore(BackupMetadata meta) => _run(() async {
        // Typed confirmation: the user must type the phrase exactly.
        // The confirm button stays disabled until it matches.
        final confirmed = await showM360ConfirmDialog(
          context,
          title: 'بیک اپ ریسٹور کریں؟',
          message: 'یہ عمل موجودہ ڈیٹا کو اس بیک اپ سے بدل دے گا:\n'
              '${meta.file.path.split('/').last}\n\n'
              'جاری رکھنے کے لیے تصدیقی عبارت بالکل ویسے ہی لکھیں۔',
          confirmLabel: 'ریسٹور کریں',
          danger: true,
          requireTypedConfirmation: true,
          expectedText: BackupService.restoreConfirmationPhrase,
          typedHint: 'تصدیق کے لیے عبارت لکھیں',
        );
        if (!confirmed) return;
        try {
          final outcome = await _service.restoreBackup(
            meta.file.path,
            confirmationToken: BackupService.restoreConfirmationPhrase,
          );
          if (!mounted) return;
          // The provider override still points at the CLOSED connection, so
          // do NOT call _refresh() here (the old db can't run queries).
          // The user must restart the app; the pre-restore copy is the
          // safety net if anything went wrong.
          setState(() => _status = 'ریسٹور مکمل۔ ایپ دوبارہ شروع کریں۔\n'
              'حفاظتی کاپی: ${outcome.report.preRestoreCopy}');
          await showM360Dialog<void>(
            context,
            title: 'ریسٹور مکمل',
            icon: Icons.restore_outlined,
            content: Text(
              'پرانے ڈیٹا کی حفاظتی کاپی محفوظ ہے:\n${outcome.report.preRestoreCopy}\n\n'
              'براہ کرم ایپ بند کر کے دوبارہ کھولیں۔',
              textDirection: TextDirection.rtl,
              style: AppTypography.bodyMedium,
            ),
            actions: [
              M360PrimaryButton(
                label: 'ٹھیک ہے',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
          // NOTE: no _refresh() here — the live connection was closed by
          // the restore; the app must be restarted before any DB access.
        } on StateError catch (e) {
          if (!mounted) return;
          setState(() => _status = 'ریسٹور ناکام: ${e.message}');
        }
      });

  Future<void> _delete(BackupMetadata meta) => _run(() async {
        final confirmed = await showM360ConfirmDialog(
          context,
          title: 'بیک اپ حذف کریں؟',
          message:
              '«${meta.file.path.split('/').last}» مستقل طور پر حذف ہو جائے گا۔',
          confirmLabel: 'حذف کریں',
          danger: true,
        );
        if (!confirmed) return;
        await _service.deleteBackup(meta.file.path);
        await _refresh();
      });

  Future<void> _cloudCopy(BackupMetadata meta) => _run(() async {
        await _service.enqueueCloudCopy(meta.file);
        if (!mounted) return;
        setState(() => _status =
            'کلاؤڈ کاپی قطار میں لگ گئی — انٹرنیٹ آنے پر اپ لوڈ ہوگی۔');
        await _refresh();
      });

  String _fmtDate(DateTime d) =>
      DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());

  Widget _cloudBadge(String? status) {
    switch (status) {
      case 'done':
        return _CloudBadge(label: 'کلاؤڈ: مکمل', color: AppColors.success);
      case 'uploading':
        return _CloudBadge(
            label: 'کلاؤڈ: اپ لوڈ ہو رہا ہے', color: AppColors.info);
      case 'failed':
        return _CloudBadge(
            label: 'کلاؤڈ: ناکام (دوبارہ کوشش ہوگی)', color: AppColors.error);
      case 'pending':
        return _CloudBadge(label: 'کلاؤڈ: قطار میں', color: AppColors.warning);
      default:
        return _CloudBadge(label: 'صرف مقامی', color: AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      scrollable: false,
      header: PageHeader(
        title: 'بیک اپ',
        breadcrumb: 'منتظم',
        description: 'مکمل ڈیٹا ایک فائل میں — انٹرنیٹ کے بغیر بھی کام کرتا ہے',
        actions: _withBack(context, []),
      ),
      child: _loading
          ? const M360LoadingState()
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  M360Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'مکمل ڈیٹا ایک فائل میں محفوظ کریں',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: AppTypography.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'انٹرنیٹ کے بغیر بھی کام کرتا ہے',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        M360PrimaryButton(
                          label: 'ابھی بیک اپ بنائیں',
                          icon: Icons.backup,
                          fullWidth: true,
                          isLoading: _working,
                          onPressed: _working ? null : _backupNow,
                        ),
                        if (_status != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _status!,
                            textDirection: TextDirection.rtl,
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  M360SectionHeader(
                    title: 'محفوظ بیک اپ',
                    subtitle: '${_backups.length} فائلیں',
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  if (_backups.isEmpty)
                    M360Card(
                      child: Text(
                        'ابھی کوئی بیک اپ نہیں — اوپر بٹن دبائیں۔',
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                  for (final b in _backups) _backupCard(b),
                ],
              ),
            ),
    );
  }

  Widget _backupCard(BackupMetadata b) {
    final m = b.manifest;
    return M360Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M360LatinText(
            b.file.path.split('/').last,
            style:
                AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            m == null
                ? 'نامعلوم فائل — تصدیق نہیں ہوئی'
                : '${_fmtDate(m.exportedAt)} • '
                    '${BackupService.formatBytes(b.sizeBytes)} • '
                    '${m.totalRows} ریکارڈ',
            textDirection: TextDirection.rtl,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          if (b.note != null)
            Text(
              b.note!,
              textDirection: TextDirection.rtl,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _cloudBadge(b.cloudStatus),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              M360SecondaryButton(
                label: 'تصدیق کریں',
                onPressed: _working ? null : () => _verify(b),
              ),
              M360DangerButton(
                label: 'ریسٹور کریں',
                onPressed: _working ? null : () => _restore(b),
              ),
              if (b.cloudStatus == null || b.cloudStatus == 'failed')
                M360TertiaryButton(
                  label: 'کلاؤڈ کاپی',
                  onPressed: _working ? null : () => _cloudCopy(b),
                ),
              M360IconButton(
                icon: Icons.delete_outline,
                tooltip: 'حذف کریں',
                color: AppColors.error,
                onPressed: _working ? null : () => _delete(b),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// RTL-aware colored pill badge for the cloud-sync state of a backup.
class _CloudBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CloudBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: AppTypography.labelMedium
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
