/// فیس وصولی کا رہنما بہاؤ — ۴ مراحل
/// Guided fee-collection flow: تفصیل → رقم → تصدیق → رسید.
///
/// Phase 9 migration: this was `_CollectFeeFlow`, pushed with its own
/// nested `Scaffold` + `AppBar`. It now renders inside [ShellPageBody] —
/// the AppShell keeps the only Scaffold/AppBar — and uses the m360
/// component language. Business rules are byte-identical to the
/// pre-redesign implementation:
///
/// * validation: amount > 0 and ≤ remaining (no payment-method step — the
///   [Fee] model has no payment-method concept and inventing one is out
///   of scope);
/// * persistence through [FeeNotifier.save]; the DB recalculates status;
/// * paid-date stamp, "فیس کی قسم = ماہانہ فیس" label and the
///   `#FEE-<month>-<id6>` receipt-number format are unchanged;
/// * receipt printing goes through the real branded Urdu PDF pipeline
///   ([FeeReceiptPdf.build] → [Printing.layoutPdf]).
///
/// Works both as a shell-hub route and as a standalone pushed screen
/// (dashboard quick actions): [ShellPageBody] restores the back chevron
/// whenever the route can pop.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/design/m360.dart';
import '../../../core/reports/documents/fee_receipt.dart';
import '../../../core/reports/report_branding.dart';
import '../../../core/reports/urdu_pdf.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/local/database_provider.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/utils/money_format.dart';
import '../../../data/models/fee.dart';
import '../../../providers/fee_provider.dart';
import '../../shell/shell_page_body.dart';
import '../../viewmodels/finance/financial_views.dart';

/// One primary CTA per step. Validation rules, the paid-date stamp, the
/// receipt-number format, and the real PDF print path are all identical to
/// the pre-redesign dialogs — only the presentation changed.
class CollectFeeScreen extends ConsumerStatefulWidget {
  final Fee fee;

  const CollectFeeScreen({super.key, required this.fee});

  @override
  ConsumerState<CollectFeeScreen> createState() => _CollectFeeScreenState();
}

class _CollectFeeScreenState extends ConsumerState<CollectFeeScreen> {
  static const _stepLabels = ['تفصیل', 'رقم', 'تصدیق', 'رسید'];

  int _step = 0;
  late final TextEditingController _amountController;
  bool _saving = false;

  /// Payment recorded in step 2 (identical rules to the old dialog).
  double _paidAmount = 0;

  /// Fee record as returned by the notifier save (step 2 → receipt).
  Fee? _savedFee;

