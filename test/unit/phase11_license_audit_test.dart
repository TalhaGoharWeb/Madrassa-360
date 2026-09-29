// Phase 11 — master admin production pass: license ops + audit export.
//
// Real-data contracts:
//  * The license status vocabulary is EXACTLY the CHECK set from
//    supabase/migrations/011_licensing.sql — the bogus 'revoked' filter
//    that once shipped must never come back.
//  * Audit export applies the identical filter params as the on-screen
//    list (auditExportFilterParams wraps auditFilterParams).
//  * Network/device export columns exist only when the fetched rows'
//    metadata actually carries them.
//  * Destructive license actions sit behind a typed confirmation whose
//    confirm button stays disabled until the exact text is entered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/design/m360.dart';
import 'package:madrasa_360/data/repositories/license_repository.dart';
import 'package:madrasa_360/presentation/screens/master_admin/audit_export.dart';

void main() {
  group('license status vocabulary (011_licensing.sql CHECK)', () {
    test('vocabulary is exactly the six CHECK values', () {
      expect(
        licenseStatusVocabulary,
        [
          'trial',
          'active',
          'grace_period',
          'expired',
          'suspended',
          'cancelled'
        ],
      );
    });

    test("filters contain 'cancelled' and never the invalid 'revoked'", () {
      expect(licenseStatusFilters, contains('cancelled'));
      expect(licenseStatusFilters, isNot(contains('revoked')));
      expect(licenseStatusFilters.first, 'all');
      expect(licenseStatusFilters.length, 7);
    });

    test('licenseStatusUrdu maps every valid status to distinct Urdu', () {
      final labels = {
        for (final s in licenseStatusVocabulary) s: licenseStatusUrdu(s),
      };
      for (final entry in labels.entries) {
        expect(entry.value, isNotEmpty, reason: entry.key);
        expect(entry.value, isNot(entry.key), reason: entry.key);
      }
      expect(labels.values.toSet().length, labels.length);
    });
  });

  group('auditExportFilterParams honours the active filters', () {
    test('empty filters -> no constraints', () {
      expect(auditExportFilterParams(), isEmpty);
    });

    test('all filters are carried verbatim', () {
      final from = DateTime(2026, 9, 1);
      final to = DateTime(2026, 9, 20);
      final p = auditExportFilterParams(
        tenantId: 't-1',
        action: 'license.revoked',
        actorId: 'u-9',
        fromDay: from,
        toDay: to,
      );
      expect(p['tenant_id'], 't-1');
      expect(p['action'], 'license.revoked');
      expect(p['user_id'], 'u-9');
      expect(p['created_from'], isNotNull);
      expect(p['created_to'], isNotNull);
    });

    test('partial filters only carry what is set', () {
      final p = auditExportFilterParams(action: 'tenant.suspended');
      expect(p.keys, ['action']);
    });
  });

  group('auditNetworkColumns — only real metadata keys', () {
    test('no metadata anywhere -> no network columns', () {
      final rows = [
        {'metadata': null},
        {
          'metadata': <String, dynamic>{'source': 'app'}
        },
        <String, dynamic>{},
      ];
      expect(auditNetworkColumns(rows), isEmpty);
    });

    test('present keys are returned in candidate order', () {
      final rows = [
        {
          'metadata': {
            'user_agent': 'Mozilla/5.0',
            'ip': '1.2.3.4',
            'source': 'app',
          },
        },
        {
          'metadata': {'device_name': 'Pixel 7'}
        },
      ];
      expect(
        auditNetworkColumns(rows),
        ['ip', 'device_name', 'user_agent'],
      );
    });

    test('empty-string values do not create columns', () {
      final rows = [
        {
          'metadata': {'ip': '', 'device': '  '}
        },
      ];
      expect(auditNetworkColumns(rows), isEmpty);
    });

    test('headers and rows stay aligned with network columns', () {
      final headers = buildAuditExportHeaders(['ip']);
      expect(headers.length, 6);
      expect(headers.last, 'آئی پی');
      final row = buildAuditExportRow(
        {
          'created_at': '2026-09-29T10:00:00Z',
          'action': 'license.revoked',
          'entity': 'license',
          'entity_id': 'abc',
          'tenants': {'name': 'ڈیمو مدرسہ'},
          'metadata': {'ip': '1.2.3.4'},
        },
        actorName: 'منتظم',
        networkColumns: ['ip'],
      );
      expect(row.length, headers.length);
      expect(row.last, '1.2.3.4');
      expect(row[4], isNotEmpty); // human-readable detail, never raw JSON
    });
  });

  group('M360ConfirmDialog typed destructive confirmation', () {
    Future<void> pumpDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: M360ConfirmDialog(
              title: 'لائسنس منسوخ کریں',
              message: 'یہ عمل ناقابل واپسی ہے۔',
              confirmLabel: 'منسوخ کریں',
              danger: true,
              requireTypedConfirmation: true,
              expectedText: 'ڈیمو مدرسہ',
              typedHint: 'تصدیق کے لیے مدرسے کا نام لکھیں',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool confirmEnabled(WidgetTester tester) {
      final btn =
          tester.widget<M360DangerButton>(find.byType(M360DangerButton));
      return btn.onPressed != null;
    }

    testWidgets('confirm disabled until the exact name is typed',
        (tester) async {
      await pumpDialog(tester);
      expect(confirmEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), 'غلط نام');
      await tester.pump();
      expect(confirmEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), 'ڈیمو مدرسہ');
      await tester.pump();
      expect(confirmEnabled(tester), isTrue);
    });
  });
}
