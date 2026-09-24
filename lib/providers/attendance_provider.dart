import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/student_model.dart';
import '../data/models/attendance_status.dart';
import '../data/models/attendance_record.dart';
import '../data/repositories/attendance_repository.dart';
import '../core/services/offline_sync_service.dart';

/// حاضری کی حالت کا انتظام
/// Attendance State Management using Riverpod

/// State class holding the list of students with their attendance
class AttendanceState {
  final List<MockStudent> students;
  final bool isLoading;
  final String? errorMessage;
  final DateTime selectedDate;

  AttendanceState({
    required this.students,
    this.isLoading = false,
    this.errorMessage,
    DateTime? selectedDate,
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
  }) {
    return AttendanceState(
      students: students ?? this.students,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      selectedDate: selectedDate ?? this.selectedDate,
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

  /// Save attendance (Mock - just prints for now)
  Future<bool> saveAttendance() async {
    state = state.copyWith(isLoading: true);

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // In Phase 2, this will save to Firebase/Hive
    // For now, just print the exceptions (non-present students)
    final exceptions = state.students.where((s) => s.status != AttendanceStatus.present);
    
    for (final student in exceptions) {
      // ignore: avoid_print
      print('📝 Exception: ${student.name} - ${student.status.urduLabel}');
    }

    state = state.copyWith(isLoading: false);
    return true;
  }
}

/// Provider for attendance state
final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AttendanceState>((ref) {
  return AttendanceNotifier();
});

// ─────────────────────────────────────────────
// Repository-backed Attendance Providers
// (Phase 5 — uses Supabase or Mock via kUseSupabase flag)
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

/// Repository provider
final attendanceRepositoryProvider = Provider<IAttendanceRepository>((ref) {
  return SupabaseAttendanceRepository();
});

/// Fetch attendance records for a class on a given date
final classAttendanceProvider =
    FutureProvider.family<List<AttendanceRecord>, AttendanceParams>(
        (ref, params) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.getClassAttendance(classId: params.classId, date: params.date);
});

/// Realtime stream of attendance records for a class+date
final attendanceStreamProvider =
    StreamProvider.family<List<AttendanceRecord>, AttendanceParams>(
        (ref, params) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.subscribeToAttendance(
      classId: params.classId, date: params.date);
});

/// Notifier for saving attendance changes
class AttendanceRecordNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(List<AttendanceRecord> records) async {
    final repo = ref.read(attendanceRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repo.saveAttendance(records);
      state = const AsyncData(null);
    } catch (e, st) {
      // Offline fallback: queue records for later sync
      await OfflineSyncService.queueAttendance(records);
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
