/// طلبہ کی فیس — m360 redesign (Phase 9)
/// Student fee management — the `fees` table register.
///
/// Presentation layer only. Business logic is reused unchanged:
/// [allFeesProvider], [feeNotifierProvider] (save/delete/validation),
/// [allStudentsProvider], the tenant-scoped repository, and the guided
/// collection flow ([CollectFeeScreen]) with the real PDF receipt.
///
/// What changed in Phase 9 (presentation only):
/// * Full m360 component language: [PageHeader], [M360StatCard],
///   [M360SearchField], [M360Card] rows, [financeChip] status chips,
///   [M360Dialog] voucher form, [showM360SnackBar] feedback.
/// * The old inner tabs (فیس کی تفصیل / وصولی) are gone — collection
///   stats live on the finance dashboard hub tab; this screen is the
///   register: list / search / filter → view → collect → voucher.
/// * Voucher deletion (unpaid vouchers only) with destructive
///   confirmation. Paid rows are immutable history — a wrong amount on an
///   unpaid voucher is corrected by deleting and re-issuing.
/// * Loading / empty / error / retry states on every data surface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/design/m360.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/money_format.dart';
import '../../../data/models/fee.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/student_provider.dart';
import '../../shell/shell_page_body.dart';
import '../../viewmodels/finance/financial_views.dart';
import '../finance/collect_fee_screen.dart';
import '../finance/finance_ui.dart';

/// طلبہ کی فیس
class FeeManagementScreen extends ConsumerStatefulWidget {
  const FeeManagementScreen({super.key});

  @override
  ConsumerState<FeeManagementScreen> createState() =>
      _FeeManagementScreenState();
}

