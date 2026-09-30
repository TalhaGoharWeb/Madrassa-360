// Regression test: displayNameProvider must never surface an email address
// as the user's name, and the locally saved profile name must win.
//
// Root cause of the reported bug: AppUser.fromSupabase falls back to
// user.email when profiles.name is absent, so every shell chip, nav-footer
// and dashboard greeting showed the raw email (e.g.
// mohtamim@madrassa.com) even after the user typed their name on the
// profile screen (which only saved to SharedPreferences under
// 'profile_name').
//
// Contract pinned here:
//   1. Local profile name wins over everything.
//   2. A real Supabase profile name is accepted.
//   3. An email-like auth name falls back to the caller-supplied default.
//   4. The local name can change at runtime and dependents rebuild.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/providers/auth_provider.dart';

void main() {
  test('local profile name wins over an email-like auth name', () {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => const AppUser(
            id: 'u1',
            email: 'mohtamim@madrassa.com',
            // fromSupabase falls back to the email when profiles.name is
            // absent — exactly the reported bug state.
            name: 'mohtamim@madrassa.com',
            role: UserRole.madrasaAdmin,
          ),
        ),
        localProfileNameProvider.overrideWith((ref) => 'محمد طلحہ'),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(displayNameProvider('مہمان')), 'محمد طلحہ');
  });

  test('real Supabase profile name is accepted', () {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => const AppUser(
            id: 'u1',
            email: 'mohtamim@madrassa.com',
            name: 'حافظ احمد صاحب',
            role: UserRole.madrasaAdmin,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(displayNameProvider('مہمان')), 'حافظ احمد صاحب');
  });

  test('email-like auth name falls back to the default', () {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => const AppUser(
            id: 'u1',
            email: 'mohtamim@madrassa.com',
            name: 'mohtamim@madrassa.com',
            role: UserRole.madrasaAdmin,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(displayNameProvider('مہمان')), 'مہمان');
  });

  test('no signed-in user falls back to the default', () {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(displayNameProvider('مہمان')), 'مہمان');
  });

  test('changing the local name updates dependents immediately', () {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => const AppUser(
            id: 'u1',
            email: 'mohtamim@madrassa.com',
            name: 'mohtamim@madrassa.com',
            role: UserRole.madrasaAdmin,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(displayNameProvider('مہمان')), 'مہمان');
    container.read(localProfileNameProvider.notifier).state = 'نیا نام';
    expect(container.read(displayNameProvider('مہمان')), 'نیا نام');
  });
}
