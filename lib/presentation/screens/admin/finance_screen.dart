import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/models.dart';
import '../../../providers/finance_provider.dart';
import '../../../providers/auth_provider.dart';

class FinanceScreen extends StatefulWidget {
  final String? madrasaId;
  const FinanceScreen({super.key, this.madrasaId});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  WidgetRef? _ref;
  TransactionType? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        _ref?.read(financeProvider.notifier).load(
            madrasaId: widget.madrasaId));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      _ref = ref;
      final state = ref.watch(financeProvider);
      final isAdmin = (ref.watch(authProvider).user?.role.name ?? '')
          .contains('admin');

      final displayed = _filter == null
          ? state.transactions
          : state.transactions.where((t) => t.type == _filter).toList();

      return Scaffold(
        appBar: AppBar(
          title: Text('مالیات', style: AppTypography.appBarTitle),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('نئی اندراج'),
                onPressed: () => _showAddDialog(context, ref),
              )
            : null,
        body: Column(children: [
          // ── Summary bar ──────────────────────────────────────
          Container(
            color: const Color(0xFF1A237E),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(children: [
              _SummaryTile('آمدن', state.totalIncome, AppColors.success),
              const SizedBox(width: 8),
              _SummaryTile('اخراجات', state.totalExpense, AppColors.error),
              const SizedBox(width: 8),
              _SummaryTile('بیلنس', state.balance,
                  state.balance >= 0 ? AppColors.success : AppColors.error),
            ]),
          ),

          // ── Filter chips ─────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              _chip('سب', null),
              const SizedBox(width: 8),
              for (final t in TransactionType.values) ...[
                _chip(t.urduLabel, t),
                const SizedBox(width: 8),
              ],
            ]),
          ),

          // ── List ─────────────────────────────────────────────
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayed.isEmpty
                    ? Center(
                        child: Text('کوئی ریکارڈ نہیں',
                            style: AppTypography.bodyLarge.copyWith(
                                color: AppColors.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: displayed.length,
                        itemBuilder: (ctx, i) =>
                            _TransactionCard(displayed[i], ref, isAdmin),
                      ),
          ),
        ]),
      );
    });
  }

  Widget _chip(String label, TransactionType? type) {
    final selected = _filter == type;
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary.withOpacity(0.15),
      checkmarkColor: AppColors.primary,
      onSelected: (_) => setState(() => _filter = type),
    );
  }

  Future<void> _showAddDialog(BuildContext ctx, WidgetRef ref) async {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final receiptCtrl = TextEditingController();
    TransactionType type = TransactionType.donation;

    await showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
        return AlertDialog(
          title: Text('نئی اندراج', style: AppTypography.titleMedium),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<TransactionType>(
              value: type,
              decoration: const InputDecoration(
                  labelText: 'نوعیت', border: OutlineInputBorder()),
              items: TransactionType.values
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(t.urduLabel)))
                  .toList(),
              onChanged: (v) => setS(() => type = v!),
            ),
            const SizedBox(height: 12),
            _field(amtCtrl, 'رقم (₹)'),
            _field(descCtrl, 'تفصیل'),
            _field(nameCtrl, 'نام (اختیاری)'),
            _field(receiptCtrl, 'رسید نمبر (اختیاری)'),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('منسوخ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(dCtx);
                final user = ref.read(authProvider).user;
                await ref.read(financeProvider.notifier).addTransaction(
                      FinanceTransaction(
                        type: type,
                        amount: double.tryParse(amtCtrl.text) ?? 0,
                        description: descCtrl.text,
                        personName: nameCtrl.text,
                        tenantId: ref.read(currentTenantIdProvider) ?? '',
                        madrasaId: widget.madrasaId,
                        receiptNumber: receiptCtrl.text,
                        createdByUserId: user?.id ?? '',
                        date: DateTime.now(),
                      ),
                    );
              },
              child: const Text('محفوظ'),
            ),
          ],
        );
      }),
    );
  }

  Widget _field(TextEditingController ctrl, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────
class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.amount, this.color);
  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(label,
              style: AppTypography.labelSmall
                  .copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: AppTypography.titleSmall.copyWith(color: color),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
class _TransactionCard extends StatelessWidget {
  const _TransactionCard(this.t, this.ref, this.isAdmin);
  final FinanceTransaction t;
  final WidgetRef ref;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type.isIncome;
    final color = isIncome ? AppColors.success : AppColors.error;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
        ),
        title: Row(children: [
          Expanded(child: Text(t.description ?? '', style: AppTypography.bodyMedium)),
          Text(
            '${isIncome ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
            style: AppTypography.bodyLarge.copyWith(
                color: color, fontWeight: FontWeight.bold),
          ),
        ]),
        subtitle: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(t.type.urduLabel,
                style:
                    AppTypography.labelSmall.copyWith(color: color)),
          ),
          if (t.personName?.isNotEmpty == true) ...[
            const SizedBox(width: 8),
            Text(t.personName ?? '',
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ]),
        trailing: isAdmin
            ? IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                onPressed: () => ref
                    .read(financeProvider.notifier)
                    .deleteTransaction(t.id ?? ''),
              )
            : null,
      ),
    );
  }
}