class _FeeManagementScreenState extends ConsumerState<FeeManagementScreen> {
  String _statusFilter = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCollect(Fee record) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CollectFeeScreen(fee: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        ref.watch(hasPermissionProvider(AppPermissions.createFees));
    final canCollect =
        ref.watch(hasPermissionProvider(AppPermissions.collectFees));

    return ShellPageBody(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'fee_voucher_fab',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('نیا واؤچر'),
              onPressed: _showVoucherDialog,
            )
          : null,
      child: Consumer(
        builder: (context, ref, _) {
          final feeAsync = ref.watch(allFeesProvider);
          return feeAsync.when(
            loading: () => const M360LoadingState(),
            error: (e, _) => M360ErrorState(
              message: 'فیس ریکارڈ لوڈ کرنے میں خطا',
              onRetry: () => ref.invalidate(allFeesProvider),
            ),
            data: (records) => _buildRegister(records, canCollect, canCreate),
          );
        },
      ),
    );
  }

  Widget _buildRegister(List<Fee> records, bool canCollect, bool canCreate) {
    final filtered = _applyFilters(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'طلبہ کی فیس',
          breadcrumb: 'مالی',
          description: 'ماہانہ فیس کے واؤچر، وصولی اور بقایا جات کا رجسٹر',
        ),
        _summaryCards(records),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: M360SearchField(
            controller: _searchController,
            hint: 'طالب علم یا جماعت تلاش کریں…',
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
          ),
        ),
        _statusChips(),
        Expanded(
          child: filtered.isEmpty
              ? M360EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: records.isEmpty
                      ? 'کوئی فیس ریکارڈ نہیں'
                      : 'کوئی ریکارڈ نہیں ملا',
                  description: records.isEmpty
                      ? 'نیا واؤچر بنا کر فیس کا ریکارڈ شروع کریں۔'
                      : 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔',
                  actionLabel:
                      records.isEmpty && canCreate ? 'نیا واؤچر بنائیں' : null,
                  onAction:
                      records.isEmpty && canCreate ? _showVoucherDialog : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) =>
                      _feeTile(filtered[i], canCollect, canCreate),
                ),
        ),
      ],
    );
  }

  List<Fee> _applyFilters(List<Fee> records) {
    var out = records;
    if (_statusFilter != 'all') {
      final status = FeeStatus.values.firstWhere(
        (s) => s.name == _statusFilter,
        orElse: () => FeeStatus.pending,
      );
      out = out.where((r) => r.status == status).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      out = out
          .where((r) =>
              r.studentName.toLowerCase().contains(q) ||
              r.studentClass.toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  Widget _summaryCards(List<Fee> records) {
    // All paid amounts count — including partial payments — because the
    // money is real regardless of row status.
    final collected = records.fold<double>(0, (s, r) => s + r.amountPaid);
    final due = records
        .where((r) => r.status != FeeStatus.paid)
        .fold<double>(0, (s, r) => s + r.remaining);
    final pastDue = records.where((r) => r.status == FeeStatus.pastDue).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: M360StatCard(
              value: formatPK(collected),
              label: 'وصول شدہ (روپے)',
              icon: Icons.check_circle_outline,
              valueColor: AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: M360StatCard(
              value: formatPK(due),
              label: 'بقایا (روپے)',
              icon: Icons.pending_outlined,
              valueColor: AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: M360StatCard(
              value: '$pastDue',
              label: 'واجب الادا ریکارڈ',
              icon: Icons.warning_amber_outlined,
              valueColor: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChips() {
    const options = [
      ('all', 'سب'),
      ('paid', 'ادا شدہ'),
      ('partial', 'جزوی'),
      ('pending', 'زیر التواء'),
      ('pastDue', 'واجب الادا'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final (id, label) in options) ...[
            FilterChip(
              label: Text(label),
              selected: _statusFilter == id,
              onSelected: (_) => setState(() => _statusFilter = id),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              checkmarkColor: AppColors.primary,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// Fee row — outstanding balance is the hero number, with a payment
  /// progress bar and the canonical status chip. Tapping opens the
  /// guided collection flow.
  Widget _feeTile(Fee record, bool canCollect, bool canCreate) {
    final view = FeeRecordView(record);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: M360Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(M360Radius.md),
          onTap: canCollect ? () => _openCollect(record) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _tileColor(view).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_tileIcon(record.status), color: _tileColor(view)),
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
                            record.studentName,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        financeChip(view.chipKind),
                      ],
                    ),
                    Text(
                      '${record.studentClass} - ${view.monthLabel}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: view.progress,
                        minHeight: 6,
                        color: _tileColor(view),
                        backgroundColor:
                            _tileColor(view).withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ادا شدہ: ${view.amountPaidLabel}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.success),
                        ),
                        if (record.remaining > 0)
                          Text(
                            'بقایا: ${view.remainingLabel} روپے',
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
              if (canCreate && record.amountPaid == 0)
                IconButton(
                  tooltip: 'واؤچر حذف کریں',
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 20),
                  onPressed: () => _confirmDeleteVoucher(record),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _tileColor(FeeRecordView view) {
    switch (view.chipKind) {
      case FinancialChipKind.paid:
        return AppColors.success;
      case FinancialChipKind.partial:
        return AppColors.warning;
      case FinancialChipKind.due:
      case FinancialChipKind.overdue:
        return AppColors.error;
      case FinancialChipKind.draft:
      case FinancialChipKind.posted:
      case FinancialChipKind.cancelled:
        return AppColors.textSecondary;
    }
  }

  IconData _tileIcon(FeeStatus status) {
    switch (status) {
      case FeeStatus.paid:
        return Icons.check_circle;
      case FeeStatus.partial:
        return Icons.pie_chart;
      case FeeStatus.pending:
        return Icons.schedule;
      case FeeStatus.pastDue:
        return Icons.warning;
    }
  }

  /// Deletes an UNPAID voucher with destructive confirmation. Rows with
  /// any payment are immutable history and cannot be deleted here.
  Future<void> _confirmDeleteVoucher(Fee record) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'واؤچر حذف کریں',
      message:
          '${record.studentName} کے ${FeeRecordView(record).monthLabel} کے واؤچر کو حذف کر دیا جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(feeNotifierProvider.notifier).delete(record.id);
      if (!mounted) return;
      showM360SnackBar(context, 'واؤچر حذف کر دیا گیا', isError: false);
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'واؤچر حذف کرنے میں خطا');
    }
  }

  // ── New voucher dialog ──

  /// Real voucher creation. The student comes from the tenant's live
  /// roster and the month from real calendar months — no free-text
  /// names, no hard-coded darja list. Persists through [FeeNotifier.save];
  /// the class shown is the selected student's own class.
  void _showVoucherDialog() {
    showM360Dialog(
      context,
      title: 'نیا واؤچر بنائیں',
      content: const _VoucherForm(),
      actions: const [],
    );
  }
}

/// Voucher form + actions in one stateful widget so the create button
/// always reads the current selection.
class _VoucherForm extends ConsumerStatefulWidget {
  const _VoucherForm();

  @override
  ConsumerState<_VoucherForm> createState() => _VoucherFormState();
}

class _VoucherFormState extends ConsumerState<_VoucherForm> {
  final _amountController = TextEditingController();
  late final List<String> _monthValues;
  late String _selectedMonth;
  String? _selectedStudentId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthValues = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
    _selectedMonth = _monthValues.first;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(allStudentsProvider);
    final students = studentsAsync.valueOrNull ?? [];
    final tenantId = ref.watch(currentTenantIdProvider);

    if (studentsAsync.isLoading) {
      return const M360LoadingState();
    }
    if (studentsAsync.hasError || tenantId == null) {
      return M360ErrorState(
        message: 'طلبہ لوڈ کرنے میں خطا',
        onRetry: () => ref.invalidate(allStudentsProvider),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        M360Dropdown<String>(
          label: 'طالب علم',
          hint: 'طالب علم منتخب کریں',
          value: _selectedStudentId,
          items: [
            for (final s in students)
              M360DropdownItem(
                  value: s.id, label: '${s.name} (${s.className})'),
          ],
          onChanged: (v) => setState(() => _selectedStudentId = v),
        ),
        const SizedBox(height: 12),
        M360Dropdown<String>(
          label: 'ماہ',
          value: _selectedMonth,
          items: [
            for (final m in _monthValues)
              M360DropdownItem(value: m, label: monthLabelUrdu(m)),
          ],
          onChanged: (v) => setState(() => _selectedMonth = v!),
        ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'رقم',
          hint: 'مثال: 500',
          controller: _amountController,
          keyboardType: TextInputType.number,
          prefixIcon: Icons.payments_outlined,
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
                label: 'واؤچر بنائیں',
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
    final students = ref.read(allStudentsProvider).valueOrNull ?? [];
    final tenantId = ref.read(currentTenantIdProvider);
    final amount = double.tryParse(_amountController.text.trim());
    final matches = [
      for (final s in students)
        if (s.id == _selectedStudentId) s
    ];
    if (matches.isEmpty || amount == null || amount <= 0 || tenantId == null) {
      showM360SnackBar(context, 'طالب علم منتخب کریں اور درست رقم درج کریں');
      return;
    }
    final student = matches.first;
    // Due on the last day of the selected month.
    final mp = _selectedMonth.split('-');
    final due = DateTime(int.parse(mp[0]), int.parse(mp[1]) + 1, 0);
    final dueStr =
        '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
    setState(() => _saving = true);
    try {
      await ref.read(feeNotifierProvider.notifier).save(Fee(
            id: '',
            tenantId: tenantId,
            studentId: student.id,
            studentName: student.name,
            studentClass: student.className,
            month: _selectedMonth,
            amountDue: amount,
            amountPaid: 0,
            dueDate: dueStr,
            status: FeeStatus.pending,
          ));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'واؤچر بنانے میں خطا');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
