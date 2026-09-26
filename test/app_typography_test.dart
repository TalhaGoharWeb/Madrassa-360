// v3 — typography system tests.
//
// Locks the v3 type contract: Jameel Noori for display (height ≥ 2.0),
// Kasheeda for hero moments, Noto Naskh Arabic for body/small text.

import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';

void main() {
  group('AppTypography display styles (Jameel Noori)', () {
    final display = {
      'headingLarge': AppTypography.headingLarge,
      'headingMedium': AppTypography.headingMedium,
      'headingSmall': AppTypography.headingSmall,
      'titleLarge': AppTypography.titleLarge,
      'titleMedium': AppTypography.titleMedium,
      'titleSmall': AppTypography.titleSmall,
      'appBarTitle': AppTypography.appBarTitle,
    };

    for (final entry in display.entries) {
      test('${entry.key} uses JameelNooriNastaleeq with height ≥ 2.0', () {
        final s = entry.value;
        expect(s.fontFamily, AppTypography.nastaliqFamily);
        expect(s.fontFamily, 'JameelNooriNastaleeq');
        expect(s.height, greaterThanOrEqualTo(2.0));
      });
    }

    test('display styles never go below 15sp (Nastaliq minimum)', () {
      for (final s in display.values) {
        expect(s.fontSize, greaterThanOrEqualTo(15));
      }
    });
  });

  group('AppTypography hero styles (Kasheeda)', () {
    test('greetingKasheeda uses the Kasheeda family', () {
      final s = AppTypography.greetingKasheeda;
      expect(s.fontFamily, AppTypography.kasheedaFamily);
      expect(s.fontFamily, 'JameelNooriKasheeda');
      expect(s.height, greaterThanOrEqualTo(2.0));
    });

    test('heroKasheeda uses the Kasheeda family', () {
      final s = AppTypography.heroKasheeda;
      expect(s.fontFamily, AppTypography.kasheedaFamily);
      expect(s.height, greaterThanOrEqualTo(2.0));
    });
  });

  group('AppTypography body styles (Noto Naskh Arabic)', () {
    final body = {
      'bodyLarge': AppTypography.bodyLarge,
      'bodyMedium': AppTypography.bodyMedium,
      'bodySmall': AppTypography.bodySmall,
      'labelLarge': AppTypography.labelLarge,
      'labelMedium': AppTypography.labelMedium,
      'labelSmall': AppTypography.labelSmall,
      'buttonText': AppTypography.buttonText,
      'navLabel': AppTypography.navLabel,
    };

    for (final entry in body.entries) {
      test('${entry.key} uses NotoNaskhArabic', () {
        expect(entry.value.fontFamily, AppTypography.naskhFamily);
        expect(entry.value.fontFamily, 'NotoNaskhArabic');
      });
    }
  });
}
