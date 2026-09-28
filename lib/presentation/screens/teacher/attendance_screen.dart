import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
// NOTE(Phase 5, worker 4): pendingSyncCountProvider is implemented by the
// sibling sync-engine worker in lib/core/sync/sync_providers.dart. It is
// imported normally here; the coordinator reconciles if that file lands
// after this one.
import '../../../core/sync/sync_providers.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/attendance_status.dart';
import '../../../providers/attendance_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/teacher_portal_provider.dart';

/// استاد حاضری اسکرین — رفتار کے لیے دوبارہ ڈیزائن
/// Teacher Attendance Screen — speed-optimized redesign.
///
/// Same provider stack and save logic as the Phase 5 local-first rewrite
/// (nothing in the business layer changed):
///
/// * Roster + existing statuses load through [classAttendanceProvider]
///   (repository → local-first cache → Supabase); students with no record
///   for the date default to present ("management by exception").
/// * Teacher edits are kept as sparse in-memory overrides and merged on save.
/// * Save goes through [attendanceRecordNotifierProvider] → local-first
///   repository (Drift + sync_queue in one transaction, SyncEngine pushes
///   when online), so this screen writes no queue of its own and saves
///   succeed even fully offline.
/// * Fails closed: no tenant / no assigned class / load error → a message,
///   never an unscoped query or a silent empty save.
///
/// UX changes (presentation only):
///
/// * One-tap per-student segmented control — حاضر (green) / چھٹی (amber) /
///   غیر حاضر (red) / تاخیر (blue, compact) — replaces the slow
///   bottom-sheet picker. Big touch targets, thumb-friendly.
/// * "سب کو حاضر کریں" (mark all present) quick action right under the
///   class/date header — one tap + save covers the common day.
/// * Sticky bottom bar with live counts (حاضر X • چھٹی Y • غیر حاضر Z •
///   تاخیر W) and the primary "حاضری محفوظ کریں" CTA with a saving state.
/// * The floating save button is gone — saving now lives in the thumb
///   zone at the bottom of the screen.
class AttendanceScreen extends ConsumerStatefulWidget {
  /// Pre-selected class (e.g. deep link from the teacher dashboard).
  /// Falls back to the teacher's first assigned class when null/invalid.
  final String? initialClassId;

  const AttendanceScreen({super.key, this.initialClassId});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String? _classId;
  DateTime _date = _today();

  /// Sparse teacher overrides: studentId -> chosen status.
  /// Empty map = show the loaded records as-is.
  Map<String, AttendanceStatus> _edits = {};

  /// (classId|date) that [_edits] belongs to — overrides reset on change.
  String _editsKey = '';

