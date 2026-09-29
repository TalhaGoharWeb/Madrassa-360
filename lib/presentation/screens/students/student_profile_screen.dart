import 'package:flutter/material.dart' hide DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money_format.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/attendance_status.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/result.dart';
import '../../../data/models/student.dart';
import '../../../providers/attendance_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/result_provider.dart';
import '../../../providers/student_provider.dart';
import '../../widgets/common/app_widgets.dart';
import '../reports/reports_hub_screen.dart';
import 'student_dialogs.dart';
import 'student_widgets.dart';

/// طالب علم کا پروفائل — information hub
///
/// Phase 10 (m360): visual/UX layer only — same providers, same tabs,
/// same flows. Deep-pushed detail screen (MaterialPageRoute), so it keeps
/// its own Scaffold with [M360AppBar] — it is not a shell destination.
///
/// Tabs included ONLY where an underlying provider exists in the repo:
///   جائزہ / ذاتی معلومات / حاضری / فیس / امتحانات
/// Omitted (no provider in repo): تعلیم، حفظ، دستاویزات.
class StudentProfileScreen extends ConsumerStatefulWidget {
  final String studentId;

  const StudentProfileScreen({super.key, required this.studentId});

  @override
  ConsumerState<StudentProfileScreen> createState() =>
      _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['جائزہ', 'ذاتی معلومات', 'حاضری', 'فیس', 'امتحانات'];
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentAsync = ref.watch(studentByIdProvider(widget.studentId));

