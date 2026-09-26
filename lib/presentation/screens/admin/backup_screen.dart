/// بیک اپ اسکرین — One-file offline backup & restore UI (admin).
///
/// All operations work OFFLINE: backup now, verify, restore (with typed
/// confirmation), backup list, delete. The optional cloud copy is
/// best-effort via the existing `pending_uploads` sync machinery — the
/// local file is always the source of truth.
///
/// NOT compiled/analyzed in this environment (no Flutter/Dart toolchain) —
/// run `flutter analyze` + `flutter test` on a dev machine before merging.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/backup/backup_service.dart';
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
      setState(() => _status = 'فہرست لوڈ نہیں ہو سکی: $e');
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'خرابی: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خرابی: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('بیک اپ کامیابی سے بن گیا / Backup created')),
        );
        await _refresh();
      });

  Future<void> _verify(BackupMetadata meta) => _run(() async {
        final v = await _service.verifyBackup(meta.file.path);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(v.valid
                ? 'بیک اپ درست ہے / Valid'
                : 'بیک اپ ناقص ہے / Invalid'),
            content: v.valid
                ? Text('ریکارڈ: ${v.manifest!.totalRows}\n'
                    'تاریخ: ${_fmtDate(v.manifest!.exportedAt)}\n'
                    'چیک سم: درست / checksum OK')
                : Text('وجوہات:\n${v.reasons.join('\n')}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('بند کریں / Close')),
            ],
          ),
        );
      });

  Future<void> _restore(BackupMetadata meta) => _run(() async {
        // Typed confirmation: the user must type RESTORE exactly.
        final typed = await _askTypedConfirmation(meta);
        if (typed == null) return; // user cancelled
        try {
          final outcome = await _service.restoreBackup(
            meta.file.path,
            confirmationToken: typed,
          );
          if (!mounted) return;
          // The provider override still points at the CLOSED connection, so
          // do NOT call _refresh() here (the old db can't run queries).
          // The user must restart the app; the pre-restore copy is the
          // safety net if anything went wrong.
          setState(() => _status = 'ریسٹور مکمل۔ ایپ دوبارہ شروع کریں۔\n'
              'Restore complete — restart the app to use the restored data.\n'
              'حفاظتی کاپی: ${outcome.report.preRestoreCopy}');
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('ریسٹور مکمل / Restore complete'),
              content: Text(
                  'پرانے ڈیٹا کی حفاظتی کاپی محفوظ ہے:\n${outcome.report.preRestoreCopy}\n\n'
                  'براہ کرم ایپ بند کر کے دوبارہ کھولیں۔\nPlease restart the app.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('ٹھیک ہے / OK')),
              ],
            ),
          );
          // NOTE: no _refresh() here — the live connection was closed by
          // the restore; the app must be restarted before any DB access.
        } on StateError catch (e) {
          if (!mounted) return;
          setState(() => _status = 'ریسٹور ناکام: ${e.message}');
        }
      });

  /// Returns the typed phrase, or null when the dialog was cancelled.
  Future<String?> _askTypedConfirmation(BackupMetadata meta) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title:
            const Text('خبردار / Warning', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'یہ عمل موجودہ ڈیٹا کو اس بیک اپ سے بدل دے گا:\n'
              '${meta.file.path.split('/').last}\n\n'
              'جاری رکھنے کے لیے بالکل یہی لکھیں:',
            ),
            const SizedBox(height: 4),
            const SelectableText(
              BackupService.restoreConfirmationPhrase,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type RESTORE here',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('منسوخ / Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('ریسٹور کریں / Restore'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BackupMetadata meta) => _run(() async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('حذف کریں؟ / Delete?'),
            content: Text(meta.file.path.split('/').last),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('منسوخ / Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('حذف کریں / Delete'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await _service.deleteBackup(meta.file.path);
        await _refresh();
      });

  Future<void> _cloudCopy(BackupMetadata meta) => _run(() async {
        await _service.enqueueCloudCopy(meta.file);
        if (!mounted) return;
        setState(() => _status =
            'کلاؤڈ کاپی قطار میں لگ گئی — انٹرنیٹ آنے پر اپ لوڈ ہوگی۔\n'
                'Cloud copy queued; uploads when online.');
        await _refresh();
      });

  String _fmtDate(DateTime d) =>
      DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());

  String _cloudLabel(String? status) {
    switch (status) {
      case 'done':
        return 'کلاؤڈ: مکمل ☁️✓';
      case 'uploading':
        return 'کلاؤڈ: اپ لوڈ ہو رہا ہے…';
      case 'failed':
        return 'کلاؤڈ: ناکام (دوبارہ کوشش ہوگی)';
      case 'pending':
        return 'کلاؤڈ: قطار میں ⏳';
      default:
        return 'کلاؤڈ: صرف مقامی 💾';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بیک اپ / Backup'),
        backgroundColor: AppColors.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'مکمل ڈیٹا ایک فائل میں محفوظ کریں\n'
                            'انٹرنیٹ کے بغیر بھی کام کرتا ہے',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _working ? null : _backupNow,
                            icon: _working
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.backup),
                            label:
                                const Text('ابھی بیک اپ بنائیں / Backup now'),
                          ),
                          if (_status != null) ...[
                            const SizedBox(height: 8),
                            Text(_status!,
                                style: const TextStyle(fontSize: 14)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('محفوظ بیک اپ (${_backups.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_backups.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'ابھی کوئی بیک اپ نہیں — اوپر بٹن دبائیں۔\nNo backups yet.',
                          textAlign: TextAlign.center,
                        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.file.path.split('/').last,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              m == null
                  ? 'نامعلوم فائل / unverified'
                  : '${_fmtDate(m.exportedAt)} • '
                      '${BackupService.formatBytes(b.sizeBytes)} • '
                      '${m.totalRows} ریکارڈ',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            if (b.note != null)
              Text(b.note!,
                  style: const TextStyle(fontSize: 14, color: Colors.red)),
            const SizedBox(height: 4),
            Text(_cloudLabel(b.cloudStatus),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                    onPressed: _working ? null : () => _verify(b),
                    child: const Text('تصدیق / Verify')),
                OutlinedButton(
                    onPressed: _working ? null : () => _restore(b),
                    child: const Text('ریسٹور / Restore')),
                if (b.cloudStatus == null || b.cloudStatus == 'failed')
                  OutlinedButton(
                      onPressed: _working ? null : () => _cloudCopy(b),
                      child: const Text('کلاؤڈ کاپی / Cloud copy')),
                IconButton(
                  tooltip: 'حذف کریں / Delete',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _working ? null : () => _delete(b),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
