import 'package:flutter/material.dart' hide DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/reports/documents/fee_receipt.dart';
import '../../../core/reports/report_branding.dart';
import '../../../core/reports/urdu_pdf.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/fee.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/student_provider.dart';
import '../../shell/shell_page_body.dart';
import '../../widgets/common/app_widgets.dart';

/// فیس کا انتظام — لین دین کا رہنما بہاؤ (redesign)
/// Fee Management Screen — guided transaction-flow redesign.
///
/// Presentation layer only. Everything in the business layer is reused
/// unchanged: [allFeesProvider], [feeNotifierProvider] (save/validation),
/// [allStudentsProvider], the tenant-scoped repository, and the real PDF
/// receipt ([FeeReceiptPdf.build] → [Printing.layoutPdf]).
///
/// UX changes (presentation only):
///
/// * Tab 1 (فیس کی تفصیل): added a student search field + a tappable fee
///   row opens a **guided 4-step wizard** (تفصیل → رقم → تصدیق → رسید)
///   instead of the old stacked dialogs. Outstanding balance (بقایا) is
///   the hero number at every step, with three clear status badges:
///   ادا شدہ (green) / جزوی ادائیگی (amber) / بقایا (red).
/// * Collection validation (amount > 0, ≤ remaining), the paid-date stamp,
///   the "فیس کی قسم = ماہانہ فیس" label, and receipt-number format are
///   identical to the pre-redesign implementation.
/// * There is deliberately NO "payment method" step: the [Fee] model and
///   repository have no payment-method concept, and the brief forbids
///   inventing one. The confirm step shows exactly what is recorded.
///
/// Tab 2 (وصولی) is unchanged — real tenant collection stats + recent
/// receipts. The "نیا واؤچر" FAB flow is unchanged.
class FeeManagementScreen extends ConsumerStatefulWidget {
  const FeeManagementScreen({super.key});

  @override
  ConsumerState<FeeManagementScreen> createState() =>
      _FeeManagementScreenState();
}