  String? _receiptNo;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the full outstanding balance — the common case.
    _amountController = TextEditingController(
      text: widget.fee.remaining.toString(),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // ── shared helpers (same business rules as the old dialogs) ──

  /// Receipt number — same format as the pre-redesign implementation.
  String _receiptNoFor(Fee record) =>
      '#FEE-${record.month}-${record.id.length >= 6 ? record.id.substring(0, 6).toUpperCase() : record.id.toUpperCase()}';

  /// Validation — identical rules to the pre-redesign collection dialog:
  /// amount must be a positive number and not exceed the remaining balance.
  String? _validateAmount(String? value) {
    if (value == null || value.isEmpty) return 'رقم درج کریں';
    final amount = double.tryParse(value);
    if (amount == null || amount <= 0) return 'درست رقم درج کریں';
    if (amount > widget.fee.remaining) {
      return 'رقم باقی رقم سے زیادہ نہیں ہو سکتی';
    }
    return null;
  }

  void _snack(String message, {bool isError = true}) {
    if (!mounted) return;
    showM360SnackBar(context, message, isError: isError);
  }

  /// Step 2 → save through the existing notifier (Phase 4 behavior):
  /// persist the payment via [FeeNotifier.save]; DB recalculates status.
  Future<void> _confirmPayment() async {
    final error = _validateAmount(_amountController.text);
    if (error != null) {
      _snack(error);
      return;
    }
    final amount = double.parse(_amountController.text);
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final paidStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final updated = widget.fee.copyWith(
        amountPaid: widget.fee.amountPaid + amount,
        paidDate: paidStr,
      );
      final saved = await ref.read(feeNotifierProvider.notifier).save(updated);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _paidAmount = amount;
        _savedFee = saved;
        _receiptNo = _receiptNoFor(saved);
        _step = 3;
      });
      _snack(
        '${formatPK(amount)} کی فیس کامیابی سے وصول کر لی گئی',
        isError: false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('فیس وصول کرنے میں خطا');
    }
  }

  /// Real receipt printing — identical path to the pre-redesign
  /// implementation: branded Urdu PDF from the fee record's real data.
  Future<void> _printReceipt(Fee record, String receiptNo) async {
    try {
      final tenantId = ref.read(currentTenantIdProvider);
      final db = ref.read(appDatabaseProvider);
      final branding = await loadReportBranding(db, tenantId ?? '');
      final bytes = await FeeReceiptPdf.build(
        branding: branding,
        urdu: UrduPdf(),
        record: record,
        receiptNo: receiptNo,
        monthLabel: monthLabelUrdu(record.month),
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      _snack('پرنٹ میں خرابی');
    }
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return ShellPageBody(
      child: Column(
        children: [
          _stepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(M360Spacing.md),
              child: switch (_step) {
                0 => _detailsStep(),
                1 => _amountStep(),
                2 => _confirmStep(),
                _ => _receiptStep(),
              },
            ),
          ),
          _bottomCta(),
        ],
      ),
    );
  }

  /// Step indicator: تفصیل → رقم → تصدیق → رسید.
  Widget _stepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'فیس وصول کریں',
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < _stepLabels.length; i++) ...[
                _stepDot(i),
                if (i < _stepLabels.length - 1) _stepConnector(i),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepDot(int i) {
    final done = i < _step;
    final active = i == _step;
    final color = (done || active) ? AppColors.primary : AppColors.divider;
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: done
                ? AppColors.success
                : active
                    ? AppColors.primary
                    : color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '${i + 1}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              active ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _stepLabels[i],
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: (done || active)
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
        ),
      ],
    );
  }

  Widget _stepConnector(int i) {
    final done = i < _step;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(bottom: 26, left: 4, right: 4),
        height: 2,
        color:
            done ? AppColors.success : AppColors.divider.withValues(alpha: 0.5),
      ),
    );
  }

  /// Step 0 — تفصیل: student + fee details, outstanding balance as hero.
  Widget _detailsStep() {
    final fee = widget.fee;
    final view = FeeRecordView(fee);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Student header
        M360Card(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person,
                    color: AppColors.primary, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fee.studentName,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${fee.studentClass} - ${view.monthLabel}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              M360StatusChip.fee(fee: _m360Fee(view.chipKind)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Outstanding balance — the hero number
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'بقایا رقم',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                '${view.remainingLabel} روپے',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              // Expanded (not spaceAround): the three stats share the row
              // evenly instead of overflowing at 360px.
              Row(
                children: [
                  Expanded(child: _heroStat('کل فیس', view.amountDueLabel)),
                  Expanded(child: _heroStat('ادا شدہ', view.amountPaidLabel)),
                  Expanded(child: _heroStat('آخری تاریخ', fee.dueDate)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroStat(String label, String value) {
    final theme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: theme.titleMedium?.copyWith(color: Colors.white),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.labelSmall?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  /// Step 1 — رقم: amount entry (pre-filled with remaining).
  Widget _amountStep() {
    final fee = widget.fee;
    final view = FeeRecordView(fee);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: AppColors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'بقایا: ${view.remainingLabel} روپے',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        M360TextField(
          label: 'وصول کی جانے والی رقم',
          controller: _amountController,
          keyboardType: TextInputType.number,
          autofocus: true,
          prefixIcon: Icons.payments_outlined,
          validator: _validateAmount,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: M360TertiaryButton(
            label: 'پوری بقایا رقم',
            onPressed: () => setState(() {
              _amountController.text = fee.remaining.toString();
            }),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'رقم باقی رقم سے زیادہ نہیں ہو سکتی',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Step 2 — تصدیق: review exactly what will be recorded.
  Widget _confirmStep() {
    final fee = widget.fee;
    final view = FeeRecordView(fee);
    final amount = double.tryParse(_amountController.text) ?? 0;
    final afterRemaining = fee.remaining - amount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M360Card(
          child: Column(
            children: [
              _infoRow(Icons.person, 'طالب علم', fee.studentName),
              _infoRow(Icons.calendar_month, 'مہینہ', view.monthLabel),
              _infoRow(
                  Icons.payments, 'وصول کی جانے والی رقم', formatPK(amount),
                  iconColor: AppColors.success),
              _infoRow(
                  Icons.pending, 'اس کے بعد بقایا', formatPK(afterRemaining),
                  iconColor:
                      afterRemaining > 0 ? AppColors.error : AppColors.success),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'تصدیق کے بعد یہ ادائیگی فوری طور پر ریکارڈ میں محفوظ ہو جائے گی۔',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          ),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Step 3 — رسید: confirmation + receipt details + print.
  Widget _receiptStep() {
    final record = _savedFee ?? widget.fee;
    final receiptNo = _receiptNo ?? _receiptNoFor(record);
    final paidAt = DateTime.tryParse(record.paidDate ?? '');
    // Display status after this payment (presentation mapping only).
    final afterKind = record.remaining <= 0
        ? FinancialChipKind.paid
        : FinancialChipKind.partial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 56),
              const SizedBox(height: 8),
              Text(
                'ادائیگی کامیاب',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: AppColors.success),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatPK(_paidAmount)} وصول کر لیے گئے',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        M360Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'فیس کی رسید',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const Divider(height: 24),
              _receiptRow('رسید نمبر', receiptNo),
              _receiptRow('طالب علم کا نام', record.studentName),
              _receiptRow('کلاس', record.studentClass),
              _receiptRow('مہینہ', monthLabelUrdu(record.month)),
              _receiptRow('فیس کی قسم', 'ماہانہ فیس'),
              _receiptRow('وصول شدہ رقم', formatPK(_paidAmount)),
              _receiptRow('بقایا', formatPK(record.remaining)),
              _receiptRow('حیثیت', afterKind.urduLabel),
              _receiptRow(
                  'تاریخ',
                  paidAt == null
                      ? '—'
                      : app_date.DateUtils.formatDateUrdu(paidAt)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: M360SecondaryButton(
                label: 'بند کریں',
                icon: Icons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: M360PrimaryButton(
                label: 'پرنٹ کریں',
                icon: Icons.print,
                onPressed: () => _printReceipt(record, receiptNo),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _receiptRow(String label, String value) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.bodyMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// One primary CTA per step (back affordance where it makes sense).
  /// Orange ([M360PrimaryButton]) is reserved for the money-moving action.
  Widget _bottomCta() {
    if (_step == 3) return const SizedBox.shrink();

    final Widget primary = switch (_step) {
      0 => M360PrimaryButton(
          label: widget.fee.remaining > 0 ? 'فیس وصول کریں' : 'رسید دیکھیں',
          icon: Icons.payments,
          fullWidth: true,
          onPressed: () {
            if (widget.fee.remaining > 0) {
              setState(() => _step = 1);
            } else {
              // Fully paid — jump straight to the receipt view.
              setState(() {
                _savedFee = widget.fee;
                _paidAmount = widget.fee.amountPaid;
                _receiptNo = _receiptNoFor(widget.fee);
                _step = 3;
              });
            }
          },
        ),
      1 => M360PrimaryButton(
          label: 'جاری رکھیں',
          icon: Icons.arrow_forward,
          fullWidth: true,
          onPressed: () {
            final error = _validateAmount(_amountController.text);
            if (error != null) {
              _snack(error);
              return;
            }
            setState(() => _step = 2);
          },
        ),
      _ => M360PrimaryButton(
          label: 'ادائیگی کی تصدیق کریں',
          icon: Icons.verified,
          fullWidth: true,
          isLoading: _saving,
          onPressed: _saving ? null : _confirmPayment,
        ),
    };

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            if (_step > 0 && _step < 3)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: M360SecondaryButton(
                  label: 'واپس',
                  onPressed:
                      _saving ? null : () => setState(() => _step = _step - 1),
                ),
              ),
            Expanded(child: primary),
          ],
        ),
      ),
    );
  }
}

/// Maps the pure-Dart [FinancialChipKind] onto the canonical fee chip.
M360FeeStatus _m360Fee(FinancialChipKind kind) {
  switch (kind) {
    case FinancialChipKind.paid:
      return M360FeeStatus.paid;
    case FinancialChipKind.partial:
      return M360FeeStatus.partial;
    case FinancialChipKind.due:
      return M360FeeStatus.due;
    case FinancialChipKind.overdue:
      return M360FeeStatus.overdue;
    case FinancialChipKind.draft:
    case FinancialChipKind.posted:
    case FinancialChipKind.cancelled:
      return M360FeeStatus.due;
  }
}
