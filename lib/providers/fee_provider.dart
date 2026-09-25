/// فیس پروائیڈر
/// Fee Provider — repository-backed state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/tenant_context.dart';
import '../data/models/fee.dart';
import '../data/repositories/fee_repository.dart';

// ─────────────────────────────────────────────
// Repository Provider
// ─────────────────────────────────────────────

final feeRepositoryProvider = Provider<IFeeRepository>((ref) {
  return SupabaseFeeRepository();
});

// ─────────────────────────────────────────────
// All Fees
// ─────────────────────────────────────────────

final allFeesProvider = FutureProvider<List<Fee>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Fee>[];
  final repo = ref.watch(feeRepositoryProvider);
  return repo.getAllFees(tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Fees by Student (family provider keyed by studentId)
// ─────────────────────────────────────────────

final feesByStudentProvider =
    FutureProvider.family<List<Fee>, String>((ref, studentId) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Fee>[];
  final repo = ref.watch(feeRepositoryProvider);
  return repo.getFeesByStudent(studentId, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Fees by Month (family provider keyed by YYYY-MM, e.g. "2026-01")
// ─────────────────────────────────────────────

final feesByMonthProvider =
    FutureProvider.family<List<Fee>, String>((ref, yearMonth) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <Fee>[];
  final repo = ref.watch(feeRepositoryProvider);
  return repo.getFeesByMonth(yearMonth, tenantId: tenantId);
});

// ─────────────────────────────────────────────
// Fee Summary Stats
// ─────────────────────────────────────────────

class FeeSummary {
  final int totalStudents;
  final int paidCount;
  final int pendingCount;
  final double totalCollected;
  final double totalDue;

  const FeeSummary({
    required this.totalStudents,
    required this.paidCount,
    required this.pendingCount,
    required this.totalCollected,
    required this.totalDue,
  });
}

final feeSummaryProvider = FutureProvider<FeeSummary>((ref) async {
  final fees = await ref.watch(allFeesProvider.future);
  final paid = fees.where((f) => f.status == FeeStatus.paid).toList();
  final pending = fees
      .where((f) =>
          f.status == FeeStatus.pending || f.status == FeeStatus.pastDue)
      .toList();
  return FeeSummary(
    totalStudents: fees.map((f) => f.studentId).toSet().length,
    paidCount: paid.length,
    pendingCount: pending.length,
    totalCollected: fees.fold(0.0, (sum, f) => sum + f.amountPaid),
    totalDue: pending.fold(0.0, (sum, f) => sum + (f.amountDue - f.amountPaid)),
  );
});

// ─────────────────────────────────────────────
// Fee Mutations Notifier
// ─────────────────────────────────────────────

class FeeNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Fee> save(Fee fee) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(feeRepositoryProvider);
    final saved = await repo.upsertFee(fee, tenantId: tenantId);
    ref.invalidate(allFeesProvider);
    ref.invalidate(feesByStudentProvider(fee.studentId));
    return saved;
  }

  Future<void> delete(String feeId) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) throw StateError('No active tenant');
    final repo = ref.read(feeRepositoryProvider);
    await repo.deleteFee(feeId, tenantId: tenantId);
    ref.invalidate(allFeesProvider);
  }
}

final feeNotifierProvider =
    AsyncNotifierProvider<FeeNotifier, void>(FeeNotifier.new);
