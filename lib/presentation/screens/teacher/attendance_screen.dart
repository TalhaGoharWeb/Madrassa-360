import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:madrasa_360/core/design/m360.dart';

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
import '../../shell/shell_page_body.dart';

/// استاد حاضری اسکرین — رفتار کے لیے دوبارہ ڈیزائن
/// Teacher Attendance Screen — speed-optimized redesign.
///
/// Phase 10 (m360): visual/UX layer only — same provider stack and save
/// logic as the Phase 5 local-first rewrite (nothing in the business
/// layer changed):
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
/// UX (presentation only):
///
/// * One-tap per-student segmented control — حاضر (green) / چھٹی (amber) /
///   غیر حاضر (red) / تاخیر (blue, compact) — big touch targets.
/// * "سب کو حاضر کریں" (mark all present) quick action under the
///   class/date header.
/// * Sticky bottom bar with live counts and the primary
///   "حاضری محفوظ کریں" CTA with a saving state.
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

  /// Inline feedback banner — used only when there is no Scaffold ancestor
  /// to host a SnackBar (standalone / test usage). See [_snack].
  _Banner? _banner;

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

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    // The screen normally lives inside AppShell's Scaffold. When used
    // standalone (widget tests, shell-less deep links) there is no Scaffold
    // ancestor and showSnackBar would throw — fall back to an inline banner
    // so the feedback is never lost.
    if (Scaffold.maybeOf(context) != null) {
      showM360SnackBar(context, message, isError: isError);
      return;
    }
    // Inline banner persists until the next _snack call (no auto-dismiss:
    // a timed clear would race widget-test pumpAndSettle expectations).
    setState(() => _banner =
        _Banner(message, isError ? AppColors.error : AppColors.primaryDark));
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
      _snack(AppStrings.noActiveTenant, isError: true);
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
        _snack(AppStrings.saveFailed, isError: true);
      } else {
        setState(() => _edits = {});
        _snack(AppStrings.attendanceSaved);
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

    return ShellPageBody(
      actions: [
        M360IconButton(
          icon: Icons.refresh,
          tooltip: AppStrings.refresh,
          onPressed: _classId == null
              ? null
              : () => ref.invalidate(classAttendanceProvider(
                  AttendanceParams(classId: _classId!, date: _date))),
        ),
      ],
      // Sticky bottom bar (counts + save CTA) — thumb-zone, one-handed.
      bottomNavigationBar: _stickySaveBar(recordsAsync),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PageHeader(
              title: 'حاضری',
              description: 'طلبہ کی روزانہ حاضری درج کریں',
            ),
          ),
          if (pendingCount > 0) _offlineBanner(pendingCount),
          if (_banner != null) _inlineBanner(_banner!),
          if (tenantId == null)
            Expanded(child: _failClosed(AppStrings.noActiveTenant))
          else ...[
            _classSelector(ref),
            Expanded(child: _recordsArea(ref, recordsAsync)),
          ],
        ],
      ),
    );
  }

  /// Slim offline banner: N records waiting in the sync queue.
  Widget _offlineBanner(int count) {
    return Container(
      width: double.infinity,
      color: AppColors.warning,
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

  /// Inline feedback banner for Scaffold-less usage (see [_snack]).
  Widget _inlineBanner(_Banner banner) {
    return Container(
      width: double.infinity,
      color: banner.color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        banner.message,
        style: AppTypography.bodyMedium.copyWith(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Class selector: label for a single assignment, dropdown for many.
  /// The selection drives the roster query — picking a class re-keys
  /// [classAttendanceProvider] so only that class's roster is shown.
  Widget _classSelector(WidgetRef ref) {
    final async = ref.watch(teacherAssignedClassesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
        error: (_, __) => M360ErrorState(
          message: AppStrings.error,
          onRetry: () => ref.invalidate(teacherAssignedClassesProvider),
        ),
        data: (classes) {
          if (classes.isEmpty) return const SizedBox.shrink();
          if (classes.length == 1) {
            return M360Card(
              child: Row(
                children: [
                  const Icon(Icons.class_, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      classes.first.name,
                      style: AppTypography.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }
          // Guard: a revoked class id must never reach the dropdown value.
          final validValue =
              classes.any((c) => c.id == _classId) ? _classId : null;
          return M360Dropdown<String>(
            label: 'جماعت',
            prefixIcon: Icons.class_,
            items: [
              for (final c in classes)
                M360DropdownItem(value: c.id, label: c.name),
            ],
            value: validValue,
            onChanged: (v) => setState(() => _classId = v),
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
            : const M360LoadingState(),
        orElse: () => const M360LoadingState(),
      );
    }
    return recordsAsync.when(
      loading: () => const M360LoadingState(),
      error: (_, __) => M360ErrorState(
        message: AppStrings.error,
        onRetry: _classId == null
            ? () => ref.invalidate(teacherAssignedClassesProvider)
            : () => ref.invalidate(classAttendanceProvider(
                AttendanceParams(classId: _classId!, date: _date))),
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
    return M360EmptyState(
      icon: Icons.people_outline,
      title: message,
      description: '',
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
          M360TappableCard(
            onTap: _pickDate,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: M360SecondaryButton(
                  label: AppStrings.markAllPresent,
                  icon: Icons.done_all,
                  fullWidth: true,
                  onPressed: () => _bulkSet(base, AttendanceStatus.present),
                ),
              ),
              if (_edits.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: M360TertiaryButton(
                    label: AppStrings.clearEdits,
                    onPressed: _clearEdits,
                  ),
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
    final edited = _edits.containsKey(record.studentId);
    return M360Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      borderColor: color.withValues(alpha: edited ? 0.5 : 0.15),
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
          // Edited rows get a stronger border tint (see borderColor above).
          Row(
            children: [
              _statusSegment(record, status, AttendanceStatus.present, flex: 3),
              _statusSegment(record, status, AttendanceStatus.leave, flex: 3),
              _statusSegment(record, status, AttendanceStatus.absent, flex: 3),
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
            M360PrimaryButton(
              label: AppStrings.saveAttendance,
              icon: Icons.save,
              fullWidth: true,
              isLoading: _saving,
              onPressed: _saving ? null : () => _saveAttendance(base),
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

/// Simple value holder for the inline Scaffold-less feedback banner.
class _Banner {
  const _Banner(this.message, this.color);

  final String message;
  final Color color;
}
