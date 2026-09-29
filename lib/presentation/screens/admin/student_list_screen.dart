import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/design/m360.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/attendance_status.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/student.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/student_provider.dart';
import '../students/student_dialogs.dart';
import '../students/student_profile_screen.dart';
import '../students/student_widgets.dart';

/// طلبہ کی فہرست — m360 redesign (Phase 10)
///
/// Same providers, same filter dimensions, same create/edit/fee dialogs.
/// Row actions open the student profile hub, the edit dialog, or the fee
/// collection flow. Rendered as an [AppShell] destination: no Scaffold,
/// no AppBar — [PageContainer]/[PageHeader] only.
class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  String _selectedClass = 'all';
  String _selectedStatus = 'all'; // all | active | inactive
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Back affordance for deep-pushed routes. Shell destinations get the
  /// shell's own back chevron, so this renders nothing for them.
  List<Widget> _withBack(BuildContext context, List<Widget> actions) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return [
      if (canPop)
        M360IconButton(
          icon: Icons.arrow_back,
          tooltip: 'واپس',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ...actions,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(allStudentsProvider);
    final total = studentsAsync.valueOrNull?.length;

    return PageContainer(
      // The whole page scrolls: the table's card list is shrink-wrapped and
      // cannot live inside a tight Expanded (it overflowed by 115px at
      // 360px with 15 students).
      scrollable: true,
      header: PageHeader(
        title: 'طلبہ',
        breadcrumb: 'منتظم',
        description: total == null
            ? 'طلبہ کی فہرست، تلاش اور فلٹر'
            : 'کل $total طالب علم — فہرست، تلاش اور فلٹر',
        actions: _withBack(context, [
          M360IconButton(
            icon: Icons.refresh,
            tooltip: 'تازہ کریں',
            onPressed: () => ref.invalidate(allStudentsProvider),
          ),
          M360PrimaryButton(
            label: 'نیا طالب علم',
            icon: Icons.person_add,
            onPressed: () => StudentDialogs.showNewAdmission(context, ref),
          ),
        ]),
      ),
      child: studentsAsync.when(
        loading: () => const M360LoadingState(),
        error: (e, _) => M360ErrorState(
          message: 'طلبہ لوڈ کرنے میں خطا ہوئی',
          onRetry: () => ref.invalidate(allStudentsProvider),
        ),
        data: (students) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: M360SearchField(
                controller: _searchController,
                hint: 'نام، والد کا نام یا رول نمبر تلاش کریں…',
                onChanged: (_) => setState(() {}),
              ),
            ),
            _FilterChips(
              selectedClass: _selectedClass,
              selectedStatus: _selectedStatus,
              onClassChanged: (v) => setState(() => _selectedClass = v),
              onStatusChanged: (v) => setState(() => _selectedStatus = v),
              onClear: () => setState(() {
                _selectedClass = 'all';
                _selectedStatus = 'all';
                _searchController.clear();
              }),
            ),
            _contentBody(students: students),
          ],
        ),
      ),
    );
  }

  /// Shared client-side filtering: class chip + status chip + search.
  List<Student> _applyFilters(List<Student> students) {
    var list = students;
    if (_selectedClass != 'all') {
      list = list.where((s) => s.className == _selectedClass).toList();
    }
    if (_selectedStatus == 'active') {
      list = list.where((s) => s.isActive).toList();
    } else if (_selectedStatus == 'inactive') {
      list = list.where((s) => !s.isActive).toList();
    }
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) {
        return s.name.toLowerCase().contains(q) ||
            s.fatherName.toLowerCase().contains(q) ||
            s.rollNo.toLowerCase().contains(q);
      }).toList();
    }
    return list;
  }

  Widget _contentBody({required List<Student> students}) {
    final filtered = _applyFilters(students);
    if (filtered.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty ||
          _selectedClass != 'all' ||
          _selectedStatus != 'all';
      return M360EmptyState(
        icon: Icons.person_off,
        title: 'کوئی طالب علم نہیں ملا',
        description: searching
            ? 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔'
            : 'پہلا طالب علم شامل کر کے شروع کریں۔',
        actionLabel: searching ? null : 'نیا طالب علم',
        onAction: searching
            ? null
            : () => StudentDialogs.showNewAdmission(context, ref),
      );
    }
    return _StudentTable(students: filtered);
  }
}

