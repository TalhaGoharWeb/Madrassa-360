/// اخراجات — the managed expense register with approval workflow.
///
/// List / search / filter → view → create (draft) → approve → post →
/// void. Writes go through [FinanceNotifier] (createExpenseDraft,
/// transitionExpense). There is no expense delete — voiding is the
/// archive equivalent, and posted rows are DB-immutable. The quick
/// immediate-post path lives on the ledger tab; this tab is the
/// approval register.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money_format.dart';
import '../../../data/models/finance.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/finance_provider.dart';
import '../../viewmodels/finance/financial_views.dart';
import 'finance_ui.dart';

/// اخراجات
class FinanceExpensesTab extends ConsumerStatefulWidget {
  const FinanceExpensesTab({super.key});

  @override
  ConsumerState<FinanceExpensesTab> createState() => _FinanceExpensesTabState();
}

class _FinanceExpensesTabState extends ConsumerState<FinanceExpensesTab> {
  String _query = '';
  DocStatus? _statusFilter;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        ref.watch(hasPermissionProvider(AppPermissions.createFinance));
    final canApprove =
        ref.watch(hasPermissionProvider(AppPermissions.approveFinance));
    final state = ref.watch(financeProvider);

    if (state.isLoading && state.expenses.isEmpty) {
      return const M360LoadingState();
    }
    if (state.error != null && state.expenses.isEmpty) {
      return M360ErrorState(
        message: 'اخراجات لوڈ کرنے میں خطا',
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
                  hint: 'مد یا وصول کنندہ تلاش کریں…',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              if (canCreate) ...[
                const SizedBox(width: 8),
                M360PrimaryButton(
                  label: 'نیا خرچ',
                  icon: Icons.add,
                  onPressed: _showCreateSheet,
                ),
              ],
            ],
          ),
        ),
        _statusChips(),
        Expanded(child: _list(state.expenses, canCreate, canApprove)),
      ],
    );
  }

  List<ExpenseEntry> _filtered(List<ExpenseEntry> all) {
    var out = all;
    if (_statusFilter != null) {
      out = out.where((e) => e.status == _statusFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out
          .where((e) =>
              e.category.toLowerCase().contains(q) ||
              (e.recipient ?? '').toLowerCase().contains(q) ||
              (e.description ?? '').toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  Widget _statusChips() {
    final options = <DocStatus?>[null, ...DocStatus.values];
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

  Widget _list(List<ExpenseEntry> all, bool canCreate, bool canApprove) {
    final filtered = _filtered(all);
    if (filtered.isEmpty) {
      return M360EmptyState(
        icon: Icons.shopping_cart_outlined,
        title: all.isEmpty ? 'کوئی خرچ درج نہیں' : 'کوئی خرچ نہیں ملا',
        description: all.isEmpty
            ? 'پہلا خرچ درج کریں — منظوری کے بعد یہ حتمی ہو کر لیجر میں آئے گا۔'
            : 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔',
        actionLabel: all.isEmpty && canCreate ? 'نیا خرچ درج کریں' : null,
        onAction: all.isEmpty && canCreate ? _showCreateSheet : null,
      );
    }
    final posted = filtered
        .where((e) => e.status == DocStatus.posted)
        .fold<double>(0, (s, e) => s + e.amount);
    final pending = filtered
        .where((e) => !e.status.isFinal)
        .fold<double>(0, (s, e) => s + e.amount);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: filtered.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: M360StatCard(
                    value: formatPK(posted),
                    label: 'حتمی اخراجات (روپے)',
                    icon: Icons.shopping_cart_outlined,
                    valueColor: AppColors.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: M360StatCard(
                    value: formatPK(pending),
                    label: 'زیر التواء (روپے)',
                    icon: Icons.pending_outlined,
                    valueColor: AppColors.warning,
                  ),
                ),
              ],
            ),
          );
        }
        return _expenseTile(filtered[i - 1], canApprove);
      },
    );
  }

  Widget _expenseTile(ExpenseEntry expense, bool canApprove) {
    final view = ExpenseView(expense);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: M360Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(M360Radius.md),
          onTap: () => _showDetail(expense, canApprove),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shopping_cart_outlined,
                    color: AppColors.error),
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
                            view.categoryLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        financeChip(view.chipKind),
                      ],
                    ),
                    Text(
                      '${view.recipientLabel} • ${formatDateUrdu(expense.expenseDate)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                view.amountLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(ExpenseEntry expense, bool canApprove) {
    final view = ExpenseView(expense);
    showM360Dialog(
      context,
      title: 'خرچ — ${view.categoryLabel}',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: financeChip(view.chipKind)),
          const SizedBox(height: 12),
          _kv('مد', view.categoryLabel),
          _kv('رقم', formatPK(expense.amount)),
          _kv('وصول کنندہ', view.recipientLabel),
          _kv('تاریخ', formatDateUrdu(expense.expenseDate)),
          if ((expense.description ?? '').isNotEmpty)
            _kv('تفصیل', expense.description!),
          if (expense.status == DocStatus.posted)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'حتمی اخراجات ناقابل ترمیم ہیں — تصحیح واپسی (reversal) اندراج سے ہوتی ہے۔',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: 'بند کریں',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (canApprove && expense.status == DocStatus.draft)
          M360PrimaryButton(
            label: 'منظور کریں',
            onPressed: () => _transition(
                expense, DocStatus.approved, 'خرچ منظور کر لیا گیا'),
          ),
        if (canApprove && expense.status == DocStatus.approved)
          M360PrimaryButton(
            label: 'حتمی کریں',
            onPressed: () =>
                _transition(expense, DocStatus.posted, 'خرچ حتمی ہو گیا'),
          ),
        if (canApprove && !expense.status.isFinal)
          M360DangerButton(
            label: 'منسوخ کریں',
            onPressed: () => _confirmTransition(
              expense,
              DocStatus.voided,
              'خرچ منسوخ کریں',
              'یہ خرچ منسوخ کر دیا جائے گا۔ منسوخ شدہ خرچ لیجر میں نہیں آئے گا۔',
            ),
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
          Flexible(
            child: Text(v,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.left,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _transition(
      ExpenseEntry expense, DocStatus to, String success) async {
    final err = await ref
        .read(financeProvider.notifier)
        .transitionExpense(expense.id ?? '', to);
    if (!mounted) return;
    Navigator.of(context).pop();
    showM360SnackBar(context, err ?? success, isError: err != null);
  }

  Future<void> _confirmTransition(
      ExpenseEntry expense, DocStatus to, String title, String message) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'جی ہاں',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    await _transition(expense, to, 'خرچ اپ ڈیٹ ہو گیا');
  }

  void _showCreateSheet() {
    showM360Dialog(
      context,
      title: 'نیا خرچ',
      content: const _ExpenseForm(),
      actions: const [],
    );
  }
}

/// Expense create form — saves a DRAFT via
/// [FinanceNotifier.createExpenseDraft]; approval happens here on the
/// register.
class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm();

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _categoryController = TextEditingController();
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _categoryController.dispose();
    _recipientController.dispose();
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M360TextField(
          label: 'مد',
          hint: 'مثلاً تنخواہ، بجلی کا بل، کرایہ',
          controller: _categoryController,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'وصول کنندہ (اختیاری)',
          controller: _recipientController,
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'رقم',
          hint: 'مثال: 5000',
          controller: _amountController,
          keyboardType: TextInputType.number,
          prefixIcon: const Icon(Icons.payments_outlined),
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'تفصیل (اختیاری)',
          controller: _descController,
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        const Text(
          'خرچ مسودے کے طور پر محفوظ ہو گا — منظوری کے بعد حتمی ہو گا۔',
          textDirection: TextDirection.rtl,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    );
  }

  Future<void> _create() async {
    final category = _categoryController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if (category.isEmpty || amount == null || amount <= 0) {
      showM360SnackBar(context, 'مد اور درست رقم درج کریں');
      return;
    }
    setState(() => _saving = true);
    final err = await ref.read(financeProvider.notifier).createExpenseDraft(
          category: category,
          recipient: _recipientController.text.trim().isEmpty
              ? null
              : _recipientController.text.trim(),
          amount: amount,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      Navigator.of(context).pop();
      showM360SnackBar(context, 'خرچ کا مسودہ بن گیا', isError: false);
    } else {
      showM360SnackBar(context, err);
    }
  }
}
