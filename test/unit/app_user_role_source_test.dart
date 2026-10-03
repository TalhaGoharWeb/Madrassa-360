/// SEC-H15 regression: role resolution must never trust `app_metadata`.
///
/// Implementation file under test:
///   lib/data/repositories/auth_repository.dart (AppUser.fromSupabase)
///
/// What is real here: the exact factory the login flow calls. `app_metadata`
/// is caller-writable through `manage-users` (pre-fix), so a spoofed
/// `app_metadata.role: 'superAdmin'` must NOT elevate the session. The only
/// role source is the server-owned `profiles.role` (trigger-locked).
///
/// If this factory ever reads `app_metadata['role']` again, the first test
/// goes red.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/data/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

sb.User _user({Map<String, dynamic>? appMetadata}) => sb.User.fromJson({
      'id': 'u1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'clerk@madrassa.com',
      'app_metadata': appMetadata ?? <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-10-03T00:00:00Z',
    })!;

void main() {
  group('AppUser.fromSupabase — SEC-H15 role source', () {
    test('ignores a spoofed app_metadata.role', () {
      final user = _user(appMetadata: {'role': 'superAdmin'});
      final appUser = AppUser.fromSupabase(user, {'role': 'teacher'});
      expect(appUser.role, UserRole.teacher);
    });

    test('ignores app_metadata.role even when the profile role is absent', () {
      final user = _user(appMetadata: {'role': 'tenant_owner'});
      final appUser = AppUser.fromSupabase(user, {});
      expect(appUser.role, UserRole.teacher);
    });

    test('honors the server-owned profiles.role (case-insensitive)', () {
      final user = _user();
      expect(
        AppUser.fromSupabase(user, {'role': 'superAdmin'}).role,
        UserRole.superAdmin,
      );
      expect(
        AppUser.fromSupabase(user, {'role': 'MADrasaADMIN'}).role,
        UserRole.madrasaAdmin,
      );
    });

    test('falls back to teacher on unknown profile role', () {
      final user = _user();
      expect(
        AppUser.fromSupabase(user, {'role': 'wizard'}).role,
        UserRole.teacher,
      );
    });
  });
}
