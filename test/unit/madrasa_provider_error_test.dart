/// Regression test for the madrasa_provider false-success fix (2026-10-01).
///
/// `MadrasaNotifier.update()` / `delete()` used to swallow write errors
/// (`catch (_) {}`) and still apply the optimistic local change, so a
/// failed Supabase write showed as succeeded with divergent local state.
/// This locks in the fix: on write failure the notifier surfaces the
/// error (returned message + `state.error`) and leaves the prior state
/// intact — no optimistic change, no silent success.
///
/// Uses a hand-written test double (no generated mocks per the repo's
/// no-mock-data CI guard).

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/data/models/madrasa.dart';
import 'package:madrasa_360/providers/madrasa_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Test double: every table operation throws, simulating a failed
/// Supabase write (network drop, RLS denial, server error).
class _ThrowingSupabaseClient extends SupabaseClient {
  _ThrowingSupabaseClient() : super('http://localhost:54321', 'test-key');

  @override
  SupabaseQueryBuilder from(String table) {
    throw Exception('simulated write failure');
  }
}

Madrasa _madrasa({required String id, required String nameUrdu}) => Madrasa(
      id: id,
      nameUrdu: nameUrdu,
      nameEnglish: 'Test Madrasa',
      cityUrdu: 'لاہور',
      cityEnglish: 'Lahore',
    );

void main() {
  group('MadrasaNotifier write-failure handling', () {
    test('update() surfaces the error and keeps prior state', () async {
      final notifier = MadrasaNotifier(client: _ThrowingSupabaseClient());
      final original = _madrasa(id: 'm1', nameUrdu: 'اصل نام');
      notifier.state = MadrasaState(madrasas: [original], selected: original);

      final edited = _madrasa(id: 'm1', nameUrdu: 'نیا نام');
      final result = await notifier.update(edited);

      // Error is surfaced both as the return value and in state —
      // as a classified safe message (never the raw driver text).
      expect(result, isNotNull);
      expect(result, isNot(contains('simulated write failure')));
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.error, isNot(contains('simulated write failure')));
      expect(notifier.state.isLoading, isFalse);
      // Prior state is untouched: no false success, no divergent list.
      expect(notifier.state.madrasas, hasLength(1));
      expect(notifier.state.madrasas.single.nameUrdu, 'اصل نام');
      expect(notifier.state.selected?.nameUrdu, 'اصل نام');
    });

    test('delete() surfaces the error and keeps the row', () async {
      final notifier = MadrasaNotifier(client: _ThrowingSupabaseClient());
      final original = _madrasa(id: 'm1', nameUrdu: 'اصل نام');
      notifier.state = MadrasaState(madrasas: [original]);

      final result = await notifier.delete('m1');

      expect(result, isNotNull);
      expect(result, isNot(contains('simulated write failure')));
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.error, isNot(contains('simulated write failure')));
      expect(notifier.state.isLoading, isFalse);
      // The row is still there: the failed delete is not shown as done.
      expect(notifier.state.madrasas, hasLength(1));
      expect(notifier.state.madrasas.single.id, 'm1');
    });

    test('toggleStatus() failure does not flip the local flag', () async {
      final notifier = MadrasaNotifier(client: _ThrowingSupabaseClient());
      final original = _madrasa(id: 'm1', nameUrdu: 'اصل نام');
      expect(original.isActive, isTrue);
      notifier.state = MadrasaState(madrasas: [original]);

      final result = await notifier.toggleStatus(original);

      expect(result, isNotNull);
      expect(notifier.state.madrasas.single.isActive, isTrue,
          reason: 'failed toggle must not flip isActive locally');
    });
  });
}
