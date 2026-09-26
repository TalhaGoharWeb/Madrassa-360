/// رپورٹ کیٹلاگ
/// Static catalog of the 15 Phase-6 reports.
///
/// The catalog drives the hub screen (grouping, filter sheet, export
/// buttons). Adding a report = one entry here + a builder in
/// `documents/` + a case in [ReportsService]. See docs/REPORTING.md.

import 'report_params.dart';

class ReportCatalog {
  ReportCatalog._();

  static const List<ReportDefinition> all = [
    // ── طلبہ / Student ──────────────────────────────────────────
    ReportDefinition(
      id: 'admission_form',
      titleEn: 'Admission Form',
      titleUr: 'داخلہ فارم',
      descriptionEn:
          'Printable admission form pre-filled from the student record.',
      descriptionUr: 'طالب علم کے ریکارڈ سے پُر شدہ داخلہ فارم۔',
      category: ReportCategory.student,
      needsStudent: true,
    ),
    ReportDefinition(
      id: 'student_id_card',
      titleEn: 'Student ID Card',
      titleUr: 'طالب علم کا شناختی کارڈ',
      descriptionEn:
          'CR80-size ID card with photo placeholder and tenant branding.',
      descriptionUr:
          'کرایہ سائز کا شناختی کارڈ بمعہ تصویر کی جگہ اور ادارے کی شناخت۔',
      category: ReportCategory.student,
      needsStudent: true,
    ),
    ReportDefinition(
      id: 'character_certificate',
      titleEn: 'Character Certificate',
      titleUr: 'کردار سرٹیفکیٹ',
      descriptionEn:
          'Character certificate. Conduct is left blank for the principal to fill by hand — the system never invents it.',
      descriptionUr: 'کردار سرٹیفکیٹ۔ برتاؤ کا خانہ خالی رکھا جاتا ہے۔',
      category: ReportCategory.student,
      needsStudent: true,
    ),
    ReportDefinition(
      id: 'transfer_certificate',
      titleEn: 'Transfer / Leaving Certificate',
      titleUr: 'منتقلی سرٹیفکیٹ',
      descriptionEn:
          'School-leaving certificate with dues computed from local invoices and payments.',
      descriptionUr: 'اسکول چھوڑنے کا سرٹیفکیٹ بمعہ واجبات کی تفصیل۔',
      category: ReportCategory.student,
      needsStudent: true,
    ),
    ReportDefinition(
      id: 'result_card',
      titleEn: 'Result Card',
      titleUr: 'رزلٹ کارڈ',
      descriptionEn:
          'Per-exam result card: subjects, marks, percentage, grade and class position.',
      descriptionUr:
          'امتحانی رزلٹ کارڈ: مضامین، نمبرات، فیصد، گریڈ اور پوزیشن۔',
      category: ReportCategory.student,
      needsStudent: true,
      needsExam: true,
    ),
    ReportDefinition(
      id: 'attendance_report',
      titleEn: 'Attendance Report',
      titleUr: 'حاضری رپورٹ',
      descriptionEn:
          'Per-student attendance with present/absent/leave/late counts and percentage.',
      descriptionUr: 'طالب علم کی حاضری بمعہ فیصد۔',
      category: ReportCategory.student,
      needsStudent: true,
      needsDateRange: true,
      tabular: true,
    ),
    ReportDefinition(
      id: 'fee_statement',
      titleEn: 'Fee Statement',
      titleUr: 'فیس اسٹیٹمنٹ',
      descriptionEn:
          'Invoices, payments, discounts and the outstanding balance for one student.',
      descriptionUr: 'ایک طالب علم کے بل، ادائیگیاں اور واجب الادا رقم۔',
      category: ReportCategory.student,
      needsStudent: true,
      tabular: true,
    ),
    // ── انتظامیہ / Admin ────────────────────────────────────────
    ReportDefinition(
      id: 'student_register',
      titleEn: 'Student Register',
      titleUr: 'طلبہ رجسٹر',
      descriptionEn:
          'Full student register, optionally filtered by class or darja.',
      descriptionUr: 'مکمل طلبہ رجسٹر (جماعت/درجہ کے فلٹر کے ساتھ)۔',
      category: ReportCategory.admin,
      needsClass: true,
      needsDarja: true,
      tabular: true,
    ),
    ReportDefinition(
      id: 'teacher_register',
      titleEn: 'Teacher / Staff Register',
      titleUr: 'اساتذہ رجسٹر',
      descriptionEn: 'Staff directory with designations and contact numbers.',
      descriptionUr: 'عملے کی فہرست بمعہ عہدہ اور رابطہ نمبر۔',
      category: ReportCategory.admin,
      tabular: true,
    ),
    ReportDefinition(
      id: 'attendance_summary',
      titleEn: 'Attendance Summary',
      titleUr: 'حاضری خلاصہ',
      descriptionEn:
          'Per-student attendance summary for a class and date range.',
      descriptionUr: 'جماعت کی حاضری کا خلاصہ (مدت کے حساب سے)۔',
      category: ReportCategory.admin,
      needsClass: true,
      needsDateRange: true,
      tabular: true,
    ),
    ReportDefinition(
      id: 'fee_collection',
      titleEn: 'Fee Collection Report',
      titleUr: 'فیس وصولی رپورٹ',
      descriptionEn: 'Payments received in a period, with totals by method.',
      descriptionUr: 'مدت میں وصول شدہ فیس بمعہ کل رقم۔',
      category: ReportCategory.admin,
      needsDateRange: true,
      tabular: true,
    ),
    ReportDefinition(
      id: 'outstanding_fees',
      titleEn: 'Outstanding Fees',
      titleUr: 'واجب الادا فیس',
      descriptionEn: 'Students with unpaid balances (invoices minus payments).',
      descriptionUr: 'واجب الادا فیس والے طلبہ کی فہرست۔',
      category: ReportCategory.admin,
      needsClass: true,
      tabular: true,
    ),
    ReportDefinition(
      id: 'income_expense',
      titleEn: 'Income & Expense Report',
      titleUr: 'آمدن و اخراجات رپورٹ',
      descriptionEn:
          'Income and expense entries for a period with the net balance.',
      descriptionUr: 'مدت کی آمدن و اخراجات بمعہ خالص بیلنس۔',
      category: ReportCategory.admin,
      needsDateRange: true,
      tabular: true,
    ),
    ReportDefinition(
      id: 'exam_results',
      titleEn: 'Exam Results',
      titleUr: 'امتحانی نتائج',
      descriptionEn: 'Whole-class result sheet for one exam with positions.',
      descriptionUr: 'ایک امتحان کے جماعت بھر کے نتائج بمعہ پوزیشنز۔',
      category: ReportCategory.admin,
      needsExam: true,
      tabular: true,
    ),
    ReportDefinition(
      id: 'academic_performance',
      titleEn: 'Academic Performance',
      titleUr: 'تعلیمی کارکردگی',
      descriptionEn:
          'Per-student average percentage across exams for a class or darja.',
      descriptionUr: 'جماعت/درجہ کے طلبہ کی مجموعی تعلیمی کارکردگی۔',
      category: ReportCategory.admin,
      needsClass: true,
      needsDarja: true,
      tabular: true,
    ),
  ];

  static ReportDefinition byId(String id) => all.firstWhere(
        (r) => r.id == id,
        orElse: () => throw ArgumentError('Unknown report id: $id'),
      );

  static List<ReportDefinition> byCategory(ReportCategory c) =>
      all.where((r) => r.category == c).toList();
}
