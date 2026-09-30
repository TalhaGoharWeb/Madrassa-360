// Regression test: tenantMembershipsProvider must source the uid from the
// live Supabase session, NOT from currentUserProvider.
//
// Root cause of the "every tenant user lands on NoAccessScreen" bug:
// during AuthNotifier._handleSignedIn the Riverpod auth state still has no
// user (it is set only after the route is decided), so the old provider
// read a null uid, returned [], and that empty list was cached — routing
// every tenant user to NoAccessScreen despite a valid, active
// tenant_memberships row. Platform admins were unaffected because their
// route comes from the platform_admins check, which is why only tenant
// logins (e.g. mohtamim@madrassa.com) broke.
//
// This test pins the contract: with NO Supabase session, the provider
// returns [] WITHOUT touching the network — even when currentUserProvider
// yields a user (the mid-sign-in state). The Supabase client points at a
// dead address, so on the old implementation this test fails with a
// SocketException instead of returning [].

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/tenant_context.dart';
import 'package:madrasa_360/data/repositories/auth_repository.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'memberships use the session uid: no session -> [] even with a '
      'Riverpod user (mid-sign-in state)', () async {
    SharedPreferences.setMockInitialValues({});
    // Dead address: any real PostgREST query fails fast with a
    // SocketException instead of hanging.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'test-anon-key',
    );

    final container = ProviderContainer(
      overrides: [
        // Simulate mid-sign-in: the Riverpod auth user exists while the
        // membership query runs. The provider must NOT use this id.
        currentUserProvider.overrideWith(
          (ref) => const AppUser(
            id: 'riverpod-user-id-without-session',
            email: 'mohtamim@madrassa.com',
            name: 'Test Mohtamim',
            role: UserRole.madrasaAdmin,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final memberships = await container.read(tenantMembershipsProvider.future);
    expect(memberships, isEmpty);
  });
}
