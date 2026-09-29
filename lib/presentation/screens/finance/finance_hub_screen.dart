/// مالی — متحد مالیاتی مرکز (Phase 9)
/// Unified finance hub.
///
/// One shell destination per finance area (مالی ڈیش بورڈ، واجبات،
/// انوائسز، ادائیگیاں، لیجر، اخراجات) all rendered by [FinanceHubScreen]
/// with the requested [FinanceSection]. The section chip bar at the top
/// switches through the real shell destinations via [requestShellNav],
/// so the rail/drawer selection stays in sync and every section keeps
/// its own permission gate from [navDestinations].
///
/// Data comes from the two existing repositories — [fee_repository] via
/// [fee_provider] and [finance_repository] via [finance_provider] — which
/// stay separate (no merges, no schema changes). [FinanceHubOverview]
/// and the view adapters in [financial_views] are the only bridge, and
/// they are read-only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/design/m360.dart';
import '../../shell/shell_nav.dart';
import '../../shell/shell_page_body.dart';
import '../reports/reports_hub_screen.dart';
import 'finance_dashboard_tab.dart';
import 'finance_dues_tab.dart';
import 'finance_expenses_tab.dart';
import 'finance_invoices_tab.dart';
import 'finance_ledger_tab.dart';
import 'finance_payments_tab.dart';

/// The finance areas of the hub.
enum FinanceSection {
  /// مالی ڈیش بورڈ
  dashboard,

  /// واجبات
  dues,

  /// انوائسز
  invoices,

  /// ادائیگیاں
  payments,

  /// لیجر
  ledger,

  /// اخراجات
  expenses,

  /// مالی رپورٹس
  reports,
}

/// Shell destination id for a section.
extension FinanceSectionNav on FinanceSection {
  String get destinationId {
    switch (this) {
      case FinanceSection.dashboard:
        return 'finance_dashboard';
      case FinanceSection.dues:
        return 'finance_dues';
      case FinanceSection.invoices:
        return 'finance_invoices';
      case FinanceSection.payments:
        return 'finance_payments';
      case FinanceSection.ledger:
        return 'finance_ledger';
      case FinanceSection.expenses:
        return 'finance_expenses';
      case FinanceSection.reports:
        return 'finance_reports';
    }
  }

  String get labelUr {
    switch (this) {
      case FinanceSection.dashboard:
        return 'مالی ڈیش بورڈ';
      case FinanceSection.dues:
        return 'واجبات';
      case FinanceSection.invoices:
        return 'انوائسز';
      case FinanceSection.payments:
        return 'ادائیگیاں';
      case FinanceSection.ledger:
        return 'لیجر';
      case FinanceSection.expenses:
        return 'اخراجات';
      case FinanceSection.reports:
        return 'مالی رپورٹس';
    }
  }

  IconData get icon {
    switch (this) {
      case FinanceSection.dashboard:
        return Icons.dashboard_outlined;
      case FinanceSection.dues:
        return Icons.pending_actions_outlined;
      case FinanceSection.invoices:
        return Icons.receipt_long_outlined;
      case FinanceSection.payments:
        return Icons.account_balance_wallet_outlined;
      case FinanceSection.ledger:
        return Icons.book_outlined;
      case FinanceSection.expenses:
        return Icons.shopping_cart_outlined;
      case FinanceSection.reports:
        return Icons.bar_chart_outlined;
    }
  }
}

/// Unified finance hub — renders [section]; the chip bar switches
/// between the seven real shell destinations.
class FinanceHubScreen extends ConsumerWidget {
  const FinanceHubScreen({super.key, required this.section});

  final FinanceSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellPageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: section.labelUr,
            breadcrumb: 'مالی',
            description: _description,
          ),
          _SectionChips(active: section),
          Expanded(child: _sectionBody()),
        ],
      ),
    );
  }

  String get _description {
    switch (section) {
      case FinanceSection.dashboard:
        return 'آمدن، اخراجات، واجبات اور بقایا جات کا خلاصہ';
      case FinanceSection.dues:
        return 'طلبہ کے بقایا جات اور واجب الادا فیس';
      case FinanceSection.invoices:
        return 'انوائسز — مسودہ، جاری اور منسوخی';
      case FinanceSection.payments:
        return 'وصول شدہ ادائیگیوں کا ریکارڈ';
      case FinanceSection.ledger:
        return 'مالیاتی لیجر — آمدن و اخراجات کی حتمی کتاب';
      case FinanceSection.expenses:
        return 'اخراجات کا اندراج اور منظوری';
      case FinanceSection.reports:
        return 'فیس، واجبات اور مالیاتی رپورٹس کا مکمل کیٹلاگ';
    }
  }

  Widget _sectionBody() {
    switch (section) {
      case FinanceSection.dashboard:
        return const FinanceDashboardTab();
      case FinanceSection.dues:
        return const FinanceDuesTab();
      case FinanceSection.invoices:
        return const FinanceInvoicesTab();
      case FinanceSection.payments:
        return const FinancePaymentsTab();
      case FinanceSection.ledger:
        return const FinanceLedgerTab();
      case FinanceSection.expenses:
        return const FinanceExpensesTab();
      case FinanceSection.reports:
        return const ReportsHubScreen();
    }
  }
}

/// Horizontal section switcher — navigates the real shell destinations
/// so nav selection stays in sync.
class _SectionChips extends ConsumerWidget {
  const _SectionChips({required this.active});

  final FinanceSection active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          for (final s in FinanceSection.values) ...[
            ChoiceChip(
              label: Text(s.labelUr),
              avatar: Icon(s.icon, size: 18),
              selected: s == active,
              onSelected: (_) {
                if (s != active) requestShellNav(ref, s.destinationId);
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
