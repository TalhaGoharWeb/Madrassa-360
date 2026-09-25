import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/fee.dart';
import '../../../providers/parent_portal_provider.dart';
import '../../widgets/common/app_widgets.dart';

/// فیس کی تاریخ
/// Fee History Screen for Parents
class FeeHistoryScreen extends StatelessWidget {
  const FeeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
    // Phase 4: parents see ONLY their own children's fees, via the
    // student_guardians link + tenant scope (never the global fee list).
    // Phase 6 (mock purge): the header card below renders the real child
    // (first linked child) — never the old hard-coded name/class/roll.
    final feesAsync = ref.watch(parentFeesProvider);
    final childrenAsync = ref.watch(parentChildrenProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.fees),
      ),
      body: feesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('فیس لوڈ کرنے میں خطا', style: AppTypography.bodyMedium),
        ),
        data: (fees) {
          final children = childrenAsync.valueOrNull ?? const [];
          // Totals aggregate across all linked children; the header names
          // them honestly (never an invented single child).
          final String? headerName = children.isEmpty
              ? null
              : (children.length == 1
                  ? children.first.name
                  : '${children.length} طلباء');
          final String? headerClass =
              children.length == 1 ? children.first.className : null;
          final String? rollLine = children.length == 1
              ? 'رول نمبر ${children.first.rollNo}'
              : null;
          return Column(
            children: [
              // Fee Summary Card
              _buildFeeSummaryCard(fees, headerName, headerClass, rollLine),

              // Fee History List
              Expanded(
                child: _buildFeeHistoryList(fees),
              ),
            ],
          );
        },
      ),
    );
    });
  }

  /// Phase 6 (mock purge): child identity comes from the real linked
  /// children — a null [childName] means no child is linked yet, so the
  /// header shows an explicit "no child" state instead of an invented name.
  Widget _buildFeeSummaryCard(
      List<Fee> fees, String? childName, String? childClass, String? rollLine) {
    final totalDue = fees.fold<double>(0, (sum, f) => sum + f.amountDue);
    final totalPaid = fees.fold<double>(0, (sum, f) => sum + f.amountPaid);
    final remaining = totalDue - totalPaid;
    final subtitle = [
      if (childClass != null && childClass.isNotEmpty) childClass,
      if (rollLine != null) rollLine,
    ].join(' - ');
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      childName ?? 'کوئی طالب علم منسلک نہیں',
                      style: AppTypography.titleLarge.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle.isEmpty ? '—' : subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'فیس مکمل',
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFeeStat('کل فیس', '${totalDue.toInt()}'),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white24,
                ),
                _buildFeeStat('ادا شدہ', '${totalPaid.toInt()}'),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white24,
                ),
                _buildFeeStat('باقی', '${remaining.toInt()}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.titleLarge.copyWith(
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildFeeHistoryList(List<Fee> fees) {
    if (fees.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'کوئی فیس ریکارڈ نہیں',
        subtitle: 'ابھی کوئی فیس ریکارڈ دستیاب نہیں',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: fees.length,
      itemBuilder: (context, index) {
        return _buildFeeHistoryTile(fees[index]);
      },
    );
  }

  Widget _buildFeeHistoryTile(Fee fee) {
    final isPaid = fee.status == FeeStatus.paid;
    
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () {},
      child: Row(
        children: [
          // Status Icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isPaid
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPaid ? Icons.check_circle : Icons.pending,
              color: isPaid ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fee.month,
                  style: AppTypography.titleMedium,
                ),
                Row(
                  children: [
                    Text(
                      'دستیابی: ${fee.dueDate}',
                      style: AppTypography.labelSmall,
                    ),
                    if (fee.paidDate != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'ادائیگی: ${fee.paidDate}',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${fee.amountDue.toInt()} روپے',
                style: AppTypography.titleMedium.copyWith(
                  color: isPaid ? AppColors.success : AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isPaid
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  fee.status.urduLabel,
                  style: AppTypography.labelSmall.copyWith(
                    color: isPaid ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