class _FeeManagementScreenState extends ConsumerState<FeeManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedStatus = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellPageBody(
      tabBar: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTypography.labelLarge,
        tabs: const [
          Tab(text: 'فیس کی تفصیل'),
          Tab(text: 'وصولی'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fee_voucher_fab',
        onPressed: () => _showNewVoucherDialog(context),
        icon: const Icon(Icons.add),
        label: Text(
          'نیا واؤچر',
          style: AppTypography.buttonText,
        ),
      ),
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildFeeListTab(),
          _buildCollectionTab(),
        ],
      ),
    );
  }

  // ── Tab 1: fee list with search + guided collection flow ─────

  Widget _buildFeeListTab() {
    return Consumer(builder: (context, ref, _) {
      final feeAsync = ref.watch(allFeesProvider);
      final feeRecords = feeAsync.valueOrNull ?? [];

      if (feeAsync.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (feeAsync.hasError) {
        return Center(
          child: Text('فیس لوڈ کرنے میں خطا', style: AppTypography.bodyMedium),
        );
      }

      return Column(
        children: [
          // Summary Cards
          _buildFeeSummary(feeRecords),

          // Student search — pick the student, then the fee
          _buildSearchField(),

          // Filter Chips
          _buildStatusFilter(),

          // Fee List
          Expanded(
            child: _buildFeeList(feeRecords),
          ),
        ],
      );
    });
  }

  /// Search field: filters the fee list by student name / class.
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        decoration: InputDecoration(
          hintText: 'طالب علم تلاش کریں…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _searchQuery = ''),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFeeSummary(List<Fee> records) {
    final collected = records
        .where((r) => r.status == FeeStatus.paid)
        .fold<double>(0, (sum, r) => sum + r.amountPaid);
    final pending = records
        .where((r) => r.status != FeeStatus.paid)
        .fold<double>(0, (sum, r) => sum + r.remaining);

    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              icon: Icons.check_circle,
              label: 'وصول شدہ',
              value: '${collected.toInt()}',
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard(
              icon: Icons.pending,
              label: 'زیر التواء',
              value: '${pending.toInt()}',
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard(
              icon: Icons.warning,
              label: 'واجب الادا',
              value:
                  '${records.where((r) => r.status == FeeStatus.pastDue).length}',
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.titleLarge.copyWith(color: color),
          ),
          Text(
            label,
            style: AppTypography.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    final statuses = [
      {'id': 'all', 'label': 'سب', 'color': AppColors.primary},
      {'id': 'paid', 'label': 'ادا شدہ', 'color': AppColors.success},
      {'id': 'partial', 'label': 'جزوی', 'color': AppColors.warning},
      {'id': 'pending', 'label': 'زیر التواء', 'color': AppColors.info},
      {'id': 'pastDue', 'label': 'واجب الادا', 'color': AppColors.error},
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: statuses.length,
        itemBuilder: (context, index) {
          final status = statuses[index];
          final isSelected = _selectedStatus == status['id'];
          final color = status['color'] as Color;

          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(status['label'] as String),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedStatus = status['id'] as String);
              },
              selectedColor: color.withValues(alpha: 0.2),
              checkmarkColor: color,
              labelStyle: AppTypography.labelMedium.copyWith(
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeeList(List<Fee> records) {
    var filteredRecords = records;

    if (_selectedStatus != 'all') {
      final status = FeeStatus.values.firstWhere(
        (s) => s.name == _selectedStatus,
        orElse: () => FeeStatus.pending,
      );
      filteredRecords = records.where((r) => r.status == status).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredRecords = filteredRecords
          .where((r) =>
              r.studentName.toLowerCase().contains(q) ||
              r.studentClass.toLowerCase().contains(q))
          .toList();
    }

    if (filteredRecords.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'کوئی فیس ریکارڈ نہیں',
        subtitle: 'فلٹر یا تلاش تبدیل کریں',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: filteredRecords.length,
      itemBuilder: (context, index) {
        final record = filteredRecords[index];
        return _buildFeeRecordTile(record);
      },
    );
  }

  /// Fee row — outstanding balance is the hero number, with a payment
  /// progress bar and the three guided-flow status badges:
  /// ادا شدہ (green) / جزوی ادائیگی (amber) / بقایا (red).
  /// Tapping a row opens the guided collection wizard.
  Widget _buildFeeRecordTile(Fee record) {
    final color = _displayStatusColor(record.status);
    final progress = record.amountDue > 0
        ? (record.amountPaid / record.amountDue).clamp(0.0, 1.0)
        : 0.0;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _CollectFeeFlow(fee: record),
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Indicator
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getStatusIcon(record.status),
              color: color,
            ),
          ),
          const SizedBox(width: 12),

          // Info + progress + outstanding
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.studentName,
                  style: AppTypography.titleMedium,
                ),
                Text(
                  '${record.studentClass} - ${_monthLabel(record.month)}',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ادا شدہ: ${record.amountPaid.toInt()}',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                    if (record.remaining > 0)
                      Text(
                        'بقایا: ${record.remaining.toInt()} روپے',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Status badge (guided-flow display mapping)
          _displayStatusBadge(record.status),
        ],
      ),
    );
  }

  /// Guided-flow status badges — presentation mapping of the exact
  /// [FeeStatus] values the code supports:
  /// ادا شدہ (green) / جزوی ادائیگی (amber) / بقایا (red).
  Color _displayStatusColor(FeeStatus status) {
    switch (status) {
      case FeeStatus.paid:
        return AppColors.success;
      case FeeStatus.partial:
        return AppColors.warning;
      case FeeStatus.pending:
      case FeeStatus.pastDue:
        return AppColors.error;
    }
  }

  String _displayStatusLabel(FeeStatus status) {
    switch (status) {
      case FeeStatus.paid:
        return 'ادا شدہ';
      case FeeStatus.partial:
        return 'جزوی ادائیگی';
      case FeeStatus.pending:
      case FeeStatus.pastDue:
        return 'بقایا';
    }
  }

  Widget _displayStatusBadge(FeeStatus status) {
    final color = _displayStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _displayStatusLabel(status),
        style: AppTypography.labelNastaliq.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  IconData _getStatusIcon(FeeStatus status) {
    switch (status) {
      case FeeStatus.paid:
        return Icons.check_circle;
      case FeeStatus.partial:
        return Icons.pie_chart;
      case FeeStatus.pending:
        return Icons.schedule;
      case FeeStatus.pastDue:
        return Icons.warning;
    }
  }

  /// '2026-09' → 'ستمبر 2026'.
  String _monthLabel(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return yearMonth;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return yearMonth;
    return '${DateUtils.formatMonthName(DateTime(y, m))} $y';
  }

  // ── Tab 2: collection stats (unchanged — real tenant data) ──

  /// Phase 4: collection stats and the recent-collections feed are built
  /// from the tenant's real fee rows ([allFeesProvider]) — no invented
  /// names, amounts or "12%+" trends.
  Widget _buildCollectionTab() {
    return Consumer(builder: (context, ref, _) {
      final feeAsync = ref.watch(allFeesProvider);
      final records = feeAsync.valueOrNull ?? [];
      final paid = records.where((r) => r.status == FeeStatus.paid).toList()
        ..sort((a, b) => (b.paidDate ?? '').compareTo(a.paidDate ?? ''));

      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final todayPaid = paid.where((r) => r.paidDate == todayStr).toList();
      final todayTotal =
          todayPaid.fold<double>(0, (sum, r) => sum + r.amountPaid);

      if (feeAsync.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (feeAsync.hasError) {
        return Center(
          child: Text('فیس لوڈ کرنے میں خطا', style: AppTypography.bodyMedium),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Collection Stats — real tenant data
            AppCard(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet,
                          color: Colors.white, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'آج کی وصولی',
                              style: AppTypography.labelMedium.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            Text(
                              '${formatPK(todayTotal)} روپے',
                              style: AppTypography.headingMedium.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${DateUtils.formatMonthName(now)} ${now.year}',
                          style: AppTypography.labelMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCollectionStat('${paid.length}', 'رسیدیں'),
                      _buildCollectionStat('${todayPaid.length}', 'آج'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Recent Collections — the tenant's real paid fees, newest first
            const SectionHeader(
              title: 'حالیہ وصولی',
              actionText: 'سب دیکھیں',
            ),

            if (paid.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'ابھی کوئی وصولی درج نہیں',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              ...paid.take(5).map((r) => _buildCollectionItem(
                    name: r.studentName,
                    amount: formatPK(r.amountPaid),
                    time: _paidTimeLabel(r),
                    method: _monthLabel(r.month),
                  )),
          ],
        ),
      );
    });
  }

  /// Relative Urdu label for when a fee was paid.
  String _paidTimeLabel(Fee r) {
    final at = DateTime.tryParse(r.paidDate ?? '');
    if (at == null) return '';
    return urduTimeAgo(at);
  }

  Widget _buildCollectionStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.titleLarge.copyWith(color: Colors.white),
        ),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildCollectionItem({
    required String name,
    required String amount,
    required String time,
    required String method,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt,
              color: AppColors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTypography.titleSmall),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: method == 'نقد'
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        method,
                        style: AppTypography.labelSmall.copyWith(
                          color: method == 'نقد'
                              ? AppColors.success
                              : AppColors.info,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(time, style: AppTypography.labelSmall),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '$amount روپے',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  // ── New voucher dialog (unchanged) ──

  /// Phase 4: real voucher creation. The student comes from the
  /// tenant's live roster and the month from real calendar months — no
  /// free-text names, no hard-coded darja list, no frozen month names.
  /// Persists through [FeeNotifier.save]; the class shown is the selected
  /// student's own class.
  void _showNewVoucherDialog(BuildContext context) {
    final amountController = TextEditingController();
    final now = DateTime.now();
    final monthValues = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
    String selectedMonth = monthValues.first;
    String? selectedStudentId;

    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final studentsAsync = ref.watch(allStudentsProvider);
          final students = studentsAsync.valueOrNull ?? [];
          final tenantId = ref.watch(currentTenantIdProvider);
          final failed = studentsAsync.hasError || tenantId == null;

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                'نیا واؤچر بنائیں',
                style: AppTypography.titleLarge,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (studentsAsync.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    else if (failed)
                      Text(
                        'طلبہ لوڈ کرنے میں خطا',
                        style: AppTypography.bodyMedium,
                      )
                    else ...[
                      // Student Selection — the tenant's real roster
                      DropdownButtonFormField<String>(
                        initialValue: selectedStudentId,
                        decoration: const InputDecoration(
                          labelText: 'طالب علم',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        items: students.map((s) {
                          return DropdownMenuItem<String>(
                            value: s.id,
                            child: Text('${s.name} (${s.className})'),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedStudentId = value),
                      ),
                      const SizedBox(height: 16),

                      // Month Selection — real months, newest first
                      DropdownButtonFormField<String>(
                        initialValue: selectedMonth,
                        decoration: const InputDecoration(
                          labelText: 'ماہ',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_month),
                        ),
                        items: monthValues.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(_monthLabel(value)),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedMonth = value!),
                      ),
                      const SizedBox(height: 16),

                      // Amount
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'رقم',
                          border: OutlineInputBorder(),
                          prefixText: 'ر ',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('منسوخ کریں'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(amountController.text);
                    final matches = students
                        .where((s) => s.id == selectedStudentId)
                        .toList();
                    if (matches.isEmpty ||
                        amount == null ||
                        amount <= 0 ||
                        tenantId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('طالب علم منتخب کریں اور درست رقم درج کریں'),
                        ),
                      );
                      return;
                    }
                    final student = matches.first;
                    // Due on the last day of the selected month.
                    final mp = selectedMonth.split('-');
                    final due =
                        DateTime(int.parse(mp[0]), int.parse(mp[1]) + 1, 0);
                    final dueStr =
                        '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
                    final fee = Fee(
                      id: '',
                      tenantId: tenantId,
                      studentId: student.id,
                      studentName: student.name,
                      studentClass: student.className,
                      month: selectedMonth,
                      amountDue: amount,
                      amountPaid: 0,
                      dueDate: dueStr,
                      status: FeeStatus.pending,
                    );
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref.read(feeNotifierProvider.notifier).save(fee);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      messenger.showSnackBar(
                        SnackBar(
                          content:
                              Text('${student.name} کے لیے واؤچر بنا دیا گیا'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (_) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('واؤچر بنانے میں خطا')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text('واؤچر بنائیں'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Guided collection wizard: تفصیل → رقم → تصدیق → رسید
// ─────────────────────────────────────────────

/// One primary CTA per step. Validation rules, the paid-date stamp, the
/// receipt-number format, and the real PDF print path are all identical to
/// the pre-redesign dialogs — only the presentation changed.
class _CollectFeeFlow extends ConsumerStatefulWidget {
  final Fee fee;

  const _CollectFeeFlow({required this.fee});

  @override
  ConsumerState<_CollectFeeFlow> createState() => _CollectFeeFlowState();
}

class _CollectFeeFlowState extends ConsumerState<_CollectFeeFlow> {
  static const _stepLabels = ['تفصیل', 'رقم', 'تصدیق', 'رسید'];

  int _step = 0;
  late final TextEditingController _amountController;
  bool _saving = false;

  /// Payment recorded in step 2 (identical rules to the old dialog).
  double _paidAmount = 0;

  /// Fee record as returned by the notifier save (step 2 → receipt).
  Fee? _savedFee;

  String? _receiptNo;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the full outstanding balance — the common case.
    _amountController = TextEditingController(
      text: widget.fee.remaining.toString(),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // ── shared helpers (same business rules as the old dialogs) ──

  /// Receipt number — same format as the pre-redesign implementation.
  String _receiptNoFor(Fee record) =>
      '#FEE-${record.month}-${record.id.length >= 6 ? record.id.substring(0, 6).toUpperCase() : record.id.toUpperCase()}';

  /// '2026-09' → 'ستمبر 2026'.
  String _monthLabel(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return yearMonth;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return yearMonth;
    return '${DateUtils.formatMonthName(DateTime(y, m))} $y';
  }

  /// Guided-flow status badge — presentation mapping of the exact
  /// [FeeStatus] values the code supports.
  Color _statusColor(FeeStatus status) {
    switch (status) {
      case FeeStatus.paid:
        return AppColors.success;
      case FeeStatus.partial:
        return AppColors.warning;
      case FeeStatus.pending:
      case FeeStatus.pastDue:
        return AppColors.error;
    }
  }

  String _statusLabel(FeeStatus status) {
    switch (status) {
      case FeeStatus.paid:
        return 'ادا شدہ';
      case FeeStatus.partial:
        return 'جزوی ادائیگی';
      case FeeStatus.pending:
      case FeeStatus.pastDue:
        return 'بقایا';
    }
  }

  /// Validation — identical rules to the pre-redesign collection dialog:
  /// amount must be a positive number and not exceed the remaining balance.
  String? _validateAmount(String value) {
    if (value.isEmpty) return 'رقم درج کریں';
    final amount = double.tryParse(value);
    if (amount == null || amount <= 0) return 'درست رقم درج کریں';
    if (amount > widget.fee.remaining) {
      return 'رقم باقی رقم سے زیادہ نہیں ہو سکتی';
    }
    return null;
  }

  void _snack(String message, {Color color = AppColors.error}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  /// Step 2 → save through the existing notifier (Phase 4 behavior):
  /// persist the payment via [FeeNotifier.save]; DB recalculates status.
  Future<void> _confirmPayment() async {
    final error = _validateAmount(_amountController.text);
    if (error != null) {
      _snack(error);
      return;
    }
    final amount = double.parse(_amountController.text);
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final paidStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final updated = widget.fee.copyWith(
        amountPaid: widget.fee.amountPaid + amount,
        paidDate: paidStr,
      );
      final saved = await ref.read(feeNotifierProvider.notifier).save(updated);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _paidAmount = amount;
        _savedFee = saved;
        _receiptNo = _receiptNoFor(saved);
        _step = 3;
      });
      _snack(
        'ر ${formatPK(amount)} کی فیس کامیابی سے وصول کر لی گئی',
        color: AppColors.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('فیس وصول کرنے میں خطا');
    }
  }

  /// Real receipt printing — identical path to the pre-redesign
  /// implementation: branded Urdu PDF from the fee record's real data.
  Future<void> _printReceipt(Fee record, String receiptNo) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tenantId = ref.read(currentTenantIdProvider);
      final db = ref.read(appDatabaseProvider);
      final branding = await loadReportBranding(db, tenantId ?? '');
      final bytes = await FeeReceiptPdf.build(
        branding: branding,
        urdu: UrduPdf(),
        record: record,
        receiptNo: receiptNo,
        monthLabel: _monthLabel(record.month),
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('پرنٹ میں خرابی: $e')),
      );
    }
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'فیس وصول کریں',
          style: AppTypography.appBarTitle,
        ),
      ),
      body: Column(
        children: [
          _stepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                0 => _detailsStep(),
                1 => _amountStep(),
                2 => _confirmStep(),
                _ => _receiptStep(),
              },
            ),
          ),
          _bottomCta(),
        ],
      ),
    );
  }

  /// Step indicator: تفصیل → رقم → تصدیق → رسید.
  Widget _stepIndicator() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < _stepLabels.length; i++) ...[
            _stepDot(i),
            if (i < _stepLabels.length - 1) _stepConnector(i),
          ],
        ],
      ),
    );
  }

  Widget _stepDot(int i) {
    final done = i < _step;
    final active = i == _step;
    final color = (done || active) ? AppColors.primary : AppColors.divider;
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: done
                ? AppColors.success
                : active
                    ? AppColors.primary
                    : color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '${i + 1}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: active ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _stepLabels[i],
          style: AppTypography.labelNastaliq.copyWith(
            color:
                (done || active) ? AppColors.primary : AppColors.textSecondary,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _stepConnector(int i) {
    final done = i < _step;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(bottom: 26, left: 4, right: 4),
        height: 2,
        color:
            done ? AppColors.success : AppColors.divider.withValues(alpha: 0.5),
      ),
    );
  }

  /// Step 0 — تفصیل: student + fee details, outstanding balance as hero.
  Widget _detailsStep() {
    final fee = widget.fee;
    final statusColor = _statusColor(fee.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Student header
        AppCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.person, color: statusColor, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fee.studentName, style: AppTypography.headingSmall),
                    Text(
                      '${fee.studentClass} - ${_monthLabel(fee.month)}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabel(fee.status),
                  style: AppTypography.labelNastaliq.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Outstanding balance — the hero number
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'بقایا رقم',
                style: AppTypography.labelNastaliq.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatPK(fee.remaining)} روپے',
                style: AppTypography.headingLarge.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _heroStat('کل فیس', '${fee.amountDue.toInt()}'),
                  _heroStat('ادا شدہ', '${fee.amountPaid.toInt()}'),
                  _heroStat('آخری تاریخ', fee.dueDate),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  /// Step 1 — رقم: amount entry (pre-filled with remaining).
  Widget _amountStep() {
    final fee = widget.fee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: AppColors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'بقایا: ${formatPK(fee.remaining)} روپے',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'وصول کی جانے والی رقم',
            border: OutlineInputBorder(),
            prefixText: 'ر ',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ActionChip(
            label: const Text('پوری بقایا رقم'),
            avatar: const Icon(Icons.done_all, size: 16),
            onPressed: () => setState(() {
              _amountController.text = fee.remaining.toString();
            }),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'رقم باقی رقم سے زیادہ نہیں ہو سکتی',
          style: AppTypography.bodySmall,
        ),
      ],
    );
  }

  /// Step 2 — تصدیق: review exactly what will be recorded.
  Widget _confirmStep() {
    final fee = widget.fee;
    final amount = double.tryParse(_amountController.text) ?? 0;
    final afterRemaining = fee.remaining - amount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              InfoTile(
                icon: Icons.person,
                label: 'طالب علم',
                value: fee.studentName,
              ),
              InfoTile(
                icon: Icons.calendar_month,
                label: 'مہینہ',
                value: _monthLabel(fee.month),
              ),
              InfoTile(
                icon: Icons.payments,
                label: 'وصول کی جانے والی رقم',
                value: '${formatPK(amount)} روپے',
                iconColor: AppColors.success,
              ),
              InfoTile(
                icon: Icons.pending,
                label: 'اس کے بعد بقایا',
                value: '${formatPK(afterRemaining)} روپے',
                iconColor:
                    afterRemaining > 0 ? AppColors.error : AppColors.success,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'تصدیق کے بعد یہ ادائیگی فوری طور پر ریکارڈ میں محفوظ ہو جائے گی۔',
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Step 3 — رسید: confirmation + receipt details + print.
  Widget _receiptStep() {
    final record = _savedFee ?? widget.fee;
    final receiptNo = _receiptNo ?? _receiptNoFor(record);
    final paidAt = DateTime.tryParse(record.paidDate ?? '');
    // Display status after this payment (presentation mapping only).
    final afterStatus =
        record.remaining <= 0 ? FeeStatus.paid : FeeStatus.partial;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 56),
              const SizedBox(height: 8),
              Text(
                'ادائیگی کامیاب',
                style: AppTypography.headingSmall.copyWith(
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatPK(_paidAmount)} روپے وصول کر لیے گئے',
                style: AppTypography.titleMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'فیس کی رسید',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const Divider(height: 24),
              _receiptRow('رسید نمبر', receiptNo),
              _receiptRow('طالب علم کا نام', record.studentName),
              _receiptRow('کلاس', record.studentClass),
              _receiptRow('مہینہ', _monthLabel(record.month)),
              _receiptRow('فیس کی قسم', 'ماہانہ فیس'),
              _receiptRow('وصول شدہ رقم', '${formatPK(_paidAmount)} روپے'),
              _receiptRow('بقایا', '${formatPK(record.remaining)} روپے'),
              _receiptRow('حیثیت', _statusLabel(afterStatus)),
              _receiptRow('تاریخ',
                  paidAt == null ? '—' : DateUtils.formatDateUrdu(paidAt)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                label: Text(
                  'بند کریں',
                  style: AppTypography.labelNastaliq,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _printReceipt(record, receiptNo),
                icon: const Icon(Icons.print),
                label: Text(
                  'پرنٹ کریں',
                  style: AppTypography.labelNastaliq.copyWith(
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: AppTypography.bodyMedium
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// One primary CTA per step (back affordance where it makes sense).
  Widget _bottomCta() {
    if (_step == 3) return const SizedBox.shrink();

    final Widget primary = switch (_step) {
      0 => _ctaButton(
          label: widget.fee.remaining > 0 ? 'فیس وصول کریں' : 'رسید دیکھیں',
          icon: Icons.payments,
          color: AppColors.success,
          onPressed: () {
            if (widget.fee.remaining > 0) {
              setState(() => _step = 1);
            } else {
              // Fully paid — jump straight to the receipt view.
              setState(() {
                _savedFee = widget.fee;
                _paidAmount = widget.fee.amountPaid;
                _receiptNo = _receiptNoFor(widget.fee);
                _step = 3;
              });
            }
          },
        ),
      1 => _ctaButton(
          label: 'جاری رکھیں',
          icon: Icons.arrow_forward,
          color: AppColors.primary,
          onPressed: () {
            final error = _validateAmount(_amountController.text);
            if (error != null) {
              _snack(error);
              return;
            }
            setState(() => _step = 2);
          },
        ),
      _ => _ctaButton(
          label: 'ادائیگی کی تصدیق کریں',
          icon: Icons.verified,
          color: AppColors.success,
          onPressed: _saving ? null : _confirmPayment,
          busy: _saving,
        ),
    };

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            if (_step > 0 && _step < 3)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => setState(() => _step = _step - 1),
                  child: Text(
                    'واپس',
                    style: AppTypography.labelNastaliq,
                  ),
                ),
              ),
            Expanded(child: primary),
          ],
        ),
      ),
    );
  }

  Widget _ctaButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 22),
        label: Text(
          label,
          style: AppTypography.labelNastaliq.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
