import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/models.dart';
import '../../../providers/finance_provider.dart';
import '../../../providers/auth_provider.dart';

/// مالیات — Phase 4: reads the posted `transactions` ledger.
/// Same layout as before (summary bar, filter chips, entry list, add
/// dialog); the backend is now invoice → payment → receipt → ledger.
/// Posted rows are immutable: the delete action only appears on drafts.
class FinanceScreen extends ConsumerStatefulWidget {
  /// DEPRECATED: kept for signature compatibility (Phase 8 removes it).
  final String? madrasaId;
  const FinanceScreen({super.key, this.madrasaId});
  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  LedgerKind? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(financeProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeProvider);
    final isAdmin = (ref.watch(authProvider).user?.role.name ?? '')
        .contains('admin');

    final displayed = _filter == null
        ? state.ledger
        : state.ledger.where((t) => t.kind == _filter).toList();

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
              onPressed: () => _showAddDialog(context),
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
            for (final k in LedgerKind.values) ...[
              _chip(k.urduLabel, k),
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
                          _LedgerCard(displayed[i], ref, isAdmin),
                    ),
        ),
      ]),
    );
  }

  Widget _chip(String label, LedgerKind? kind) {
    final selected = _filter == kind;
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary.withOpacity(0.15),
      checkmarkColor: AppColors.primary,
      onSelected: (_) => setState(() => _filter = kind),
    );
  }

  Future<void> _showAddDialog(BuildContext ctx) async {
    final amtCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    // 0 = income, 1 = expense, 2 = fee payment
    int entryKind = 0;
    TransactionCategory incomeCat = TransactionCategory.donation;
    PaymentMethod payMethod = PaymentMethod.cash;
    String? accountId;

    await showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
        final accounts = ref.read(financeProvider).accounts;
        return AlertDialog(
          title: Text('نئی اندراج', style: AppTypography.titleMedium),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: entryKind,
              decoration: const InputDecoration(
                  labelText: 'نوعیت', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 0, child: Text('آمدن')),
                DropdownMenuItem(value: 1, child: Text('اخراجات')),
                DropdownMenuItem(value: 2, child: Text('فیس وصولی')),
              ],
              onChanged: (v) => setS(() => entryKind = v ?? 0),
            ),
            const SizedBox(height: 12),
            if (entryKind == 0)
              DropdownButtonFormField<TransactionCategory>(
                value: incomeCat,
                decoration: const InputDecoration(
                    labelText: 'ذریعہ', border: OutlineInputBorder()),
                items: const [
                  TransactionCategory.donation,
                  TransactionCategory.zakat,
                  TransactionCategory.sadqa,
                  TransactionCategory.other,
                ]
                    .map((c) => DropdownMenuItem(
                        value: c, child: Text(c.urduLabel)))
                    .toList(),
                onChanged: (v) => setS(() => incomeCat = v!),
              )
            else if (entryKind == 2)
              DropdownButtonFormField<PaymentMethod>(
                value: payMethod,
                decoration: const InputDecoration(
                    labelText: 'طریقہ', border: OutlineInputBorder()),
                items: PaymentMethod.values
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(m.urduLabel)))
                    .toList(),
                onChanged: (v) => setS(() => payMethod = v!),
              ),
            const SizedBox(height: 12),
            if (accounts.isNotEmpty)
              DropdownButtonFormField<String?>(
                value: accountId,
                decoration: const InputDecoration(
                    labelText: 'کھاتہ', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('—')),
                  for (final a in accounts)
                    DropdownMenuItem(
                        value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setS(() => accountId = v),
              ),
            const SizedBox(height: 12),
            _field(amtCtrl, 'رقم (₹)'),
            _field(descCtrl, entryKind == 1 ? 'تفصیل / مد' : 'تفصیل'),
            _field(nameCtrl, entryKind == 0
                ? 'عطیہ دہندہ (اختیاری)'
                : entryKind == 1
                    ? 'وصول کنندہ (اختیاری)'
                    : 'نوٹ (اختیاری)'),
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
                final notifier = ref.read(financeProvider.notifier);
                final amount = double.tryParse(amtCtrl.text) ?? 0;
                if (amount <= 0) return;
                String? err;
                if (entryKind == 0) {
                  err = await notifier.recordIncome(
                    sourceType: incomeCat,
                    donorName:
                        nameCtrl.text.isEmpty ? null : nameCtrl.text,
                    amount: amount,
                    accountId: accountId,
                    description: descCtrl.text.isEmpty
                        ? null
                        : descCtrl.text,
                  );
                } else if (entryKind == 1) {
                  err = await notifier.recordExpense(
                    category: descCtrl.text.isEmpty
                        ? 'دیگر'
                        : descCtrl.text,
                    recipient:
                        nameCtrl.text.isEmpty ? null : nameCtrl.text,
                    amount: amount,
                    accountId: accountId,
                    description: descCtrl.text.isEmpty
                        ? null
                        : descCtrl.text,
                  );
                } else {
                  err = await notifier.recordPayment(
                    amount: amount,
                    method: payMethod,
                    accountId: accountId,
                    notes:
                        nameCtrl.text.isEmpty ? null : nameCtrl.text,
                  );
                }
                if (err != null && ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(err)));
                }
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
class _LedgerCard extends StatelessWidget {
  const _LedgerCard(this.t, this.ref, this.isAdmin);
  final LedgerTransaction t;
  final WidgetRef ref;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final isIncome = t.isIncome;
    final color = isIncome ? AppColors.success : AppColors.error;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          Expanded(
              child: Text(t.description ?? '',
                  style: AppTypography.bodyMedium)),
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
            child: Text(t.category.urduLabel,
                style: AppTypography.labelSmall.copyWith(color: color)),
          ),
          if (t.status == DocStatus.draft) ...[
            const SizedBox(width: 8),
            Text(DocStatus.draft.urduLabel,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ]),
        // Posted/void rows are immutable — delete only on drafts.
        trailing: isAdmin && t.status == DocStatus.draft
            ? IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                onPressed: () => ref
                    .read(financeProvider.notifier)
                    .deleteLedgerDraft(t.id ?? ''),
              )
            : null,
      ),
    );
  }
}
