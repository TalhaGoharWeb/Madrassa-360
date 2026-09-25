import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/tenant_context.dart';
import '../data/models/attendance_record.dart';
import '../data/repositories/attendance_repository.dart';
import '../core/sync/sync_providers.dart';

/// حاضری کی حالت کا انتظام
/// Attendance State Management using Riverpod
///
/// NOTE (mock purge, Phase 6): the Phase-1 in-memory attendance state
/// (the legacy state/notifier classes and the Phase-1 student model) was
/// deleted — nothing in the app referenced it after the teacher attendance
/// screen was rewired to [classAttendanceProvider]. This file now only
/// carries the repository-backed (tenant-scoped, local-first) providers.

// ─────────────────────────────────────────────
// Repository-backed Attendance Providers
// (tenant-scoped; Supabase via IAttendanceRepository)
// ─────────────────────────────────────────────

/// Parameters for attendance queries (classId + date)
class AttendanceParams {
  final String classId;
  final DateTime date;

  const AttendanceParams({required this.classId, required this.date});

  @override
  bool operator ==(Object other) =>
      other is AttendanceParams &&
      other.classId == classId &&
      _dateStr(other.date) == _dateStr(date);

  @override
  int get hashCode => Object.hash(classId, _dateStr(date));

  String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);
}

/// Repository provider (local-first: Drift + sync engine)
final attendanceRepositoryProvider = Provider<IAttendanceRepository>((ref) {
  return LocalAttendanceRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncEngineProvider),
  );
});

/// Fetch attendance records for a class on a given date
final classAttendanceProvider =
    FutureProvider.family<List<AttendanceRecord>, AttendanceParams>(
        (ref, params) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return <AttendanceRecord>[];
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.getClassAttendance(
      classId: params.classId, date: params.date, tenantId: tenantId);
});

/// Realtime stream of attendance records for a class+date
final attendanceStreamProvider =
    StreamProvider.family<List<AttendanceRecord>, AttendanceParams>(
        (ref, params) {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null) return Stream<List<AttendanceRecord>>.empty();
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.subscribeToAttendance(
      classId: params.classId, date: params.date, tenantId: tenantId);
});

/// Notifier for saving attendance changes
class AttendanceRecordNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(List<AttendanceRecord> records) async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      state = AsyncError(
          StateError('No active tenant'), StackTrace.current);
      return;
    }
    final repo = ref.read(attendanceRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repo.saveAttendance(records);
      state = const AsyncData(null);
    } catch (e, st) {
      // Local-first: saveAttendance writes to Drift + the sync queue in one
      // transaction, so a failure here is a LOCAL failure (no separate
      // offline queue needed — the legacy OfflineSyncService fallback is
      // obsolete). The queue row was never created, so the user can retry.
      state = AsyncError(e, st);
    }
    // Invalidate the cache so next read is fresh
    if (records.isNotEmpty) {
      final params = AttendanceParams(
        classId: records.first.classId,
        date: DateTime.tryParse(records.first.date) ?? DateTime.now(),
      );
      ref.invalidate(classAttendanceProvider(params));
    }
  }
}

final attendanceRecordNotifierProvider =
    AsyncNotifierProvider<AttendanceRecordNotifier, void>(
        AttendanceRecordNotifier.new);
