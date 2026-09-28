// AuthorizationService unit tests (Phase 5).
//
// Implementation file under test:
//   lib/core/services/authorization_service.dart
//
// These tests run against the OFFLINE path: Supabase is not initialized in
// unit tests, so PermissionService.loadEffectivePermissions() throws inside
// its guarded block and falls back to the static per-tenant role defaults.
// That is exactly the behavior under test here — the in-memory cache
// semantics (load per tenant, serve from memory, clear on demand), which
// AuthNotifier relies on at sign-in and on tenant switches.
//
// The live RPC path (get_my_permissions_detailed) is NOT covered here.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_permissions.dart';
import 'package:madrasa_360/core/services/authorization_service.dart';

void main() {
  ProviderContainer makeContainer() => ProviderContainer();

  group('AuthorizationService cache semantics (offline fallback)', () {
    test('ensureLoaded resolves the role fallback set for the tenant',
        () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final svc = c.read(authorizationServiceProvider);

      final codes = await svc.ensureLoaded('t1', roleKey: 'teacher');
      expect(codes, contains(AppPermissions.markAttendance));
      expect(codes, isNot(contains(AppPermissions.collectFees)));
      expect(svc.loadedTenantId, 't1');
    });

    test('has / hasAll / hasAny read the loaded tenant set', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final svc = c.read(authorizationServiceProvider);
      await svc.ensureLoaded('t1', roleKey: 'teacher');

      expect(svc.has(AppPermissions.markAttendance), isTrue);
      expect(svc.has(AppPermissions.collectFees), isFalse);
      expect(
          svc.hasAll(
              [AppPermissions.markAttendance, AppPermissions.viewStudents]),
          isTrue);
      expect(
          svc.hasAny(
              [AppPermissions.collectFees, AppPermissions.markAttendance]),
          isTrue);
      expect(svc.hasAny([AppPermissions.collectFees]), isFalse);
    });

    test('sourceOf reports static role provenance for fallback sets', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final svc = c.read(authorizationServiceProvider);
      await svc.ensureLoaded('t1', roleKey: 'teacher');

      expect(svc.sourceOf(AppPermissions.markAttendance), 'role');
      expect(svc.sourceOf(AppPermissions.collectFees), isNull);
    });

    test('switching tenant reloads (no stale cross-tenant permissions)',
        () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final svc = c.read(authorizationServiceProvider);

      await svc.ensureLoaded('t1', roleKey: 'teacher');
      expect(svc.has(AppPermissions.collectFees), isFalse);

      await svc.ensureLoaded('t2', roleKey: 'accountant');
      expect(svc.loadedTenantId, 't2');
      expect(svc.has(AppPermissions.collectFees), isTrue);
      expect(svc.has(AppPermissions.markAttendance), isFalse);
    });

    test('fail-closed: nothing loaded means no permissions', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final svc = c.read(authorizationServiceProvider);

      expect(svc.has(AppPermissions.viewStudents), isFalse);
      expect(svc.effectivePermissions, isEmpty);
      expect(svc.loadedTenantId, isNull);
    });

    test('clearCache drops the in-memory set', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final svc = c.read(authorizationServiceProvider);

      await svc.ensureLoaded('t1', roleKey: 'teacher');
      expect(svc.has(AppPermissions.markAttendance), isTrue);
      svc.clearCache();
      expect(svc.has(AppPermissions.markAttendance), isFalse);
      expect(svc.loadedTenantId, isNull);
      expect(svc.sourceOf(AppPermissions.markAttendance), isNull);
    });
  });
}
