/// کتب خانہ فراہم کنندہ
/// Library Provider — LOCAL-FIRST (Phase 5 offline-first sync).
///
/// `load()` stays REMOTE (Supabase reads). All writes (addBook /
/// issueBook / returnBook / deleteBook) go to the local Drift envelope
/// tables (`library_books`, `book_issues`) + a `sync_queue` row in the
/// SAME transaction via [SyncEngine.writeLocalRow] /
/// [SyncEngine.softDeleteLocalRow] + [SyncQueue.enqueue], then
/// opportunistically trigger [SyncEngine.syncNow]. The sync engine is
/// the only writer to the server (via the `sync_apply` RPC).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_providers.dart';
import '../data/models/library.dart';

class LibraryState {
  final List<LibraryBook> books;
  final List<BookIssue> issues;
  final bool isLoading;
  final String? error;
  const LibraryState({
    this.books = const [], this.issues = const [],
    this.isLoading = false, this.error,
  });
  LibraryState copyWith({
    List<LibraryBook>? books, List<BookIssue>? issues,
    bool? isLoading, String? error, bool clearError = false,
  }) => LibraryState(
    books: books ?? this.books, issues: issues ?? this.issues,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  LibraryNotifier(this._ref) : super(const LibraryState());
  final Ref _ref;
  final _c = SupabaseService.client;

  /// [madrasaId] is DEPRECATED (kept for signature compatibility; Phase 8
  /// removes it). Tenant scoping is mandatory via [currentTenantIdProvider].
  Future<void> load({String? madrasaId}) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = state.copyWith(isLoading: false, books: const [], issues: const []);
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final bq = _c.from('library_books').select().eq('tenant_id', tenantId) as dynamic;
      final brows = await bq.order('title');

      final iq = _c.from('book_issues').select().eq('tenant_id', tenantId) as dynamic;
      final irows = await iq.order('issued_at', ascending: false);

      state = state.copyWith(
        isLoading: false,
        books:  brows.map<LibraryBook>((r) => LibraryBook.fromJson(r)).toList(),
        issues: irows.map<BookIssue>((r) => BookIssue.fromJson(r)).toList(),
      );
    } catch (_) { state = state.copyWith(isLoading: false); }
  }

  Future<String?> addBook(LibraryBook b) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final id = b.id ?? const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final data = {...b.toJson(), 'id': id, 'tenant_id': tenantId};
      final exists =
          await SyncQueue.rowExists(db, 'library_books', tenantId, id);
      final baseRev = exists
          ? await SyncQueue.currentRevision(
              db, 'library_books', tenantId, id)
          : 0;

      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'library_books',
          id: id,
          tenantId: tenantId,
          indexed: {'title': b.title},
          data: data,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'library_books',
          entityId: id,
          operation: exists ? 'update' : 'create',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
        isLoading: false,
        books: [...state.books, LibraryBook.fromJson(data)],
      );
      return null;
    } catch (e) {
      // Local write is the source of truth — only reach here on a
      // genuine local failure.
      state = state.copyWith(isLoading: false, error: e.toString());
      return e.toString();
    }
  }

  /// Issues a book: ONE transaction doing TWO local writes — the
  /// `book_issues` insert + its queue row, AND the `library_books`
  /// update (available_copies − 1, current value read from state) +
  /// its queue row — then state updates from the local models.
  Future<String?> issueBook(BookIssue issue) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final issueId = issue.id ?? const Uuid().v4();
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final issueData = {
        ...issue.toJson(),
        'id': issueId,
        'tenant_id': tenantId,
      };
      final issueBaseRev = await SyncQueue.currentRevision(
          db, 'book_issues', tenantId, issueId);

      // Current available count comes from state (remote-loaded list).
      final book = state.books.firstWhere((b) => b.id == issue.bookId);
      final bookId = book.id!;
      final newAvailable = book.availableCopies - 1;
      final bookData = {
        ...book.toJson(),
        'id': bookId,
        'tenant_id': tenantId,
        'available_copies': newAvailable,
      };
      final bookBaseRev = await SyncQueue.currentRevision(
          db, 'library_books', tenantId, bookId);

      await db.transaction(() async {
        // 1) the issue record + its queue row
        await SyncEngine.writeLocalRow(
          db,
          table: 'book_issues',
          id: issueId,
          tenantId: tenantId,
          indexed: {'book_id': issue.bookId},
          data: issueData,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'book_issues',
          entityId: issueId,
          operation: 'create',
          payload: {...issueData, 'updated_at': nowIso},
          baseRevision: issueBaseRev,
        );

        // 2) the book's decremented available_copies + its queue row
        await SyncEngine.writeLocalRow(
          db,
          table: 'library_books',
          id: bookId,
          tenantId: tenantId,
          indexed: {'title': book.title},
          data: bookData,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'library_books',
          entityId: bookId,
          operation: 'update',
          payload: {...bookData, 'updated_at': nowIso},
          baseRevision: bookBaseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
        isLoading: false,
        issues: [BookIssue.fromJson(issueData), ...state.issues],
        books: state.books
            .map((b) => b.id == bookId ? LibraryBook.fromJson(bookData) : b)
            .toList(),
      );
      return null;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return e.toString();
    }
  }

  Future<String?> returnBook(String issueId, {double? fine}) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final existing =
          state.issues.firstWhere((i) => i.id == issueId);
      final data = {
        ...existing.toJson(),
        'id': issueId,
        'tenant_id': tenantId,
        'is_returned': true,
        'returned_at': nowIso,
        if (fine != null) 'fine': fine,
      };
      final baseRev = await SyncQueue.currentRevision(
          db, 'book_issues', tenantId, issueId);

      await db.transaction(() async {
        await SyncEngine.writeLocalRow(
          db,
          table: 'book_issues',
          id: issueId,
          tenantId: tenantId,
          indexed: {'book_id': existing.bookId},
          data: data,
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'book_issues',
          entityId: issueId,
          operation: 'update',
          payload: {...data, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
        issues: state.issues
            .map((i) => i.id == issueId ? BookIssue.fromJson(data) : i)
            .toList(),
      );
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<void> deleteBook(String id) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = state.copyWith(error: 'No active tenant');
      return;
    }
    try {
      final db = _ref.read(appDatabaseProvider);
      final engine = _ref.read(syncEngineProvider);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final baseRev = await SyncQueue.currentRevision(
          db, 'library_books', tenantId, id);

      await db.transaction(() async {
        await SyncEngine.softDeleteLocalRow(
          db,
          table: 'library_books',
          id: id,
          tenantId: tenantId,
          dataPatch: {'is_active': false},
        );

        await SyncQueue.enqueue(
          db,
          tenantId: tenantId,
          entity: 'library_books',
          entityId: id,
          operation: 'delete',
          payload: {'id': id, 'tenant_id': tenantId, 'updated_at': nowIso},
          baseRevision: baseRev,
        );
      });

      engine?.notifyLocalChange();
      unawaited(engine?.syncNow() ?? Future.value());

      state = state.copyWith(
          books: state.books.where((b) => b.id != id).toList());
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  List<BookIssue> get activeIssues =>
      state.issues.where((i) => !i.isReturned).toList();
  List<BookIssue> get overdueIssues =>
      state.issues.where((i) => i.isOverdue).toList();
}

final libraryProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>((ref) => LibraryNotifier(ref));
