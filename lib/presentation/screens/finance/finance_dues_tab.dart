/// واجبات — students with outstanding fee balances.
///
/// Read-only aggregation over the fee rows ([outstandingBalancesProvider]).
/// Tapping a student opens the detail sheet with their unpaid rows;
/// each row can start the real guided collection flow
/// ([CollectFeeScreen]). Permission-gated by [AppPermissions.collectFees].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../core/utils/money_format.dart';
import '../../../data/models/fee.dart';
import '../../../providers/auth_provider.dart';
import '../../viewmodels/finance/finance_overview_provider.dart';
import '../../viewmodels/finance/financial_views.dart';
import 'collect_fee_screen.dart';
import 'finance_ui.dart';

/// واجبات
class FinanceDuesTab extends ConsumerStatefulWidget {
  const FinanceDuesTab({super.key});

  @override
  ConsumerState<FinanceDuesTab> createState() => _FinanceDuesTabState();
}

class _FinanceDuesTabState extends ConsumerState<FinanceDuesTab> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duesAsync = ref.watch(outstandingBalancesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: M360SearchField(
            controller: _searchController,
            hint: 'طالب علم تلاش کریں…',
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: duesAsync.when(
            loading: () => const M360LoadingState(),
            error: (e, _) => M360ErrorState(
              message: 'واجبات لوڈ کرنے میں خطا',
              onRetry: () => ref.invalidate(outstandingBalancesProvider),
            ),
            data: (dues) => _buildList(dues),
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<OutstandingBalanceView> dues) {
    final filtered = _query.isEmpty
        ? dues
        : dues
            .where((d) =>
                d.studentName.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    if (filtered.isEmpty) {
      return M360EmptyState(
        icon: Icons.check_circle_outline,
        title: dues.isEmpty ? 'کوئی واجبات نہیں' : 'کوئی طالب علم نہیں ملا',
        description: dues.isEmpty
            ? 'تمام طلبہ کی فیس وصول ہو چکی ہے۔'
            : 'تلاش تبدیل کر کے دوبارہ کوشش کریں۔',
      );
    }
    final total = filtered.fold<double>(0, (s, d) => s + d.remaining);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: filtered.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _totalBanner(total, filtered.length);
        return _dueTile(filtered[i - 1]);
      },
    );
  }

  Widget _totalBanner(double total, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: M360StatCard(
        value: formatPK(total),
        label: 'کل واجبات (روپے) • $count طلبہ',
        icon: Icons.pending_actions_outlined,
        valueColor: AppColors.error,
      ),
    );
  }

  Widget _dueTile(OutstandingBalanceView due) {
    final canCollect =
        ref.watch(hasPermissionProvider(AppPermissions.collectFees));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: M360Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(M360Radius.md),
          onTap: () => _showDueSheet(due, canCollect),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: (due.overdueCount > 0
                          ? AppColors.error
                          : AppColors.warning)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  due.overdueCount > 0
                      ? Icons.warning_amber_outlined
                      : Icons.schedule_outlined,
                  color: due.overdueCount > 0
                      ? AppColors.error
                      : AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      due.studentName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${due.studentClass} • ${due.monthCount} ماہ بقایا',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    due.remainingLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Text(
                    'روپے بقایا',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              const Icon(Icons.chevron_left, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// Student dues detail — unpaid rows oldest first, each row opens the
  /// real collection flow.
  void _showDueSheet(OutstandingBalanceView due, bool canCollect) {
    showM360Dialog(
      context,
      title: '${due.studentName} — واجبات',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < due.records.length; i++) ...[
            _dueRow(due.records[i], canCollect),
            if (i < due.records.length - 1) const Divider(),
          ],
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: 'بند کریں',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _dueRow(Fee record, bool canCollect) {
    final view = FeeRecordView(record);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.monthLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textDirection: TextDirection.rtl,
                ),
                Text(
                  'بقایا: ${view.remainingLabel} روپے',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ),
          ),
          financeChip(view.chipKind),
          if (canCollect) ...[
            const SizedBox(width: 8),
            M360PrimaryButton(
              label: 'وصول کریں',
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CollectFeeScreen(fee: record),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
