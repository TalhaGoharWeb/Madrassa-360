/// Reports regression tests — MultiPage pagination + ID-card robustness.
///
/// R-1: a long dataTable wrapped in pw.Column inside a pw.MultiPage threw
/// when it overflowed a page. These tests build the real PDFs (in-memory
/// Drift DB, real UrduPdf rasteriser) and assert they complete.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madrasa_360/core/reports/data/report_data.dart';
import 'package:madrasa_360/core/reports/documents/admin_reports.dart';
import 'package:madrasa_360/core/reports/documents/student_documents.dart';
import 'package:madrasa_360/core/reports/report_branding.dart';
import 'package:madrasa_360/core/reports/report_context.dart';
import 'package:madrasa_360/core/reports/report_params.dart';
import 'package:madrasa_360/core/reports/urdu_pdf.dart';
import 'package:madrasa_360/data/local/app_database.dart';

ReportBranding _branding({String? nameUrdu, String? phone}) => ReportBranding(
      name: 'Test Madrassa',
      nameUrdu: nameUrdu ?? 'ٹیسٹ مدرسہ',
      addressLine: 'ٹیسٹ پتہ، شہر',
      phone: phone ?? '03170008311',
      primary: const Color(0xFF0E7C5B),
      secondary: const Color(0xFF14532D),
      accent: const Color(0xFFF59E0B),
    );

ReportContext _ctx(
  AppDatabase db,
  ReportParams params, {
  ReportBranding? branding,
}) {
  return ReportContext(
    data: ReportData(db),
    branding: branding ?? _branding(),
    urdu: UrduPdf(),
    params: params,
    definition: const ReportDefinition(
      id: 'income_expense',
      titleEn: 'Income & Expense',
      titleUr: 'آمدن و اخراجات',
      descriptionEn: '',
      descriptionUr: '',
      category: ReportCategory.admin,
    ),
  );
}

/// Counts PDF page objects in the raw bytes (`/Type /Page`, excluding
/// the `/Type /Pages` catalog node).
int _pageCount(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  return RegExp(r'/Type\s*/Page([^s]|$)').allMatches(raw).length;
}

Future<void> _seedMoney(
  AppDatabase db,
  String tenant,
  int rows,
) async {
  for (var i = 0; i < rows; i++) {
    final day = ((i % 28) + 1).toString().padLeft(2, '0');
    await db.customStatement(
      'INSERT INTO income (id, tenant_id, updated_at, data) '
      'VALUES (?, ?, ?, ?)',
      [
        'inc-$i',
        tenant,
        0,
        jsonEncode({
          'amount': 1000 + i,
          'entry_date': '2026-09-$day',
          'category': 'عطیات',
          'description': 'آمدن اندراج نمبر $i برائے مدرسہ فنڈ',
        }),
      ],
    );
    await db.customStatement(
      'INSERT INTO expenses (id, tenant_id, updated_at, data) '
      'VALUES (?, ?, ?, ?)',
      [
        'exp-$i',
        tenant,
        0,
        jsonEncode({
          'amount': 500 + i,
          'entry_date': '2026-09-$day',
          'category': 'تنخواہیں',
          'description': 'اخراجات اندراج نمبر $i برائے عملہ',
        }),
      ],
    );
  }
}

void main() {
  test(
    'income/expense report with more rows than fit one page completes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const tenant = 't1';
      // 60 rows per section overflow a single A4 page several times over.
      await _seedMoney(db, tenant, 60);

      final ctx = _ctx(db, const ReportParams(tenantId: tenant));
      final bytes = await AdminReports.incomeExpense(ctx);

      expect(bytes.isNotEmpty, isTrue);
      expect(_pageCount(bytes), greaterThan(1));
    },
  );

  test(
    'Urdu-heavy ID card (long name, Urdu-digit phone) renders',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const tenant = 't1';
      const longName = 'محمد طلحہ بن فرید الفاروقی بن محمد اسلم خان صاحب';
      await db.customStatement(
        'INSERT INTO students (id, tenant_id, name, updated_at, data) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          's1',
          tenant,
          longName,
          0,
          jsonEncode({
            'father_name': 'محمد فرید صاحب مرحوم بن عبدالرحمن',
            'phone': '۰۳۱۷۰۰۰۸۳۱۱',
          }),
        ],
      );

      final ctx = _ctx(
        db,
        const ReportParams(tenantId: tenant, studentId: 's1'),
        branding: _branding(
          nameUrdu: 'جامعہ دارالعلوم الاسلامیہ الفریدیہ للبنین والبنات ٹرسٹ',
          phone: '۰۳۱۷۰۰۰۸۳۱۱',
        ),
      );
      final bytes = await StudentDocuments.idCard(ctx);

      expect(bytes.isNotEmpty, isTrue);
      debugPrint('ID-CARD PAGES: ${_pageCount(bytes)}');
    },
  );
}
