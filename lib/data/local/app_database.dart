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

/// عملہ — staff directory.
@DataClassName('LocalStaff')
class Staffs extends Table {
  @override
  String get tableName => 'staff';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get designation => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_staff_tenant',
            'CREATE INDEX idx_staff_tenant ON staff (tenant_id)'),
        Index('idx_staff_name',
            'CREATE INDEX idx_staff_name ON staff (tenant_id, name)'),
      ];
}

/// درجے کے حصے — sections within a darja.
@DataClassName('LocalDarjaSection')
class DarjaSections extends Table {
  @override
  String get tableName => 'darja_sections';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get darjaId => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_darja_sections_tenant',
            'CREATE INDEX idx_darja_sections_tenant ON darja_sections (tenant_id)'),
        Index('idx_darja_sections_darja',
            'CREATE INDEX idx_darja_sections_darja ON darja_sections (tenant_id, darja_id)'),
      ];
}

/// لائبریری کی کتابیں — library catalog.
@DataClassName('LocalLibraryBook')
class LibraryBooks extends Table {
  @override
  String get tableName => 'library_books';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get title => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_library_books_tenant',
            'CREATE INDEX idx_library_books_tenant ON library_books (tenant_id)'),
        Index('idx_library_books_title',
            'CREATE INDEX idx_library_books_title ON library_books (tenant_id, title)'),
      ];
}

/// کتابوں کا اجرا — book lending records.
@DataClassName('LocalBookIssue')
class BookIssues extends Table {
  @override
  String get tableName => 'book_issues';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get bookId => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_book_issues_tenant',
            'CREATE INDEX idx_book_issues_tenant ON book_issues (tenant_id)'),
        Index('idx_book_issues_book',
            'CREATE INDEX idx_book_issues_book ON book_issues (tenant_id, book_id)'),
      ];
}

/// اکاؤنٹس — chart of accounts.
@DataClassName('LocalAccount')
class Accounts extends Table {
  @override
  String get tableName => 'accounts';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get code => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_accounts_tenant',
            'CREATE INDEX idx_accounts_tenant ON accounts (tenant_id)'),
        Index('idx_accounts_code',
            'CREATE INDEX idx_accounts_code ON accounts (tenant_id, code)'),
      ];
}

/// لین دین — journal transactions.
@DataClassName('LocalTransaction')
class Transactions extends Table {
  @override
  String get tableName => 'transactions';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_transactions_tenant',
            'CREATE INDEX idx_transactions_tenant ON transactions (tenant_id)'),
      ];
}

/// آمدنی — income entries.
@DataClassName('LocalIncome')
class IncomeEntries extends Table {
  @override
  String get tableName => 'income';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_income_tenant',
            'CREATE INDEX idx_income_tenant ON income (tenant_id)'),
      ];
}

/// اخراجات — expense entries.
@DataClassName('LocalExpense')
class ExpenseEntries extends Table {
  @override
  String get tableName => 'expenses';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_expenses_tenant',
            'CREATE INDEX idx_expenses_tenant ON expenses (tenant_id)'),
      ];
}

/// رقم کی واپسی — fee refunds.
@DataClassName('LocalRefund')
class Refunds extends Table {
  @override
  String get tableName => 'refunds';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_refunds_tenant',
            'CREATE INDEX idx_refunds_tenant ON refunds (tenant_id)'),
      ];
}

/// رعایتیں — invoice discounts.
@DataClassName('LocalDiscount')
class Discounts extends Table {
  @override
  String get tableName => 'discounts';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get invoiceId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_discounts_tenant',
            'CREATE INDEX idx_discounts_tenant ON discounts (tenant_id)'),
        Index('idx_discounts_invoice',
            'CREATE INDEX idx_discounts_invoice ON discounts (tenant_id, invoice_id)'),
      ];
}

/// وظائف — scholarships.
@DataClassName('LocalScholarship')
class Scholarships extends Table {
  @override
  String get tableName => 'scholarships';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get studentId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_scholarships_tenant',
            'CREATE INDEX idx_scholarships_tenant ON scholarships (tenant_id)'),
        Index('idx_scholarships_student',
            'CREATE INDEX idx_scholarships_student ON scholarships (tenant_id, student_id)'),
      ];
}