// ─────────────────────────────────────────────────────────────
// Responsive register: sortable table on wide screens, card list
// on narrow ones (handled inside [M360ResponsiveTable]).
// ─────────────────────────────────────────────────────────────

class _StudentTable extends ConsumerWidget {
  final List<Student> students;

  const _StudentTable({required this.students});

  static void _openProfile(BuildContext context, Student s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentProfileScreen(studentId: s.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeStatusByStudent = _feeStatusByStudent(ref);
    return M360ResponsiveTable<Student>(
      rows: students,
      rowId: (s) => s.id,
      pageSize: 25,
      emptyIcon: Icons.person_off,
      emptyTitle: 'کوئی طالب علم نہیں ملا',
      emptyDescription: 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔',
      columns: [
        M360TableColumn<Student>(
          title: 'نام',
          value: (s) => s.name,
          sortable: true,
          sortKey: (s) => s.name,
          cell: (s) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudentAvatar(student: s, radius: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: AppTypography.titleSmall.copyWith(fontSize: 15)),
                    Text('بن ${s.fatherName}', style: AppTypography.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        M360TableColumn<Student>(
          title: 'رول نمبر',
          value: (s) => s.rollNo.isEmpty ? '—' : s.rollNo,
          cell: (s) => M360LatinText(s.rollNo.isEmpty ? '—' : s.rollNo),
        ),
        M360TableColumn<Student>(
          title: 'کلاس',
          value: (s) => _shortClassLabel(s.className),
        ),
        M360TableColumn<Student>(
          title: 'حاضری',
          value: (s) => _attendanceLabel(s.attendanceStatus),
          cell: (s) => M360StatusChip.attendance(
            attendance: _mapAttendance(s.attendanceStatus),
          ),
        ),
        M360TableColumn<Student>(
          title: 'فیس',
          value: (s) {
            final fee = feeStatusByStudent[s.id];
            return fee == null ? '—' : _feeLabel(fee);
          },
          cell: (s) {
            final fee = feeStatusByStudent[s.id];
            return fee == null
                ? Text('—', style: AppTypography.bodySmall)
                : M360StatusChip.fee(fee: _mapFee(fee));
          },
        ),
      ],
      rowActions: [
        M360TableAction<Student>(
          label: 'پروفائل دیکھیں',
          icon: Icons.visibility,
          onTap: (s) => _openProfile(context, s),
        ),
        M360TableAction<Student>(
          label: 'ترمیم',
          icon: Icons.edit,
          onTap: (s) => StudentDialogs.showEditStudent(context, ref, s),
        ),
        M360TableAction<Student>(
          label: 'فیس وصول کریں',
          icon: Icons.receipt,
          onTap: (s) => StudentDialogs.showFeeCollection(context, ref, s),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Filter chips: جماعت + حالت (کلاس، درجہ/حالت dimensions)
// ─────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final String selectedClass;
  final String selectedStatus;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onClear;

  const _FilterChips({
    required this.selectedClass,
    required this.selectedStatus,
    required this.onClassChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final classChips = <Map<String, String>>[
      {'id': 'all', 'label': 'سب جماعتیں'},
      for (final c in StudentDialogs.classOptions)
        {'id': c, 'label': _shortClassLabel(c)},
    ];
    final statusChips = <Map<String, String>>[
      {'id': 'all', 'label': 'سب'},
      {'id': 'active', 'label': 'فعال'},
      {'id': 'inactive', 'label': 'غیر فعال'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChipRow(
          title: 'جماعت',
          chips: classChips,
          selectedId: selectedClass,
          onChanged: onClassChanged,
        ),
        _ChipRow(
          title: 'حالت',
          chips: statusChips,
          selectedId: selectedStatus,
          onChanged: onStatusChanged,
          statusColors: const {
            'active': AppColors.success,
            'inactive': AppColors.error
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: M360TertiaryButton(
              label: 'فلٹر صاف کریں',
              onPressed: onClear,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  final String title;
  final List<Map<String, String>> chips;
  final String selectedId;
  final ValueChanged<String> onChanged;
  final Map<String, Color> statusColors;

  const _ChipRow({
    required this.title,
    required this.chips,
    required this.selectedId,
    required this.onChanged,
    this.statusColors = const {},
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: Text(title,
                style: AppTypography.labelNastaliq.copyWith(fontSize: 15)),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: chips.length,
              itemBuilder: (context, index) {
                final chip = chips[index];
                final isSelected = selectedId == chip['id'];
                final accent = statusColors[chip['id']] ?? AppColors.primary;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(
                    label: Text(chip['label']!),
                    selected: isSelected,
                    onSelected: (_) => onChanged(chip['id']!),
                    selectedColor: accent.withValues(alpha: 0.18),
                    checkmarkColor: accent,
                    labelStyle: AppTypography.labelNastaliq.copyWith(
                      fontSize: 14,
                      color: isSelected ? accent : AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 'درجہ اولیٰ (اول سال)' -> 'درجہ اولیٰ'
String _shortClassLabel(String full) {
  final idx = full.indexOf('(');
  return idx > 0 ? full.substring(0, idx).trim() : full;
}

// ─────────────────────────────────────────────────────────────
// Status mapping onto the canonical m360 chips
// ─────────────────────────────────────────────────────────────

M360AttendanceStatus _mapAttendance(AttendanceStatus s) {
  switch (s) {
    case AttendanceStatus.present:
      return M360AttendanceStatus.present;
    case AttendanceStatus.absent:
      return M360AttendanceStatus.absent;
    case AttendanceStatus.leave:
      return M360AttendanceStatus.leave;
    case AttendanceStatus.late:
      return M360AttendanceStatus.late;
  }
}

String _attendanceLabel(AttendanceStatus s) {
  switch (s) {
    case AttendanceStatus.present:
      return 'حاضر';
    case AttendanceStatus.absent:
      return 'غیر حاضر';
    case AttendanceStatus.leave:
      return 'رخصت';
    case AttendanceStatus.late:
      return 'تاخیر';
  }
}

M360FeeStatus _mapFee(FeeStatus s) {
  switch (s) {
    case FeeStatus.paid:
      return M360FeeStatus.paid;
    case FeeStatus.partial:
      return M360FeeStatus.partial;
    case FeeStatus.pending:
      return M360FeeStatus.due;
    case FeeStatus.pastDue:
      return M360FeeStatus.overdue;
  }
}

String _feeLabel(FeeStatus s) {
  switch (s) {
    case FeeStatus.paid:
      return 'ادا شدہ';
    case FeeStatus.partial:
      return 'جزوی';
    case FeeStatus.pending:
      return 'واجب الادا';
    case FeeStatus.pastDue:
      return 'بقایا';
  }
}

// ─────────────────────────────────────────────────────────────
// Fee status aggregation (derived from existing allFeesProvider)
// ─────────────────────────────────────────────────────────────

/// Derives one representative fee status per student from the existing
/// fee records: worst outstanding status wins (واجب الادا > جزوی >
/// زیر التواء > ادا شدہ). Students with no fee records map to null.
Map<String, FeeStatus> _feeStatusByStudent(WidgetRef ref) {
  final fees = ref.watch(allFeesProvider).valueOrNull ?? const <Fee>[];
  final result = <String, FeeStatus>{};
  for (final fee in fees) {
    final current = result[fee.studentId];
    result[fee.studentId] = _worseStatus(current, fee.status);
  }
  return result;
}

FeeStatus _worseStatus(FeeStatus? a, FeeStatus b) {
  int rank(FeeStatus s) => switch (s) {
        FeeStatus.pastDue => 4,
        FeeStatus.partial => 3,
        FeeStatus.pending => 2,
        FeeStatus.paid => 1,
      };
  if (a == null) return b;
  return rank(b) > rank(a) ? b : a;
}
