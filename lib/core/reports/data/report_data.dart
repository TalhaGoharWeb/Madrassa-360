/// رپورٹ ڈیٹا فیچرز — صرف مقامی ڈیٹا بیس
/// Report data fetchers — LOCAL DRIFT DATABASE ONLY.
///
/// Hard rule: nothing here touches the network. Every query is scoped
/// by `tenant_id` and excludes soft-deleted rows (`deleted_at IS NULL`).
/// Business detail lives in the typed envelope columns plus the `data`
/// JSON blob; JSON is parsed defensively — a missing/unparseable value
/// yields null (→ empty states downstream), never fabricated data.
///
/// Table/column names mirror lib/data/local/app_database.dart exactly.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import 'report_models.dart';

/// Fetches every report's data from the local database.
class ReportData {
  ReportData(this._db);
  final AppDatabase _db;

  // ── low-level helpers ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _q(
    String sql, [
    List<Variable> vars = const [],
  ]) async {
    try {
      final rows = await _db.customSelect(sql, variables: vars).get();
      return rows.map((r) {
        final m = Map<String, dynamic>.from(r.data);
        final raw = m['data'];
        Map<String, dynamic> decoded = const {};
        if (raw is String && raw.isNotEmpty) {
          try {
            decoded = Map<String, dynamic>.from(
                jsonDecode(raw) as Map);
          } catch (_) {
            decoded = const {};
          }
        }
        m['_data'] = decoded;
        return m;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _d(Map<String, dynamic> r) =>
      (r['_data'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};

  static String? _s(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _n(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double _nz(dynamic v) => _n(v) ?? 0.0;

  /// Matches the student repository's "live" filter: not deleted and
  /// (is_active missing or true). `is_active` lives in the data JSON.
  static const _liveStudent =
      "s.deleted_at IS NULL AND (json_extract(s.data, '\$.is_active') IS NULL "
      "OR json_extract(s.data, '\$.is_active') = 1)";

  static ReportStudent _student(Map<String, dynamic> r) {
    final d = _d(r);
    return ReportStudent(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? '',
      rollNo: _s(r['roll_no']),
      classId: _s(r['class_id']),
      className: _s(r['class_name']),
      darjaName: _s(r['darja_name']),
      fatherName: _s(d['father_name']),
      dateOfBirth: _s(d['date_of_birth']),
      dateOfAdmit: _s(d['date_of_admit']),
      phone: _s(d['phone']),
      address: _s(d['address']),
    );
  }

  static const _studentSelect = 's.*, c.name AS class_name, '
      'd.name AS darja_name FROM students s '
      'LEFT JOIN classes c ON c.id = s.class_id AND c.tenant_id = s.tenant_id '
      'AND c.deleted_at IS NULL '
      'LEFT JOIN darjas d ON d.id = c.darja_id AND d.tenant_id = c.tenant_id '
      'AND d.deleted_at IS NULL';

  // ── students / classes / darjas / staff ────────────────────────

  Future<List<ReportStudent>> students(
    String tenantId, {
    String? classId,
    String? darjaId,
    String? search,
  }) async {
    final where = StringBuffer('s.tenant_id = ? AND $_liveStudent');
    final vars = <Variable>[Variable.withString(tenantId)];
    if (classId != null) {
      where.write(' AND s.class_id = ?');
      vars.add(Variable.withString(classId));
    }
    if (darjaId != null) {
      where.write(' AND s.class_id IN (SELECT id FROM classes '
          'WHERE tenant_id = ? AND darja_id = ? AND deleted_at IS NULL)');
      vars.addAll(
          [Variable.withString(tenantId), Variable.withString(darjaId)]);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND (s.name LIKE ? OR s.roll_no LIKE ?)');
      final like = '%${search.trim()}%';
      vars.addAll(
          [Variable.withString(like), Variable.withString(like)]);
    }
    final rows = await _q(
      'SELECT $_studentSelect WHERE $where ORDER BY s.roll_no, s.name',
      vars,
    );
    return rows.map(_student).toList();
  }

  Future<ReportStudent?> studentById(
      String tenantId, String studentId) async {
    final rows = await _q(
      'SELECT $_studentSelect WHERE s.tenant_id = ? AND s.id = ? '
      'AND s.deleted_at IS NULL LIMIT 1',
      [Variable.withString(tenantId), Variable.withString(studentId)],
    );
    if (rows.isEmpty) return null;
    return _student(rows.first);
  }

  Future<List<ReportClass>> classes(String tenantId) async {
    final rows = await _q(
      'SELECT c.*, d.name AS darja_name FROM classes c '
      'LEFT JOIN darjas d ON d.id = c.darja_id '
      'AND d.tenant_id = c.tenant_id AND d.deleted_at IS NULL '
      'WHERE c.tenant_id = ? AND c.deleted_at IS NULL ORDER BY c.name',
      [Variable.withString(tenantId)],
    );
    return rows
        .map((r) => ReportClass(
              id: r['id'] as String,
              name: (r['name'] as String?) ?? '',
              darjaId: _s(r['darja_id']),
              darjaName: _s(r['darja_name']),
            ))
        .toList();
  }

  Future<List<ReportDarja>> darjas(String tenantId) async {
    final rows = await _q(
      'SELECT * FROM darjas WHERE tenant_id = ? AND deleted_at IS NULL '
      'ORDER BY name',
      [Variable.withString(tenantId)],
    );
    return rows
        .map((r) => ReportDarja(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? ''))
        .toList();
  }

  Future<List<ReportStaff>> staff(String tenantId) async {
    final rows = await _q(
      'SELECT * FROM staff WHERE tenant_id = ? AND deleted_at IS NULL '
      'ORDER BY name',
      [Variable.withString(tenantId)],
    );
    return rows.map((r) {
      final d = _d(r);
      return ReportStaff(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        designation: _s(r['designation']) ?? _s(d['designation']),
        phone: _s(d['phone']) ?? _s(d['phone_number']),
      );
    }).toList();
  }

  // ── attendance ─────────────────────────────────────────────────

  Future<List<AttendanceMark>> attendance(
    String tenantId, {
    String? studentId,
    String? classId,
    String? fromIso,
    String? toIso,
  }) async {
    final where = StringBuffer(
        'tenant_id = ? AND deleted_at IS NULL');
    final vars = <Variable>[Variable.withString(tenantId)];
    if (studentId != null) {
      where.write(' AND student_id = ?');
      vars.add(Variable.withString(studentId));
    }
    if (classId != null) {
      where.write(' AND class_id = ?');
      vars.add(Variable.withString(classId));
    }
    if (fromIso != null) {
      where.write(' AND date >= ?');
      vars.add(Variable.withString(fromIso));
    }
    if (toIso != null) {
      where.write(' AND date <= ?');
      vars.add(Variable.withString(toIso));
    }
    final rows = await _q(
      'SELECT student_id, date, status FROM attendance_records '
      'WHERE $where ORDER BY date, student_id',
      vars,
    );
    return rows
        .map((r) => AttendanceMark(
              studentId: r['student_id'] as String,
              date: (r['date'] as String?) ?? '',
              status: ((r['status'] as String?) ?? 'present').toLowerCase(),
            ))
        .toList();
  }

  /// Summarises marks per student (joins names locally).
  Future<List<AttendanceSummary>> attendanceSummary(
    String tenantId, {
    String? classId,
    String? fromIso,
    String? toIso,
  }) async {
    final marks = await attendance(tenantId,
        classId: classId, fromIso: fromIso, toIso: toIso);
    if (marks.isEmpty) return [];
    final roster = await students(tenantId, classId: classId);
    final names = {for (final s in roster) s.id: s};
    final out = <String, AttendanceSummary>{};
    for (final m in marks) {
      final s = out.putIfAbsent(
        m.studentId,
        () {
          final stu = names[m.studentId];
          return AttendanceSummary(
            studentId: m.studentId,
            studentName: stu?.name ?? m.studentId,
            rollNo: stu?.rollNo,
          );
        },
      );
      switch (m.status) {
        case 'present':
          s.present++;
        case 'absent':
          s.absent++;
        case 'leave':
          s.leave++;
        case 'late':
          s.late++;
        default:
          // Never inflate attendance: unrecognised statuses are
          // tracked separately and excluded from the numerator.
          s.unknown++;
      }
    }
    final list = out.values.toList()
      ..sort((a, b) =>
          (a.rollNo ?? '').compareTo(b.rollNo ?? ''));
    return list;
  }

  // ── fees ───────────────────────────────────────────────────────

  Future<List<ReportInvoice>> invoices(
    String tenantId, {
    String? studentId,
  }) async {
    final where = StringBuffer('tenant_id = ? AND deleted_at IS NULL');
    final vars = <Variable>[Variable.withString(tenantId)];
    if (studentId != null) {
      where.write(' AND student_id = ?');
      vars.add(Variable.withString(studentId));
    }
    final rows = await _q(
      'SELECT * FROM invoices WHERE $where ORDER BY id',
      vars,
    );
    return rows.map((r) {
      final d = _d(r);
      return ReportInvoice(
        id: r['id'] as String,
        studentId: (r['student_id'] as String?) ?? '',
        invoiceNumber:
            _s(d['invoice_number']) ?? _s(r['id'] as String),
        billingMonth: _s(d['billing_month']),
        issueDate: _s(d['issue_date']),
        dueDate: _s(d['due_date']),
        status: ((r['status'] as String?) ?? 'unpaid').toLowerCase(),
        total: _nz(r['total']),
        amountPaid: _nz(d['amount_paid']),
        discountTotal:
            _nz(d['discount_total']) + _nz(d['discount']),
      );
    }).toList();
  }

  Future<List<ReportPayment>> payments(
    String tenantId, {
    String? studentId,
    String? fromIso,
    String? toIso,
  }) async {
    final where = StringBuffer('tenant_id = ? AND deleted_at IS NULL');
    final vars = <Variable>[Variable.withString(tenantId)];
    if (studentId != null) {
      where.write(' AND student_id = ?');
      vars.add(Variable.withString(studentId));
    }
    // payment date lives in the data JSON (server-shaped payload).
    final rows = await _q('SELECT * FROM payments WHERE $where', vars);
    final list = rows.map((r) {
      final d = _d(r);
      return ReportPayment(
        id: r['id'] as String,
        studentId: _s(r['student_id'] as String?),
        invoiceId: _s(r['invoice_id'] as String?),
        amount: _nz(r['amount']),
        paymentDate: _s(d['payment_date']) ??
            _s(d['paid_at']) ??
            _s(d['date']),
        method: _s(d['method']) ?? _s(d['payment_method']),
        notes: _s(d['notes']),
      );
    }).toList();
    // Date filter in Dart (date is inside the JSON blob).
    final filtered = list.where((p) {
      if (fromIso != null &&
          (p.paymentDate == null || p.paymentDate!.compareTo(fromIso) < 0)) {
        return false;
      }
      if (toIso != null &&
          (p.paymentDate == null || p.paymentDate!.compareTo(toIso) > 0)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          (b.paymentDate ?? '').compareTo(a.paymentDate ?? ''));
    return filtered;
  }

  Future<List<ReportInvoiceItem>> invoiceItems(String invoiceId) async {
    final rows = await _q(
      'SELECT * FROM invoice_items WHERE invoice_id = ? '
      'AND deleted_at IS NULL',
      [Variable.withString(invoiceId)],
    );
    return rows.map((r) {
      final d = _d(r);
      return ReportInvoiceItem(
        description: _s(d['description']) ??
            _s(d['label']) ??
            'Item',
        amount: _nz(d['line_total'] ?? d['amount']),
      );
    }).toList();
  }

  // ── exams & results ────────────────────────────────────────────

  Future<List<ReportExam>> exams(String tenantId, {String? classId}) async {
    final where = StringBuffer('e.tenant_id = ? AND e.deleted_at IS NULL');
    final vars = <Variable>[Variable.withString(tenantId)];
    if (classId != null) {
      where.write(' AND e.class_id = ?');
      vars.add(Variable.withString(classId));
    }
    final rows = await _q(
      'SELECT e.*, c.name AS class_name FROM exams e '
      'LEFT JOIN classes c ON c.id = e.class_id '
      'AND c.tenant_id = e.tenant_id AND c.deleted_at IS NULL '
      'WHERE $where ORDER BY e.id',
      vars,
    );
    return rows.map((r) {
      final d = _d(r);
      return ReportExam(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        classId: _s(r['class_id'] as String?),
        className: _s(r['class_name']),
        examDate: _s(d['exam_date']) ?? _s(d['date']),
      );
    }).toList();
  }

  Future<List<ReportResult>> results(
    String tenantId, {
    String? examId,
    String? studentId,
  }) async {
    final where = StringBuffer('tenant_id = ? AND deleted_at IS NULL');
    final vars = <Variable>[Variable.withString(tenantId)];
    if (examId != null) {
      where.write(' AND exam_id = ?');
      vars.add(Variable.withString(examId));
    }
    if (studentId != null) {
      where.write(' AND student_id = ?');
      vars.add(Variable.withString(studentId));
    }
    final rows = await _q('SELECT * FROM results WHERE $where', vars);
    return rows.map((r) {
      final d = _d(r);
      // Keep nulls null: missing marks are "not entered", never 0.
      final obtained = _n(r['marks']) ?? _n(d['marks_obtained']);
      return ReportResult(
        examId: (r['exam_id'] as String?) ?? '',
        studentId: (r['student_id'] as String?) ?? '',
        subject: _s(d['subject']) ?? '—',
        obtained: obtained,
        totalMarks: _n(d['total_marks']),
      );
    }).toList();
  }

  /// Whole-exam sheet with class positions (dense ranking).
  Future<List<ExamOutcome>> examOutcomes(
      String tenantId, String examId) async {
    final res = await results(tenantId, examId: examId);
    if (res.isEmpty) return [];
    final roster = await students(tenantId);
    final names = {for (final s in roster) s.id: s};
    final byStudent = <String, ExamOutcome>{};
    for (final r in res) {
      final o = byStudent.putIfAbsent(r.studentId, () {
        final stu = names[r.studentId];
        return ExamOutcome(
          studentId: r.studentId,
          studentName: stu?.name ?? r.studentId,
          rollNo: stu?.rollNo,
        );
      });
      // Only usable rows feed totals and rankings.
      if (r.usable) {
        o.obtained += r.obtained!;
        o.total += r.totalMarks!;
        o.hasMarks = true;
      }
    }
    // Dense ranking by obtained marks — only over students who have
    // usable marks. Students without marks stay unranked (position 0).
    final ranked = byStudent.values.where((o) => o.hasMarks).toList()
      ..sort((a, b) => b.obtained.compareTo(a.obtained));
    var rank = 0;
    double? last;
    for (final o in ranked) {
      if (last == null || o.obtained < last) {
        rank++;
        last = o.obtained;
      }
      o.position = rank;
    }
    final list = byStudent.values.toList()
      ..sort((a, b) {
        if (a.position == 0 && b.position == 0) {
          return (a.rollNo ?? '').compareTo(b.rollNo ?? '');
        }
        if (a.position == 0) return 1;
        if (b.position == 0) return -1;
        return a.position.compareTo(b.position);
      });
    return list;
  }

  // ── income / expense ───────────────────────────────────────────

  Future<List<MoneyEntry>> moneyEntries(
    String tenantId, {
    required bool income,
    String? fromIso,
    String? toIso,
  }) async {
    final table = income ? 'income' : 'expenses';
    final rows = await _q(
      'SELECT * FROM $table WHERE tenant_id = ? AND deleted_at IS NULL',
      [Variable.withString(tenantId)],
    );
    final list = rows.map((r) {
      final d = _d(r);
      return MoneyEntry(
        id: r['id'] as String,
        isIncome: income,
        amount: _n(d['amount']),
        entryDate: _s(d['entry_date']) ?? _s(d['date']),
        category: _s(d['category']),
        description: _s(d['description']) ?? _s(d['notes']),
      );
    }).where((e) {
      if (fromIso != null &&
          (e.entryDate == null || e.entryDate!.compareTo(fromIso) < 0)) {
        return false;
      }
      if (toIso != null &&
          (e.entryDate == null || e.entryDate!.compareTo(toIso) > 0)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          (b.entryDate ?? '').compareTo(a.entryDate ?? ''));
    return list;
  }
}
