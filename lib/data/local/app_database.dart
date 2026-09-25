/// مقامی ڈیٹا بیس (Drift + SQLite)
/// Local Drift database — the offline-first store for the Phase 5 sync engine.
///
/// Every business table carries `tenant_id` (multi-tenant scoping),
/// `revision` / `server_revision` (optimistic-concurrency bookkeeping),
/// `updated_at` / `deleted_at` (epoch millis; soft delete), and a `data`
/// JSON blob for flexible server columns, plus indexed key columns for the
/// queries the app actually runs offline.
///
/// There is deliberately NO `dirty` flag: the [SyncQueue] table is the
/// source of truth for pending pushes.
///
/// GENERATED CODE: run
///   flutter pub run build_runner build --delete-conflicting-outputs
/// to produce `app_database.g.dart` (see lib/data/local/BUILD_NOTES.md).
/// This file is hand-written and has NOT been compiled yet.

import 'package:drift/drift.dart';

part 'app_database.g.dart';

// ─────────────────────────────────────────────
// Business tables (mirror of the server schema)
// ─────────────────────────────────────────────

/// طلبہ — cached students for offline use.
@DataClassName('LocalStudent')
class Students extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get rollNo => text().nullable()();
  TextColumn get classId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_students_tenant',
            'CREATE INDEX idx_students_tenant ON students (tenant_id)'),
        Index('idx_students_class',
            'CREATE INDEX idx_students_class ON students (tenant_id, class_id)'),
        Index('idx_students_roll',
            'CREATE INDEX idx_students_roll ON students (tenant_id, roll_no)'),
      ];
}

/// جماعتیں — cached classes.
@DataClassName('LocalClass')
class Classes extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get darjaId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_classes_tenant',
            'CREATE INDEX idx_classes_tenant ON classes (tenant_id)'),
        Index('idx_classes_darja',
            'CREATE INDEX idx_classes_darja ON classes (tenant_id, darja_id)'),
      ];
}

/// درجات — cached darjas (grade levels).
@DataClassName('LocalDarja')
class Darjas extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_darjas_tenant',
            'CREATE INDEX idx_darjas_tenant ON darjas (tenant_id)'),
      ];
}

/// حاضری — cached attendance records.
@DataClassName('LocalAttendanceRecord')
class AttendanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get studentId => text()();
  TextColumn get classId => text().nullable()();
  TextColumn get date => text()(); // YYYY-MM-DD
  TextColumn get status => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index(
            'idx_attendance_lookup',
            'CREATE INDEX idx_attendance_lookup ON '
            'attendance_records (tenant_id, class_id, date)'),
        Index(
            'idx_attendance_student',
            'CREATE INDEX idx_attendance_student ON '
            'attendance_records (tenant_id, student_id, date)'),
      ];
}

/// فیس کے بل — cached fee invoices.
@DataClassName('LocalInvoice')
class Invoices extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get studentId => text()();
  TextColumn get status => text().withDefault(const Constant('unpaid'))();
  RealColumn get total => real().withDefault(const Constant(0.0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_invoices_student',
            'CREATE INDEX idx_invoices_student ON invoices (tenant_id, student_id)'),
        Index('idx_invoices_status',
            'CREATE INDEX idx_invoices_status ON invoices (tenant_id, status)'),
      ];
}

/// ادائیگیاں — cached payments.
@DataClassName('LocalPayment')
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get studentId => text().nullable()();
  TextColumn get invoiceId => text().nullable()();
  RealColumn get amount => real().withDefault(const Constant(0.0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_payments_student',
            'CREATE INDEX idx_payments_student ON payments (tenant_id, student_id)'),
        Index('idx_payments_invoice',
            'CREATE INDEX idx_payments_invoice ON payments (tenant_id, invoice_id)'),
      ];
}

