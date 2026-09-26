/// ڈیش بورڈ فریم ورک — شیڈول سلاٹ
/// Dashboard framework — schedule slot.
///
/// Watches a day-schedule provider and renders its events in a
/// [DayTimeline]. While loading (or with no data) the timeline shows its
/// honest empty state — never invented rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/day_schedule_provider.dart';
import 'day_timeline.dart';

/// Renders 'آج کا شیڈول' from a day-schedule provider.
class ScheduleSlot extends ConsumerWidget {
  /// e.g. [teacherDayScheduleProvider].
  final ProviderListenable<AsyncValue<List<DayScheduleEvent>>> scheduleProvider;

  const ScheduleSlot({super.key, required this.scheduleProvider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider).valueOrNull ?? const [];
    return DayTimeline.fromSchedule(schedule: schedule);
  }
}
