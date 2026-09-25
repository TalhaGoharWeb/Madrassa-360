/// کتب خانہ فراہم کنندہ
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/supabase_service.dart';
import '../core/services/tenant_context.dart';
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
    try {
      final payload = <String, dynamic>{...b.toJson(), 'tenant_id': tenantId};
      final data = await _c.from('library_books').insert(payload).select().single();
      state = state.copyWith(books: [...state.books, LibraryBook.fromJson(data)]);
      return null;
    } catch (_) {
      final opt = LibraryBook(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tenantId: tenantId, madrasaId: b.madrasaId, title: b.title, author: b.author,
        subject: b.subject, totalCopies: b.totalCopies,
        availableCopies: b.totalCopies,
      );
      state = state.copyWith(books: [...state.books, opt]);
      return null;
    }
  }

  Future<String?> issueBook(BookIssue issue) async {
    final tenantId = _ref.read(currentTenantIdProvider);
    if (tenantId == null) return 'No active tenant';
    try {
      final payload = <String, dynamic>{...issue.toJson(), 'tenant_id': tenantId};
      final data = await _c.from('book_issues').insert(payload).select().single();
      state = state.copyWith(issues: [BookIssue.fromJson(data), ...state.issues]);
      // Decrease available copies
      final book = state.books.firstWhere((b) => b.id == issue.bookId);
      await _c.from('library_books').update({
        'available_copies': book.availableCopies - 1
      }).eq('id', book.id!);
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<String?> returnBook(String issueId, {double? fine}) async {
    try {
      await _c.from('book_issues').update({
        'is_returned': true,
        'returned_at': DateTime.now().toIso8601String(),
        if (fine != null) 'fine': fine,
      }).eq('id', issueId);
      state = state.copyWith(
        issues: state.issues.map((i) => i.id == issueId
            ? BookIssue(
                id: i.id, tenantId: i.tenantId, madrasaId: i.madrasaId, bookId: i.bookId,
                bookTitle: i.bookTitle, borrowerId: i.borrowerId,
                borrowerName: i.borrowerName, borrowerType: i.borrowerType,
                issuedAt: i.issuedAt, dueAt: i.dueAt,
                returnedAt: DateTime.now(), fine: fine, isReturned: true,
              )
            : i).toList(),
      );
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<void> deleteBook(String id) async {
    try { await _c.from('library_books').delete().eq('id', id); } catch (_) {}
    state = state.copyWith(books: state.books.where((b) => b.id != id).toList());
  }

  List<BookIssue> get activeIssues =>
      state.issues.where((i) => !i.isReturned).toList();
  List<BookIssue> get overdueIssues =>
      state.issues.where((i) => i.isOverdue).toList();
}

final libraryProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>((ref) => LibraryNotifier(ref));