    return Scaffold(
      appBar: const M360AppBar(title: 'طالب علم کا پروفائل'),
      body: studentAsync.when(
        loading: () => const M360LoadingState(),
        error: (_, __) => M360ErrorState(
          message: 'طالب علم کی معلومات لوڈ کرنے میں خطا',
          onRetry: () => ref.invalidate(studentByIdProvider(widget.studentId)),
        ),
        data: (student) {
          if (student == null) {
            return const M360EmptyState(
              icon: Icons.person_off_outlined,
              title: 'طالب علم نہیں ملا',
              description: 'یہ ریکارڈ دستیاب نہیں',
            );
          }
          return Column(
            children: [
              _IdentityHeader(
                student: student,
                onFee: () =>
                    StudentDialogs.showFeeCollection(context, ref, student),
                onEdit: () =>
                    StudentDialogs.showEditStudent(context, ref, student),
                onAttendance: () => _tabController.animateTo(2),
                onReport: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReportsHubScreen(),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primaryDark,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: AppTypography.labelNastaliq.copyWith(fontSize: 15),
                unselectedLabelStyle:
                    AppTypography.labelNastaliq.copyWith(fontSize: 15),
                tabs: _tabs.map((t) => Tab(text: t)).toList(),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _OverviewTab(student: student),
                    _PersonalInfoTab(student: student),
                    _AttendanceTab(student: student),
                    _FeesTab(student: student),
                    _ExamsTab(student: student),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Identity header with contextual quick actions
// ─────────────────────────────────────────────────────────────

class _IdentityHeader extends StatelessWidget {
  final Student student;
  final VoidCallback onFee;
  final VoidCallback onEdit;
  final VoidCallback onAttendance;
  final VoidCallback onReport;

  const _IdentityHeader({
    required this.student,
    required this.onFee,
    required this.onEdit,
    required this.onAttendance,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                StudentAvatar(student: student, radius: 38),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: AppTypography.titleLarge
                            .copyWith(color: Colors.white),
                      ),
                      Text(
                        'بن ${student.fatherName}',
                        style: AppTypography.bodySmall
                            .copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _HeaderChip(
                            label:
                                'رول: ${student.rollNo.isEmpty ? '—' : student.rollNo}',
                          ),
                          _HeaderChip(label: student.className),
                          studentStatusBadge(student.isActive),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _QuickAction(
                  icon: Icons.receipt,
                  label: 'فیس وصول کریں',
                  onTap: onFee,
                ),
                const SizedBox(width: 8),
                _QuickAction(
                  icon: Icons.edit,
                  label: 'ترمیم',
                  onTap: onEdit,
                ),
                const SizedBox(width: 8),
                _QuickAction(
                  icon: Icons.fact_check,
                  label: 'حاضری دیکھیں',
                  onTap: onAttendance,
                ),
                const SizedBox(width: 8),
                _QuickAction(
                  icon: Icons.bar_chart,
                  label: 'رپورٹ',
                  onTap: onReport,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;

  const _HeaderChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: Colors.white),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.gold, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTypography.labelNastaliq
                    .copyWith(fontSize: 14, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab 1: جائزہ — live summary from existing providers
// ─────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  final Student student;

  const _OverviewTab({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const M360SectionHeader(
          title: 'خلاصہ',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _AttendanceStatCard(student: student)),
            const SizedBox(width: 12),
            Expanded(child: _FeeDueStatCard(studentId: student.id)),
          ],
        ),
        const SizedBox(height: 12),
        _ExamAverageCard(studentId: student.id),
        const SizedBox(height: 20),
        const M360SectionHeader(
          title: 'اہم معلومات',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        M360Card(
          child: Column(
            children: [
              InfoTile(
                icon: Icons.class_,
                label: 'جماعت',
                value: student.className,
              ),
              InfoTile(
                icon: Icons.layers,
                label: 'درجہ',
                value: student.darjaName.isEmpty ? '—' : student.darjaName,
              ),
              if (student.phone != null)
                InfoTile(
                  icon: Icons.phone,
                  label: 'والد کا فون',
                  value: student.phone!,
                ),
              if (student.dateOfAdmit != null)
                InfoTile(
                  icon: Icons.event,
                  label: 'داخلہ کی تاریخ',
                  value: student.dateOfAdmit!,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttendanceStatCard extends ConsumerWidget {
  final Student student;

  const _AttendanceStatCard({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    int present = 0, total = 0, pending = 0;
    for (var i = 0; i < 30; i++) {
      final day = today.subtract(Duration(days: i));
      final async = ref.watch(classAttendanceProvider(
          AttendanceParams(classId: student.classId, date: day)));
      if (async.isLoading) {
        pending++;
        continue;
      }
      final records = async.valueOrNull ?? const <AttendanceRecord>[];
      for (final r in records) {
        if (r.studentId != student.id) continue;
        total++;
        if (r.status == AttendanceStatus.present ||
            r.status == AttendanceStatus.late) {
          present++;
        }
      }
    }
    if (pending > 0) {
      return const M360StatCard(
        icon: Icons.fact_check,
        label: 'حاضری (۳۰ دن)',
        value: '…',
        valueColor: AppColors.textSecondary,
      );
    }
    final pct = total > 0 ? (present / total * 100) : 0.0;
    return M360StatCard(
      icon: Icons.fact_check,
      label: 'حاضری (۳۰ دن)',
      value: '${pct.toStringAsFixed(0)}٪',
      valueColor: pct >= 75
          ? AppColors.success
          : (pct >= 50 ? AppColors.warning : AppColors.error),
    );
  }
}

class _FeeDueStatCard extends ConsumerWidget {
  final String studentId;

  const _FeeDueStatCard({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feesAsync = ref.watch(feesByStudentProvider(studentId));
    final fees = feesAsync.valueOrNull ?? const <Fee>[];
    final due =
        fees.fold<double>(0, (sum, f) => sum + (f.amountDue - f.amountPaid));
    return M360StatCard(
      icon: Icons.receipt_long,
      label: 'فیس بقایا',
      value: 'ر ${formatPK(due)}',
      valueColor: due > 0 ? AppColors.error : AppColors.success,
    );
  }
}

class _ExamAverageCard extends ConsumerWidget {
  final String studentId;

  const _ExamAverageCard({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(allResultsProvider);
    final results = (resultsAsync.valueOrNull ?? const <StudentResult>[])
        .where((r) => r.studentId == studentId)
        .toList();
    if (results.isEmpty) {
      return const M360StatCard(
        icon: Icons.school,
        label: 'امتحانی اوسط',
        value: '—',
        valueColor: AppColors.textSecondary,
      );
    }
    final avg =
        results.fold<double>(0, (s, r) => s + r.percentage) / results.length;
    return M360StatCard(
      icon: Icons.school,
      label: 'امتحانی اوسط (${results.length} امتحان)',
      value: '${avg.toStringAsFixed(1)}٪',
      valueColor: avg >= 60 ? AppColors.success : AppColors.error,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab 2: ذاتی معلومات
// ─────────────────────────────────────────────────────────────

class _PersonalInfoTab extends ConsumerWidget {
  final Student student;

  const _PersonalInfoTab({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        M360SectionHeader(
          title: 'ذاتی معلومات',
          padding: EdgeInsets.zero,
          actionLabel: 'ترمیم',
          onAction: () => StudentDialogs.showEditStudent(context, ref, student),
        ),
        const SizedBox(height: 8),
        M360Card(
          child: Column(
            children: [
              InfoTile(
                icon: Icons.person,
                label: 'نام',
                value: student.name,
              ),
              InfoTile(
                icon: Icons.family_restroom,
                label: 'والد کا نام',
                value: student.fatherName,
              ),
              InfoTile(
                icon: Icons.format_list_numbered,
                label: 'رول نمبر',
                value: student.rollNo.isEmpty ? '—' : student.rollNo,
              ),
              InfoTile(
                icon: Icons.class_,
                label: 'جماعت',
                value: student.className,
              ),
              InfoTile(
                icon: Icons.layers,
                label: 'درجہ',
                value: student.darjaName.isEmpty ? '—' : student.darjaName,
              ),
              if (student.phone != null)
                InfoTile(
                  icon: Icons.phone,
                  label: 'فون نمبر',
                  value: student.phone!,
                ),
              if (student.address != null)
                InfoTile(
                  icon: Icons.location_on,
                  label: 'پتہ',
                  value: student.address!,
                ),
              if (student.dateOfBirth != null)
                InfoTile(
                  icon: Icons.cake,
                  label: 'تاریخ پیدائش',
                  value: student.dateOfBirth!,
                ),
              if (student.dateOfAdmit != null)
                InfoTile(
                  icon: Icons.event,
                  label: 'داخلہ کی تاریخ',
                  value: student.dateOfAdmit!,
                ),
              InfoTile(
                icon: Icons.toggle_on,
                label: 'حالت',
                value: student.isActive ? 'فعال' : 'غیر فعال',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab 3: حاضری — last 30 days from classAttendanceProvider
// ─────────────────────────────────────────────────────────────

class _AttendanceTab extends ConsumerWidget {
  final Student student;

  const _AttendanceTab({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    int present = 0, absent = 0, leave = 0, late = 0, pending = 0;
    final dayRecords = <_DayRecord>[];

    for (var i = 0; i < 30; i++) {
      final day = today.subtract(Duration(days: i));
      final async = ref.watch(classAttendanceProvider(
          AttendanceParams(classId: student.classId, date: day)));
      if (async.isLoading) {
        pending++;
        continue;
      }
      final records = async.valueOrNull ?? const <AttendanceRecord>[];
      AttendanceRecord? mine;
      for (final r in records) {
        if (r.studentId == student.id) {
          mine = r;
          break;
        }
      }
      if (mine != null) {
        switch (mine.status) {
          case AttendanceStatus.present:
            present++;
            break;
          case AttendanceStatus.absent:
            absent++;
            break;
          case AttendanceStatus.leave:
            leave++;
            break;
          case AttendanceStatus.late:
            late++;
            break;
        }
        dayRecords.add(_DayRecord(date: day, status: mine.status));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const M360SectionHeader(
          title: 'حاضری کا خلاصہ',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _CountChip(
                    label: 'حاضر', count: present, color: AppColors.success)),
            const SizedBox(width: 8),
            Expanded(
                child: _CountChip(
                    label: 'غیر حاضر', count: absent, color: AppColors.error)),
            const SizedBox(width: 8),
            Expanded(
                child: _CountChip(
                    label: 'چھٹی', count: leave, color: AppColors.leave)),
            const SizedBox(width: 8),
            Expanded(
                child: _CountChip(
                    label: 'تاخیر', count: late, color: AppColors.late)),
          ],
        ),
        const SizedBox(height: 20),
        const M360SectionHeader(
          title: 'پچھلے ۳۰ دن',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        if (pending > 0) const LinearProgressIndicator(),
        if (dayRecords.isEmpty && pending == 0)
          const M360EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'حاضری کا ریکارڈ نہیں ملا',
            description: 'پچھلے ۳۰ دنوں میں کوئی حاضری درج نہیں',
          )
        else
          ...dayRecords.map((d) => M360Card(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${d.date.day} ${DateUtils.formatMonthName(d.date)} ${d.date.year}',
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                    attendanceBadge(d.status, compact: true),
                  ],
                ),
              )),
      ],
    );
  }
}

class _DayRecord {
  final DateTime date;
  final AttendanceStatus status;

  _DayRecord({required this.date, required this.status});
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('$count',
              style: AppTypography.titleMedium.copyWith(color: color)),
          Text(label,
              style: AppTypography.labelNastaliq
                  .copyWith(fontSize: 14, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab 4: فیس — feesByStudentProvider
// ─────────────────────────────────────────────────────────────

class _FeesTab extends ConsumerWidget {
  final Student student;

  const _FeesTab({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feesAsync = ref.watch(feesByStudentProvider(student.id));

    return feesAsync.when(
      loading: () => const M360LoadingState(),
      error: (_, __) => M360ErrorState(
        message: 'فیس لوڈ کرنے میں خطا',
        onRetry: () => ref.invalidate(feesByStudentProvider(student.id)),
      ),
      data: (fees) {
        final sorted = List<Fee>.from(fees)
          ..sort((a, b) => b.month.compareTo(a.month));
        final totalDue = fees.fold<double>(0, (s, f) => s + f.amountDue);
        final totalPaid = fees.fold<double>(0, (s, f) => s + f.amountPaid);
        final balance = totalDue - totalPaid;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            M360SectionHeader(
              title: 'فیس کی صورتحال',
              padding: EdgeInsets.zero,
              actionLabel: 'فیس وصول کریں',
              onAction: () =>
                  StudentDialogs.showFeeCollection(context, ref, student),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: M360StatCard(
                        icon: Icons.payments,
                        label: 'کل واجب',
                        value: 'ر ${formatPK(totalDue)}',
                        valueColor: AppColors.info)),
                const SizedBox(width: 12),
                Expanded(
                    child: M360StatCard(
                        icon: Icons.check_circle,
                        label: 'کل ادا',
                        value: 'ر ${formatPK(totalPaid)}',
                        valueColor: AppColors.success)),
                const SizedBox(width: 12),
                Expanded(
                    child: M360StatCard(
                        icon: Icons.warning,
                        label: 'بقایا',
                        value: 'ر ${formatPK(balance)}',
                        valueColor: balance > 0
                            ? AppColors.error
                            : AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 20),
            const M360SectionHeader(
              title: 'ماہانہ ریکارڈ',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              const M360EmptyState(
                icon: Icons.receipt_outlined,
                title: 'فیس کا کوئی ریکارڈ نہیں',
                description: 'ابھی تک کوئی فیس درج نہیں کی گئی',
              )
            else
              ...sorted.map((f) => M360Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _feeMonthLabel(f.month),
                                style: AppTypography.labelNastaliq
                                    .copyWith(fontSize: 16),
                              ),
                              Text(
                                'ر ${formatPK(f.amountPaid)} / ر ${formatPK(f.amountDue)}',
                                style: AppTypography.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        feeBadge(f.status, compact: true),
                      ],
                    ),
                  )),
          ],
        );
      },
    );
  }

  static String _feeMonthLabel(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return yearMonth;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return yearMonth;
    return '${DateUtils.formatMonthName(DateTime(y, m))} $y';
  }
}

// ─────────────────────────────────────────────────────────────
// Tab 5: امتحانات — allResultsProvider filtered by student
// ─────────────────────────────────────────────────────────────

class _ExamsTab extends ConsumerWidget {
  final Student student;

  const _ExamsTab({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(allResultsProvider);

    return resultsAsync.when(
      loading: () => const M360LoadingState(),
      error: (_, __) => M360ErrorState(
        message: 'نتائج لوڈ کرنے میں خطا',
        onRetry: () => ref.invalidate(allResultsProvider),
      ),
      data: (all) {
        final mine = all.where((r) => r.studentId == student.id).toList();
        if (mine.isEmpty) {
          return const M360EmptyState(
            icon: Icons.school_outlined,
            title: 'کوئی امتحانی نتیجہ نہیں',
            description: 'اس طالب علم کا ابھی کوئی نتیجہ درج نہیں',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const M360SectionHeader(
              title: 'امتحانی نتائج',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            ...mine.map((r) => _ExamCard(result: r)),
          ],
        );
      },
    );
  }
}

class _ExamCard extends StatelessWidget {
  final StudentResult result;

  const _ExamCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final pct = result.percentage;
    final color = pct >= 60 ? AppColors.success : AppColors.error;
    return M360Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(result.examName,
            style: AppTypography.titleSmall.copyWith(fontSize: 15)),
        subtitle: Text(
          '${result.totalObtained.toStringAsFixed(0)} / ${result.totalMarks.toStringAsFixed(0)} • گریڈ: ${result.grade}',
          style: AppTypography.bodySmall,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${pct.toStringAsFixed(1)}٪',
              style: AppTypography.labelNastaliq
                  .copyWith(fontSize: 15, color: color)),
        ),
        children: result.subjects
            .map((s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.subject, style: AppTypography.bodyMedium),
                  trailing: Text(
                    '${s.marksObtained.toStringAsFixed(0)}/${s.totalMarks.toStringAsFixed(0)} • ${s.grade}',
                    style: AppTypography.bodySmall,
                  ),
                ))
            .toList(),
      ),
    );
  }
}
