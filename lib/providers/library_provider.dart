/// کتب خانہ فراہم کنندہ
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/supabase_service.dart';
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
  LibraryNotifier() : super(const LibraryState());
  final _c = SupabaseService.client;

  Future<void> load({String? madrasaId}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var bq = _c.from('library_books').select();
      if (madrasaId != null) bq = bq.eq('madrasa_id', madrasaId) as dynamic;
      final brows = await bq.order('title');

      var iq = _c.from('book_issues').select();
      if (madrasaId != null) iq = iq.eq('madrasa_id', madrasaId) as dynamic;
      final irows = await iq.order('issued_at', ascending: false);

      state = state.copyWith(
        isLoading: false,
        books:  brows.map<LibraryBook>((r) => LibraryBook.fromJson(r)).toList(),
        issues: irows.map<BookIssue>((r) => BookIssue.fromJson(r)).toList(),
      );
    } catch (_) { state = state.copyWith(isLoading: false); }
  }

  Future<String?> addBook(LibraryBook b) async {
    try {
      final data = await _c.from('library_books').insert(b.toJson()).select().single();
      state = state.copyWith(books: [...state.books, LibraryBook.fromJson(data)]);
      return null;
    } catch (_) {
      final opt = LibraryBook(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        madrasaId: b.madrasaId, title: b.title, author: b.author,
        subject: b.subject, totalCopies: b.totalCopies,
        availableCopies: b.totalCopies,
      );
      state = state.copyWith(books: [...state.books, opt]);
      return null;
    }
  }

  Future<String?> issueBook(BookIssue issue) async {
    try {
      final data = await _c.from('book_issues').insert(issue.toJson()).select().single();
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
                id: i.id, madrasaId: i.madrasaId, bookId: i.bookId,
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
    StateNotifierProvider<LibraryNotifier, LibraryState>((_) => LibraryNotifier());
