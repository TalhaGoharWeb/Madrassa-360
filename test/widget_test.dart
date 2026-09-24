// This is a basic Flutter widget test for Madrasa 360
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:al_markaz_al_islami/main.dart';

void main() {
  testWidgets('App starts with login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: Madrasa360App()));

    // Verify that login screen is shown
    expect(find.text('المرکز الاسلامی قصور'), findsOneWidget);
    expect(find.text('Al Markaz al Islami Kasur'), findsOneWidget);
  });
}
