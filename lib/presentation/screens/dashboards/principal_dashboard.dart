/// پرنسپل / مہتمم ڈیش بورڈ — ٹاسک اورینٹڈ کمانڈ سینٹر (redesign v2).
///
/// Replaces the stat-card-wallpaper layout with a task-oriented command
/// centre:
///
/// * Greeting header (from [DashboardScaffold]): السلام علیکم + user name +
///   role + today's date in Urdu (Gregorian + Hijri — rendered by the
///   scaffold itself).
/// * App-bar search entry + a tappable "تلاش کریں..." field opening
///   [GlobalSearchPage] (global_search.dart).
/// * "آج کا انتظامی خلاصہ": five tappable key metrics (کل طلبہ، آج کی
///   حاضری، آج کی فیس وصولی، بقایا فیس، فعال کلاسز) — each card jumps to
///   the relevant workflow screen.
/// * "آج کیا کرنا ہے؟": data-driven task list; every task carries a
///   primary CTA button jumping straight into the workflow. An "all done"
///   state renders when nothing is pending.
/// * Data sections, rendered ONLY when their provider exists:
///   آج کی حاضری کا خلاصہ، زیر التواء فیس، حالیہ داخلے، اہم اعلانات،
///   آنے والے امتحانات + a collapsed "مدرسے کے شعبے" nav block.
/// * Mobile-first: single column on mobile, 2-column grid on desktop.
///
/// Presentation layer only: every number comes from existing providers —
/// [dashboardStatsProvider], [feeSummaryProvider], [allFeesProvider],
/// [todayCollectionProvider], [examsWithoutResultsProvider],
/// [newAdmissionsProvider], [allExamsProvider], [announcementListProvider],
/// [safeDarjaListProvider]. No new backend calls, no mock data; permission
/// and module gating ([hasPermissionProvider], [tenantModulesProvider])
/// preserved from the previous design.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../../data/models/fee.dart';
import '../../widgets/dashboard/alert_card.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/dashboard_section.dart';
import '../../widgets/dashboard/schedule_slot.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../widgets/global_search.dart';
import '../../../providers/admin_dashboard_provider.dart';
import '../../../providers/announcement_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/day_schedule_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/result_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../admin/darja_screen.dart';
import '../admin/fee_management_screen.dart';
import '../admin/finance_screen.dart';
import '../admin/library_screen.dart';
import '../admin/staff_list_screen.dart';
import '../admin/student_list_screen.dart';
import '../admin/user_management_screen.dart';
import '../common/announcements_screen.dart';
import '../common/dashboard_guide_screen.dart';
import '../reports/reports_hub_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/results_screen.dart';
import 'exam_dashboard.dart';
import 'exam_wizard_screen.dart';

class PrincipalDashboardScreen extends ConsumerWidget {
  const PrincipalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'مہتمم';
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';

    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    // Module gating: null (still loading) → don't hide, avoid flicker.
    final enabledModules = ref.watch(tenantModulesProvider).valueOrNull;
    bool moduleOk(String module) =>
        enabledModules == null || enabledModules.contains(module);

    bool can(String permission) => ref.watch(hasPermissionProvider(permission));

    return FutureBuilder<String>(
      future: roleKeys.isEmpty
          ? Future.value('')
          : roleService.roleUrduLabel(roleKeys.first),
      builder: (context, snap) => DashboardScaffold(
        greeting: 'السلام علیکم ورحمۃ اللہ',
        userName: userName,
        roleLabel: snap.data?.isEmpty == true ? null : snap.data,
        madrasaName: madrasaName,
        actions: [
          IconButton(
            tooltip: 'تلاش کریں',
            icon: const Icon(Icons.search_outlined),
            onPressed: () => _openSearch(context),
          ),
          const DashboardGuideButton(roleKey: 'principal'),
        ],
        schedule: ScheduleSlot(scheduleProvider: principalDayScheduleProvider),
        stats: _KeyMetrics(can: can, moduleOk: moduleOk),
        alertsTitle: 'آج کیا کرنا ہے؟',
        alerts: _TodayTasks(can: can, moduleOk: moduleOk),
        sections: [
          _ResponsiveSections(can: can, moduleOk: moduleOk),
          _DepartmentsSection(can: can, moduleOk: moduleOk),
        ],
      ),
    );
  }

  static void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GlobalSearchPage()),
    );
  }
}

