/// ڈیش بورڈ فریم ورک — بنیادی ڈھانچہ
/// Dashboard framework — shared scaffold for every role dashboard.
///
/// [DashboardScaffold] renders the standard dashboard anatomy:
/// greeting header (السلام علیکم ورحمۃ اللہ + user + madrasa + آج date),
/// then body slots: schedule timeline, stats row, alerts, quick actions,
/// today-tasks, and collapsible sections. All widgets are RTL-native; the
/// app root already forces [TextDirection.rtl].

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/utils/hijri_date.dart';
import '../profile_avatar_button.dart';
import 'pattern_background.dart';

/// Shared dashboard shell. [schedule], [stats], [alerts], [quickActions]
/// and [todayTasks] are the ordered body slots; [sections] renders below.
class DashboardScaffold extends StatelessWidget {
  /// Greeting line, e.g. 'السلام علیکم ورحمۃ اللہ'.
  final String greeting;

  /// Signed-in user's display name.
  final String userName;

  /// Optional role/position line under the name, e.g. 'مہتمم'.
  final String? roleLabel;

  /// Madrasa name from tenant branding.
  final String madrasaName;

  /// "آج کا شیڈول" slot (typically a [DayTimeline]). Hidden when null.
  final Widget? schedule;

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
    this.schedule,
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
    final hijriLine = HijriDate.fromGregorian(now).formatUrdu();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(madrasaName),
        // Every dashboard gets the profile button: existing actions first
        // (e.g. the notifications bell), then the tappable avatar.
        actions: [...?actions, const ProfileAvatarButton()],
      ),
      body: PatternBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                greeting: greeting,
                userName: userName,
                roleLabel: roleLabel,
                dateLine: dateLine,
                hijriLine: hijriLine,
              ),
              if (schedule != null) ...[
                const SizedBox(height: 16),
                schedule!,
              ],
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
      ),
    );
  }
}

/// Greeting header block: Kasheeda greeting + name + madrasa + today's
/// Gregorian and Hijri dates in Urdu.
class _Header extends StatelessWidget {
  final String greeting;
  final String userName;
  final String? roleLabel;
  final String dateLine;
  final String hijriLine;

  const _Header({
    required this.greeting,
    required this.userName,
    this.roleLabel,
    required this.dateLine,
    required this.hijriLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: AppTypography.greetingKasheeda.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
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
              style: AppTypography.labelNastaliq.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    dateLine,
                    style: AppTypography.labelNastaliq.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              _HijriChip(hijriLine: hijriLine),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small pill showing the Hijri date (tabular calendar).
class _HijriChip extends StatelessWidget {
  final String hijriLine;

  const _HijriChip({required this.hijriLine});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        hijriLine,
        style: AppTypography.labelNastaliq.copyWith(
          fontSize: 15,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Small section title used above the alert / quick-action slots.
/// Prefixed with the ❁ ornament per the v3 visual language.
class _SlotTitle extends StatelessWidget {
  final String title;

  const _SlotTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '❁ $title',
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
