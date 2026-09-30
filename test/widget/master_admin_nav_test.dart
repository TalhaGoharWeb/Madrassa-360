// Widget tests for the platform-console navigation rail
// (lib/presentation/screens/master_admin/master_admin_nav.dart).
//
// The console previously had a plain mobile-only Drawer with an
// ungrouped English-only item list. The rail must: render every console
// destination grouped under Urdu section labels, carry the product logo,
// show the operator identity + role, and report selections (including the
// 'create-madrasa' action) back to the shell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/presentation/screens/master_admin/master_admin_nav.dart';

Widget _pumpable({
  String selectedId = 'dashboard',
  ValueChanged<String>? onSelect,
  String? role,
  String? operatorEmail,
  VoidCallback? onBackToApp,
  bool inDrawer = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MasterAdminNavRail(
        selectedId: selectedId,
        onSelect: onSelect ?? (_) {},
        inDrawer: inDrawer,
        role: role,
        operatorEmail: operatorEmail,
        onBackToApp: onBackToApp,
      ),
    ),
  );
}

/// Tall surface so the whole rail (header + all groups + footer) is laid
/// out without scrolling — the rail's list only builds visible children.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  group('MasterAdminNavRail', () {
    testWidgets('renders all groups and destinations with Urdu labels',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_pumpable());

      // Group labels.
      for (final label in ['جائزہ', 'مدارس', 'لائسنسنگ', 'پلیٹ فارم']) {
        expect(find.text(label), findsOneWidget);
      }
      // Every destination (9 total).
      for (final label in [
        'ڈیش بورڈ',
        'مدارس کی فہرست',
        'نیا مدرسہ بنائیں',
        'پلانز',
        'سبسکرپشنز',
        'لائسنسز',
        'ماڈیولز',
        'آڈٹ لاگز',
        'پلیٹ فارم صارفین',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('shows product logo, console title and operator identity',
        (tester) async {
      await tester.pumpWidget(_pumpable(
        role: 'platform_owner',
        operatorEmail: 'owner@example.com',
      ));

      expect(find.text('پلیٹ فارم کنسول'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('مالک'), findsOneWidget);
      // Product logo in the brand header and in the footer.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'assets/images/app_logo.png',
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('reports destination selections to the shell', (tester) async {
      _useTallSurface(tester);
      String? selected;
      await tester.pumpWidget(_pumpable(onSelect: (id) => selected = id));

      await tester.tap(find.text('لائسنسز'));
      expect(selected, 'licenses');

      await tester.tap(find.text('آڈٹ لاگز'));
      expect(selected, 'audit-logs');
    });

    testWidgets('create-madrasa action is reported as an action id',
        (tester) async {
      String? selected;
      await tester.pumpWidget(_pumpable(onSelect: (id) => selected = id));

      await tester.tap(find.text('نیا مدرسہ بنائیں'));
      expect(selected, 'create-madrasa');
    });

    testWidgets('back-to-app button calls onBackToApp', (tester) async {
      var backPressed = false;
      await tester.pumpWidget(_pumpable(onBackToApp: () => backPressed = true));

      await tester.tap(find.text('واپس ایپ پر'));
      expect(backPressed, isTrue);
    });

    testWidgets('drawer mode shows a close affordance', (tester) async {
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MasterAdminNavRail(
            selectedId: 'dashboard',
            onSelect: (_) {},
            inDrawer: true,
            onCloseDrawer: () => closed = true,
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });
  });
}
