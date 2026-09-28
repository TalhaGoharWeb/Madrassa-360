import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/student.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/student_provider.dart';
import '../../widgets/common/app_widgets.dart';
import '../students/student_dialogs.dart';
import '../students/student_profile_screen.dart';
import '../students/student_widgets.dart';

/// طلبہ کی فہرست — redesigned (presentation layer only)
///
/// Same providers, same filters dimensions, same create/edit/fee dialogs.
/// Row tap opens the student profile hub.
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

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(allStudentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.students, style: AppTypography.appBarTitle),
        actions: [
          IconButton(
            tooltip: 'تازہ کریں',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allStudentsProvider),
          ),
        ],
      ),
      body: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppColors.error),
              const SizedBox(height: 12),
              Text('طلباء لوڈ کرنے میں خطا',
                  style: AppTypography.labelNastaliq),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => ref.invalidate(allStudentsProvider),
                icon: const Icon(Icons.refresh),
                label: Text('دوبارہ کوشش کریں',
                    style: AppTypography.labelNastaliq),
              ),
            ],
          ),
        ),
        data: (students) => Column(
          children: [
            _HeaderRow(
              total: students.length,
              onAdd: () => StudentDialogs.showNewAdmission(context, ref),
            ),
            SearchField(
              controller: _searchController,
              hintText: 'نام، والد کا نام یا رول نمبر تلاش کریں…',
              onChanged: (_) => setState(() {}),
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
            Expanded(child: _contentBody(students: students)),
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
      return EmptyState(
        icon: Icons.person_off,
        title: 'کوئی طالب علم نہیں ملا',
        subtitle:
            searching ? 'تلاش یا فلٹر تبدیل کریں' : 'پہلا طالب علم شامل کریں',
        buttonText: searching ? null : 'نیا طالب علم',
        onButtonPressed: searching
            ? null
            : () => StudentDialogs.showNewAdmission(context, ref),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return _DesktopStudentTable(
            students: filtered,
            onEdit: (s) => StudentDialogs.showEditStudent(context, ref, s),
            onFee: (s) => StudentDialogs.showFeeCollection(context, ref, s),
          );
        }
        return _MobileStudentList(
          students: filtered,
          onEdit: (s) => StudentDialogs.showEditStudent(context, ref, s),
          onFee: (s) => StudentDialogs.showFeeCollection(context, ref, s),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header: title + prominent primary CTA
// ─────────────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  final int total;
  final VoidCallback onAdd;

  const _HeaderRow({required this.total, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('طلبہ', style: AppTypography.headingSmall),
                Text(
                  'کل $total طالب علم',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: Text('+ نیا طالب علم', style: AppTypography.buttonText),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
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
            child: TextButton(
              onPressed: onClear,
              child: Text('فلٹر صاف کریں', style: AppTypography.labelNastaliq),
            ),
          ),
        ),
      ],
    );
  }

  static String _shortClassLabel(String full) {
    // 'درجہ اولیٰ (اول سال)' -> 'درجہ اولیٰ'
    final idx = full.indexOf('(');
    return idx > 0 ? full.substring(0, idx).trim() : full;
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

// ─────────────────────────────────────────────────────────────
// Desktop: professional data table
// ─────────────────────────────────────────────────────────────

class _DesktopStudentTable extends ConsumerWidget {
  final List<Student> students;
  final ValueChanged<Student> onEdit;
  final ValueChanged<Student> onFee;

  const _DesktopStudentTable({
    required this.students,
    required this.onEdit,
    required this.onFee,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeStatusByStudent = _feeStatusByStudent(ref);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              AppColors.primary.withValues(alpha: 0.08),
            ),
            headingTextStyle: AppTypography.labelNastaliq.copyWith(
              color: AppColors.primaryDark,
            ),
            dataTextStyle: AppTypography.bodyMedium,
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('نام')),
              DataColumn(label: Text('رول نمبر')),
              DataColumn(label: Text('کلاس')),
              DataColumn(label: Text('حاضری')),
              DataColumn(label: Text('فیس کی حالت')),
              DataColumn(label: Text('اعمال')),
            ],
            rows: students.map((s) {
              final feeStatus = feeStatusByStudent[s.id];
              return DataRow(
                onSelectChanged: (_) => _openProfile(context, s),
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StudentAvatar(student: s, radius: 18),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                style: AppTypography.titleSmall
                                    .copyWith(fontSize: 15)),
                            Text('بن ${s.fatherName}',
                                style: AppTypography.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(s.rollNo.isEmpty ? '—' : s.rollNo)),
                  DataCell(Text(_FilterChips._shortClassLabel(s.className))),
                  DataCell(attendanceBadge(s.attendanceStatus)),
                  DataCell(feeStatus == null
                      ? Text('—', style: AppTypography.bodySmall)
                      : feeBadge(feeStatus)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'پروفائل',
                          icon: const Icon(Icons.visibility,
                              color: AppColors.primary),
                          onPressed: () => _openProfile(context, s),
                        ),
                        IconButton(
                          tooltip: 'ترمیم',
                          icon: const Icon(Icons.edit, color: AppColors.info),
                          onPressed: () => onEdit(s),
                        ),
                        IconButton(
                          tooltip: 'فیس وصول کریں',
                          icon: const Icon(Icons.receipt,
                              color: AppColors.success),
                          onPressed: () => onFee(s),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  static void _openProfile(BuildContext context, Student s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentProfileScreen(studentId: s.id),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Mobile: compact student cards
// ─────────────────────────────────────────────────────────────

class _MobileStudentList extends ConsumerWidget {
  final List<Student> students;
  final ValueChanged<Student> onEdit;
  final ValueChanged<Student> onFee;

  const _MobileStudentList({
    required this.students,
    required this.onEdit,
    required this.onFee,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeStatusByStudent = _feeStatusByStudent(ref);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90, top: 4),
      itemCount: students.length,
      itemBuilder: (context, index) {
        final s = students[index];
        final feeStatus = feeStatusByStudent[s.id];
        return AppCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentProfileScreen(studentId: s.id),
            ),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              StudentAvatar(student: s, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style:
                            AppTypography.labelNastaliq.copyWith(fontSize: 17)),
                    Text(
                      'بن ${s.fatherName} • رول: ${s.rollNo.isEmpty ? '—' : s.rollNo}',
                      style: AppTypography.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MiniTag(
                          label: _FilterChips._shortClassLabel(s.className),
                          color: AppColors.primary,
                        ),
                        attendanceBadge(s.attendanceStatus, compact: true),
                        if (feeStatus != null)
                          feeBadge(feeStatus, compact: true),
                        if (!s.isActive)
                          _MiniTag(label: 'غیر فعال', color: AppColors.error),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon:
                    const Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (value) {
                  if (value == 'edit') onEdit(s);
                  if (value == 'fee') onFee(s);
                  if (value == 'profile') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentProfileScreen(studentId: s.id),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Text('پروفائل دیکھیں',
                        style:
                            AppTypography.labelNastaliq.copyWith(fontSize: 15)),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('ترمیم',
                        style:
                            AppTypography.labelNastaliq.copyWith(fontSize: 15)),
                  ),
                  PopupMenuItem(
                    value: 'fee',
                    child: Text('فیس وصول کریں',
                        style:
                            AppTypography.labelNastaliq.copyWith(fontSize: 15)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
    );
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
