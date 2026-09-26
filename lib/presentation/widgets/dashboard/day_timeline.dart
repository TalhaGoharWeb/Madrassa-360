/// ڈیش بورڈ فریم ورک — آج کا شیڈول
/// Dashboard framework — "آج کا شیڈول" day timeline.
///
/// Vertical timeline of today's events in three states:
/// done (✓ green), now (● pulsing amber), upcoming (○ hollow).
/// Events come from REAL provider data owned by the caller — this widget
/// never invents rows. When [events] is empty it renders an honest empty
/// state instead of hiding itself.

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/day_schedule_provider.dart';

/// State of one timeline event.
enum DayTimelineState {
  /// Already happened — green check.
  done,

  /// Happening now — pulsing amber dot.
  now,

  /// Still ahead — hollow dot.
  upcoming,
}

/// One row of the day timeline.
class DayTimelineEvent {
  /// Urdu title, e.g. 'حاضری — جماعت پنجم'.
  final String title;

  /// Optional supporting line, e.g. '32 طلبہ'.
  final String? subtitle;

  /// Optional time label, e.g. '9:00'. Null when the source data has no
  /// real time — the widget never fabricates one.
  final String? timeLabel;

  final DayTimelineState state;

  /// Optional tap action for the row.
  final VoidCallback? onTap;

  const DayTimelineEvent({
    required this.title,
    this.subtitle,
    this.timeLabel,
    this.state = DayTimelineState.upcoming,
    this.onTap,
  });
}

/// 'آج کا شیڈول' card with a vertical event timeline.
class DayTimeline extends StatelessWidget {
  /// Card title. Defaults to 'آج کا شیڈول'.
  final String title;

  /// Events in display order. Empty → honest empty state.
  final List<DayTimelineEvent> events;

  /// Message shown when [events] is empty. Must stay honest — it means
  /// "no schedule data", never a fabricated schedule.
  final String emptyMessage;

  const DayTimeline({
    super.key,
    this.title = 'آج کا شیڈول',
    this.events = const [],
    this.emptyMessage = 'آج کے لیے کوئی شیڈول درج نہیں ہے',
  });

  /// Builds a timeline from [DayScheduleEvent]s produced by the
  /// day-schedule providers (real data, never invented).
  factory DayTimeline.fromSchedule({
    Key? key,
    String title = 'آج کا شیڈول',
    required List<DayScheduleEvent> schedule,
    String emptyMessage = 'آج کے لیے کوئی شیڈول درج نہیں ہے',
  }) {
    return DayTimeline(
      key: key,
      title: title,
      emptyMessage: emptyMessage,
      events: schedule
          .map(
            (e) => DayTimelineEvent(
              title: e.title,
              subtitle: e.subtitle,
              timeLabel: e.timeLabel,
              state: switch (e.state) {
                DayScheduleState.done => DayTimelineState.done,
                DayScheduleState.now => DayTimelineState.now,
                DayScheduleState.upcoming => DayTimelineState.upcoming,
              },
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                '❁ $title',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (events.isEmpty)
            _EmptyState(message: emptyMessage)
          else
            ...List.generate(events.length, (i) {
              final event = events[i];
              return _TimelineRow(
                event: event,
                isFirst: i == 0,
                isLast: i == events.length - 1,
              );
            }),
        ],
      ),
    );
  }
}

/// Honest empty state — shown when no real schedule data exists.
class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.event_note_outlined,
            color: AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.labelNastaliq,
            ),
          ),
        ],
      ),
    );
  }
}

/// One timeline row: rail dot + connecting line beside the content.
class _TimelineRow extends StatelessWidget {
  final DayTimelineEvent event;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  Color get _stateColor => switch (event.state) {
        DayTimelineState.done => AppColors.present,
        DayTimelineState.now => AppColors.warning,
        DayTimelineState.upcoming => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: event.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rail: dot centred on a vertical connector line.
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  if (!isFirst)
                    Container(width: 2, height: 8, color: _railColor())
                  else
                    const SizedBox(height: 8),
                  _StateDot(state: event.state),
                  if (!isLast)
                    Container(width: 2, height: 28, color: _railColor())
                  else
                    const SizedBox(height: 28),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.timeLabel != null && event.timeLabel!.isNotEmpty)
                    Text(
                      event.timeLabel!,
                      style: AppTypography.labelNastaliq.copyWith(
                        fontSize: 15,
                        color: _stateColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    event.title,
                    style: AppTypography.labelNastaliq.copyWith(
                      fontSize: 17,
                      fontWeight: event.state == DayTimelineState.now
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: event.state == DayTimelineState.done
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (event.subtitle != null && event.subtitle!.isNotEmpty)
                    Text(
                      event.subtitle!,
                      style: AppTypography.labelNastaliq.copyWith(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (event.state == DayTimelineState.done)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.check_circle,
                  color: AppColors.present,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _railColor() => event.state == DayTimelineState.done
      ? AppColors.present.withValues(alpha: 0.4)
      : AppColors.divider;
}

/// State dot: green check, pulsing amber, or hollow grey.
class _StateDot extends StatelessWidget {
  final DayTimelineState state;

  const _StateDot({required this.state});

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      DayTimelineState.done => Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppColors.present,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 14),
        ),
      DayTimelineState.now => const _PulsingDot(),
      DayTimelineState.upcoming => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.textSecondary, width: 2),
            color: AppColors.surface,
          ),
        ),
    };
  }
}

/// Amber dot with a soft expanding pulse ring.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = _pulse.value;
              return Container(
                width: 14 + t * 14,
                height: 14 + t * 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.warning.withValues(alpha: 0.35 * (1 - t)),
                ),
              );
            },
          ),
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
