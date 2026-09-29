/// انوائسز — real invoice lifecycle on the finance backend.
///
/// List / search / filter → view → create → issue / cancel → delete
/// draft. All writes go through [FinanceNotifier] (createInvoice,
/// transitionInvoice, deleteInvoiceDraft); posted rows are DB-immutable
/// and can only be cancelled, never deleted. Destructive actions always
/// confirm first.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../core/utils/money_format.dart';
import '../../../data/models/finance.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/finance_provider.dart';
import '../../../providers/student_provider.dart';
import '../../viewmodels/finance/financial_views.dart';
import 'finance_ui.dart';

/// انوائسز
class FinanceInvoicesTab extends ConsumerStatefulWidget {
  const FinanceInvoicesTab({super.key});

  @override
  ConsumerState<FinanceInvoicesTab> createState() => _FinanceInvoicesTabState();
}

class _FinanceInvoicesTabState extends ConsumerState<FinanceInvoicesTab> {
  String _query = '';
  InvoiceStatus? _statusFilter;
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
    final state = ref.watch(financeProvider);

    if (state.isLoading && state.invoices.isEmpty) {
      return const M360LoadingState();
    }
    if (state.error != null && state.invoices.isEmpty) {
      return M360ErrorState(
        message: 'انوائسز لوڈ کرنے میں خطا',
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
                  hint: 'نمبر یا طالب علم تلاش کریں…',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 8),
                M360PrimaryButton(
                  label: 'نئی انوائس',
                  icon: Icons.add,
                  onPressed: _showCreateSheet,
                ),
              ],
            ],
          ),
        ),
        _statusChips(),
        Expanded(child: _list(state.invoices, canManage)),
      ],
    );
  }

  List<Invoice> _filtered(List<Invoice> all) {
    var out = all;
    if (_statusFilter != null) {
      out = out.where((i) => i.status == _statusFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out
          .where((i) =>
              (i.invoiceNumber ?? '').toLowerCase().contains(q) ||
              (i.studentName ?? '').toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  Widget _statusChips() {
    final options = <InvoiceStatus?>[
      null,
      InvoiceStatus.draft,
      InvoiceStatus.issued,
      InvoiceStatus.partiallyPaid,
      InvoiceStatus.paid,
      InvoiceStatus.overdue,
      InvoiceStatus.cancelled,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final s in options) ...[
            FilterChip(
              label: Text(s == null ? 'سب' : s.urduLabel),
              selected: _statusFilter == s,
              onSelected: (_) => setState(() => _statusFilter = s),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _list(List<Invoice> all, bool canManage) {
    final filtered = _filtered(all);
    if (filtered.isEmpty) {
      return M360EmptyState(
        icon: Icons.receipt_long_outlined,
        title: all.isEmpty ? 'کوئی انوائس نہیں' : 'کوئی انوائس نہیں ملی',
        description: all.isEmpty
            ? 'پہلی انوائس بنا کر آغاز کریں — مسودہ سے جاری تک کا مکمل چکر یہیں ہے۔'
            : 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔',
        actionLabel: all.isEmpty && canManage ? 'نئی انوائس بنائیں' : null,
        onAction: all.isEmpty && canManage ? _showCreateSheet : null,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: filtered.length,
      itemBuilder: (context, i) => _invoiceTile(filtered[i], canManage),
    );
  }

  Widget _invoiceTile(Invoice invoice, bool canManage) {
    final view = InvoiceView(invoice);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: M360Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(M360Radius.md),
          onTap: () => _showDetail(invoice, canManage),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: AppColors.primary),
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
                            view.numberLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        financeChip(view.chipKind),
                      ],
                    ),
                    Text(
                      '${view.studentLabel} • ${view.monthLabel}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'کل: ${view.totalLabel}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        if (invoice.balanceDue > 0)
                          Text(
                            'بقایا: ${view.balanceLabel}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// Invoice detail + lifecycle actions.
  void _showDetail(Invoice invoice, bool canManage) {
    final view = InvoiceView(invoice);
    showM360Dialog(
      context,
      title: 'انوائس ${view.numberLabel}',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: financeChip(view.chipKind)),
          const SizedBox(height: 12),
          _kv('طالب علم', view.studentLabel),
          _kv('بلنگ ماہ', view.monthLabel),
          _kv('تاریخ اجراء',
              app_date.DateUtils.formatDateUrdu(invoice.issueDate)),
          _kv('آخری تاریخ', app_date.DateUtils.formatDateUrdu(invoice.dueDate)),
          const Divider(),
          _kv('ذیلی کل', formatPK(invoice.subtotal)),
          _kv('رعایت', formatPK(invoice.discountTotal)),
          _kv('کل رقم', formatPK(invoice.total)),
          _kv('ادا شدہ', formatPK(invoice.amountPaid)),
          _kv('بقایا', formatPK(invoice.balanceDue)),
          if ((invoice.notes ?? '').isNotEmpty) _kv('نوٹس', invoice.notes!),
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: 'بند کریں',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (canManage && view.canIssue)
          M360PrimaryButton(
            label: 'جاری کریں',
            onPressed: () => _transition(
                invoice, InvoiceStatus.issued, 'انوائس جاری کر دی گئی'),
          ),
        if (canManage && view.canCancel)
          M360DangerButton(
            label: 'منسوخ کریں',
            onPressed: () => _confirmTransition(
              invoice,
              InvoiceStatus.cancelled,
              'انوائس منسوخ کریں',
              'یہ انوائس منسوخ کر دی جائے گی۔ منسوخی کے بعد ترمیم ممکن نہیں۔',
            ),
          ),
        if (canManage && view.canDelete)
          M360DangerButton(
            label: 'مسودہ حذف کریں',
            onPressed: () => _confirmDelete(invoice),
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
          Text(k, style: const TextStyle(color: AppColors.textSecondary)),
          Text(v,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _transition(
      Invoice invoice, InvoiceStatus to, String success) async {
    final err = await ref
        .read(financeProvider.notifier)
        .transitionInvoice(invoice.id ?? '', to);
    if (!mounted) return;
    Navigator.of(context).pop();
    showM360SnackBar(context, err ?? success, isError: err != null);
  }

  Future<void> _confirmTransition(
      Invoice invoice, InvoiceStatus to, String title, String message) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'جی ہاں',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    await _transition(invoice, to, 'انوائس اپ ڈیٹ ہو گئی');
  }

  Future<void> _confirmDelete(Invoice invoice) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'مسودہ حذف کریں',
      message:
          'یہ انوائس کا مسودہ حذف کر دیا جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final err = await ref
        .read(financeProvider.notifier)
        .deleteInvoiceDraft(invoice.id ?? '');
    if (!mounted) return;
    Navigator.of(context).pop();
    showM360SnackBar(context, err ?? 'مسودہ حذف کر دیا گیا',
        isError: err != null);
  }

  void _showCreateSheet() {
    showM360Dialog(
      context,
      title: 'نئی انوائس',
      content: const _InvoiceForm(),
      actions: const [],
    );
  }
}

/// Invoice create form — student, dates and dynamic line items.
/// Persists via [FinanceNotifier.createInvoice] (draft).
class _InvoiceForm extends ConsumerStatefulWidget {
  const _InvoiceForm();

  @override
  ConsumerState<_InvoiceForm> createState() => _InvoiceFormState();
}

class _ItemRow {
  final desc = TextEditingController();
  final amount = TextEditingController();
  void dispose() {
    desc.dispose();
    amount.dispose();
  }
}

class _InvoiceFormState extends ConsumerState<_InvoiceForm> {
  String? _studentId;
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  String? _billingMonth;
  final _notesController = TextEditingController();
  final _items = <_ItemRow>[_ItemRow()];
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(allStudentsProvider);
    final students = studentsAsync.valueOrNull ?? [];
    final now = DateTime.now();
    final months = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (studentsAsync.isLoading)
          const M360LoadingState()
        else ...[
          M360Dropdown<String>(
            label: 'طالب علم',
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
          M360Dropdown<String>(
            label: 'بلنگ ماہ (اختیاری)',
            hint: 'ماہ منتخب کریں',
            value: _billingMonth,
            items: [
              for (final m in months)
                M360DropdownItem(value: m, label: monthLabelUrdu(m)),
            ],
            onChanged: (v) => setState(() => _billingMonth = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _dateField('تاریخ اجراء', _issueDate,
                      (d) => setState(() => _issueDate = d))),
              const SizedBox(width: 12),
              Expanded(
                  child: _dateField('آخری تاریخ', _dueDate,
                      (d) => setState(() => _dueDate = d))),
            ],
          ),
          const SizedBox(height: 12),
          const Text('مدات',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: M360TextField(
                      label: 'تفصیل',
                      hint: 'مثلاً ماہانہ فیس',
                      controller: _items[i].desc,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: M360TextField(
                      label: 'رقم',
                      hint: '500',
                      controller: _items[i].amount,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  if (_items.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: AppColors.error),
                      onPressed: () =>
                          setState(() => _items.removeAt(i).dispose()),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: M360TertiaryButton(
              label: 'مد شامل کریں',
              onPressed: () => setState(() => _items.add(_ItemRow())),
            ),
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
                  label: 'مسودہ بنائیں',
                  isLoading: _saving,
                  onPressed: _saving ? null : _create,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dateField(
      String label, DateTime value, ValueChanged<DateTime> onPick) {
    return InkWell(
      borderRadius: BorderRadius.circular(M360Radius.md),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2040),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
            Text(app_date.DateUtils.formatDateUrdu(value),
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final tenantId = ref.read(currentTenantIdProvider) ?? '';
    final items = <InvoiceItem>[];
    for (final row in _items) {
      final desc = row.desc.text.trim();
      final amt = double.tryParse(row.amount.text.trim());
      if (desc.isEmpty || amt == null || amt <= 0) continue;
      items.add(InvoiceItem(
        tenantId: tenantId,
        invoiceId: '',
        description: desc,
        unitAmount: amt,
      ));
    }
    if (_studentId == null || items.isEmpty) {
      showM360SnackBar(context, 'طالب علم اور کم از کم ایک درست مد درج کریں');
      return;
    }
    setState(() => _saving = true);
    final err = await ref.read(financeProvider.notifier).createInvoice(
          studentId: _studentId!,
          issueDate: _issueDate,
          dueDate: _dueDate,
          items: items,
          billingMonth: _billingMonth,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      Navigator.of(context).pop();
      showM360SnackBar(context, 'انوائس کا مسودہ بن گیا', isError: false);
    } else {
      showM360SnackBar(context, err);
    }
  }
}