  bool _saving = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);

  // ── helpers ────────────────────────────────────────────────

  /// Merge sparse overrides over the loaded records.
  List<AttendanceRecord> _effective(List<AttendanceRecord> base) => base
      .map((r) => r.copyWith(status: _edits[r.studentId] ?? r.status))
      .toList();

  Color _colorFor(AttendanceStatus s) => switch (s) {
        AttendanceStatus.present => AppColors.present,
        AttendanceStatus.absent => AppColors.absent,
        AttendanceStatus.leave => AppColors.leave,
        AttendanceStatus.late => AppColors.late,
      };

  IconData _iconFor(AttendanceStatus s) => switch (s) {
        AttendanceStatus.present => Icons.check,
        AttendanceStatus.absent => Icons.close,
        AttendanceStatus.leave => Icons.event_busy,
        AttendanceStatus.late => Icons.access_time,
      };

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(color: Colors.white),
        ),
        backgroundColor: color,
      ),
    );
  }

  /// One-tap status change: selecting the loaded value drops the override
  /// (edits stay sparse); anything else records it.
  void _setStatus(AttendanceRecord record, AttendanceStatus status) {
    setState(() {
      if (status == record.status) {
        _edits.remove(record.studentId);
      } else {
        _edits[record.studentId] = status;
      }
    });
  }

  void _bulkSet(List<AttendanceRecord> base, AttendanceStatus status) {
    setState(() {
      _edits = {for (final r in base) r.studentId: status};
    });
  }

  void _clearEdits() => setState(() => _edits = {});

  /// Date picker: defaults to today, never allows a future date.
  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    final d = DateTime(picked.year, picked.month, picked.day);
    if (d.isAfter(today)) return; // defensive; the picker already caps this
    setState(() => _date = d);
  }

  /// Save through the existing provider stack (Phase 5 local-first). The
  /// notifier writes to Drift + sync_queue in one transaction, which
  /// succeeds even fully offline — the SyncEngine pushes when online. An
  /// AsyncError here therefore means the LOCAL write itself failed
  /// (nothing was queued); it is retryable, not an offline state.
  ///
  /// Identical to the pre-redesign implementation — only the UI around it
  /// changed.
  Future<void> _saveAttendance(List<AttendanceRecord> base) async {
    final tenantId = ref.read(currentTenantIdProvider);
    final teacherId = ref.read(currentUserProvider)?.id;
    if (tenantId == null || teacherId == null || _classId == null) {
      _snack(AppStrings.noActiveTenant, AppColors.error);
      return; // fail closed — never save unscoped
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(attendanceRecordNotifierProvider.notifier)
          .save(_effective(base));
      if (!mounted) return;
      final st = ref.read(attendanceRecordNotifierProvider);
      if (st is AsyncError) {
        // The LOCAL write failed (nothing was queued) — honest failure,
        // retryable. Never claim "saved offline" here.
        _snack(AppStrings.saveFailed, AppColors.error);
      } else {
        setState(() => _edits = {});
        _snack(AppStrings.attendanceSaved, AppColors.success);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Auto-select the teacher's class once assignments resolve, and
    // re-resolve if the assignment list changes underneath us.
    // Declarative (not ref.listen): the provider may already hold data
    // when this build runs, and ref.listen only fires on later changes —
    // plus ref.listen is illegal in initState in Riverpod 2.x.
    // (Mutating _classId during build is safe: the build already reflects it.)
    final assigned = ref.watch(teacherAssignedClassesProvider).valueOrNull;
    if (assigned != null) {
      final ids = assigned.map((c) => c.id).toList();
      if (_classId == null || !ids.contains(_classId)) {
        final initial = widget.initialClassId;
        _classId = (initial != null && ids.contains(initial))
            ? initial
            : (ids.isNotEmpty ? ids.first : null);
      }
    }
    final tenantId = ref.watch(currentTenantIdProvider);

    // Sibling-owned provider (see import note). Defensive read so this file
    // compiles whether it is declared as Provider<int> or AsyncValue<int>.
    final Object? pendingRaw = ref.watch(pendingSyncCountProvider);
    final int pendingCount = pendingRaw is int
        ? pendingRaw
        : (pendingRaw is AsyncValue<int> ? (pendingRaw.valueOrNull ?? 0) : 0);

    // Overrides belong to exactly one (class, date) — drop them on change.
    // (Mutating fields during build is safe: the build already reflects it.)
    final editsKey = '${_classId ?? ''}|${_dateStr(_date)}';
    if (_editsKey != editsKey) {
      _editsKey = editsKey;
      _edits = {};
    }

    final recordsAsync = _classId == null
        ? null
        : ref.watch(classAttendanceProvider(
            AttendanceParams(classId: _classId!, date: _date)));

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.attendanceRegister),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppStrings.refresh,
            onPressed: _classId == null
                ? null
                : () => ref.invalidate(classAttendanceProvider(
                    AttendanceParams(classId: _classId!, date: _date))),
          ),
        ],
      ),
      body: Column(
        children: [
          if (pendingCount > 0) _offlineBanner(pendingCount),
          if (tenantId == null)
            Expanded(child: _failClosed(AppStrings.noActiveTenant))
          else ...[
            _classSelector(ref),
            Expanded(child: _recordsArea(ref, recordsAsync)),
          ],
        ],
      ),
      // Sticky bottom bar (counts + save CTA) — thumb-zone, one-handed.
      bottomNavigationBar: _stickySaveBar(recordsAsync),
    );
  }

  /// Slim offline banner: N records waiting in the sync queue.
  Widget _offlineBanner(int count) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${AppStrings.pendingSyncBanner}: $count',
              style: AppTypography.labelMedium.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Class selector: hidden label for a single assignment, dropdown for many.
  Widget _classSelector(WidgetRef ref) {
    final async = ref.watch(teacherAssignedClassesProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(AppStrings.error, style: AppTypography.bodyMedium),
        ),
        data: (classes) {
          if (classes.isEmpty) return const SizedBox.shrink();
          if (classes.length == 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.class_, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(classes.first.name, style: AppTypography.titleMedium),
                ],
              ),
            );
          }
          // Guard: a revoked class id must never reach DropdownButton.value.
          final validValue =
              classes.any((c) => c.id == _classId) ? _classId : null;
          return Row(
            children: [
              const Icon(Icons.class_, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: validValue,
                    hint: Text(AppStrings.selectClass),
                    isExpanded: true,
                    items: [
                      for (final c in classes)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        ),
                    ],
                    onChanged: (v) => setState(() => _classId = v),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Roster area: loading / error / empty / data states.
  Widget _recordsArea(
    WidgetRef ref,
    AsyncValue<List<AttendanceRecord>>? recordsAsync,
  ) {
    if (recordsAsync == null) {
      // No class chosen yet — assignments still loading, or none assigned.
      final a = ref.watch(teacherAssignedClassesProvider);
      return a.maybeWhen(
        data: (classes) => classes.isEmpty
            ? _failClosed(AppStrings.noClassAssigned)
            : const Center(child: CircularProgressIndicator()),
        orElse: () => const Center(child: CircularProgressIndicator()),
      );
    }
    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(AppStrings.error, style: AppTypography.titleMedium),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _classId == null
                  ? null
                  : () => ref.invalidate(classAttendanceProvider(
                      AttendanceParams(classId: _classId!, date: _date))),
              child: Text(AppStrings.refresh),
            ),
          ],
        ),
      ),
      data: (records) {
        if (records.isEmpty) return _failClosed(AppStrings.noData);
        return Column(
          children: [
            _actionHeader(records),
            Expanded(child: _studentList(records)),
          ],
        );
      },
    );
  }

  /// Fail-closed placeholder: message, no data, no actions.
  Widget _failClosed(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Compact action header: tappable date chip + "mark all present" quick
  /// action + clear-edits (only when overrides exist).
  Widget _actionHeader(List<AttendanceRecord> base) {
    final dateFormatter = DateFormat('EEEE، d MMMM yyyy', 'ur');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateFormatter.format(_date),
                      style: AppTypography.labelNastaliq,
                    ),
                  ),
                  const Icon(Icons.edit_calendar,
                      color: AppColors.textSecondary, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _bulkSet(base, AttendanceStatus.present),
                  icon: const Icon(Icons.done_all, size: 20),
                  label: Text(
                    AppStrings.markAllPresent,
                    style: AppTypography.labelNastaliq.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.present,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (_edits.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _clearEdits,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text(AppStrings.clearEdits),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Roster list — one compact card per student with a one-tap segmented
  /// control (حاضر / چھٹی / غیر حاضر / تاخیر).
  Widget _studentList(List<AttendanceRecord> base) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      itemCount: base.length,
      itemBuilder: (context, index) {
        final record = base[index];
        final status = _edits[record.studentId] ?? record.status;
        return _rosterRow(record, status);
      },
    );
  }

  /// One roster row: avatar + name + roll, with the rapid segmented control
  /// spanning the full row width underneath (thumb-friendly, one-handed).
  Widget _rosterRow(AttendanceRecord record, AttendanceStatus status) {
    final color = _colorFor(status);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(
              alpha: _edits.containsKey(record.studentId) ? 0.5 : 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar — status-tinted initials
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Center(
                  child: Text(
                    record.initials,
                    style: AppTypography.titleMedium.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name + roll
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.studentName,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'رول: ${record.studentRollNo}',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Live status dot
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Rapid segmented control — one tap per student.
          // Order (RTL: right → left): حاضر، چھٹی، غیر حاضر، تاخیر.
          Row(
            children: [
              _statusSegment(record, status, AttendanceStatus.present,
                  flex: 3),
              _statusSegment(record, status, AttendanceStatus.leave, flex: 3),
              _statusSegment(record, status, AttendanceStatus.absent,
                  flex: 3),
              _statusSegment(record, status, AttendanceStatus.late, flex: 2),
            ],
          ),
        ],
      ),
    );
  }

  /// One segment of the rapid status control: big touch target, one tap.
  Widget _statusSegment(
    AttendanceRecord record,
    AttendanceStatus current,
    AttendanceStatus option, {
    int flex = 3,
  }) {
    final color = _colorFor(option);
    final selected = current == option;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _setStatus(record, option),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconFor(option),
                    size: 16,
                    color: selected ? Colors.white : color,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        option.urduLabel,
                        style: AppTypography.labelNastaliq.copyWith(
                          color: selected ? Colors.white : color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sticky bottom bar: live status counts + primary save CTA.
  /// Hidden (collapsed) until a roster is loaded.
  Widget _stickySaveBar(AsyncValue<List<AttendanceRecord>>? recordsAsync) {
    final base = recordsAsync?.valueOrNull;
    if (base == null || base.isEmpty) return const SizedBox.shrink();
    final effective = _effective(base);

    int countOf(AttendanceStatus s) =>
        effective.where((r) => r.status == s).length;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.5),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _countChip(
                  AppStrings.presentCount,
                  countOf(AttendanceStatus.present),
                  AppColors.present,
                ),
                _countChip(
                  AppStrings.leaveCount,
                  countOf(AttendanceStatus.leave),
                  AppColors.leave,
                ),
                _countChip(
                  AppStrings.absentCount,
                  countOf(AttendanceStatus.absent),
                  AppColors.absent,
                ),
                _countChip(
                  AppStrings.lateCount,
                  countOf(AttendanceStatus.late),
                  AppColors.late,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _saving ? null : () => _saveAttendance(base),
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save, size: 22),
                label: Text(
                  AppStrings.saveAttendance,
                  style: AppTypography.labelNastaliq.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One live count cell in the sticky bar.
  Widget _countChip(String label, int value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: AppTypography.titleMedium.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
