/// مالیاتی ماڈل
/// Finance — donations, expenses, salary payments

enum TransactionType { donation, zakat, sadqa, expense, salary, fee }

extension TransactionTypeX on TransactionType {
  String get urduLabel {
    switch (this) {
      case TransactionType.donation: return 'عطیہ';
      case TransactionType.zakat:    return 'زکوٰۃ';
      case TransactionType.sadqa:    return 'صدقہ';
      case TransactionType.expense:  return 'اخراجات';
      case TransactionType.salary:   return 'تنخواہ';
      case TransactionType.fee:      return 'فیس';
    }
  }

  bool get isIncome =>
      this == TransactionType.donation ||
      this == TransactionType.zakat ||
      this == TransactionType.sadqa ||
      this == TransactionType.fee;
}

class FinanceTransaction {
  final String? id;
  final String? madrasaId;
  final TransactionType type;
  final double amount;
  final String? description;
  final String? personName;   // donor / recipient
  final String? referenceId;  // staffId for salary, studentId for fee
  final DateTime date;
  final String? receiptNumber;
  final String? createdByUserId;

  const FinanceTransaction({
    this.id,
    this.madrasaId,
    required this.type,
    required this.amount,
    this.description,
    this.personName,
    this.referenceId,
    required this.date,
    this.receiptNumber,
    this.createdByUserId,
  });

  factory FinanceTransaction.fromJson(Map<String, dynamic> j) =>
      FinanceTransaction(
        id:                j['id'] as String?,
        madrasaId:         j['madrasa_id'] as String?,
        type:              TransactionType.values.firstWhere(
            (t) => t.name == (j['type'] as String? ?? 'expense'),
            orElse: () => TransactionType.expense),
        amount:            (j['amount'] as num).toDouble(),
        description:       j['description'] as String?,
        personName:        j['person_name'] as String?,
        referenceId:       j['reference_id'] as String?,
        date:              DateTime.parse(j['date'] as String),
        receiptNumber:     j['receipt_number'] as String?,
        createdByUserId:   j['created_by_user_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'madrasa_id':           madrasaId,
        'type':                 type.name,
        'amount':               amount,
        'description':          description,
        'person_name':          personName,
        'reference_id':         referenceId,
        'date':                 date.toIso8601String(),
        'receipt_number':       receiptNumber,
        'created_by_user_id':   createdByUserId,
      };
}
