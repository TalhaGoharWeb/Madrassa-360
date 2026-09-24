import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/fee.dart';
import '../../../providers/fee_provider.dart';
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

  Widget _buildCollectionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Collection Stats
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
                            '15,500 روپے',
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.trending_up, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '12%+',
                            style: AppTypography.labelMedium.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
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
                    _buildCollectionStat('5', 'رسیدیں'),
                    _buildCollectionStat('3', 'نقد'),
                    _buildCollectionStat('2', 'آن لائن'),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Recent Collections
          const SectionHeader(
            title: 'حالیہ وصولی',
            actionText: 'سب دیکھیں',
          ),
          
          // Collection List
          ...List.generate(5, (index) {
            return _buildCollectionItem(
              name: ['محمد احمد', 'عبداللہ خان', 'حافظ عمر', 'یوسف علی', 'حسن رضا'][index],
              amount: ['3,000', '1,500', '3,000', '2,500', '3,000'][index],
              time: ['ابھی', '15 منٹ پہلے', '1 گھنٹہ پہلے', '2 گھنٹے پہلے', 'صبح'][index],
              method: index % 2 == 0 ? 'نقد' : 'آن لائن',
            );
          }),
        ],
      ),
    );
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
                      onPressed: () => _showReceiptDialog(context),
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

  void _showReceiptDialog(BuildContext context) {
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
                    _buildReceiptRow('رسید نمبر', '#FEE-2026-001'),
                    _buildReceiptRow('طالب علم کا نام', 'محمد احمد'),
                    _buildReceiptRow('کلاس', 'دہم جماعت'),
                    _buildReceiptRow('فیس کی قسم', 'ماہانہ فیس'),
                    _buildReceiptRow('رقم', 'ر 2,500'),
                    _buildReceiptRow('وصول کرنے والا', 'مدرسہ منتظم'),
                    _buildReceiptRow('تاریخ', '9 جنوری 2026'),
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
                        // Mock print functionality
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('رسید پرنٹ ہو رہی ہے...'),
                            backgroundColor: Colors.green,
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () {
              final amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0 && amount <= record.remaining) {
                // Mock fee collection
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('ر ${amount} کی فیس کامیابی سے وصول کر لی گئی'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context);
                // In a real app, this would update the record status
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('وصول کریں'),
          ),
        ],
      ),
    );
  }

  void _showNewVoucherDialog(BuildContext context) {
    final TextEditingController studentController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    const classOptions = [
      'درجہ اولیٰ (اول سال)',
      'درجہ ثانیہ (دوسرا سال)',
      'درجہ ثالثہ (تیسرا سال)',
      'درجہ رابعہ (چوتھا سال)',
      'درجہ خامسہ (پانچواں سال)',
      'درجہ سادسہ (چھٹا سال)',
      'درجہ سابِعہ (ساتواں سال)',
      'دورہ حدیث (آٹھواں سال/آخری سال)',
    ];
    String selectedClass = classOptions.first;
    String selectedMonth = 'جنوری';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: Text(
          'نیا واؤچر بنائیں',
          style: AppTypography.titleLarge,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Student Selection
              TextFormField(
                controller: studentController,
                decoration: const InputDecoration(
                  labelText: 'طالب علم کا نام',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'طالب علم کا نام درج کریں';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Class Selection
              DropdownButtonFormField<String>(
                value: selectedClass,
                decoration: const InputDecoration(
                  labelText: 'کلاس',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.class_),
                ),
                items: classOptions.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedClass = value!),
              ),
              const SizedBox(height: 16),

              // Month Selection
              DropdownButtonFormField<String>(
                value: selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'ماہ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_month),
                ),
                items: [
                  'جنوری',
                  'فروری',
                  'مارچ',
                  'اپریل',
                  'مئی',
                  'جون',
                  'جولائی',
                  'اگست',
                  'ستمبر',
                  'اکتوبر',
                  'نومبر',
                  'دسمبر',
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'رقم درج کریں';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'درست رقم درج کریں';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'تفصیل (اختیاری)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('منسوخ کریں'),
          ),
          ElevatedButton(
            onPressed: () {
              if (studentController.text.isNotEmpty &&
                  amountController.text.isNotEmpty) {
                final amount = double.tryParse(amountController.text);
                if (amount != null && amount > 0) {
                  // Mock voucher creation
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('نیا واؤچر ${studentController.text} کے لیے بنایا گیا'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                  // In a real app, this would save the voucher to database
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('واؤچر بنائیں'),
          ),
        ],
      ),
      ),
    );
  }
}