/// بل کی مدات — invoice line items.
@DataClassName('LocalInvoiceItem')
class InvoiceItems extends Table {
  @override
  String get tableName => 'invoice_items';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get invoiceId => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_invoice_items_tenant',
            'CREATE INDEX idx_invoice_items_tenant ON invoice_items (tenant_id)'),
        Index('idx_invoice_items_invoice',
            'CREATE INDEX idx_invoice_items_invoice ON invoice_items (tenant_id, invoice_id)'),
      ];
}

/// زیر التواء اپ لوڈز — files queued for Supabase Storage.
/// A sync_queue row may reference a pending upload through the
/// `_pending_upload_id` payload key; the sync engine must not push that
/// row until the upload is done (see `_ensureUploadDone`).
@DataClassName('LocalPendingUpload')
class PendingUploads extends Table {
  @override
  String get tableName => 'pending_uploads';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  // 'upload' | 'delete' — spelled out like SyncQueue's operation column.
  TextColumn get op => text().customConstraint(
        "NOT NULL CHECK (\"op\" IN ('upload', 'delete'))",
      )();
  TextColumn get localPath => text().nullable()(); // null for delete ops
  TextColumn get bucket => text()();
  TextColumn get destPath => text()();
  // 'pending' | 'uploading' | 'failed' | 'done'
  TextColumn get status => text().customConstraint(
        "NOT NULL DEFAULT 'pending' CHECK (\"status\" IN "
        "('pending', 'uploading', 'failed', 'done'))",
      )();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
  IntColumn get createdAt => integer()(); // epoch millis

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Index> get indexes => [
        Index('idx_pending_uploads_status',
            'CREATE INDEX idx_pending_uploads_status ON '
            'pending_uploads (tenant_id, status)'),
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

@DriftAccessor(tables: [Staffs])
class StaffsDao extends DatabaseAccessor<AppDatabase>
    with _$StaffsDaoMixin {
  StaffsDao(super.db);

  Future<void> upsert(StaffsCompanion entry) =>
      into(db.staffs).insertOnConflictUpdate(entry);

  Future<LocalStaff?> getById(String id, String tenantId) =>
      (select(db.staffs)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalStaff>> listByTenant(String tenantId) =>
      (select(db.staffs)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalStaff>> watchByTenant(String tenantId) =>
      (select(db.staffs)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.staffs)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.staffs)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(StaffsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [DarjaSections])
class DarjaSectionsDao extends DatabaseAccessor<AppDatabase>
    with _$DarjaSectionsDaoMixin {
  DarjaSectionsDao(super.db);

  Future<void> upsert(DarjaSectionsCompanion entry) =>
      into(db.darjaSections).insertOnConflictUpdate(entry);

  Future<LocalDarjaSection?> getById(String id, String tenantId) =>
      (select(db.darjaSections)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalDarjaSection>> listByTenant(String tenantId) =>
      (select(db.darjaSections)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalDarjaSection>> watchByTenant(String tenantId) =>
      (select(db.darjaSections)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.darjaSections)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.darjaSections)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(DarjaSectionsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [LibraryBooks])
class LibraryBooksDao extends DatabaseAccessor<AppDatabase>
    with _$LibraryBooksDaoMixin {
  LibraryBooksDao(super.db);

  Future<void> upsert(LibraryBooksCompanion entry) =>
      into(db.libraryBooks).insertOnConflictUpdate(entry);

  Future<LocalLibraryBook?> getById(String id, String tenantId) =>
      (select(db.libraryBooks)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalLibraryBook>> listByTenant(String tenantId) =>
      (select(db.libraryBooks)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalLibraryBook>> watchByTenant(String tenantId) =>
      (select(db.libraryBooks)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.libraryBooks)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.libraryBooks)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(LibraryBooksCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [BookIssues])
class BookIssuesDao extends DatabaseAccessor<AppDatabase>
    with _$BookIssuesDaoMixin {
  BookIssuesDao(super.db);

  Future<void> upsert(BookIssuesCompanion entry) =>
      into(db.bookIssues).insertOnConflictUpdate(entry);

  Future<LocalBookIssue?> getById(String id, String tenantId) =>
      (select(db.bookIssues)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalBookIssue>> listByTenant(String tenantId) =>
      (select(db.bookIssues)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalBookIssue>> watchByTenant(String tenantId) =>
      (select(db.bookIssues)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.bookIssues)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.bookIssues)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(BookIssuesCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Accounts])
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.db);

  Future<void> upsert(AccountsCompanion entry) =>
      into(db.accounts).insertOnConflictUpdate(entry);

  Future<LocalAccount?> getById(String id, String tenantId) =>
      (select(db.accounts)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalAccount>> listByTenant(String tenantId) =>
      (select(db.accounts)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalAccount>> watchByTenant(String tenantId) =>
      (select(db.accounts)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.accounts)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.accounts)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(AccountsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  Future<void> upsert(TransactionsCompanion entry) =>
      into(db.transactions).insertOnConflictUpdate(entry);

  Future<LocalTransaction?> getById(String id, String tenantId) =>
      (select(db.transactions)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalTransaction>> listByTenant(String tenantId) =>
      (select(db.transactions)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalTransaction>> watchByTenant(String tenantId) =>
      (select(db.transactions)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.transactions)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.transactions)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(TransactionsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [IncomeEntries])
class IncomeEntriesDao extends DatabaseAccessor<AppDatabase>
    with _$IncomeEntriesDaoMixin {
  IncomeEntriesDao(super.db);

  Future<void> upsert(IncomeEntriesCompanion entry) =>
      into(db.incomeEntries).insertOnConflictUpdate(entry);

  Future<LocalIncome?> getById(String id, String tenantId) =>
      (select(db.incomeEntries)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalIncome>> listByTenant(String tenantId) =>
      (select(db.incomeEntries)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalIncome>> watchByTenant(String tenantId) =>
      (select(db.incomeEntries)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.incomeEntries)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.incomeEntries)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(IncomeEntriesCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [ExpenseEntries])
class ExpenseEntriesDao extends DatabaseAccessor<AppDatabase>
    with _$ExpenseEntriesDaoMixin {
  ExpenseEntriesDao(super.db);

  Future<void> upsert(ExpenseEntriesCompanion entry) =>
      into(db.expenseEntries).insertOnConflictUpdate(entry);

  Future<LocalExpense?> getById(String id, String tenantId) =>
      (select(db.expenseEntries)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalExpense>> listByTenant(String tenantId) =>
      (select(db.expenseEntries)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalExpense>> watchByTenant(String tenantId) =>
      (select(db.expenseEntries)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.expenseEntries)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.expenseEntries)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(ExpenseEntriesCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Refunds])
class RefundsDao extends DatabaseAccessor<AppDatabase>
    with _$RefundsDaoMixin {
  RefundsDao(super.db);

  Future<void> upsert(RefundsCompanion entry) =>
      into(db.refunds).insertOnConflictUpdate(entry);

  Future<LocalRefund?> getById(String id, String tenantId) =>
      (select(db.refunds)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalRefund>> listByTenant(String tenantId) =>
      (select(db.refunds)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalRefund>> watchByTenant(String tenantId) =>
      (select(db.refunds)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.refunds)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.refunds)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(RefundsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Discounts])
class DiscountsDao extends DatabaseAccessor<AppDatabase>
    with _$DiscountsDaoMixin {
  DiscountsDao(super.db);

  Future<void> upsert(DiscountsCompanion entry) =>
      into(db.discounts).insertOnConflictUpdate(entry);

  Future<LocalDiscount?> getById(String id, String tenantId) =>
      (select(db.discounts)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalDiscount>> listByTenant(String tenantId) =>
      (select(db.discounts)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalDiscount>> watchByTenant(String tenantId) =>
      (select(db.discounts)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.discounts)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.discounts)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(DiscountsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [Scholarships])
class ScholarshipsDao extends DatabaseAccessor<AppDatabase>
    with _$ScholarshipsDaoMixin {
  ScholarshipsDao(super.db);

  Future<void> upsert(ScholarshipsCompanion entry) =>
      into(db.scholarships).insertOnConflictUpdate(entry);

  Future<LocalScholarship?> getById(String id, String tenantId) =>
      (select(db.scholarships)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalScholarship>> listByTenant(String tenantId) =>
      (select(db.scholarships)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalScholarship>> watchByTenant(String tenantId) =>
      (select(db.scholarships)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.scholarships)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.scholarships)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(ScholarshipsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [InvoiceItems])
class InvoiceItemsDao extends DatabaseAccessor<AppDatabase>
    with _$InvoiceItemsDaoMixin {
  InvoiceItemsDao(super.db);

  Future<void> upsert(InvoiceItemsCompanion entry) =>
      into(db.invoiceItems).insertOnConflictUpdate(entry);

  Future<LocalInvoiceItem?> getById(String id, String tenantId) =>
      (select(db.invoiceItems)
            ..where((t) =>
                t.id.equals(id) &
                t.tenantId.equals(tenantId) &
                t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<LocalInvoiceItem>> listByTenant(String tenantId) =>
      (select(db.invoiceItems)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();

  Stream<List<LocalInvoiceItem>> watchByTenant(String tenantId) =>
      (select(db.invoiceItems)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.updatedAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Future<void> markClean(String id, String tenantId) => transaction(() async {
        final row = await (select(db.invoiceItems)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.invoiceItems)
              ..where(
                  (t) => t.id.equals(id) & t.tenantId.equals(tenantId)))
            .write(InvoiceItemsCompanion(serverRevision: Value(row.revision)));
      });
}

@DriftAccessor(tables: [PendingUploads])
class PendingUploadsDao extends DatabaseAccessor<AppDatabase>
    with _$PendingUploadsDaoMixin {
  PendingUploadsDao(super.db);

  Future<void> upsert(PendingUploadsCompanion entry) =>
      into(db.pendingUploads).insertOnConflictUpdate(entry);

  Future<LocalPendingUpload?> getById(String id, String tenantId) =>
      (select(db.pendingUploads)
            ..where((t) =>
                t.id.equals(id) & t.tenantId.equals(tenantId)))
          .getSingleOrNull();

  /// Atomically claims this tenant's pending uploads, oldest first,
  /// flipping them to `uploading` so concurrent workers never double-send.
  Future<List<LocalPendingUpload>> claimPending(String tenantId,
      {int limit = 10}) {
    return transaction(() async {
      final rows = await (select(db.pendingUploads)
            ..where((t) =>
                t.tenantId.equals(tenantId) & t.status.equals('pending'))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
            ..limit(limit))
          .get();
      for (final row in rows) {
        await (update(db.pendingUploads)
              ..where((t) => t.id.equals(row.id)))
            .write(
                const PendingUploadsCompanion(status: Value('uploading')));
      }
      return rows;
    });
  }

  Future<void> markDone(String id) async {
    await (update(db.pendingUploads)..where((t) => t.id.equals(id)))
        .write(const PendingUploadsCompanion(
      status: Value('done'),
      error: Value(null),
    ));
  }

  Future<void> markFailed(String id, String error) =>
      transaction(() async {
        final row = await (select(db.pendingUploads)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (row == null) return;
        await (update(db.pendingUploads)..where((t) => t.id.equals(id)))
            .write(PendingUploadsCompanion(
          status: const Value('failed'),
          retryCount: Value(row.retryCount + 1),
          error: Value(error),
        ));
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
    Staffs,
    DarjaSections,
    LibraryBooks,
    BookIssues,
    Accounts,
    Transactions,
    IncomeEntries,
    ExpenseEntries,
    Refunds,
    Discounts,
    Scholarships,
    InvoiceItems,
    PendingUploads,
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
    StaffsDao,
    DarjaSectionsDao,
    LibraryBooksDao,
    BookIssuesDao,
    AccountsDao,
    TransactionsDao,
    IncomeEntriesDao,
    ExpenseEntriesDao,
    RefundsDao,
    DiscountsDao,
    ScholarshipsDao,
    InvoiceItemsDao,
    PendingUploadsDao,
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
