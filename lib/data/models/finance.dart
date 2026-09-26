/// مالیاتی ماڈلز — Phase 4 finance rebuild (014_finance.sql)
/// Invoice → payment → receipt → ledger flow against the new tables.
/// Legacy `FinanceTransaction`/`TransactionType` (flat finance_transactions
/// log) are replaced: new writes go to invoices/payments/income/expenses
/// and the canonical `transactions` ledger.

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String);
String? _s(dynamic v) => v as String?;

/// Drop null values so DB defaults (sequences, timestamps) apply on insert.
Map<String, dynamic> _clean(Map<String, dynamic> m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

// ─────────────────────────────────────────────
// Enums (dbValue matches the SQL CHECK constraints)
// ─────────────────────────────────────────────

enum LedgerKind {
  income,
  expense,
  transfer;

  static LedgerKind fromDb(String? v) => LedgerKind.values
      .firstWhere((e) => e.name == v, orElse: () => LedgerKind.expense);
}

extension LedgerKindX on LedgerKind {
  String get dbValue => name;
  String get urduLabel {
    switch (this) {
      case LedgerKind.income:
        return 'آمدن';
      case LedgerKind.expense:
        return 'اخراجات';
      case LedgerKind.transfer:
        return 'منتقلی';
    }
  }

  bool get isIncome => this == LedgerKind.income;
}

enum TransactionCategory {
  donation,
  zakat,
  sadqa,
  salary,
  fee,
  refund,
  other,
  ;

  static TransactionCategory fromDb(String? v) => TransactionCategory.values
      .firstWhere((e) => e.name == v, orElse: () => TransactionCategory.other);
}

extension TransactionCategoryX on TransactionCategory {
  String get dbValue => name;
  String get urduLabel {
    switch (this) {
      case TransactionCategory.donation:
        return 'عطیہ';
      case TransactionCategory.zakat:
        return 'زکوٰۃ';
      case TransactionCategory.sadqa:
        return 'صدقہ';
      case TransactionCategory.salary:
        return 'تنخواہ';
      case TransactionCategory.fee:
        return 'فیس';
      case TransactionCategory.refund:
        return 'واپسی';
      case TransactionCategory.other:
        return 'دیگر';
    }
  }
}

enum PaymentMethod {
  cash,
  bankTransfer,
  jazzcash,
  easypaisa,
  cheque,
  other;

  static PaymentMethod fromDb(String? v) {
    switch (v) {
      case 'cash':
        return PaymentMethod.cash;
      case 'bank_transfer':
        return PaymentMethod.bankTransfer;
      case 'jazzcash':
        return PaymentMethod.jazzcash;
      case 'easypaisa':
        return PaymentMethod.easypaisa;
      case 'cheque':
        return PaymentMethod.cheque;
      default:
        return PaymentMethod.other;
    }
  }
}

extension PaymentMethodX on PaymentMethod {
  String get dbValue {
    switch (this) {
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
      default:
        return name;
    }
  }

  String get urduLabel {
    switch (this) {
      case PaymentMethod.cash:
        return 'نقد';
      case PaymentMethod.bankTransfer:
        return 'بینک ٹرانسفر';
      case PaymentMethod.jazzcash:
        return 'جاز کیش';
      case PaymentMethod.easypaisa:
        return 'ایزی پیسہ';
      case PaymentMethod.cheque:
        return 'چیک';
      case PaymentMethod.other:
        return 'دیگر';
    }
  }
}

/// Lifecycle of a financial document. Posted/void rows are IMMUTABLE
/// (DB-enforced); corrections happen via reversal entries.
enum DocStatus {
  draft,
  approved,
  posted,
  voided;

  static DocStatus fromDb(String? v) => DocStatus.values
      .firstWhere((e) => e.dbValue == v, orElse: () => DocStatus.draft);
}

extension DocStatusX on DocStatus {
  String get dbValue => this == DocStatus.voided ? 'void' : name;
  String get urduLabel {
    switch (this) {
      case DocStatus.draft:
        return 'مسودہ';
      case DocStatus.approved:
        return 'منظور شدہ';
      case DocStatus.posted:
        return 'حتمی';
      case DocStatus.voided:
        return 'منسوخ';
    }
  }

  bool get isFinal => this == DocStatus.posted || this == DocStatus.voided;
}

enum InvoiceStatus {
  draft,
  issued,
  partiallyPaid,
  paid,
  overdue,
  cancelled,
  voided,
  ;

  static InvoiceStatus fromDb(String? v) {
    switch (v) {
      case 'partially_paid':
        return InvoiceStatus.partiallyPaid;
      case 'draft':
        return InvoiceStatus.draft;
      case 'issued':
        return InvoiceStatus.issued;
      case 'paid':
        return InvoiceStatus.paid;
      case 'overdue':
        return InvoiceStatus.overdue;
      case 'cancelled':
        return InvoiceStatus.cancelled;
      case 'void':
        return InvoiceStatus.voided;
      default:
        return InvoiceStatus.draft;
    }
  }
}

extension InvoiceStatusX on InvoiceStatus {
  String get dbValue {
    switch (this) {
      case InvoiceStatus.partiallyPaid:
        return 'partially_paid';
      case InvoiceStatus.voided:
        return 'void';
      default:
        return name;
    }
  }

  String get urduLabel {
    switch (this) {
      case InvoiceStatus.draft:
        return 'مسودہ';
      case InvoiceStatus.issued:
        return 'جاری';
      case InvoiceStatus.partiallyPaid:
        return 'جزوی ادا';
      case InvoiceStatus.paid:
        return 'ادا شدہ';
      case InvoiceStatus.overdue:
        return 'واجب الادا';
      case InvoiceStatus.cancelled:
        return 'منسوخ';
      case InvoiceStatus.voided:
        return 'کالعدم';
    }
  }

  bool get isFinal =>
      this == InvoiceStatus.paid ||
      this == InvoiceStatus.cancelled ||
      this == InvoiceStatus.voided;
}

enum DiscountKind {
  percentage,
  fixed;

  static DiscountKind fromDb(String? v) => DiscountKind.values
      .firstWhere((e) => e.name == v, orElse: () => DiscountKind.fixed);
}

extension DiscountKindX on DiscountKind {
  String get dbValue => name;
  String get urduLabel =>
      this == DiscountKind.percentage ? 'فیصد' : 'مقررہ رقم';
}

enum DiscountStatus {
  draft,
  applied,
  voided;

  static DiscountStatus fromDb(String? v) => DiscountStatus.values
      .firstWhere((e) => e.name == v, orElse: () => DiscountStatus.draft);
}

extension DiscountStatusX on DiscountStatus {
  String get dbValue => this == DiscountStatus.voided ? 'void' : name;
}

enum ScholarshipStatus {
  active,
  expired,
  revoked;

  static ScholarshipStatus fromDb(String? v) => ScholarshipStatus.values
      .firstWhere((e) => e.name == v, orElse: () => ScholarshipStatus.active);
}

extension ScholarshipStatusX on ScholarshipStatus {
  String get dbValue => name;
  String get urduLabel {
    switch (this) {
      case ScholarshipStatus.active:
        return 'فعال';
      case ScholarshipStatus.expired:
        return 'ختم شدہ';
      case ScholarshipStatus.revoked:
        return 'واپس شدہ';
    }
  }
}

enum AccountType {
  asset,
  liability,
  equity,
  income,
  expense;

  static AccountType fromDb(String? v) => AccountType.values
      .firstWhere((e) => e.name == v, orElse: () => AccountType.asset);
}

extension AccountTypeX on AccountType {
  String get dbValue => name;
  String get urduLabel {
    switch (this) {
      case AccountType.asset:
        return 'اثاثہ';
      case AccountType.liability:
        return 'ذمہ داری';
      case AccountType.equity:
        return 'سرمایہ';
      case AccountType.income:
        return 'آمدن';
      case AccountType.expense:
        return 'اخراجات';
    }
  }
}

enum FeeFrequency {
  monthly,
  quarterly,
  annual,
  oneTime;

  static FeeFrequency fromDb(String? v) {
    switch (v) {
      case 'monthly':
        return FeeFrequency.monthly;
      case 'quarterly':
        return FeeFrequency.quarterly;
      case 'annual':
        return FeeFrequency.annual;
      default:
        return FeeFrequency.oneTime;
    }
  }
}

extension FeeFrequencyX on FeeFrequency {
  String get dbValue => this == FeeFrequency.oneTime ? 'one_time' : name;
  String get urduLabel {
    switch (this) {
      case FeeFrequency.monthly:
        return 'ماہانہ';
      case FeeFrequency.quarterly:
        return 'سہ ماہی';
      case FeeFrequency.annual:
        return 'سالانہ';
      case FeeFrequency.oneTime:
        return 'یک مشت';
    }
  }
}

// ─────────────────────────────────────────────
// Account (chart of accounts)
// ─────────────────────────────────────────────

class Account {
  final String? id;
  final String tenantId;
  final String code;
  final String name;
  final String? nameUrdu;
  final AccountType accountType;
  final String? parentId;
  final bool isActive;
  final double openingBalance;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Account({
    this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    this.nameUrdu,
    this.accountType = AccountType.asset,
    this.parentId,
    this.isActive = true,
    this.openingBalance = 0,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        code: (_s(j['code']) ?? ''),
        name: (_s(j['name']) ?? ''),
        nameUrdu: _s(j['name_urdu']),
        accountType: AccountType.fromDb(_s(j['account_type'])),
        parentId: _s(j['parent_id']),
        isActive: (j['is_active'] as bool?) ?? true,
        openingBalance: _d(j['opening_balance']),
        createdBy: _s(j['created_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'code': code,
        'name': name,
        'name_urdu': nameUrdu,
        'account_type': accountType.dbValue,
        'parent_id': parentId,
        'is_active': isActive,
        'opening_balance': openingBalance,
        'created_by': createdBy,
        'updated_by': updatedBy,
      });
}

// ─────────────────────────────────────────────
// LedgerTransaction (canonical ledger: public.transactions)
// ─────────────────────────────────────────────

class LedgerTransaction {
  final String? id;
  final String tenantId;
  final DateTime entryDate;
  final LedgerKind kind;
  final TransactionCategory category;
  final double amount;
  final String? accountId;
  final String? description;
  final String? referenceType;
  final String? referenceId;
  final DocStatus status;
  final DateTime? postedAt;
  final String? createdBy;
  final String? approvedBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LedgerTransaction({
    this.id,
    required this.tenantId,
    required this.entryDate,
    required this.kind,
    this.category = TransactionCategory.other,
    required this.amount,
    this.accountId,
    this.description,
    this.referenceType,
    this.referenceId,
    this.status = DocStatus.draft,
    this.postedAt,
    this.createdBy,
    this.approvedBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  bool get isIncome => kind.isIncome;

  factory LedgerTransaction.fromJson(Map<String, dynamic> j) =>
      LedgerTransaction(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        entryDate: _dt(j['entry_date']) ?? DateTime.now(),
        kind: LedgerKind.fromDb(_s(j['kind'])),
        category: TransactionCategory.fromDb(_s(j['category'])),
        amount: _d(j['amount']),
        accountId: _s(j['account_id']),
        description: _s(j['description']),
        referenceType: _s(j['reference_type']),
        referenceId: _s(j['reference_id']),
        status: DocStatus.fromDb(_s(j['status'])),
        postedAt: _dt(j['posted_at']),
        createdBy: _s(j['created_by']),
        approvedBy: _s(j['approved_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'entry_date': entryDate.toIso8601String().substring(0, 10),
        'kind': kind.dbValue,
        'category': category.dbValue,
        'amount': amount,
        'account_id': accountId,
        'description': description,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'status': status.dbValue,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'updated_by': updatedBy,
      });
}

// ─────────────────────────────────────────────
// IncomeEntry / ExpenseEntry
// ─────────────────────────────────────────────

class IncomeEntry {
  final String? id;
  final String tenantId;
  final TransactionCategory sourceType;
  final String? donorName;
  final double amount;
  final String? accountId;
  final DateTime receivedDate;
  final String? receiptNumber;
  final String? description;
  final DocStatus status;
  final DateTime? postedAt;
  final String? createdBy;
  final String? approvedBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const IncomeEntry({
    this.id,
    required this.tenantId,
    this.sourceType = TransactionCategory.donation,
    this.donorName,
    required this.amount,
    this.accountId,
    required this.receivedDate,
    this.receiptNumber,
    this.description,
    this.status = DocStatus.draft,
    this.postedAt,
    this.createdBy,
    this.approvedBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory IncomeEntry.fromJson(Map<String, dynamic> j) => IncomeEntry(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        sourceType: TransactionCategory.fromDb(_s(j['source_type'])),
        donorName: _s(j['donor_name']),
        amount: _d(j['amount']),
        accountId: _s(j['account_id']),
        receivedDate: _dt(j['received_date']) ?? DateTime.now(),
        receiptNumber: _s(j['receipt_number']),
        description: _s(j['description']),
        status: DocStatus.fromDb(_s(j['status'])),
        postedAt: _dt(j['posted_at']),
        createdBy: _s(j['created_by']),
        approvedBy: _s(j['approved_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'source_type': sourceType.dbValue,
        'donor_name': donorName,
        'amount': amount,
        'account_id': accountId,
        'received_date': receivedDate.toIso8601String().substring(0, 10),
        'receipt_number': receiptNumber,
        'description': description,
        'status': status.dbValue,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'updated_by': updatedBy,
      });
}

class ExpenseEntry {
  final String? id;
  final String tenantId;
  final String category;
  final String? recipient;
  final double amount;
  final String? accountId;
  final DateTime expenseDate;
  final String? receiptUrl;
  final String? description;
  final DocStatus status;
  final DateTime? postedAt;
  final String? createdBy;
  final String? approvedBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExpenseEntry({
    this.id,
    required this.tenantId,
    required this.category,
    this.recipient,
    required this.amount,
    this.accountId,
    required this.expenseDate,
    this.receiptUrl,
    this.description,
    this.status = DocStatus.draft,
    this.postedAt,
    this.createdBy,
    this.approvedBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory ExpenseEntry.fromJson(Map<String, dynamic> j) => ExpenseEntry(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        category: (_s(j['category']) ?? ''),
        recipient: _s(j['recipient']),
        amount: _d(j['amount']),
        accountId: _s(j['account_id']),
        expenseDate: _dt(j['expense_date']) ?? DateTime.now(),
        receiptUrl: _s(j['receipt_url']),
        description: _s(j['description']),
        status: DocStatus.fromDb(_s(j['status'])),
        postedAt: _dt(j['posted_at']),
        createdBy: _s(j['created_by']),
        approvedBy: _s(j['approved_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'category': category,
        'recipient': recipient,
        'amount': amount,
        'account_id': accountId,
        'expense_date': expenseDate.toIso8601String().substring(0, 10),
        'receipt_url': receiptUrl,
        'description': description,
        'status': status.dbValue,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'updated_by': updatedBy,
      });
}

// ─────────────────────────────────────────────
// FeeStructure / FeeItem
// ─────────────────────────────────────────────

class FeeStructure {
  final String? id;
  final String tenantId;
  final String name;
  final String? nameUrdu;
  final String? darjaId;
  final String academicYear;
  final bool isActive;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FeeStructure({
    this.id,
    required this.tenantId,
    required this.name,
    this.nameUrdu,
    this.darjaId,
    required this.academicYear,
    this.isActive = true,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory FeeStructure.fromJson(Map<String, dynamic> j) => FeeStructure(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        name: (_s(j['name']) ?? ''),
        nameUrdu: _s(j['name_urdu']),
        darjaId: _s(j['darja_id']),
        academicYear: (_s(j['academic_year']) ?? ''),
        isActive: (j['is_active'] as bool?) ?? true,
        createdBy: _s(j['created_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'name_urdu': nameUrdu,
        'darja_id': darjaId,
        'academic_year': academicYear,
        'is_active': isActive,
        'created_by': createdBy,
        'updated_by': updatedBy,
      });
}

class FeeItem {
  final String? id;
  final String tenantId;
  final String feeStructureId;
  final String name;
  final String? nameUrdu;
  final double amount;
  final FeeFrequency frequency;
  final bool isActive;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FeeItem({
    this.id,
    required this.tenantId,
    required this.feeStructureId,
    required this.name,
    this.nameUrdu,
    required this.amount,
    this.frequency = FeeFrequency.monthly,
    this.isActive = true,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory FeeItem.fromJson(Map<String, dynamic> j) => FeeItem(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        feeStructureId: (_s(j['fee_structure_id']) ?? ''),
        name: (_s(j['name']) ?? ''),
        nameUrdu: _s(j['name_urdu']),
        amount: _d(j['amount']),
        frequency: FeeFrequency.fromDb(_s(j['frequency'])),
        isActive: (j['is_active'] as bool?) ?? true,
        createdBy: _s(j['created_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'fee_structure_id': feeStructureId,
        'name': name,
        'name_urdu': nameUrdu,
        'amount': amount,
        'frequency': frequency.dbValue,
        'is_active': isActive,
        'created_by': createdBy,
        'updated_by': updatedBy,
      });
}

// ─────────────────────────────────────────────
// Invoice / InvoiceItem
// ─────────────────────────────────────────────

class Invoice {
  final String? id;
  final String tenantId;
  final String studentId;
  final String? studentName; // joined
  final String? feeStructureId;
  final String? invoiceNumber;
  final String? billingMonth;
  final DateTime issueDate;
  final DateTime dueDate;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final double amountPaid;
  final double balanceDue;
  final InvoiceStatus status;
  final String? reversedById;
  final String? notes;
  final String? createdBy;
  final String? approvedBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Invoice({
    this.id,
    required this.tenantId,
    required this.studentId,
    this.studentName,
    this.feeStructureId,
    this.invoiceNumber,
    this.billingMonth,
    required this.issueDate,
    required this.dueDate,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.total = 0,
    this.amountPaid = 0,
    this.balanceDue = 0,
    this.status = InvoiceStatus.draft,
    this.reversedById,
    this.notes,
    this.createdBy,
    this.approvedBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final student = j['students'] as Map<String, dynamic>?;
    return Invoice(
      id: _s(j['id']),
      tenantId: (_s(j['tenant_id']) ?? ''),
      studentId: (_s(j['student_id']) ?? ''),
      studentName:
          student != null ? _s(student['name']) : _s(j['student_name']),
      feeStructureId: _s(j['fee_structure_id']),
      invoiceNumber: _s(j['invoice_number']),
      billingMonth: _s(j['billing_month']),
      issueDate: _dt(j['issue_date']) ?? DateTime.now(),
      dueDate: _dt(j['due_date']) ?? DateTime.now(),
      subtotal: _d(j['subtotal']),
      discountTotal: _d(j['discount_total']),
      taxTotal: _d(j['tax_total']),
      total: _d(j['total']),
      amountPaid: _d(j['amount_paid']),
      balanceDue: _d(j['balance_due']),
      status: InvoiceStatus.fromDb(_s(j['status'])),
      reversedById: _s(j['reversed_by_id']),
      notes: _s(j['notes']),
      createdBy: _s(j['created_by']),
      approvedBy: _s(j['approved_by']),
      updatedBy: _s(j['updated_by']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'student_id': studentId,
        'fee_structure_id': feeStructureId,
        'invoice_number': invoiceNumber,
        'billing_month': billingMonth,
        'issue_date': issueDate.toIso8601String().substring(0, 10),
        'due_date': dueDate.toIso8601String().substring(0, 10),
        'tax_total': taxTotal,
        'status': status.dbValue,
        'notes': notes,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'updated_by': updatedBy,
      });
}

class InvoiceItem {
  final String? id;
  final String tenantId;
  final String invoiceId;
  final String? feeItemId;
  final String description;
  final double quantity;
  final double unitAmount;
  final double lineTotal;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InvoiceItem({
    this.id,
    required this.tenantId,
    required this.invoiceId,
    this.feeItemId,
    required this.description,
    this.quantity = 1,
    required this.unitAmount,
    this.lineTotal = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        invoiceId: (_s(j['invoice_id']) ?? ''),
        feeItemId: _s(j['fee_item_id']),
        description: (_s(j['description']) ?? ''),
        quantity: _d(j['quantity']),
        unitAmount: _d(j['unit_amount']),
        lineTotal: _d(j['line_total']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'invoice_id': invoiceId,
        'fee_item_id': feeItemId,
        'description': description,
        'quantity': quantity,
        'unit_amount': unitAmount,
      });
}

// ─────────────────────────────────────────────
// Payment / PaymentAllocation
// ─────────────────────────────────────────────

class Payment {
  final String? id;
  final String tenantId;
  final String? studentId;
  final String? studentName; // joined
  final String? invoiceId;
  final String? accountId;
  final double amount;
  final DateTime paymentDate;
  final PaymentMethod method;
  final String? receiptNumber;
  final DocStatus status;
  final DateTime? postedAt;
  final String? notes;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Payment({
    this.id,
    required this.tenantId,
    this.studentId,
    this.studentName,
    this.invoiceId,
    this.accountId,
    required this.amount,
    required this.paymentDate,
    this.method = PaymentMethod.cash,
    this.receiptNumber,
    this.status = DocStatus.draft,
    this.postedAt,
    this.notes,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Payment.fromJson(Map<String, dynamic> j) {
    final student = j['students'] as Map<String, dynamic>?;
    return Payment(
      id: _s(j['id']),
      tenantId: (_s(j['tenant_id']) ?? ''),
      studentId: _s(j['student_id']),
      studentName:
          student != null ? _s(student['name']) : _s(j['student_name']),
      invoiceId: _s(j['invoice_id']),
      accountId: _s(j['account_id']),
      amount: _d(j['amount']),
      paymentDate: _dt(j['payment_date']) ?? DateTime.now(),
      method: PaymentMethod.fromDb(_s(j['method'])),
      receiptNumber: _s(j['receipt_number']),
      status: DocStatus.fromDb(_s(j['status'])),
      postedAt: _dt(j['posted_at']),
      notes: _s(j['notes']),
      createdBy: _s(j['created_by']),
      updatedBy: _s(j['updated_by']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'student_id': studentId,
        'invoice_id': invoiceId,
        'account_id': accountId,
        'amount': amount,
        'payment_date': paymentDate.toIso8601String().substring(0, 10),
        'method': method.dbValue,
        'receipt_number': receiptNumber,
        'status': status.dbValue,
        'notes': notes,
        'created_by': createdBy,
        'updated_by': updatedBy,
      });
}

class PaymentAllocation {
  final String? id;
  final String tenantId;
  final String paymentId;
  final String invoiceId;
  final double amount;
  final DateTime? createdAt;

  const PaymentAllocation({
    this.id,
    required this.tenantId,
    required this.paymentId,
    required this.invoiceId,
    required this.amount,
    this.createdAt,
  });

  factory PaymentAllocation.fromJson(Map<String, dynamic> j) =>
      PaymentAllocation(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        paymentId: (_s(j['payment_id']) ?? ''),
        invoiceId: (_s(j['invoice_id']) ?? ''),
        amount: _d(j['amount']),
        createdAt: _dt(j['created_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'payment_id': paymentId,
        'invoice_id': invoiceId,
        'amount': amount,
      });
}

// ─────────────────────────────────────────────
// Refund / Discount / Scholarship
// ─────────────────────────────────────────────

class Refund {
  final String? id;
  final String tenantId;
  final String paymentId;
  final String? studentId;
  final double amount;
  final String reason;
  final DateTime refundDate;
  final DocStatus status;
  final DateTime? postedAt;
  final String? createdBy;
  final String? approvedBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Refund({
    this.id,
    required this.tenantId,
    required this.paymentId,
    this.studentId,
    required this.amount,
    required this.reason,
    required this.refundDate,
    this.status = DocStatus.draft,
    this.postedAt,
    this.createdBy,
    this.approvedBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Refund.fromJson(Map<String, dynamic> j) => Refund(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        paymentId: (_s(j['payment_id']) ?? ''),
        studentId: _s(j['student_id']),
        amount: _d(j['amount']),
        reason: (_s(j['reason']) ?? ''),
        refundDate: _dt(j['refund_date']) ?? DateTime.now(),
        status: DocStatus.fromDb(_s(j['status'])),
        postedAt: _dt(j['posted_at']),
        createdBy: _s(j['created_by']),
        approvedBy: _s(j['approved_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'payment_id': paymentId,
        'student_id': studentId,
        'amount': amount,
        'reason': reason,
        'refund_date': refundDate.toIso8601String().substring(0, 10),
        'status': status.dbValue,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'updated_by': updatedBy,
      });
}

class Discount {
  final String? id;
  final String tenantId;
  final String? studentId;
  final String? invoiceId;
  final DiscountKind discountType;
  final double value;
  final String? reason;
  final DiscountStatus status;
  final DateTime? appliedAt;
  final String? createdBy;
  final String? approvedBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Discount({
    this.id,
    required this.tenantId,
    this.studentId,
    this.invoiceId,
    this.discountType = DiscountKind.fixed,
    required this.value,
    this.reason,
    this.status = DiscountStatus.draft,
    this.appliedAt,
    this.createdBy,
    this.approvedBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Discount.fromJson(Map<String, dynamic> j) => Discount(
        id: _s(j['id']),
        tenantId: (_s(j['tenant_id']) ?? ''),
        studentId: _s(j['student_id']),
        invoiceId: _s(j['invoice_id']),
        discountType: DiscountKind.fromDb(_s(j['discount_type'])),
        value: _d(j['value']),
        reason: _s(j['reason']),
        status: DiscountStatus.fromDb(_s(j['status'])),
        appliedAt: _dt(j['applied_at']),
        createdBy: _s(j['created_by']),
        approvedBy: _s(j['approved_by']),
        updatedBy: _s(j['updated_by']),
        createdAt: _dt(j['created_at']),
        updatedAt: _dt(j['updated_at']),
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'student_id': studentId,
        'invoice_id': invoiceId,
        'discount_type': discountType.dbValue,
        'value': value,
        'reason': reason,
        'status': status.dbValue,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'updated_by': updatedBy,
      });
}

class Scholarship {
  final String? id;
  final String tenantId;
  final String studentId;
  final String? studentName; // joined
  final String name;
  final double discountPercent;
  final DateTime startDate;
  final DateTime? endDate;
  final ScholarshipStatus status;
  final String? createdBy;
  final String? approvedBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Scholarship({
    this.id,
    required this.tenantId,
    required this.studentId,
    this.studentName,
    required this.name,
    required this.discountPercent,
    required this.startDate,
    this.endDate,
    this.status = ScholarshipStatus.active,
    this.createdBy,
    this.approvedBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Scholarship.fromJson(Map<String, dynamic> j) {
    final student = j['students'] as Map<String, dynamic>?;
    return Scholarship(
      id: _s(j['id']),
      tenantId: (_s(j['tenant_id']) ?? ''),
      studentId: (_s(j['student_id']) ?? ''),
      studentName: student != null ? _s(student['name']) : null,
      name: (_s(j['name']) ?? ''),
      discountPercent: _d(j['discount_percent']),
      startDate: _dt(j['start_date']) ?? DateTime.now(),
      endDate: _dt(j['end_date']),
      status: ScholarshipStatus.fromDb(_s(j['status'])),
      createdBy: _s(j['created_by']),
      approvedBy: _s(j['approved_by']),
      updatedBy: _s(j['updated_by']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'tenant_id': tenantId,
        'student_id': studentId,
        'name': name,
        'discount_percent': discountPercent,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate?.toIso8601String().substring(0, 10),
        'status': status.dbValue,
        'created_by': createdBy,
        'approved_by': approvedBy,
        'updated_by': updatedBy,
      });
}
