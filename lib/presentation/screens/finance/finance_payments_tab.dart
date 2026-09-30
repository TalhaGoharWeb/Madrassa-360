/// ادائیگیاں — real payment history on the finance backend.
///
/// List / search / filter → view → record → delete draft. Payments are
/// recorded through the existing [FinanceNotifier.recordPayment]
/// (draft → posted with receipt number, ledger entry and invoice
/// allocation filled by DB triggers). Only DRAFT payments can be
/// deleted; posted rows are DB-immutable. Destructive actions always
/// confirm first.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/utils/money_format.dart';
import '../../../data/models/finance.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/finance_provider.dart';
import '../../../providers/student_provider.dart';
import '../../viewmodels/finance/financial_views.dart';
import 'finance_ui.dart';

/// ادائیگیاں
class FinancePaymentsTab extends ConsumerStatefulWidget {
  const FinancePaymentsTab({super.key});

  @override
  ConsumerState<FinancePaymentsTab> createState() => _FinancePaymentsTabState();
}

class _FinancePaymentsTabState extends ConsumerState<FinancePaymentsTab> {
  String _query = '';
  DocStatus? _statusFilter;
  PaymentMethod? _methodFilter;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.approveFinance));
    final canRecord =
        ref.watch(hasPermissionProvider(AppPermissions.createFinance));
    final state = ref.watch(financeProvider);

    if (state.isLoading && state.payments.isEmpty) {
      return const M360LoadingState();
    }
    if (state.error != null && state.payments.isEmpty) {
      return M360ErrorState(
        message: 'ادائیگیاں لوڈ کرنے میں خطا',
        onRetry: () => ref.read(financeProvider.notifier).load(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: M360SearchField(
                  controller: _searchController,
                  hint: 'رسید نمبر یا طالب علم تلاش کریں…',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              if (canRecord) ...[
                const SizedBox(width: 8),
                M360PrimaryButton(
                  label: 'ادائیگی ریکارڈ کریں',
                  icon: Icons.add,
                  onPressed: _showRecordSheet,
                ),
              ],
            ],
          ),
        ),
        _filterChips(),
        Expanded(child: _list(state.payments, canManage)),
      ],
    );
  }

  void _showRecordSheet() {
    showM360Dialog(
      context,
      title: 'ادائیگی ریکارڈ کریں',
      content: const _PaymentForm(),
    );
  }

  List<Payment> _filtered(List<Payment> all) {
    var out = all;
    if (_statusFilter != null) {
      out = out.where((p) => p.status == _statusFilter).toList();
    }
    if (_methodFilter != null) {
      out = out.where((p) => p.method == _methodFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out
          .where((p) =>
              (p.receiptNumber ?? '').toLowerCase().contains(q) ||
              (p.studentName ?? '').toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _chip(
              'سب',
              _statusFilter == null && _methodFilter == null,
              () => setState(() {
                    _statusFilter = null;
                    _methodFilter = null;
                  })),
          for (final s in DocStatus.values)
            _chip(s.urduLabel, _statusFilter == s,
                () => setState(() => _statusFilter = s)),
          for (final m in PaymentMethod.values)
            _chip(m.urduLabel, _methodFilter == m,
                () => setState(() => _methodFilter = m)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        checkmarkColor: AppColors.primary,
      ),
    );
  }

  Widget _list(List<Payment> all, bool canManage) {
    final filtered = _filtered(all);
    if (filtered.isEmpty) {
      return M360EmptyState(
        icon: Icons.payments_outlined,
        title: all.isEmpty ? 'کوئی ادائیگی درج نہیں' : 'کوئی ادائیگی نہیں ملی',
        description: all.isEmpty
            ? 'ادائیگی ریکارڈ ہوتے ہی یہاں نظر آئے گی — رسید نمبر خودکار بنتا ہے۔'
            : 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔',
      );
    }
    final total = filtered
        .where((p) => p.status == DocStatus.posted)
        .fold<double>(0, (s, p) => s + p.amount);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: filtered.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: M360StatCard(
              value: formatPK(total),
              label: 'حتمی وصول شدہ (روپے)',
              icon: Icons.payments_outlined,
              valueColor: AppColors.success,
            ),
          );
        }
        return _paymentTile(filtered[i - 1], canManage);
      },
    );
  }

  Widget _paymentTile(Payment payment, bool canManage) {
    final view = PaymentView(payment);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: M360Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(M360Radius.md),
          onTap: () => _showDetail(payment, canManage),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.payments_outlined,
                    color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            view.receiptLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                        financeChip(view.chipKind),
                      ],
                    ),
                    Text(
                      '${view.studentLabel} • ${view.methodLabel}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    Text(
                      app_date.DateUtils.formatDateUrdu(payment.paymentDate),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                view.amountLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(Payment payment, bool canManage) {
    final view = PaymentView(payment);
    showM360Dialog(
      context,
      title: 'ادائیگی ${view.receiptLabel}',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: financeChip(view.chipKind)),
          const SizedBox(height: 12),
          _kv('طالب علم', view.studentLabel),
          _kv('رقم', formatPK(payment.amount)),
          _kv('طریقہ', view.methodLabel),
          _kv('تاریخ', app_date.DateUtils.formatDateUrdu(payment.paymentDate)),
          if ((payment.notes ?? '').isNotEmpty) _kv('نوٹس', payment.notes!),
          const SizedBox(height: 8),
          const Text(
            'حتمی ادائیگیاں ناقابل ترمیم ہیں — تصحیح واپسی (reversal) اندراج سے ہوتی ہے۔',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: 'بند کریں',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (canManage && view.canDelete)
          M360DangerButton(
            label: 'مسودہ حذف کریں',
            onPressed: () => _confirmDelete(payment),
          ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: AppTypography.labelNastaliq
                  .copyWith(color: AppColors.textSecondary)),
          Flexible(
            child: Text(v,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleSmall
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Payment payment) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'مسودہ حذف کریں',
      message:
          'یہ ادائیگی کا مسودہ حذف کر دیا جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final err = await ref
        .read(financeProvider.notifier)
        .deletePaymentDraft(payment.id ?? '');
    if (!mounted) return;
    Navigator.of(context).pop();
    showM360SnackBar(context, err ?? 'مسودہ حذف کر دیا گیا',
        isError: err != null);
  }
}

/// Record-payment form — writes through the real
/// [FinanceNotifier.recordPayment]. The student is optional (donations /
/// general receipts); the method dropdown uses the backend's real
/// [PaymentMethod] values. Receipt number, ledger entry and invoice
/// allocation are filled by DB triggers — never invented here.
class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm();

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  String? _studentId;
  PaymentMethod _method = PaymentMethod.cash;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(allStudentsProvider);
    final students = studentsAsync.valueOrNull ?? [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (studentsAsync.isLoading)
          const M360LoadingState()
        else ...[
          M360Dropdown<String>(
            label: 'طالب علم (اختیاری)',
            hint: 'طالب علم منتخب کریں',
            value: _studentId,
            items: [
              for (final s in students)
                M360DropdownItem(
                    value: s.id, label: '${s.name} (${s.className})'),
            ],
            onChanged: (v) => setState(() => _studentId = v),
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'رقم',
            hint: 'مثلاً 1000',
            controller: _amountController,
            keyboardType: TextInputType.number,
            prefixIcon: Icons.payments_outlined,
          ),
          const SizedBox(height: 12),
          M360Dropdown<PaymentMethod>(
            label: 'ادائیگی کا طریقہ',
            value: _method,
            items: [
              for (final m in PaymentMethod.values)
                M360DropdownItem(value: m, label: m.urduLabel),
            ],
            onChanged: (v) => setState(() => _method = v ?? PaymentMethod.cash),
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'نوٹس (اختیاری)',
            controller: _notesController,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: M360TertiaryButton(
                  label: 'منسوخ کریں',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M360PrimaryButton(
                  label: 'ریکارڈ کریں',
                  icon: Icons.check,
                  isLoading: _saving,
                  onPressed: _saving ? null : _record,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _record() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showM360SnackBar(context, 'درست رقم درج کریں');
      return;
    }
    setState(() => _saving = true);
    final err = await ref.read(financeProvider.notifier).recordPayment(
          studentId: _studentId,
          amount: amount,
          method: _method,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      Navigator.of(context).pop();
      showM360SnackBar(context, 'ادائیگی ریکارڈ ہو گئی', isError: false);
    } else {
      showM360SnackBar(context, err);
    }
  }
}