/// امتحانات — cached exams.
@DataClassName('LocalExam')
class Exams extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get classId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_exams_tenant',
            'CREATE INDEX idx_exams_tenant ON exams (tenant_id)'),
        Index('idx_exams_class',
            'CREATE INDEX idx_exams_class ON exams (tenant_id, class_id)'),
      ];
}

/// نتائج — cached exam results.
@DataClassName('LocalResult')
class Results extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get examId => text()();
  TextColumn get studentId => text()();
  RealColumn get marks => real().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_results_exam',
            'CREATE INDEX idx_results_exam ON results (tenant_id, exam_id)'),
        Index('idx_results_student',
            'CREATE INDEX idx_results_student ON results (tenant_id, student_id)'),
      ];
}

/// اعلانات — cached announcements.
@DataClassName('LocalAnnouncement')
class Announcements extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get title => text()();
  TextColumn get audience => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_announcements_tenant',
            'CREATE INDEX idx_announcements_tenant ON announcements (tenant_id)'),
      ];
}

// ─────────────────────────────────────────────
// Sync-engine tables
// ─────────────────────────────────────────────

/// ٹیننٹ سیٹنگز کیش — per-tenant settings payload pulled from the server.
@DataClassName('LocalTenantSettings')
class TenantSettingsCache extends Table {
  @override
  String get tableName => 'tenant_settings_cache';

  TextColumn get tenantId => text()();
  TextColumn get payload => text()();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {tenantId};
}

/// مطابقت پذیری کی قطار — the source of truth for pending pushes.
/// One row per local mutation that still has to reach the server.
@DataClassName('SyncQueueEntry')
class SyncQueue extends Table {
  TextColumn get operationId => text()();
  TextColumn get tenantId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  // customConstraint replaces drift's generated clause, so NOT NULL and the
  // DEFAULT are spelled out explicitly here.
  TextColumn get operation => text().customConstraint(
        "NOT NULL CHECK (\"operation\" IN ('create', 'update', 'delete'))",
      )();
  TextColumn get payloadJson => text()();
  IntColumn get baseRevision => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  TextColumn get syncStatus => text().customConstraint(
        "NOT NULL DEFAULT 'pending' CHECK (\"sync_status\" IN "
        "('pending', 'in_progress', 'failed', 'done', 'dead_letter'))",
      )();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get nextRetryAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {operationId};

  @override
  List<Index> get indexes => [
        Index(
            'idx_sync_queue_claim',
            'CREATE INDEX idx_sync_queue_claim ON '
            'sync_queue (sync_status, next_retry_at, created_at)'),
        Index(
            'idx_sync_queue_tenant',
            'CREATE INDEX idx_sync_queue_tenant ON '
            'sync_queue (tenant_id, sync_status)'),
      ];
}

/// تنازعات — conflicts needing manual review (financial entities especially).
@DataClassName('SyncConflictEntry')
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tenantId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get localPayloadJson => text()();
  TextColumn get serverPayloadJson => text()();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get resolved => integer().withDefault(const Constant(0))();

  @override
  List<Index> get indexes => [
        Index(
            'idx_sync_conflicts_open',
            'CREATE INDEX idx_sync_conflicts_open ON '
            'sync_conflicts (tenant_id, resolved)'),
      ];
}

/// پل واٹرمارکس — per-entity, per-tenant pull watermarks.
@DataClassName('SyncStateEntry')
class SyncStates extends Table {
  @override
  String get tableName => 'sync_state';

  TextColumn get entity => text()();
  TextColumn get tenantId => text()();
  IntColumn get lastServerVersion => integer().withDefault(const Constant(0))();
  IntColumn get lastPullAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {entity, tenantId};
}

// ─────────────────────────────────────────────
// DAOs — one per business entity
// ─────────────────────────────────────────────

