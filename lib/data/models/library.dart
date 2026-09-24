/// کتب خانہ ماڈل
/// LibraryBook and BookIssue

enum BookStatus { available, issued, lost }

class LibraryBook {
  final String? id;
  final String? madrasaId;
  final String title;
  final String? author;
  final String? subject;
  final String? isbn;
  final int totalCopies;
  final int availableCopies;
  final BookStatus status;
  final DateTime? addedAt;

  const LibraryBook({
    this.id,
    this.madrasaId,
    required this.title,
    this.author,
    this.subject,
    this.isbn,
    this.totalCopies = 1,
    this.availableCopies = 1,
    this.status = BookStatus.available,
    this.addedAt,
  });

  factory LibraryBook.fromJson(Map<String, dynamic> j) => LibraryBook(
        id:               j['id'] as String?,
        madrasaId:        j['madrasa_id'] as String?,
        title:            j['title'] as String? ?? '',
        author:           j['author'] as String?,
        subject:          j['subject'] as String?,
        isbn:             j['isbn'] as String?,
        totalCopies:      j['total_copies'] as int? ?? 1,
        availableCopies:  j['available_copies'] as int? ?? 1,
        status:           BookStatus.values.firstWhere(
            (s) => s.name == (j['status'] as String? ?? 'available'),
            orElse: () => BookStatus.available),
        addedAt:          j['added_at'] != null
            ? DateTime.tryParse(j['added_at'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'madrasa_id':       madrasaId,
        'title':            title,
        'author':           author,
        'subject':          subject,
        'isbn':             isbn,
        'total_copies':     totalCopies,
        'available_copies': availableCopies,
        'status':           status.name,
      };
}

class BookIssue {
  final String? id;
  final String? madrasaId;
  final String bookId;
  final String bookTitle;
  final String borrowerId;   // student or staff id
  final String borrowerName;
  final String borrowerType; // 'student' | 'staff'
  final DateTime issuedAt;
  final DateTime dueAt;
  final DateTime? returnedAt;
  final double? fine;
  final bool isReturned;

  const BookIssue({
    this.id,
    this.madrasaId,
    required this.bookId,
    required this.bookTitle,
    required this.borrowerId,
    required this.borrowerName,
    required this.borrowerType,
    required this.issuedAt,
    required this.dueAt,
    this.returnedAt,
    this.fine,
    this.isReturned = false,
  });

  factory BookIssue.fromJson(Map<String, dynamic> j) => BookIssue(
        id:           j['id'] as String?,
        madrasaId:    j['madrasa_id'] as String?,
        bookId:       j['book_id'] as String,
        bookTitle:    j['book_title'] as String? ?? '',
        borrowerId:   j['borrower_id'] as String,
        borrowerName: j['borrower_name'] as String? ?? '',
        borrowerType: j['borrower_type'] as String? ?? 'student',
        issuedAt:     DateTime.parse(j['issued_at'] as String),
        dueAt:        DateTime.parse(j['due_at'] as String),
        returnedAt:   j['returned_at'] != null
            ? DateTime.tryParse(j['returned_at'] as String) : null,
        fine:         (j['fine'] as num?)?.toDouble(),
        isReturned:   j['is_returned'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'madrasa_id':   madrasaId,
        'book_id':      bookId,
        'book_title':   bookTitle,
        'borrower_id':  borrowerId,
        'borrower_name': borrowerName,
        'borrower_type': borrowerType,
        'issued_at':    issuedAt.toIso8601String(),
        'due_at':       dueAt.toIso8601String(),
        'returned_at':  returnedAt?.toIso8601String(),
        'fine':         fine,
        'is_returned':  isReturned,
      };

  bool get isOverdue =>
      !isReturned && DateTime.now().isAfter(dueAt);
}
