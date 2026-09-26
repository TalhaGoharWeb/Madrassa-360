/// ڈیش بورڈ فریم ورک — بنیادی ڈھانچہ
/// Dashboard framework — shared scaffold for every role dashboard.
///
/// [DashboardScaffold] renders the standard dashboard anatomy:
/// greeting header (السلام علیکم ورحمۃ اللہ + user + madrasa + آج date),
/// then body slots: stats row, alerts, quick actions, today-tasks,
/// and collapsible sections. All widgets are RTL-native; the app root
/// already forces [TextDirection.rtl].

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/date_utils.dart' as app_date;

/// Shared dashboard shell. [stats], [alerts], [quickActions] and
/// [todayTasks] are the ordered body slots; [sections] renders below them.
class DashboardScaffold extends StatelessWidget {
  /// Greeting line, e.g. 'السلام علیکم ورحمۃ اللہ'.
  final String greeting;

  /// Signed-in user's display name.
  final String userName;

  /// Optional role/position line under the name, e.g. 'مہتمم'.
  final String? roleLabel;

  /// Madrasa name from tenant branding.
  final String madrasaName;

  /// Stats row slot (typically a Row of [StatCard]s).
  final Widget stats;

  /// Alerts slot (typically a Column of [AlertCard]s). Hidden when null.
  final Widget? alerts;

  /// Quick actions slot (typically a [QuickActionGrid]). Hidden when null.
  final Widget? quickActions;

  /// "میرا آج کا کام" slot (typically a [TodayTasks]). Hidden when null.
  final Widget? todayTasks;

  /// Section title shown above [alerts], e.g. 'اہم امور'.
  final String? alertsTitle;

  /// Section title shown above [quickActions], e.g. 'فوری عمل'.
  final String? quickActionsTitle;

  /// Extra titled sections rendered after the slots.
  final List<Widget> sections;

  /// Optional AppBar actions (e.g. notifications bell).
  final List<Widget>? actions;

  const DashboardScaffold({
    super.key,
    required this.greeting,
    required this.userName,
    this.roleLabel,
    required this.madrasaName,
    required this.stats,
    this.alerts,
    this.quickActions,
    this.todayTasks,
    this.alertsTitle,
    this.quickActionsTitle,
    this.sections = const [],
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLine =
        '${app_date.DateUtils.formatDayName(now)}، ${app_date.DateUtils.formatDateUrdu(now)}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(madrasaName),
        actions: actions,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              greeting: greeting,
              userName: userName,
              roleLabel: roleLabel,
              dateLine: dateLine,
            ),
            const SizedBox(height: 16),
            stats,
            if (alerts != null) ...[
              const SizedBox(height: 8),
              _SlotTitle(title: alertsTitle ?? 'اہم امور'),
              alerts!,
            ],
            if (quickActions != null) ...[
              const SizedBox(height: 8),
              _SlotTitle(title: quickActionsTitle ?? 'فوری عمل'),
              quickActions!,
            ],
            if (todayTasks != null) ...[
              const SizedBox(height: 16),
              todayTasks!,
            ],
            ...sections,
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Greeting header block: greeting + name + madrasa + today's date in Urdu.
/// Calm solid colour per the restrained dashboard styling (§46).
class _Header extends StatelessWidget {
  final String greeting;
  final String userName;
  final String? roleLabel;
  final String dateLine;

  const _Header({
    required this.greeting,
    required this.userName,
    this.roleLabel,
    required this.dateLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            userName,
            style: AppTypography.headingSmall.copyWith(
              color: Colors.white,
            ),
          ),
          if (roleLabel != null && roleLabel!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              roleLabel!,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                dateLine,
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small section title used above the alert / quick-action slots.
class _SlotTitle extends StatelessWidget {
  final String title;

  const _SlotTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