// ─────────────────────────────────────────────
// "آج کا انتظامی خلاصہ" — tappable key metrics
// ─────────────────────────────────────────────

/// Five live metrics, each card deep-linking to its workflow screen.
/// Single column stack + tappable search entry on top; metrics render as
/// a 2-column grid on mobile, a 5-across row on desktop.
class _KeyMetrics extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _KeyMetrics({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider).valueOrNull ??
        const DashboardStats.zero();
    final statsLoading = ref.watch(dashboardStatsProvider).isLoading;
    final feeSummary = ref.watch(feeSummaryProvider).valueOrNull;
    final todayCollection =
        ref.watch(todayCollectionProvider).valueOrNull ?? 0.0;

    final canSeeStudents = can(AppPermissions.viewStudents);
    final canSeeAttendance = can(AppPermissions.viewAttendance) ||
        can(AppPermissions.markAttendance);
    final canSeeFees =
        (can(AppPermissions.viewFees) || can(AppPermissions.collectFees)) &&
            moduleOk('fees');
    final canSeeDarjas =
        can(AppPermissions.viewDarjas) && moduleOk('academics');

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final marked = stats.todayPresent + stats.todayAbsent + stats.todayLeave;
    final attendancePct =
        marked == 0 ? null : (stats.todayPresent * 100 / marked);

    final cards = <Widget>[
      if (canSeeStudents)
        StatCard(
          icon: Icons.people_outline,
          label: 'کل طلبہ',
          value: statsLoading ? '…' : '${stats.totalStudents}',
          color: AppColors.primary,
          onTap: () => go(const StudentListScreen()),
        ),
      if (canSeeAttendance)
        StatCard(
          icon: Icons.fact_check_outlined,
          label: 'آج کی حاضری',
          value: attendancePct == null ? '—' : '${attendancePct.round()}٪',
          color: AppColors.present,
          subtitle: attendancePct == null ? 'ابھی شروع نہیں ہوئی' : null,
          onTap: () => go(const AttendanceScreen()),
        ),
      if (canSeeFees)
        StatCard(
          icon: Icons.payments_outlined,
          label: 'آج کی فیس وصولی',
          value: _formatRs(todayCollection),
          color: AppColors.success,
          onTap: () => go(const FeeManagementScreen()),
        ),
      if (canSeeFees)
        StatCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'بقایا فیس',
          value: feeSummary == null ? '…' : _formatRs(feeSummary.totalDue),
          color: AppColors.warning,
          subtitle: feeSummary == null
              ? null
              : '${feeSummary.pendingCount} بقایا جات',
          onTap: () => go(const FeeManagementScreen()),
        ),
      if (canSeeDarjas)
        StatCard(
          icon: Icons.school_outlined,
          label: 'فعال کلاسز',
          value: statsLoading ? '…' : '${stats.totalClasses}',
          color: AppColors.info,
          onTap: () => go(const DarjaScreen()),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tappable search entry (app-bar search icon mirrors this).
        _SearchEntry(
            onTap: () => PrincipalDashboardScreen._openSearch(context)),
        const SizedBox(height: 16),
        Text(
          'آج کا انتظامی خلاصہ',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (cards.isEmpty)
          const _EmptyState(message: 'دیکھنے کی اجازت نہیں ہے'),
        if (cards.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              // Desktop: all metrics in one row. Mobile: manual 2-per-row
              // layout (rows size to the tallest card — no fixed heights,
              // so Nastaliq labels never clip).
              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              }
              final rows = <Widget>[];
              for (var i = 0; i < cards.length; i += 2) {
                final end = (i + 2).clamp(0, cards.length);
                final rowCards = cards.sublist(i, end);
                rows.add(
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = 0; j < rowCards.length; j++) ...[
                          if (j > 0) const SizedBox(width: 10),
                          Expanded(child: rowCards[j]),
                        ],
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    rows[i],
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Tappable fake search field: "تلاش کریں..." — opens [GlobalSearchPage].
class _SearchEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_outlined, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'تلاش کریں...',
                  style: AppTypography.labelNastaliq.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              Text(
                'طلبہ • اساتذہ • درجات • فیس',
                style: AppTypography.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// "آج کیا کرنا ہے؟" — data-driven task list
// ─────────────────────────────────────────────

/// Tasks with live counts, each with a primary CTA into the workflow.
/// Renders an honest "all done" state when nothing is pending.
class _TodayTasks extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _TodayTasks({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = <Widget>[];

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    // 1 — حاضری مکمل کریں (remaining = enrolled − marked today).
    if (can(AppPermissions.viewAttendance) ||
        can(AppPermissions.markAttendance)) {
      final stats = ref.watch(dashboardStatsProvider).valueOrNull;
      if (stats != null && stats.totalStudents > 0) {
        final marked =
            stats.todayPresent + stats.todayAbsent + stats.todayLeave;
        final remaining = stats.totalStudents - marked;
        if (remaining > 0) {
          tasks.add(AlertCard(
            icon: Icons.fact_check_outlined,
            message: marked == 0
                ? 'آج کی حاضری ابھی شروع نہیں ہوئی'
                : '$remaining طلبہ کی حاضری باقی ہے',
            actionLabel: 'حاضری لگائیں',
            onAction: () => go(const AttendanceScreen()),
          ));
        }
      }
    }

    // 2 — فیس وصول کریں (pending dues).
    if ((can(AppPermissions.viewFees) || can(AppPermissions.collectFees)) &&
        moduleOk('fees')) {
      final summary = ref.watch(feeSummaryProvider).valueOrNull;
      if (summary != null && summary.pendingCount > 0) {
        tasks.add(AlertCard(
          icon: Icons.payments_outlined,
          message:
              '${summary.pendingCount} بقایا جات — ${_formatRs(summary.totalDue)} وصول کرنا ہے',
          actionLabel: 'فیس وصول کریں',
          onAction: () => go(const FeeManagementScreen()),
        ));
      }
    }

    // 3 — نتائج درج کریں (exams with zero result rows).
    if (can(AppPermissions.viewResults) || can(AppPermissions.enterResults)) {
      final pending = ref.watch(examsWithoutResultsProvider).valueOrNull;
      if (pending != null && pending.isNotEmpty) {
        tasks.add(AlertCard(
          icon: Icons.assessment_outlined,
          message: pending.length == 1
              ? '«${pending.first.name}» کے نتائج درج نہیں ہوئے'
              : '${pending.length} امتحانات کے نتائج درج نہیں ہوئے',
          actionLabel: 'درج کریں',
          onAction: () => go(const ResultsScreen()),
          severity: AlertSeverity.info,
        ));
      }
    }

    // 4 — اعلان کریں (recent announcements exist → review/post; this is a
    // standing CTA, no fake count attached).
    if (can(AppPermissions.sendNotifications)) {
      final announcements = ref.watch(announcementListProvider);
      final recent = announcements.where((a) {
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        return a.createdAt != null && a.createdAt!.isAfter(cutoff);
      }).length;
      if (recent > 0) {
        tasks.add(AlertCard(
          icon: Icons.campaign_outlined,
          message: 'پچھلے 7 دنوں میں $recent نئے اعلانات شائع ہوئے',
          actionLabel: 'اعلانات دیکھیں',
          onAction: () => go(const AnnouncementsScreen()),
          severity: AlertSeverity.info,
        ));
      }
    }

    if (tasks.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline,
        message: 'سب امور مکمل ہیں — کوئی زیر التواء کام نہیں',
        iconColor: AppColors.success,
      );
    }
    return Column(children: tasks);
  }
}

// ─────────────────────────────────────────────
// Data sections (responsive 1-col / 2-col)
// ─────────────────────────────────────────────

/// Wraps the five data sections: single column on mobile, 2-column grid
/// on desktop.
class _ResponsiveSections extends ConsumerWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _ResponsiveSections({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <Widget>[
      if (can(AppPermissions.viewAttendance) ||
          can(AppPermissions.markAttendance))
        const _AttendanceSummarySection(),
      if ((can(AppPermissions.viewFees) || can(AppPermissions.collectFees)) &&
          moduleOk('fees'))
        const _PendingFeesSection(),
      if (can(AppPermissions.createStudents) ||
          can(AppPermissions.viewStudents))
        const _RecentAdmissionsSection(),
      if (can(AppPermissions.viewAnnouncements)) const _AnnouncementsSection(),
      if (can(AppPermissions.viewExams)) const _UpcomingExamsSection(),
    ];

    if (sections.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          // Desktop: two masonry-style columns (manual split, not a
          // fixed-extent grid — sections have variable content heights).
          final left = <Widget>[];
          final right = <Widget>[];
          for (var i = 0; i < sections.length; i++) {
            (i.isEven ? left : right).add(sections[i]);
          }
          Widget column(List<Widget> items) => Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      items[i],
                    ],
                  ],
                ),
              );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(left),
              const SizedBox(width: 12),
              column(right),
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              sections[i],
            ],
          ],
        );
      },
    );
  }
}

