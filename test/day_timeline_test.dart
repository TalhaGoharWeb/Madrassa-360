// v3 — DayTimeline widget tests.
//
// Verifies the three states (done / now / upcoming), the honest empty
// state, and the provider-event mapping. Hermetic: no providers, no
// network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/presentation/widgets/dashboard/day_timeline.dart';
import 'package:madrasa_360/providers/day_schedule_provider.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('DayTimeline', () {
    testWidgets('renders title and all three states', (tester) async {
      await tester.pumpWidget(_wrap(const DayTimeline(
        events: [
          DayTimelineEvent(title: 'حاضری مکمل', state: DayTimelineState.done),
          DayTimelineEvent(title: 'جاری سبق', state: DayTimelineState.now),
          DayTimelineEvent(title: 'اگلا کام', state: DayTimelineState.upcoming),
        ],
      )));

      expect(find.text('❁ آج کا شیڈول'), findsOneWidget);
      expect(find.text('حاضری مکمل'), findsOneWidget);
      expect(find.text('جاری سبق'), findsOneWidget);
      expect(find.text('اگلا کام'), findsOneWidget);
      // done rows carry a green check affordance
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows honest empty state when there are no events',
        (tester) async {
      await tester.pumpWidget(_wrap(const DayTimeline(events: [])));

      expect(find.text('آج کے لیے کوئی شیڈول درج نہیں ہے'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('shows custom empty message', (tester) async {
      await tester.pumpWidget(_wrap(const DayTimeline(
        events: [],
        emptyMessage: 'کوئی ڈیٹا نہیں',
      )));

      expect(find.text('کوئی ڈیٹا نہیں'), findsOneWidget);
    });

    testWidgets('renders optional time labels and subtitles', (tester) async {
      await tester.pumpWidget(_wrap(const DayTimeline(
        events: [
          DayTimelineEvent(
            title: 'امتحان',
            subtitle: '32 طلبہ',
            timeLabel: '9:00',
            state: DayTimelineState.upcoming,
          ),
        ],
      )));

      expect(find.text('9:00'), findsOneWidget);
      expect(find.text('32 طلبہ'), findsOneWidget);
    });

    testWidgets('tapping a row fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(DayTimeline(
        events: [
          DayTimelineEvent(
            title: 'قابلِ عمل',
            state: DayTimelineState.upcoming,
            onTap: () => tapped = true,
          ),
        ],
      )));

      await tester.tap(find.text('قابلِ عمل'));
      expect(tapped, isTrue);
    });
  });

  group('DayTimeline.fromSchedule', () {
    testWidgets('maps provider states to widget states', (tester) async {
      await tester.pumpWidget(_wrap(DayTimeline.fromSchedule(
        schedule: const [
          DayScheduleEvent(title: 'مکمل', state: DayScheduleState.done),
          DayScheduleEvent(title: 'ابھی', state: DayScheduleState.now),
          DayScheduleEvent(title: 'بعد میں', state: DayScheduleState.upcoming),
        ],
      )));

      expect(find.text('مکمل'), findsOneWidget);
      expect(find.text('ابھی'), findsOneWidget);
      expect(find.text('بعد میں'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('empty schedule shows the empty state', (tester) async {
      await tester
          .pumpWidget(_wrap(DayTimeline.fromSchedule(schedule: const [])));

      expect(find.text('آج کے لیے کوئی شیڈول درج نہیں ہے'), findsOneWidget);
    });
  });
}
