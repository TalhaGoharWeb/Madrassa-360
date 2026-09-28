/// تنازعات کا جائزہ
/// Conflict Review Screen — lists unresolved `sync_conflicts` rows for the
/// ACTIVE tenant and lets a privileged user resolve each one.
///
/// Resolution actions (mirror the engine's rules, see sync_engine.dart):
///   * "Keep server" (سرور رکھیں) — discard the local change, apply the
///     fresh server row locally. Available for every conflict.
///   * "Retry local as new revision" (مقامی تبدیلی دوبارہ بھیجیں) —
///     re-enqueue the local payload with a fresh base_revision. Only for
///     NON-FINANCIAL entities.
///   * Financial entities (invoices, payments, transactions, refunds) show
///     an explanatory note instead: corrections must go through the finance
///     reversal flow, with a link to [FinanceScreen]. Sync never overwrites
///     server financial data.
///
/// Style follows the existing screens (AppColors / AppTypography / AppCard /
/// EmptyState). Tenant scoping comes from [syncConflictsProvider], which is
/// already scoped to the active tenant.
///
/// NOTE: UNCOMPILED — no Flutter toolchain in this environment.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../../presentation/widgets/common/app_widgets.dart';
import '../../presentation/screens/admin/finance_screen.dart';
import 'sync_engine.dart';
import 'sync_providers.dart';

/// تنازعات کا جائزہ — Sync conflict review.
class ConflictReviewScreen extends ConsumerWidget {
  const ConflictReviewScreen({super.key});

  static const _entityLabels = {
    'students': 'طلبہ',
    'classes': 'جماعتیں',
    'darjas': 'درجات',
    'attendance': 'حاضری',
    'exams': 'امتحانات',
    'results': 'نتائج',
    'announcements': 'اعلانات',
    'invoices': 'انوائسز',
    'payments': 'ادائیگیاں',
    'transactions': 'لین دین',
    'refunds': 'ریفنڈز',
    'fees': 'فیس',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictsAsync = ref.watch(syncConflictsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('سنک تنازعات', style: AppTypography.appBarTitle),
      ),
      body: conflictsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child:
              Text('تنازعات لوڈ کرنے میں خطا', style: AppTypography.bodyMedium),
        ),
        data: (conflicts) {
          if (conflicts.isEmpty) {
            return const EmptyState(
              icon: Icons.cloud_done,
              title: 'کوئی تنازع نہیں',
              subtitle: 'تمام تبدیلیاں کامیابی سے سنک ہو گئیں',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(syncConflictsProvider);
              await ref.read(syncEngineProvider)?.syncNow();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: conflicts.length,
              itemBuilder: (context, i) =>
                  _ConflictCard(conflict: conflicts[i]),
            ),
          );
        },
      ),
    );
  }

  static String entityLabel(String entity) => _entityLabels[entity] ?? entity;
}

class _ConflictCard extends ConsumerStatefulWidget {
  final SyncConflict conflict;

  const _ConflictCard({required this.conflict});

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  bool _expanded = false;
  bool _busy = false;

  SyncConflict get c => widget.conflict;

  @override
  Widget build(BuildContext context) {
    final financial = c.isFinancial;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── header ──
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: financial
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : AppColors.info.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ConflictReviewScreen.entityLabel(c.entity),
                    style: AppTypography.labelMedium.copyWith(
                      color: financial ? AppColors.warning : AppColors.info,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shortId(c.entityId),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                  ),
                ),
                Text(
                  _formatDate(c.createdAt),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _reasonText(c.reason),
              style: AppTypography.bodyMedium,
            ),
            // ── local vs server summary ──
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                  _expanded ? 'تفصیل چھپائیں' : 'مقامی بمقابلہ سرور دیکھیں'),
            ),
            if (_expanded) _buildComparison(),
            const SizedBox(height: 8),
            // ── actions ──
            if (financial)
              _buildFinancialNote(context)
            else
              _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildComparison() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child:
                  _payloadColumn('مقامی', c.localPayload, AppColors.primary)),
          const SizedBox(width: 8),
          Expanded(
              child: _payloadColumn(
                  'سرور', c.serverPayload ?? const {}, AppColors.info)),
        ],
      ),
    );
  }

  Widget _payloadColumn(
      String title, Map<String, dynamic> payload, Color accent) {
    final entries = payload.entries
        // Review metadata lives in `_`-prefixed keys (see SyncConflict);
        // never show it as data, and never send it back to the server.
        .where((e) => !e.key.startsWith('_') && !_skippedKeys.contains(e.key))
        .take(8)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge.copyWith(color: accent)),
        const SizedBox(height: 4),
        if (entries.isEmpty) Text('—', style: AppTypography.bodySmall),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${e.key}: ${_shortValue(e.value)}',
              style: AppTypography.bodySmall,
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
      ],
    );
  }

  static const _skippedKeys = {
    'tenant_id',
    'server_version',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  Widget _buildActions(BuildContext context) {
    if (_busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _resolve(context, keepServer: true),
            icon: const Icon(Icons.cloud_download),
            label: const Text('سرور رکھیں'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _resolve(context, keepServer: false),
            icon: const Icon(Icons.cloud_upload),
            label: const Text('مقامی دوبارہ بھیجیں'),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lock, size: 18, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'مالیاتی ریکارڈ محفوظ ہے — سرور کا ڈیٹا تبدیل نہیں ہوا',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'رقم سے متعلق تنازعات سنک سے حل نہیں ہوتے۔ اصلاح صرف فنانس '
            'ریورسل فلو کے ذریعے کریں تاکہ آڈٹ ٹریل محفوظ رہے۔',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _resolve(context, keepServer: true),
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('سرور رکھیں (مقامی حذف کریں)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FinanceScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance),
                  label: const Text('فنانس کھولیں'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context,
      {required bool keepServer}) async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    setState(() => _busy = true);
    try {
      if (keepServer) {
        await engine.resolveConflictKeepServer(c.id);
      } else {
        await engine.resolveConflictRetryLocal(c.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تنازع حل ہو گیا')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حل ناکام: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _shortId(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

  String _shortValue(dynamic v) {
    final s = '$v';
    return s.length > 40 ? '${s.substring(0, 40)}…' : s;
  }

  String _reasonText(String reason) {
    switch (reason) {
      case 'conflict':
        return 'سنک تنازع: سرور پر نئی ریویژن موجود — جائزے کے لیے روک دیا گیا';
      case 'already_exists':
        return 'سرور پر یہ ریکارڈ پہلے سے موجود ہے';
      case 'deleted':
        return 'سرور پر یہ ریکارڈ حذف شدہ ہے';
      case 'conflict_after_rebase':
        return 'دوبارہ کوشش کے بعد بھی تنازع برقرار — دستی جائزہ درکار';
      default:
        return 'سنک تنازع ($reason) — جائزے کے لیے روک دیا گیا';
    }
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
