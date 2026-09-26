import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/attendance_status.dart';
import '../../../data/models/student.dart';
import '../../../providers/parent_portal_provider.dart';
import '../../widgets/common/app_widgets.dart';
import '../common/announcements_screen.dart';
import '../common/notifications_screen.dart';
import 'fee_history_screen.dart';

/// والدین ڈیش بورڈ
/// Parent Dashboard Screen with Child Overview
///
/// Phase 4: shows ONLY the signed-in parent's own children, resolved
/// through the `student_guardians` link + active tenant. Stats are
/// computed from scoped providers — never from global lists.
class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends ConsumerState<ParentDashboardScreen> {
  String? _selectedChildId;

  @override
  Widget build(BuildContext context) {
    final childrenAsync = ref.watch(parentChildrenProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.home),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: childrenAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('بچوں کا ڈیٹا لوڈ کرنے میں خطا',
              style: AppTypography.bodyMedium),
        ),
        data: (children) {
          if (children.isEmpty) {
            return const EmptyState(
              icon: Icons.family_restroom,
              title: 'کوئی بچہ منسلک نہیں',
              subtitle: 'آپ کا کوئی بچہ اس ادارے سے منسلک نہیں ہے',
            );
          }
          final selected = children.firstWhere(
            (c) => c.id == _selectedChildId,
            orElse: () => children.first,
          );

          // Scoped stats for the selected child.
          final fees = (ref.watch(parentFeesProvider).valueOrNull ?? const [])
              .where((f) => f.studentId == selected.id)
              .toList();
          final results =
              (ref.watch(parentResultsProvider).valueOrNull ?? const [])
                  .where((r) => r.studentId == selected.id)
                  .toList();
          final attendance = ref
                  .watch(parentAttendanceProvider(
                      ParentAttendanceArgs(studentId: selected.id, days: 30)))
                  .valueOrNull ??
              const [];

          final attendancePct = attendance.isEmpty
              ? null
              : attendance
                      .where((a) => a.status == AttendanceStatus.present)
                      .length /
                  attendance.length *
                  100;
          final resultPct = results.isEmpty
              ? null
              : results.map((r) => r.percentage).reduce((a, b) => a + b) /
                  results.length;
          final feeDue = fees.fold<double>(
              0, (sum, f) => sum + (f.amountDue - f.amountPaid));

          final todayStr = DateTime.now().toIso8601String().substring(0, 10);
          final todayRecords =
              attendance.where((a) => a.date == todayStr).toList();

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Child selector (only when more than one child)
                if (children.length > 1)
                  _buildChildSelector(children, selected),

                // Child Profile Card
                _buildChildProfileCard(selected, attendancePct, resultPct),

                // Quick Stats
                _buildQuickStats(attendancePct, resultPct, feeDue),

                // Today's Update Section
                const SectionHeader(
                  title: 'آج کی اپ ڈیٹ',
                ),
                _buildTodayUpdate(
                    todayRecords.isEmpty ? null : todayRecords.first.status),

                // Recent Activities / Timeline
                const SectionHeader(
                  title: 'حالیہ سرگرمیاں',
                  actionText: 'مزید دیکھیں',
                ),
                _buildActivityTimeline(),

                // Upcoming Events
                const SectionHeader(
                  title: 'آئندہ امتحانات',
                ),
                _buildUpcomingExams(),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Chips to switch between the parent's own children.
  Widget _buildChildSelector(List<Student> children, Student selected) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: children.length,
        itemBuilder: (context, index) {
          final child = children[index];
          final isSelected = child.id == selected.id;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(child.name),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedChildId = child.id),
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: AppTypography.labelMedium.copyWith(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChildProfileCard(
      Student child, double? attendancePct, double? resultPct) {
    final initial = child.name.isNotEmpty ? child.name[0] : 'م';
    final attendanceLabel = attendancePct == null
        ? 'حاضری —'
        : 'حاضری ${attendancePct.toStringAsFixed(0)}٪';
    final resultLabel =
        resultPct == null ? 'نتائج —' : 'اوسط ${resultPct.toStringAsFixed(0)}٪';
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
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Child Avatar
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 2),
            ),
            child: Center(
              child: Text(
                initial,
                style: AppTypography.headingLarge.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Child Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.name,
                  style: AppTypography.headingSmall.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${child.className} -  رول نمبر ${child.rollNo}',
                    style: AppTypography.labelMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildChildStat(Icons.calendar_today, attendanceLabel),
                    const SizedBox(width: 16),
                    _buildChildStat(Icons.star, resultLabel),
                  ],
                ),
              ],
            ),
          ),

          // More Options — real child actions (fee history, announcements).
          IconButton(
            onPressed: () => _showChildActions(context),
            icon: const Icon(Icons.more_vert, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildChildStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(
      double? attendancePct, double? resultPct, double feeDue) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.fact_check,
              label: 'اس ماہ حاضری',
              value: attendancePct == null
                  ? '—'
                  : '${attendancePct.toStringAsFixed(0)}%',
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.assessment,
              label: 'امتحانی نمبر',
              value:
                  resultPct == null ? '—' : '${resultPct.toStringAsFixed(0)}%',
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.payments,
              label: 'فیس کی حالت',
              value: feeDue > 0.005 ? 'بقایا' : 'مکمل',
              color: AppColors.info,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(color: color),
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

  Widget _buildTodayUpdate(AttendanceStatus? todayStatus) {
    final statusLabel = todayStatus?.urduLabel ?? 'ریکارڈ نہیں';
    final statusColor = switch (todayStatus) {
      AttendanceStatus.absent => AppColors.absent,
      AttendanceStatus.leave => AppColors.leave,
      _ => AppColors.present,
    };
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.check_circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'آج کی حاضری',
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      statusLabel,
                      style: AppTypography.bodySmall.copyWith(
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.menu_book,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'آج کا سبق',
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      'سورۃ البقرۃ - آیت 125 سے 130',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Real child actions: fee history and announcements — both
  /// data-backed screens, never placeholders.
  void _showChildActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading:
                  const Icon(Icons.receipt_long_outlined, color: Colors.green),
              title: Text('فیس کی ہسٹری', style: AppTypography.bodyLarge),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FeeHistoryScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined, color: Colors.blue),
              title: Text('اعلانات', style: AppTypography.bodyLarge),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AnnouncementsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Phase 6 (mock purge): the old static mock activity rows are gone.
  /// A real child activity feed arrives with the notifications module.
  /// TODO(phase-8): wire to the real notifications/activity feed; until
  /// then show an explicit empty state — never invented rows.
  Widget _buildActivityTimeline() {
    return _buildEmptySection(
      icon: Icons.timeline_outlined,
      message: 'ابھی کوئی سرگرمی ریکارڈ نہیں',
    );
  }

  /// Phase 6 (mock purge): the old static mock exam rows are gone.
  /// TODO(phase-8): wire to a real exams/schedule source; until then show
  /// an explicit empty state — never invented exam dates.
  Widget _buildUpcomingExams() {
    return _buildEmptySection(
      icon: Icons.event_outlined,
      message: 'ابھی کوئی امتحان شیڈول نہیں',
    );
  }

  /// Explicit empty state — never invented rows.
  Widget _buildEmptySection({required IconData icon, required String message}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(icon,
                size: 48,
                color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
