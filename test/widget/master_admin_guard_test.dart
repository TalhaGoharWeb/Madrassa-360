/// Widget tests for [MasterAdminGuard] (fail-closed platform-admin gate).
///
/// Implementation files under test:
///   lib/core/widgets/master_admin_guard.dart  (fetchPlatformAdminRole,
///                                             MasterAdminGuard)
///
/// Supabase is initialized to a dummy URL with no signed-in user, so
/// `fetchPlatformAdminRole` returns null (no `platform_admins` row can
/// exist for a null uid) — exercising the deny path exactly as production
/// does for a non-platform-admin (RLS yields zero rows → deny).
///
/// NOTE: the allow path (a `platform_admins` row IS returned) has no seam
/// in the current implementation — the guard reads `Supabase.instance`
/// directly instead of an injectable client — so it cannot be covered
/// without a live backend or a production refactor.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:madrasa_360/core/widgets/master_admin_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'widget-test-anon-key',
    );
  });

  Future<void> pumpGuard(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MasterAdminGuard(
          child: Text('SECRET-ADMIN-CHILD'),
        ),
      ),
    );
  }

  group('MasterAdminGuard', () {
    testWidgets(
        'non-platform-admin sees access-denied and the child is never built',
        (tester) async {
      await pumpGuard(tester);
      await tester.pumpAndSettle();

      // Deny panel content.
      expect(find.text('Access denied'), findsOneWidget);
      expect(find.textContaining('restricted to platform operators'),
          findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Sign out'), findsOneWidget);

      // Fails closed: the protected child must not exist in the tree.
      expect(find.text('SECRET-ADMIN-CHILD'), findsNothing);
    });

    testWidgets('fetchPlatformAdminRole returns null without a session',
        (_) async {
      // Null uid → null role (no network involved: the lookup needs a uid).
      expect(await fetchPlatformAdminRole(), isNull);
    });
  });
}
