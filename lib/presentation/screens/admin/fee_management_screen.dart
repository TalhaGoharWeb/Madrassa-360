import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/fee.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/student_provider.dart';
import '../../widgets/common/app_widgets.dart';

/// فیس کی فہرست
/// Fee Management Screen for Admin
class FeeManagementScreen extends StatefulWidget {
  const FeeManagementScreen({super.key});

  @override
  State<FeeManagementScreen> createState() => _FeeManagementScreenState();
}

class _FeeManagementScreenState extends State<FeeManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedStatus = 'all';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.fees),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelStyle: AppTypography.labelLarge,
          tabs: const [
            Tab(text: 'فیس کی تفصیل'),
            Tab(text: 'وصولی'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeeListTab(),
          _buildCollectionTab(),
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
    );
  }

  Widget _buildFeeListTab() {
    return Consumer(builder: (context, ref, _) {
    final feeAsync = ref.watch(allFeesProvider);
    final feeRecords = feeAsync.valueOrNull ?? [];

    if (feeAsync.isLoading) return const Center(child: CircularProgressIndicator());
    if (feeAsync.hasError) {
      return Center(
        child: Text('فیس لوڈ کرنے میں خطا', style: AppTypography.bodyMedium),
      );
    }

    return Column(
      children: [
        // Summary Cards
        _buildFeeSummary(feeRecords),

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
              value: '${records.where((r) => r.status == FeeStatus.pastDue).length}',
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
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
              selectedColor: color.withOpacity(0.2),
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

    if (filteredRecords.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'کوئی فیس ریکارڈ نہیں',
        subtitle: 'فلٹر تبدیل کریں',
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

  Widget _buildFeeRecordTile(Fee record) {
    return AppCard(
      onTap: () => _showFeeDetails(record),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Status Indicator
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _getStatusColor(record.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getStatusIcon(record.status),
              color: _getStatusColor(record.status),
            ),
          ),
          const SizedBox(width: 12),
          
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.studentName,
                  style: AppTypography.titleMedium,
                ),
                Text(
                  '${record.studentClass} - ${record.month}',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${record.amountPaid.toInt()}',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      ' / ${record.amountDue.toInt()} روپے',
                      style: AppTypography.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Status Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildStatusBadge(record.status),
              const SizedBox(height: 8),
              if (record.remaining > 0)
                Text(
                  'باقی: ${record.remaining.toInt()}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(FeeStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.urduLabel,
        style: AppTypography.labelSmall.copyWith(
          color: _getStatusColor(status),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(FeeStatus status) {
    switch (status) {
      case FeeStatus.paid:
        return AppColors.success;
      case FeeStatus.partial:
        return AppColors.warning;
      case FeeStatus.pending:
        return AppColors.info;
      case FeeStatus.pastDue:
        return AppColors.error;
    }
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

  /// Phase 4: collection stats and the recent-collections feed are built
  /// from the tenant's real fee rows ([allFeesProvider]) — no invented
  /// names, amounts or "12%+" trends.
  Widget _buildCollectionTab() {
    return Consumer(builder: (context, ref, _) {
    final feeAsync = ref.watch(allFeesProvider);
    final records = feeAsync.valueOrNull ?? [];
    final paid = records
        .where((r) => r.status == FeeStatus.paid)
        .toList()
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
                    const Icon(Icons.account_balance_wallet, color: Colors.white, size: 32),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
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

  /// '2026-09' → 'ستمبر 2026'.
  String _monthLabel(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return yearMonth;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return yearMonth;
    return '${DateUtils.formatMonthName(DateTime(y, m))} $y';
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
              color: AppColors.success.withOpacity(0.1),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: method == 'نقد'
                            ? AppColors.success.withOpacity(0.1)
                            : AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        method,
                        style: AppTypography.labelSmall.copyWith(
                          color: method == 'نقد' ? AppColors.success : AppColors.info,
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

  void _showFeeDetails(Fee record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _getStatusColor(record.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _getStatusIcon(record.status),
                          color: _getStatusColor(record.status),
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(record.studentName, style: AppTypography.headingSmall),
                            Text(
                              '${record.studentClass} - ${record.month}',
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(),
                  
                  // Fee Details
                  InfoTile(
                    icon: Icons.payments,
                    label: 'کل فیس',
                    value: '${record.amountDue.toInt()} روپے',
                  ),
                  InfoTile(
                    icon: Icons.check_circle,
                    label: 'ادا شدہ',
                    value: '${record.amountPaid.toInt()} روپے',
                    iconColor: AppColors.success,
                  ),
                  InfoTile(
                    icon: Icons.pending,
                    label: 'باقی رقم',
                    value: '${record.remaining.toInt()} روپے',
                    iconColor: record.remaining > 0 ? AppColors.error : AppColors.success,
                  ),
                  InfoTile(
                    icon: Icons.calendar_today,
                    label: 'آخری تاریخ',
                    value: record.dueDate,
                  ),
                  if (record.paidDate != null)
                    InfoTile(
                      icon: Icons.event_available,
                      label: 'ادائیگی کی تاریخ',
                      value: record.paidDate!,
                      iconColor: AppColors.success,
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  if (record.status != FeeStatus.paid)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showFeeCollectionDialog(context, record),
                        icon: const Icon(Icons.payments),
                        label: const Text('فیس وصول کریں'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showReceiptDialog(context, record),
                      icon: const Icon(Icons.print),
                      label: const Text('رسید پرنٹ کریں'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Phase 4: the receipt prints the selected fee record's real data —
  /// no invented names, dates or amounts.
  void _showReceiptDialog(BuildContext context, Fee record) {
    final receiptNo =
        '#FEE-${record.month}-${record.id.length >= 6 ? record.id.substring(0, 6).toUpperCase() : record.id.toUpperCase()}';
    final paidAt = DateTime.tryParse(record.paidDate ?? '');
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Text(
                'فیس کی رسید',
                style: AppTypography.headingMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Receipt Content
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _buildReceiptRow('رسید نمبر', receiptNo),
                    _buildReceiptRow('طالب علم کا نام', record.studentName),
                    _buildReceiptRow('کلاس', record.studentClass),
                    _buildReceiptRow('مہینہ', _monthLabel(record.month)),
                    _buildReceiptRow('فیس کی قسم', 'ماہانہ فیس'),
                    _buildReceiptRow('رقم', '${formatPK(record.amountPaid)} روپے'),
                    _buildReceiptRow('حیثیت', record.status.urduLabel),
                    _buildReceiptRow(
                        'تاریخ',
                        paidAt == null
                            ? '—'
                            : DateUtils.formatDateUrdu(paidAt)),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('بند کریں'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Phase 6 (mock purge): there is no print engine yet —
                        // the old code showed a fake "printing…" success. Be
                        // honest instead.
                        // TODO(phase-8): wire to a real receipt printer via the
                        // `printing` package once the dependency is approved.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('رسید پرنٹنگ جلد دستیاب ہوگی'),
                          ),
                        );
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('پرنٹ کریں'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w500),
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

  void _showFeeCollectionDialog(BuildContext context, Fee record) {
    final TextEditingController amountController = TextEditingController(
      text: record.remaining.toString(),
    );

    // Phase 4: collecting a fee persists the payment through the fee
    // notifier (DB status is recalculated server-side) — no more mock.
    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) => AlertDialog(
        title: Text(
          'فیس وصول کریں',
          style: AppTypography.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'طالب علم: ${record.studentName}',
              style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'کلاس: ${record.studentClass}',
              style: AppTypography.bodyMedium,
            ),
            Text(
              'ماہ: ${record.month}',
              style: AppTypography.bodyMedium,
            ),
            Text(
              'باقی رقم: ر ${record.remaining}',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'وصول کی جانے والی رقم',
                border: OutlineInputBorder(),
                prefixText: 'ر ',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'رقم درج کریں';
                }
                final amount = double.tryParse(value);
                if (amount == null || amount <= 0) {
                  return 'درست رقم درج کریں';
                }
                if (amount > record.remaining) {
                  return 'رقم باقی رقم سے زیادہ نہیں ہو سکتی';
                }
                return null;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('منسوخ کریں'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null ||
                  amount <= 0 ||
                  amount > record.remaining) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('درست رقم درج کریں (باقی رقم سے زیادہ نہیں)')),
                );
                return;
              }
              final now = DateTime.now();
              final paidStr =
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
              final updated = record.copyWith(
                amountPaid: record.amountPaid + amount,
                paidDate: paidStr,
              );
              try {
                await ref.read(feeNotifierProvider.notifier).save(updated);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'ر ${formatPK(amount)} کی فیس کامیابی سے وصول کر لی گئی'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('فیس وصول کرنے میں خطا')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('وصول کریں'),
          ),
        ],
        ),
      ),
    );
  }

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
                        value: selectedStudentId,
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
                        value: selectedMonth,
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
                          content: Text(
                              'طالب علم منتخب کریں اور درست رقم درج کریں'),
                        ),
                      );
                      return;
                    }
                    final student = matches.first;
                    // Due on the last day of the selected month.
                    final mp = selectedMonth.split('-');
                    final due = DateTime(
                        int.parse(mp[0]), int.parse(mp[1]) + 1, 0);
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
                    try {
                      await ref.read(feeNotifierProvider.notifier).save(fee);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '${student.name} کے لیے واؤچر بنا دیا گیا'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('واؤچر بنانے میں خطا')),
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