/// Section card shell: Nastaliq title + optional "view all" action.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.labelNastaliq.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppTypography.labelNastaliq.copyWith(
                      color: AppColors.primary,
                      fontSize: 15,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// آج کی حاضری کا خلاصہ — present/absent/leave + coverage bar.
class _AttendanceSummarySection extends ConsumerWidget {
  const _AttendanceSummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardStatsProvider);

    void go() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );

    return _SectionCard(
      icon: Icons.fact_check_outlined,
      title: 'آج کی حاضری کا خلاصہ',
      actionLabel: 'حاضری',
      onAction: go,
      child: async.when(
        loading: () => const _LoadingState(),
        error: (e, _) => _ErrorState(
          onRetry: () => ref.refresh(dashboardStatsProvider.future),
        ),
        data: (stats) {
          final marked =
              stats.todayPresent + stats.todayAbsent + stats.todayLeave;
          if (stats.totalStudents == 0) {
            return const _EmptyState(message: 'کوئی طالب علم درج نہیں');
          }
          final pct = marked == 0
              ? 0.0
              : (stats.todayPresent / stats.totalStudents).clamp(0.0, 1.0);
          return Column(
            children: [
              Row(
                children: [
                  _MiniCount(
                    label: 'حاضر',
                    count: stats.todayPresent,
                    color: AppColors.present,
                  ),
                  _MiniCount(
                    label: 'غیر حاضر',
                    count: stats.todayAbsent,
                    color: AppColors.error,
                  ),
                  _MiniCount(
                    label: 'چھٹی',
                    count: stats.todayLeave,
                    color: AppColors.leave,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: AppColors.divider.withValues(alpha: 0.4),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.present),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  marked == 0
                      ? 'ابھی حاضری شروع نہیں ہوئی'
                      : '$marked از ${stats.totalStudents} طلبہ کی حاضری لگ چکی',
                  style: AppTypography.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _MiniCount({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: AppTypography.customBody(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: AppTypography.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// زیر التواء فیس — pending dues + top unpaid rows.
class _PendingFeesSection extends ConsumerWidget {
  const _PendingFeesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allFeesProvider);

    void go() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FeeManagementScreen()),
        );

    return _SectionCard(
      icon: Icons.payments_outlined,
      title: 'زیر التواء فیس',
      actionLabel: 'فیس',
      onAction: go,
      child: async.when(
        loading: () => const _LoadingState(),
        error: (e, _) =>
            _ErrorState(onRetry: () => ref.refresh(allFeesProvider.future)),
        data: (fees) {
          final pending = fees
              .where((f) =>
                  f.status == FeeStatus.pending ||
                  f.status == FeeStatus.pastDue ||
                  f.status == FeeStatus.partial)
              .toList()
            ..sort((a, b) => (b.amountDue - b.amountPaid)
                .compareTo(a.amountDue - a.amountPaid));
          if (pending.isEmpty) {
            return const _EmptyState(
              icon: Icons.check_circle_outline,
              message: 'کوئی بقایا فیس نہیں — سب ادا شدہ',
              iconColor: AppColors.success,
            );
          }
          final totalDue = pending.fold<double>(
              0, (s, f) => s + (f.amountDue - f.amountPaid));
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${pending.length} بقایا جات',
                      style: AppTypography.labelNastaliq,
                    ),
                  ),
                  Text(
                    _formatRs(totalDue),
                    style: AppTypography.customBody(
                      fontWeight: FontWeight.bold,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final fee in pending.take(3))
                _FeeRow(
                  studentName: fee.studentName,
                  month: fee.month,
                  remaining: fee.amountDue - fee.amountPaid,
                  statusLabel: fee.status.urduLabel,
                  isPastDue: fee.status == FeeStatus.pastDue,
                ),
              if (pending.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'اور ${pending.length - 3} بقایا جات…',
                    style: AppTypography.labelSmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String studentName;
  final String month;
  final double remaining;
  final String statusLabel;
  final bool isPastDue;

  const _FeeRow({
    required this.studentName,
    required this.month,
    required this.remaining,
    required this.statusLabel,
    required this.isPastDue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPastDue ? AppColors.error : AppColors.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentName,
                  style: AppTypography.customBody(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$month • $statusLabel',
                  style: AppTypography.labelSmall,
                ),
              ],
            ),
          ),
          Text(
            _formatRs(remaining),
            style: AppTypography.customBody(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// حالیہ داخلے — students admitted in the last 7 days
/// ([newAdmissionsProvider]).
class _RecentAdmissionsSection extends ConsumerWidget {
  const _RecentAdmissionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(newAdmissionsProvider);

    void go() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StudentListScreen()),
        );

    return _SectionCard(
      icon: Icons.person_add_outlined,
      title: 'حالیہ داخلے',
      actionLabel: 'طلبہ',
      onAction: go,
      child: async.when(
        loading: () => const _LoadingState(),
        error: (e, _) => _ErrorState(
            onRetry: () => ref.refresh(newAdmissionsProvider.future)),
        data: (students) {
          if (students.isEmpty) {
            return const _EmptyState(
                message: 'پچھلے 7 دنوں میں کوئی نیا داخلہ نہیں');
          }
          return Column(
            children: [
              for (final s in students.take(4))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(
                      s.name.isNotEmpty ? s.name.characters.first : '?',
                      style: AppTypography.customBody(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  title: Text(
                    s.name,
                    style: AppTypography.labelNastaliq.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    s.darjaName.isNotEmpty
                        ? '${s.darjaName} • رول نمبر ${s.rollNo}'
                        : 'رول نمبر ${s.rollNo}',
                    style: AppTypography.labelSmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// اہم اعلانات — pinned first, then newest.
class _AnnouncementsSection extends ConsumerWidget {
  const _AnnouncementsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(announcementListProvider);

    void go() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
        );

    final sorted = [...announcements]..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });

    return _SectionCard(
      icon: Icons.campaign_outlined,
      title: 'اہم اعلانات',
      actionLabel: 'سب دیکھیں',
      onAction: go,
      child: sorted.isEmpty
          ? const _EmptyState(message: 'کوئی اعلان شائع نہیں ہوا')
          : Column(
              children: [
                for (final a in sorted.take(4))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.isPinned
                          ? Icons.push_pin_outlined
                          : Icons.campaign_outlined,
                      color: a.isPinned
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    title: Text(
                      a.title,
                      style: AppTypography.labelNastaliq.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: a.createdAt == null
                        ? null
                        : Text(
                            _timeAgo(a.createdAt!),
                            style: AppTypography.labelSmall,
                          ),
                    onTap: go,
                  ),
              ],
            ),
    );
  }
}

/// آنے والے امتحانات — exams with exam_date ≥ today, soonest first.
class _UpcomingExamsSection extends ConsumerWidget {
  const _UpcomingExamsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allExamsProvider);

    void go() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExamDashboardScreen()),
        );

    return _SectionCard(
      icon: Icons.assignment_outlined,
      title: 'آنے والے امتحانات',
      actionLabel: 'امتحانات',
      onAction: go,
      child: async.when(
        loading: () => const _LoadingState(),
        error: (e, _) =>
            _ErrorState(onRetry: () => ref.refresh(allExamsProvider.future)),
        data: (exams) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final upcoming = exams
              .map((e) => (exam: e, date: DateTime.tryParse(e.examDate)))
              .where((r) => r.date != null && !r.date!.isBefore(today))
              .toList()
            ..sort((a, b) => a.date!.compareTo(b.date!));
          if (upcoming.isEmpty) {
            return const _EmptyState(
                message: 'کوئی آنے والا امتحان شیڈول نہیں');
          }
          return Column(
            children: [
              for (final r in upcoming.take(4))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.event_outlined,
                    color: AppColors.info,
                    size: 20,
                  ),
                  title: Text(
                    r.exam.name,
                    style: AppTypography.labelNastaliq.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _examDateLabel(r.date!),
                    style: AppTypography.labelSmall,
                  ),
                  onTap: go,
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Collapsed nav: "مدرسے کے شعبے"
// ─────────────────────────────────────────────

/// Permission-gated navigation tiles (existing DashboardSection widgets).
/// Kept collapsed so the command centre stays focused; deep-links into
/// every module the role may access.
class _DepartmentsSection extends StatelessWidget {
  final bool Function(String) can;
  final bool Function(String) moduleOk;

  const _DepartmentsSection({required this.can, required this.moduleOk});

  @override
  Widget build(BuildContext context) {
    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    final tiles = [
      if (can(AppPermissions.viewStudents))
        SectionTile(
          icon: Icons.people_outline,
          label: 'طلبہ',
          onTap: () => go(const StudentListScreen()),
        ),
      if (can(AppPermissions.viewTeachers))
        SectionTile(
          icon: Icons.person_outline,
          label: 'اساتذہ',
          onTap: () => go(const StaffListScreen()),
        ),
      if (can(AppPermissions.viewDarjas) && moduleOk('academics'))
        SectionTile(
          icon: Icons.school_outlined,
          label: 'درجات',
          onTap: () => go(const DarjaScreen()),
        ),
      if (can(AppPermissions.viewExams))
        SectionTile(
          icon: Icons.assignment_outlined,
          label: 'امتحانات',
          onTap: () => go(const ExamDashboardScreen()),
        ),
      if (can(AppPermissions.viewResults))
        SectionTile(
          icon: Icons.assessment_outlined,
          label: 'نتائج',
          onTap: () => go(const ResultsScreen()),
        ),
      if (can(AppPermissions.viewFees) && moduleOk('fees'))
        SectionTile(
          icon: Icons.payments_outlined,
          label: 'فیس',
          onTap: () => go(const FeeManagementScreen()),
        ),
      if (can(AppPermissions.viewFinance))
        SectionTile(
          icon: Icons.account_balance_outlined,
          label: 'مالی حساب',
          onTap: () => go(const FinanceScreen()),
        ),
      if (can(AppPermissions.viewReports))
        SectionTile(
          icon: Icons.bar_chart_outlined,
          label: 'رپورٹس',
          onTap: () => go(const ReportsHubScreen()),
        ),
      if (can(AppPermissions.viewStaff))
        SectionTile(
          icon: Icons.badge_outlined,
          label: 'عملہ',
          onTap: () => go(const StaffListScreen()),
        ),
      if (can(AppPermissions.viewUsers))
        SectionTile(
          icon: Icons.manage_accounts_outlined,
          label: 'صارفین',
          onTap: () => go(const UserManagementScreen()),
        ),
      if (can(AppPermissions.createExams))
        SectionTile(
          icon: Icons.add_box_outlined,
          label: 'امتحان بنائیں',
          onTap: () => go(const ExamWizardScreen()),
        ),
      if (can(AppPermissions.viewLibrary) && moduleOk('library'))
        SectionTile(
          icon: Icons.local_library_outlined,
          label: 'کتب خانہ',
          onTap: () => go(const LibraryScreen()),
        ),
    ];

    if (tiles.isEmpty) return const SizedBox.shrink();
    return DashboardSection(
      title: 'مدرسے کے شعبے',
      icon: Icons.dashboard_outlined,
      initiallyExpanded: false,
      tiles: tiles,
    );
  }
}

// ─────────────────────────────────────────────
// Minimal local state widgets
//
// TODO(design-system): swap these with the shared loading / empty / error
// states once the design-system workstream lands them.
// ─────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color iconColor;

  const _EmptyState({
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.iconColor = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.labelNastaliq.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ڈیٹا لوڈ نہیں ہو سکا',
              style: AppTypography.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'دوبارہ کوشش کریں',
              style: AppTypography.labelNastaliq.copyWith(
                color: AppColors.primary,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

/// Rs formatting with Pakistani digit grouping (1,25,000).
String _formatRs(double amount) {
  final s = amount.round().toString();
  if (s.length <= 3) return 'Rs $s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return 'Rs ${parts.join(',')},$last3';
}

/// Relative Urdu timestamp for announcements.
String _timeAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'ابھی';
  if (diff.inMinutes < 60) return '${diff.inMinutes} منٹ پہلے';
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? '1 گھنٹہ پہلے' : '${diff.inHours} گھنٹے پہلے';
  }
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  if (at.year == yesterday.year &&
      at.month == yesterday.month &&
      at.day == yesterday.day) {
    return 'کل';
  }
  return '${at.day}/${at.month}/${at.year}';
}

/// Exam date label: 'آج' | 'کل' | '<n> دن بعد' | 'dd/MM/yyyy'.
String _examDateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = date.difference(today).inDays;
  if (diff == 0) return 'آج';
  if (diff == 1) return 'کل';
  if (diff < 30) return '$diff دن بعد';
  return '${date.day}/${date.month}/${date.year}';
}