@DriftAccessor(tables: [Students])
class StudentsDao extends DatabaseAccessor<AppDatabase>
    with _$StudentsDaoMixin {
  StudentsDao(super.db);

  Future<void> upsert(StudentsCompanion entry) =>
      into(db.students).insertOnConflictUpdate(entry);

  Future<LocalStudent?> getById(String id, String tenantId) =>
      (select(db.students)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalStudent>> listByTenant(String tenantId) =>
      (select(db.students)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalStudent>> watchByTenant(String tenantId) =>
      (select(db.students)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  /// server_revision := revision (local row now matches the server).
  /// Queue state is NOT touched here — [SyncQueueDao] owns it.
  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.students)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.students)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(StudentsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Classes])
class ClassesDao extends DatabaseAccessor<AppDatabase>
    with _$ClassesDaoMixin {
  ClassesDao(super.db);

  Future<void> upsert(ClassesCompanion entry) =>
      into(db.classes).insertOnConflictUpdate(entry);

  Future<LocalClass?> getById(String id, String tenantId) =>
      (select(db.classes)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalClass>> listByTenant(String tenantId) =>
      (select(db.classes)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalClass>> watchByTenant(String tenantId) =>
      (select(db.classes)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.classes)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.classes)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(ClassesCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Darjas])
class DarjasDao extends DatabaseAccessor<AppDatabase> with _$DarjasDaoMixin {
  DarjasDao(super.db);

  Future<void> upsert(DarjasCompanion entry) =>
      into(db.darjas).insertOnConflictUpdate(entry);

  Future<LocalDarja?> getById(String id, String tenantId) =>
      (select(db.darjas)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalDarja>> listByTenant(String tenantId) =>
      (select(db.darjas)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalDarja>> watchByTenant(String tenantId) =>
      (select(db.darjas)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.darjas)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.darjas)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(DarjasCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [AttendanceRecords])
class AttendanceRecordsDao extends DatabaseAccessor<AppDatabase>
    with _$AttendanceRecordsDaoMixin {
  AttendanceRecordsDao(super.db);

  Future<void> upsert(AttendanceRecordsCompanion entry) =>
      into(db.attendanceRecords).insertOnConflictUpdate(entry);

  Future<LocalAttendanceRecord?> getById(String id, String tenantId) =>
      (select(db.attendanceRecords)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalAttendanceRecord>> listByTenant(String tenantId) =>
      (select(db.attendanceRecords)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  /// Hot offline query: one class on one day.
  Future<List<LocalAttendanceRecord>> listByClassAndDate(
          String tenantId, String classId, String date) =>
      (select(db.attendanceRecords)
            ..where((t) =>
                t.tenantId.equals(tenantId) &
                t.classId.equals(classId) &
                t.date.equals(date) &
                t.deletedAt.isNull()))
          .get();

  Stream<List<LocalAttendanceRecord>> watchByTenant(String tenantId) =>
      (select(db.attendanceRecords)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.attendanceRecords)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.attendanceRecords)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(AttendanceRecordsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Invoices])
class InvoicesDao extends DatabaseAccessor<AppDatabase>
    with _$InvoicesDaoMixin {
  InvoicesDao(super.db);

  Future<void> upsert(InvoicesCompanion entry) =>
      into(db.invoices).insertOnConflictUpdate(entry);

  Future<LocalInvoice?> getById(String id, String tenantId) =>
      (select(db.invoices)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalInvoice>> listByTenant(String tenantId) =>
      (select(db.invoices)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  /// Hot offline query: a student's invoices, newest first.
  Future<List<LocalInvoice>> listByStudent(
          String tenantId, String studentId) =>
      (select(db.invoices)
            ..where((t) =>
                t.tenantId.equals(tenantId) &
                t.studentId.equals(studentId) &
                t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalInvoice>> watchByTenant(String tenantId) =>
      (select(db.invoices)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.invoices)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.invoices)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(InvoicesCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Payments])
class PaymentsDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentsDaoMixin {
  PaymentsDao(super.db);

  Future<void> upsert(PaymentsCompanion entry) =>
      into(db.payments).insertOnConflictUpdate(entry);

  Future<LocalPayment?> getById(String id, String tenantId) =>
      (select(db.payments)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalPayment>> listByTenant(String tenantId) =>
      (select(db.payments)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalPayment>> watchByTenant(String tenantId) =>
      (select(db.payments)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.payments)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.payments)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(PaymentsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Exams])
class ExamsDao extends DatabaseAccessor<AppDatabase> with _$ExamsDaoMixin {
  ExamsDao(super.db);

  Future<void> upsert(ExamsCompanion entry) =>
      into(db.exams).insertOnConflictUpdate(entry);

  Future<LocalExam?> getById(String id, String tenantId) =>
      (select(db.exams)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalExam>> listByTenant(String tenantId) =>
      (select(db.exams)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalExam>> watchByTenant(String tenantId) =>
      (select(db.exams)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.exams)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.exams)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(ExamsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Results])
class ResultsDao extends DatabaseAccessor<AppDatabase> with _$ResultsDaoMixin {
  ResultsDao(super.db);

  Future<void> upsert(ResultsCompanion entry) =>
      into(db.results).insertOnConflictUpdate(entry);

  Future<LocalResult?> getById(String id, String tenantId) =>
      (select(db.results)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalResult>> listByTenant(String tenantId) =>
      (select(db.results)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  /// Hot offline query: all results for one exam.
  Future<List<LocalResult>> listByExam(String tenantId, String examId) =>
      (select(db.results)
            ..where((t) =>
                t.tenantId.equals(tenantId) &
                t.examId.equals(examId) &
                t.deletedAt.isNull()))
          .get();

  Stream<List<LocalResult>> watchByTenant(String tenantId) =>
      (select(db.results)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.results)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.results)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(ResultsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Announcements])
class AnnouncementsDao extends DatabaseAccessor<AppDatabase>
    with _$AnnouncementsDaoMixin {
  AnnouncementsDao(super.db);

  Future<void> upsert(AnnouncementsCompanion entry) =>
      into(db.announcements).insertOnConflictUpdate(entry);

  Future<LocalAnnouncement?> getById(String id, String tenantId) =>
      (select(db.announcements)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalAnnouncement>> listByTenant(String tenantId) =>
      (select(db.announcements)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalAnnouncement>> watchByTenant(String tenantId) =>
      (select(db.announcements)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.announcements)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.announcements)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(AnnouncementsCompanion(serverRevision: Value(row.revision)));
      });
}

// ─────────────────────────────────────────────
// Sync-engine DAOs
// ─────────────────────────────────────────────

@DriftAccessor(tables: [TenantSettingsCache])
class TenantSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$TenantSettingsDaoMixin {
  TenantSettingsDao(super.db);

  Future<String?> getPayload(String tenantId) async {
    final row = await (select(db.tenantSettingsCache)
          ..where((t) => t.tenantId.equals(tenantId)))
        .getSingleOrNull();
    return row?.payload;
  }

  Future<void> setPayload(String tenantId, String payloadJson) =>
      into(db.tenantSettingsCache).insertOnConflictUpdate(
        TenantSettingsCacheCompanion(
          tenantId: Value(tenantId),
          payload: Value(payloadJson),
          cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Clears cached settings for one tenant (logout / tenant switch).
  Future<void> clear(String tenantId) =>
      (delete(db.tenantSettingsCache)
            ..where((t) => t.tenantId.equals(tenantId)))
          .go();
}

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  static const List<String> validOperations = ['create', 'update', 'delete'];
  static const List<String> pendingStatuses = ['pending', 'failed'];

  /// Seconds to wait before retry N (index N-1), capped afterwards.
  static const List<int> _backoffSeconds = [
    60, 300, 900, 3600, 10800, 21600, 43200, 86400
  ];

  Future<void> enqueue(SyncQueueCompanion entry) =>
      into(db.syncQueue).insert(entry);

  /// Applies the local change AND records the queue row in ONE transaction,
  /// so a crash can never leave a mutation without its queue entry (or
  /// vice versa).
  Future<void> enqueueInTransaction(
    SyncQueueCompanion entry,
    Future<void> Function() applyLocalChange,
  ) =>
      transaction(() async {
        await applyLocalChange();
        await into(db.syncQueue).insert(entry);
      });

  /// Claims up to [limit] due operations, oldest first (FIFO), flipping them
  /// to `in_progress` inside the same transaction — concurrent pumpers can
  /// never double-send the same row. Optionally scoped to one [entity].
  /// Only rows whose backoff has expired are eligible.
  Future<List<SyncQueueEntry>> claimNextBatch(
      {String? entity, int limit = 50}) {
    return transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final query = select(db.syncQueue)
        ..where((q) =>
            q.syncStatus.equals('pending') |
            (q.syncStatus.equals('failed') &
                q.nextRetryAt.isSmallerOrEqualValue(now)))
        ..orderBy([(q) => OrderingTerm(expression: q.createdAt)])
        ..limit(limit);
      if (entity != null) {
        query.where((q) => q.entity.equals(entity));
      }
      final batch = await query.get();
      for (final row in batch) {
        await (update(db.syncQueue)
              ..where((q) => q.operationId.equals(row.operationId)))
            .write(const SyncQueueCompanion(
                syncStatus: Value('in_progress')));
      }
      return batch;
    });
  }

  Future<void> markDone(String operationId) async {
    await (update(db.syncQueue)
          ..where((q) => q.operationId.equals(operationId)))
        .write(const SyncQueueCompanion(syncStatus: Value('done')));
  }

  /// Deletes `done` rows older than [olderThanMs] (queue hygiene).
  /// Returns the number of rows removed.
  Future<int> purgeDone({required int olderThanMs}) =>
      (delete(db.syncQueue)
            ..where((q) =>
                q.syncStatus.equals('done') &
                q.createdAt.isSmallerThanValue(olderThanMs)))
          .go();

  /// Records a failed push with exponential backoff. Returns the resulting
  /// status: `'failed'`, or `'dead_letter'` once [maxRetries] is exhausted.
  Future<String> markFailed(String operationId, String error,
      {int maxRetries = 8}) {
    return transaction(() async {
      final row = await (select(db.syncQueue)
            ..where((q) => q.operationId.equals(operationId)))
          .getSingleOrNull();
      if (row == null) return 'done';
      final attempts = row.retryCount + 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (attempts >= maxRetries) {
        await (update(db.syncQueue)
              ..where((q) => q.operationId.equals(operationId)))
            .write(SyncQueueCompanion(
              syncStatus: const Value('dead_letter'),
              retryCount: Value(attempts),
              lastError: Value(error),
              nextRetryAt: const Value(null),
            ));
        return 'dead_letter';
      }
      final backoffIndex =
          attempts - 1 < _backoffSeconds.length ? attempts - 1 : _backoffSeconds.length - 1;
      await (update(db.syncQueue)
            ..where((q) => q.operationId.equals(operationId)))
          .write(SyncQueueCompanion(
            syncStatus: const Value('failed'),
            retryCount: Value(attempts),
            lastError: Value(error),
            nextRetryAt: Value(now + _backoffSeconds[backoffIndex] * 1000),
          ));
      return 'failed';
    });
  }

  /// Moves a row straight to the dead-letter bucket (e.g. a poison payload
  /// the server will never accept).
  Future<void> deadLetter(String operationId, String reason) async {
    await (update(db.syncQueue)
          ..where((q) => q.operationId.equals(operationId)))
        .write(SyncQueueCompanion(
          syncStatus: const Value('dead_letter'),
          lastError: Value(reason),
          nextRetryAt: const Value(null),
        ));
  }

  /// Counts rows still needing a push for ONE tenant (pending + failed).
  /// The tenant filter makes cross-tenant leakage impossible here.
  Future<int> pendingCount(String tenantId) async {
    final count = db.syncQueue.operationId.count();
    final row = await (selectOnly(db.syncQueue)
          ..addColumns([count])
          ..where(db.syncQueue.tenantId.equals(tenantId) &
              db.syncQueue.syncStatus.isIn(pendingStatuses)))
        .getSingleOrNull();
    return row?.read(count) ?? 0;
  }

  /// Rows stuck in `in_progress` (e.g. after a crash) for one tenant —
  /// the sync engine reclaims these back to `pending`.
  Future<List<SyncQueueEntry>> listStuck(String tenantId) =>
      (select(db.syncQueue)
            ..where((q) =>
                q.tenantId.equals(tenantId) &
                q.syncStatus.equals('in_progress'))
            ..orderBy([(q) => OrderingTerm(expression: q.createdAt)]))
          .get();

  Future<void> reclaimStuck(String tenantId) async {
    await (update(db.syncQueue)
          ..where((q) =>
              q.tenantId.equals(tenantId) &
              q.syncStatus.equals('in_progress')))
        .write(const SyncQueueCompanion(syncStatus: Value('pending')));
  }
}

@DriftAccessor(tables: [SyncStates])
class SyncStateDao extends DatabaseAccessor<AppDatabase>
    with _$SyncStateDaoMixin {
  SyncStateDao(super.db);

  /// Pull watermark for (entity, tenant); 0 when never synced.
  Future<int> getWatermark(String entity, String tenantId) async {
    final row = await (select(db.syncStates)
          ..where((s) =>
              s.entity.equals(entity) & s.tenantId.equals(tenantId)))
        .getSingleOrNull();
    return row?.lastServerVersion ?? 0;
  }

  Future<void> setWatermark(
          String entity, String tenantId, int serverVersion) =>
      into(db.syncStates).insertOnConflictUpdate(SyncStatesCompanion(
        entity: Value(entity),
        tenantId: Value(tenantId),
        lastServerVersion: Value(serverVersion),
        lastPullAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

  /// Drops all watermarks for one tenant (logout / tenant switch).
  Future<void> clearTenant(String tenantId) =>
      (delete(db.syncStates)..where((s) => s.tenantId.equals(tenantId))).go();
}

@DriftAccessor(tables: [SyncConflicts])
class SyncConflictDao extends DatabaseAccessor<AppDatabase>
    with _$SyncConflictDaoMixin {
  SyncConflictDao(super.db);

  Future<int> record(SyncConflictsCompanion entry) =>
      into(db.syncConflicts).insert(entry);

  Future<List<SyncConflictEntry>> listOpen(String tenantId) =>
      (select(db.syncConflicts)
            ..where((c) =>
                c.tenantId.equals(tenantId) & c.resolved.equals(0))
            ..orderBy([
              (c) => OrderingTerm(
                  expression: c.createdAt, mode: OrderingMode.desc)
            ]))
          .get();

  Future<void> resolve(int id) async {
    await (update(db.syncConflicts)..where((c) => c.id.equals(id)))
        .write(const SyncConflictsCompanion(resolved: Value(1)));
  }

  /// Clears all conflict rows for one tenant (logout / tenant switch).
  Future<void> clearTenant(String tenantId) =>
      (delete(db.syncConflicts)..where((c) => c.tenantId.equals(tenantId)))
          .go();
}

// ─────────────────────────────────────────────
// The database itself
// ─────────────────────────────────────────────

@DriftDatabase(
  tables: [
    Students,
    Classes,
    Darjas,
    AttendanceRecords,
    Invoices,
    Payments,
    Exams,
    Results,
    Announcements,
    TenantSettingsCache,
    SyncQueue,
    SyncConflicts,
    SyncStates,
  ],
  daos: [
    StudentsDao,
    ClassesDao,
    DarjasDao,
    AttendanceRecordsDao,
    InvoicesDao,
    PaymentsDao,
    ExamsDao,
    ResultsDao,
    AnnouncementsDao,
    TenantSettingsDao,
    SyncQueueDao,
    SyncStateDao,
    SyncConflictDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
      );
}
