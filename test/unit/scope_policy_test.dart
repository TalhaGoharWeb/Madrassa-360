// Phase 9: ScopePolicy narrow-only unit tests.
//
// Implementation file under test:
//   lib/core/services/scope_policy.dart
//
// Pure Dart — no Supabase, no widgets. Covers the fail-closed grant
// policy: a granter can never grant a scope wider than their own, and
// an undeterminable granter scope refuses the grant.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/services/scope_policy.dart';

/// Defaults: unrestricted granter, single class requested.
String? _grant({
  bool granterKnown = true,
  String granterType = 'all',
  Set<String> granterClassIds = const {},
  Set<String> granterStudentIds = const {},
  String requestedType = 'classes',
  Set<String> requestedClassIds = const {'c1'},
  Set<String> requestedStudentIds = const {},
  Set<String> requestedStudentClassIds = const {},
}) =>
    ScopePolicy.validateGrant(
      granterKnown: granterKnown,
      granterType: granterType,
      granterClassIds: granterClassIds,
      granterStudentIds: granterStudentIds,
      requestedType: requestedType,
      requestedClassIds: requestedClassIds,
      requestedStudentIds: requestedStudentIds,
      requestedStudentClassIds: requestedStudentClassIds,
    );

void main() {
  group('scopeTypeUrdu', () {
    test('labels every known type in Urdu', () {
      expect(scopeTypeUrdu('all'), 'پورا مدرسہ');
      expect(scopeTypeUrdu('department'), 'صرف شعبہ');
      expect(scopeTypeUrdu('classes'), 'مقرر کردہ جماعتیں');
      expect(scopeTypeUrdu('students'), 'مخصوص طلبہ');
    });

    test('unknown type falls back without leaking the raw code', () {
      expect(scopeTypeUrdu('hostel'), 'پورا مدرسہ');
      expect(scopeTypeUrdu(''), 'پورا مدرسہ');
    });
  });

  group('scopeTypeHintUrdu', () {
    test('department hint is honest about non-enforcement', () {
      expect(scopeTypeHintUrdu('department'), contains('سرور'));
    });
  });

  group('scopeSummaryUrdu', () {
    test('includes counts for narrowed types', () {
      expect(scopeSummaryUrdu('classes', classCount: 2),
          contains('مقرر کردہ جماعتیں'));
      expect(scopeSummaryUrdu('classes', classCount: 2), contains('2'));
      expect(scopeSummaryUrdu('students', studentCount: 3), contains('3'));
    });

    test('empty narrowed selection says so plainly', () {
      expect(scopeSummaryUrdu('classes'), contains('کوئی جماعت منتخب نہیں'));
    });
  });

  group('ScopePolicy.validateGrant', () {
    test('unrestricted granter may grant anything', () {
      expect(_grant(), isNull);
      expect(_grant(requestedType: 'all', requestedClassIds: const {}), isNull);
      expect(
          _grant(
              requestedType: 'students',
              requestedClassIds: const {},
              requestedStudentIds: const {'s1'}),
          isNull);
    });

    test('unknown granter scope fails closed', () {
      final refusal = _grant(granterKnown: false);
      expect(refusal, isNotNull);
      expect(refusal, contains('معلوم نہیں'));
    });

    test('class-scoped granter allows a subset of own classes', () {
      expect(
          _grant(
            granterType: 'classes',
            granterClassIds: const {'c1', 'c2'},
            requestedClassIds: const {'c1'},
          ),
          isNull);
    });

    test('class-scoped granter refuses classes outside own scope', () {
      final refusal = _grant(
        granterType: 'classes',
        granterClassIds: const {'c1'},
        requestedClassIds: const {'c1', 'c2'},
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('اپنے دائرہ کار'));
    });

    test('class-scoped granter refuses whole-madrasa and department', () {
      expect(
          _grant(
              granterType: 'classes',
              granterClassIds: const {'c1'},
              requestedType: 'all',
              requestedClassIds: const {}),
          isNotNull);
      expect(
          _grant(
              granterType: 'classes',
              granterClassIds: const {'c1'},
              requestedType: 'department',
              requestedClassIds: const {}),
          isNotNull);
    });

    test('class-scoped granter allows students inside own classes', () {
      expect(
          _grant(
            granterType: 'classes',
            granterClassIds: const {'c1'},
            requestedType: 'students',
            requestedClassIds: const {},
            requestedStudentIds: const {'s1'},
            requestedStudentClassIds: const {'c1'},
          ),
          isNull);
    });

    test('class-scoped granter refuses students from other classes', () {
      final refusal = _grant(
        granterType: 'classes',
        granterClassIds: const {'c1'},
        requestedType: 'students',
        requestedClassIds: const {},
        requestedStudentIds: const {'s9'},
        requestedStudentClassIds: const {'c9'},
      );
      expect(refusal, isNotNull);
    });

    test('student-scoped granter allows a subset of own students', () {
      expect(
          _grant(
            granterType: 'students',
            granterStudentIds: const {'s1', 's2'},
            requestedType: 'students',
            requestedClassIds: const {},
            requestedStudentIds: const {'s1'},
          ),
          isNull);
    });

    test('student-scoped granter refuses other students and classes', () {
      expect(
          _grant(
            granterType: 'students',
            granterStudentIds: const {'s1'},
            requestedType: 'students',
            requestedClassIds: const {},
            requestedStudentIds: const {'s1', 's2'},
          ),
          isNotNull);
      expect(
          _grant(
            granterType: 'students',
            granterStudentIds: const {'s1'},
            requestedType: 'classes',
            requestedClassIds: const {'c1'},
          ),
          isNotNull);
    });

    test('department-scoped granter fails closed', () {
      final refusal = _grant(
        granterType: 'department',
        requestedClassIds: const {'c1'},
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('شعبے'));
    });

    test('empty narrowed selection is refused with guidance', () {
      expect(
          _grant(
              granterType: 'classes',
              granterClassIds: const {'c1'},
              requestedClassIds: const {}),
          contains('کم از کم ایک جماعت'));
    });

    test('refusals never leak codes or latin scope names', () {
      final refusals = [
        _grant(granterKnown: false),
        _grant(
            granterType: 'classes',
            granterClassIds: const {'c1'},
            requestedType: 'all',
            requestedClassIds: const {}),
        _grant(
            granterType: 'classes',
            granterClassIds: const {'c1'},
            requestedClassIds: const {'c2'}),
        _grant(granterType: 'department', requestedClassIds: const {'c1'}),
        _grant(
            granterType: 'students',
            granterStudentIds: const {'s1'},
            requestedType: 'classes',
            requestedClassIds: const {'c1'}),
        _grant(granterType: 'bogus', requestedClassIds: const {'c1'}),
      ];
      for (final r in refusals) {
        expect(r, isNotNull);
        for (final latin in [
          'scope',
          'grant',
          'all',
          'classes',
          'students',
          'department',
        ]) {
          expect(r, isNot(contains(latin)), reason: 'leak in: $r');
        }
      }
    });
  });
}
