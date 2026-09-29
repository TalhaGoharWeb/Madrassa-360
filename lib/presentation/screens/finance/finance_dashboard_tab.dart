/// مالی ڈیش بورڈ — read-only summary of the whole مالی system.
///
/// All numbers come from [FinanceHubOverview], which aggregates the two
/// existing repositories (fee rows + posted ledger) — no new queries,
/// no invented statistics. Amounts use the shared [formatPK] formatter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/design/m360.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money_format.dart';
import '../../shell/shell_nav.dart';
import '../../viewmodels/finance/finance_overview_provider.dart';
import '../../viewmodels/finance/financial_views.dart';
import 'finance_hub_screen.dart';
import 'finance_ui.dart';

/// مالی ڈیش بورڈ
class FinanceDashboardTab extends ConsumerWidget {
  const FinanceDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(financeHubOverviewProvider);
    return overviewAsync.when(
      loading: () => const M360LoadingState(),
      error: (e, _) => M360ErrorState(
        message: 'مالیاتی خلاصہ لوڈ کرنے میں خطا',
        onRetry: () => ref.invalidate(financeHubOverviewProvider),
      ),
      data: (overview) => _buildBody(context, ref, overview),
    );
  }

  bool _isEmpty(FinanceHubOverview o) =>
      o.postedIncome == 0 &&
      o.postedExpense == 0 &&
      o.totalOutstanding == 0 &&
      o.pendingRecords == 0;

  Widget _buildBody(BuildContext context, WidgetRef ref, FinanceHubOverview o) {
    if (_isEmpty(o)) {
      return M360EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'مالیاتی ڈیٹا موجود نہیں',
        description:
            'ابھی کوئی فیس ریکارڈ یا لیجر اندراج نہیں۔ واؤچر یا لیجر اندراج کے بعد خلاصہ یہاں نظر آئے گا۔',
        actionLabel: 'طلبہ کی فیس کھولیں',
        onAction: () => requestShellNav(ref, 'student_fees'),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _statGrid(o),
        const FinanceSectionHeader(title: 'فوری توجہ کے بقایا جات'),
        _topDuesCard(ref, o),
        const FinanceSectionHeader(title: 'حالیہ ادائیگیاں'),
        _recentPaymentsCard(ref, o),
      ],
    );
  }

  Widget _statGrid(FinanceHubOverview o) {
    final cards = [
      _Stat(
        label: 'حتمی آمدن (روپے)',
        value: formatPK(o.postedIncome),
        icon: Icons.trending_up,
        color: AppColors.success,
      ),
      _Stat(
        label: 'حتمی اخراجات (روپے)',
        value: formatPK(o.postedExpense),
        icon: Icons.trending_down,
        color: AppColors.error,
      ),
      _Stat(
        label: 'خالص بیلنس (روپے)',
        value: formatPK(o.balance),
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.primary,
      ),
      _Stat(
        label: 'کل بقایا (روپے)',
        value: formatPK(o.totalOutstanding),
        icon: Icons.pending_actions_outlined,
        color: AppColors.warning,
      ),
      _Stat(
        label: 'اس ماہ وصول شدہ (روپے)',
        value: formatPK(o.monthCollected),
        icon: Icons.calendar_month_outlined,
        color: AppColors.primary,
      ),
      _Stat(
        label: 'واجب الادا ریکارڈ',
        value: '${o.overdueRecords}',
        icon: Icons.warning_amber_outlined,
        color: AppColors.error,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 720 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 132,
          ),
          itemCount: cards.length,
          itemBuilder: (context, i) {
            final c = cards[i];
            return M360StatCard(
              value: c.value,
              label: c.label,
              icon: c.icon,
              valueColor: c.color,
            );
          },
        );
      },
    );
  }

  Widget _topDuesCard(WidgetRef ref, FinanceHubOverview o) {
    if (o.topDues.isEmpty) {
      return const M360Card(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'کوئی بقایا نہیں — تمام فیس وصول ہو چکی ہے۔',
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
      );
    }
    return M360Card(
      child: Column(
        children: [
          for (var i = 0; i < o.topDues.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(M360Radius.md),
              onTap: () =>
                  requestShellNav(ref, FinanceSection.dues.destinationId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_outline,
                          color: AppColors.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.topDues[i].studentName,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${o.topDues[i].monthCount} ریکارڈ بقایا',
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatPK(o.topDues[i].remaining),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                    ),
                    const Icon(Icons.chevron_left,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            if (i < o.topDues.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }

  Widget _recentPaymentsCard(WidgetRef ref, FinanceHubOverview o) {
    if (o.recentPayments.isEmpty) {
      return const M360Card(
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.textSecondary),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'مالیاتی نظام میں ابھی کوئی ادائیگی درج نہیں۔',
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
      );
    }
    return M360Card(
      child: Column(
        children: [
          for (var i = 0; i < o.recentPayments.length; i++) ...[
            Builder(builder: (context) {
              final p = PaymentView(o.recentPayments[i]);
              return InkWell(
                borderRadius: BorderRadius.circular(M360Radius.md),
                onTap: () =>
                    requestShellNav(ref, FinanceSection.payments.destinationId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.payments_outlined,
                            color: AppColors.success),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.studentLabel,
                              textDirection: TextDirection.rtl,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${p.receiptLabel} • ${urduTimeAgo(p.payment.paymentDate)}',
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        p.amountLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (i < o.recentPayments.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _Stat {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}
