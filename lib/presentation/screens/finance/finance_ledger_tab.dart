/// لیجر — the finance backend's book of record.
///
/// List / search / filter → view → create → delete draft. Income and
/// expense entries are recorded end-to-end through [FinanceNotifier]
/// (recordIncome / recordExpense: draft → approved → posted) and then
/// appear here as posted ledger rows. Drafts can be deleted with
/// confirmation; posted rows are DB-immutable — corrections go through
/// reversal entries.

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

/// لیجر
class FinanceLedgerTab extends ConsumerStatefulWidget {
  const FinanceLedgerTab({super.key});

  @override
  ConsumerState<FinanceLedgerTab> createState() => _FinanceLedgerTabState();
}

class _FinanceLedgerTabState extends ConsumerState<FinanceLedgerTab> {
  String _query = '';
  LedgerKind? _kindFilter;
  TransactionCategory? _categoryFilter;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        ref.watch(hasPermissionProvider(AppPermissions.createFinance));
    final state = ref.watch(financeProvider);

    if (state.isLoading && state.ledger.isEmpty) {
      return const M360LoadingState();
    }
    if (state.error != null && state.ledger.isEmpty) {
      return M360ErrorState(
        message: 'لیجر لوڈ کرنے میں خطا',
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
                  hint: 'تفصیل تلاش کریں…',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 8),
                M360PrimaryButton(
                  label: 'نیا اندراج',
                  icon: Icons.add,
                  onPressed: _showCreateSheet,
                ),
              ],
            ],
          ),
        ),
        _filterChips(),
        Expanded(child: _list(state.ledger, canManage)),
      ],
    );
  }

  List<LedgerTransaction> _filtered(List<LedgerTransaction> all) {
    var out = all;
    if (_kindFilter != null) {
      out = out.where((e) => e.kind == _kindFilter).toList();
    }
    if (_categoryFilter != null) {
      out = out.where((e) => e.category == _categoryFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out
          .where((e) =>
              (e.description ?? '').toLowerCase().contains(q) ||
              e.category.urduLabel.contains(_query))
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
          _chip('سب', _kindFilter == null && _categoryFilter == null, () {
            setState(() {
              _kindFilter = null;
              _categoryFilter = null;
            });
          }),
          for (final k in LedgerKind.values)
            _chip(k.urduLabel, _kindFilter == k,
                () => setState(() => _kindFilter = k)),
          for (final c in TransactionCategory.values)
            _chip(c.urduLabel, _categoryFilter == c,
                () => setState(() => _categoryFilter = c)),
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

  Widget _list(List<LedgerTransaction> all, bool canManage) {
    final filtered = _filtered(all);
    if (filtered.isEmpty) {
      return M360EmptyState(
        icon: Icons.book_outlined,
        title: all.isEmpty ? 'لیجر خالی ہے' : 'کوئی اندراج نہیں ملا',
        description: all.isEmpty
            ? 'پہلا اندراج (آمدن یا خرچ) درج کریں — حتمی اندراجات یہیں کتاب میں آئیں گے۔'
            : 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔',
        actionLabel: all.isEmpty && canManage ? 'نیا اندراج کریں' : null,
        onAction: all.isEmpty && canManage ? _showCreateSheet : null,
      );
    }
    final income = filtered
        .where((e) => e.isIncome && e.status == DocStatus.posted)
        .fold<double>(0, (s, e) => s + e.amount);
    final expense = filtered
        .where((e) => !e.isIncome && e.status == DocStatus.posted)
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
                    value: formatPK(income),
                    label: 'آمدن (روپے)',
                    icon: Icons.trending_up,
                    valueColor: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: M360StatCard(
                    value: formatPK(expense),
                    label: 'اخراجات (روپے)',
                    icon: Icons.trending_down,
                    valueColor: AppColors.error,
                  ),
                ),
              ],
            ),
          );
        }
        return _ledgerTile(filtered[i - 1], canManage);
      },
    );
  }

  Widget _ledgerTile(LedgerTransaction entry, bool canManage) {
    final view = LedgerEntryView(entry);
    final color = view.isIncome ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: M360Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(M360Radius.md),
          onTap: () => _showDetail(entry, canManage),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  view.isIncome ? Icons.trending_up : Icons.trending_down,
                  color: color,
                ),
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
                            view.title,
                            style: Theme.of(context).textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        financeChip(view.statusChip),
                      ],
                    ),
                    Text(
                      '${entry.category.urduLabel} • ${formatDateUrdu(entry.entryDate)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '${view.isIncome ? '+' : '-'}${view.amountLabel}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(LedgerTransaction entry, bool canManage) {
    final view = LedgerEntryView(entry);
    showM360Dialog(
      context,
      title: 'لیجر اندراج',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: financeChip(view.statusChip)),
          const SizedBox(height: 12),
          _kv('قسم', entry.kind.urduLabel),
          _kv('زمرہ', entry.category.urduLabel),
          _kv('رقم', formatPK(entry.amount)),
          _kv('تاریخ', formatDateUrdu(entry.entryDate)),
          _kv('تفصیل', view.title),
          if (entry.status == DocStatus.posted)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'حتمی اندراجات ناقابل ترمیم ہیں — تصحیح واپسی (reversal) اندراج سے ہوتی ہے۔',
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
        if (canManage && view.canDelete)
          M360DangerButton(
            label: 'مسودہ حذف کریں',
            onPressed: () => _confirmDelete(entry),
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

  Future<void> _confirmDelete(LedgerTransaction entry) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'مسودہ حذف کریں',
      message: 'یہ لیجر مسودہ حذف کر دیا جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final err = await ref
        .read(financeProvider.notifier)
        .deleteLedgerDraft(entry.id ?? '');
    if (!mounted) return;
    Navigator.of(context).pop();
    showM360SnackBar(context, err ?? 'مسودہ حذف کر دیا گیا',
        isError: err != null);
  }

  void _showCreateSheet() {
    showM360Dialog(
      context,
      title: 'نیا لیجر اندراج',
      content: const _LedgerForm(),
      actions: const [],
    );
  }
}

/// Ledger entry form — income (by category + donor) or expense (by
/// category text + recipient). Posts end-to-end via [FinanceNotifier].
class _LedgerForm extends ConsumerStatefulWidget {
  const _LedgerForm();

  @override
  ConsumerState<_LedgerForm> createState() => _LedgerFormState();
}

class _LedgerFormState extends ConsumerState<_LedgerForm> {
  LedgerKind _kind = LedgerKind.expense;
  TransactionCategory _incomeCategory = TransactionCategory.donation;
  final _categoryController = TextEditingController();
  final _personController = TextEditingController();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _categoryController.dispose();
    _personController.dispose();
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = _kind == LedgerKind.income;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M360Dropdown<LedgerKind>(
          label: 'قسم',
          value: _kind,
          items: const [
            M360DropdownItem(value: LedgerKind.expense, label: 'اخراجات'),
            M360DropdownItem(value: LedgerKind.income, label: 'آمدن'),
          ],
          onChanged: (v) => setState(() => _kind = v!),
        ),
        const SizedBox(height: 12),
        if (isIncome)
          M360Dropdown<TransactionCategory>(
            label: 'ذریعہ',
            value: _incomeCategory,
            items: [
              for (final c in TransactionCategory.values)
                M360DropdownItem(value: c, label: c.urduLabel),
            ],
            onChanged: (v) => setState(() => _incomeCategory = v!),
          )
        else
          M360TextField(
            label: 'مد',
            hint: 'مثلاً تنخواہ، بجلی کا بل، کرایہ',
            controller: _categoryController,
          ),
        const SizedBox(height: 12),
        M360TextField(
          label: isIncome ? 'عطیہ دہندہ (اختیاری)' : 'وصول کنندہ (اختیاری)',
          controller: _personController,
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
          'اندراج حتمی (posted) ہو گا — بعد میں ترمیم ممکن نہیں۔',
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
                label: 'اندراج کریں',
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
    final amount = double.tryParse(_amountController.text.trim());
    final category = _kind == LedgerKind.income
        ? _incomeCategory.urduLabel
        : _categoryController.text.trim();
    if (amount == null || amount <= 0 || category.isEmpty) {
      showM360SnackBar(context, 'مد اور درست رقم درج کریں');
      return;
    }
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'حتمی اندراج',
      message:
          '${formatPK(amount)} روپے کا ${_kind.urduLabel} اندراج حتمی ہو جائے گا۔ جاری رکھیں؟',
      confirmLabel: 'جی ہاں، درج کریں',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final notifier = ref.read(financeProvider.notifier);
    final person = _personController.text.trim().isEmpty
        ? null
        : _personController.text.trim();
    final desc = _descController.text.trim().isEmpty
        ? null
        : _descController.text.trim();
    final String? err;
    if (_kind == LedgerKind.income) {
      err = await notifier.recordIncome(
        sourceType: _incomeCategory,
        donorName: person,
        amount: amount,
        description: desc,
      );
    } else {
      err = await notifier.recordExpense(
        category: category,
        recipient: person,
        amount: amount,
        description: desc,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      Navigator.of(context).pop();
      showM360SnackBar(context, 'اندراج حتمی ہو گیا', isError: false);
    } else {
      showM360SnackBar(context, err);
    }
  }
}
