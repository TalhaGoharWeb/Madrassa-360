// Regression test: the dashboard sidebar (AppNavRail — drawer AND desktop
// rail) must carry the Madrassa-360 product logo in its footer.
//
// Bug found 2026-09-30: the branding pass added the product logo footer to
// AppDrawer, but every dashboard shell actually renders AppNavRail — the
// footer never appeared on any real sidebar, and AppDrawer was dead code.
// This test pumps the real sidebar widget and asserts the product logo is
// present; it fails if the footer is moved back to a widget the shell does
// not render.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/data/models/announcement.dart';
import 'package:madrasa_360/presentation/shell/app_nav_rail.dart';
import 'package:madrasa_360/providers/announcement_provider.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';

Widget _harness(ProviderContainer c, Widget child) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: child)),
    );

Finder _productLogoFinder() => find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/images/app_logo.png',
    );

void main() {
  testWidgets('drawer sidebar shows the Madrassa-360 product logo in footer',
      (tester) async {
    final c = ProviderContainer(overrides: [
      userPermissionsProvider.overrideWithValue(<String>{}),
      activeRoleKeysProvider.overrideWithValue(<String>[]),
      tenantBrandingProvider
          .overrideWith((ref) async => TenantBranding.fallback()),
      // The always-visible announcements destination carries a badge backed
      // by Supabase; stub it so the rail builds without a live backend.
      announcementListProvider.overrideWithValue(<Announcement>[]),
      displayNameProvider('مہمان').overrideWithValue('مہمان'),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(
      c,
      AppNavRail(
        selectedId: 'dashboard',
        onSelect: (_) {},
        inDrawer: true,
      ),
    ));
    await tester.pump();

    // Exactly one product logo: the footer. The tenant header shows the
    // tenant's own logo slot (۳۶۰ fallback mark here), never this asset.
    expect(_productLogoFinder(), findsOneWidget);
    // Footer label next to the logo.
    expect(find.text('مدرسہ 360'), findsWidgets);
  });

  testWidgets('desktop rail sidebar shows the Madrassa-360 product logo',
      (tester) async {
    final c = ProviderContainer(overrides: [
      userPermissionsProvider.overrideWithValue(<String>{}),
      activeRoleKeysProvider.overrideWithValue(<String>[]),
      tenantBrandingProvider
          .overrideWith((ref) async => TenantBranding.fallback()),
      announcementListProvider.overrideWithValue(<Announcement>[]),
      displayNameProvider('مہمان').overrideWithValue('مہمان'),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(_harness(
      c,
      AppNavRail(
        selectedId: 'dashboard',
        onSelect: (_) {},
      ),
    ));
    await tester.pump();

    expect(_productLogoFinder(), findsOneWidget);
  });
}
