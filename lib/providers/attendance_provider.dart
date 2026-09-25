import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/tenant_context.dart';
import '../data/models/student_model.dart';
import '../data/models/attendance_status.dart';
import '../data/models/attendance_record.dart';
import '../data/repositories/attendance_repository.dart';
import '../core/sync/sync_providers.dart';

/// حاضری کی حالت کا انتظام
/// Attendance State Management using Riverpod

/// State class holding the list of students with their attendance
class AttendanceState {
  final List<MockStudent> students;
  final bool isLoading;
  final String? errorMessage;
  final DateTime selectedDate;

  /// The class these students belong to (needed by the real save path to
  /// build AttendanceRecords). Null until a class is loaded.
  final String? classId;

  AttendanceState({
    required this.students,
    this.isLoading = false,
    this.errorMessage,
    DateTime? selectedDate,
    this.classId,
  }) : selectedDate = selectedDate ?? DateTime.now();

  /// Create initial state — empty until a class is loaded from the database
  factory AttendanceState.initial() {
    return AttendanceState(
      students: [],
      isLoading: false,
    );
  }

  /// Copy with for immutability
  AttendanceState copyWith({
    List<MockStudent>? students,
    bool? isLoading,
    String? errorMessage,
    DateTime? selectedDate,
    String? classId,
  }) {
    return AttendanceState(
      students: students ?? this.students,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      selectedDate: selectedDate ?? this.selectedDate,
      classId: classId ?? this.classId,
    );
  }

  /// Count students by status
  int get presentCount => students.where((s) => s.status == AttendanceStatus.present).length;
  int get absentCount => students.where((s) => s.status == AttendanceStatus.absent).length;
  int get leaveCount => students.where((s) => s.status == AttendanceStatus.leave).length;
  int get totalCount => students.length;
}

/// StateNotifier for managing attendance
class AttendanceNotifier extends StateNotifier<AttendanceState> {
  AttendanceNotifier() : super(AttendanceState.initial());

  /// Toggle student attendance status (Present -> Absent -> Leave -> Present)
  void toggleAttendance(String studentId) {
    final updatedStudents = state.students.map((student) {
      if (student.id == studentId) {
        // Cycle through statuses
        return student.copyWith(status: student.status.next);
      }
      return student;
    }).toList();

    state = state.copyWith(students: updatedStudents);
  }

  /// Set specific status for a student
  void setAttendanceStatus(String studentId, AttendanceStatus newStatus) {
    final updatedStudents = state.students.map((student) {
      if (student.id == studentId) {
        return student.copyWith(status: newStatus);
      }
      return student;
    }).toList();

    state = state.copyWith(students: updatedStudents);
  }

  /// Reset all students to PRESENT (Default state)
  void resetToPresent() {
    final updatedStudents = state.students.map((student) {
      return student.copyWith(status: AttendanceStatus.present);
    }).toList();

    state = state.copyWith(students: updatedStudents);
  }

  /// Mark all students as ABSENT (useful for testing)
  void markAllAbsent() {
    final updatedStudents = state.students.map((student) {
      return student.copyWith(status: AttendanceStatus.absent);
    }).toList();

    state = state.copyWith(students: updatedStudents);
  }

  /// Load students for a specific class/darja
  /// Real data is loaded via classAttendanceProvider (Supabase-backed).
  void loadStudentsForDarja(String darjaName) {
    state = state.copyWith(students: [], isLoading: false);
  }
}

/// Provider for attendance state
final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AttendanceState>((ref) {
  return AttendanceNotifier();
});

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
