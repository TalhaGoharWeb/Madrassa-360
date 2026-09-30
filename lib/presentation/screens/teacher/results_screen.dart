import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madrasa_360/core/design/m360.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/reports/documents/result_documents.dart';
import '../../../core/reports/report_branding.dart';
import '../../../core/reports/urdu_pdf.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/widgets/tenant_logo.dart';
import '../../../data/models/result.dart';
import '../../../data/models/student.dart';
import '../../../providers/result_provider.dart';
import '../../../providers/teacher_portal_provider.dart';
import '../../shell/shell_page_body.dart';

/// نتائج کی سکرین
/// Results Screen — نتائج دیکھیں اور نئے نتائج درج کریں.
///
/// Phase 10 (m360): visual/UX layer only — same providers, same queries,
/// same save/delete flows. Shell destination: no Scaffold of its own;
/// [ShellPageBody] hosts the tab bar (Phase 8 hostel pattern) and the
/// [PageHeader] sits above the tab views.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Id of the teacher's assigned class being filtered ('' = all assigned).
  /// Phase 4: only classes from `teacherAssignedClassesProvider` are ever
  /// offered — a teacher cannot filter by (or see) unassigned classes.
  String _selectedClassId = '';

  /// Id of the teacher's assigned class used by the ENTRY tab ('' = none).
  /// Phase 6 (mock purge): entry cards render the real roster of this
  /// class — never a hard-coded name list.
  String _entryClassId = '';

  /// Exam type picked in the ENTRY tab (null = not picked yet).
  String? _entryExamType;

  /// Entry-tab save in progress (drives the primary button's spinner).
  bool _savingEntry = false;

  /// Marks controllers keyed by '<studentId>::<subject>'.
  final Map<String, TextEditingController> _marksControllers = {};

  TextEditingController _marksController(String studentId, String subject) {
    final key = '$studentId::$subject';
    return _marksControllers.putIfAbsent(key, TextEditingController.new);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _marksControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Subjects for the ENTRY tab, derived from the teacher's REAL class
  /// assignments ([TeacherClassAssignment.subject]) for the selected entry
  /// class — distinct, non-empty, in assignment order. Never a hard-coded
  /// list: when the teacher has no subject recorded, the entry tab shows
  /// an honest empty state instead.
  List<String> _entrySubjects(List<TeacherClassAssignment> assignments) {
    final seen = <String>[];
    for (final a in assignments) {
      if (a.classId != _entryClassId) continue;
      final subject = a.subject.trim();
      if (subject.isNotEmpty && !seen.contains(subject)) seen.add(subject);
    }
    return seen;
  }

  @override
  Widget build(BuildContext context) {
    return ShellPageBody(
      tabBar: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTypography.labelLarge,
        tabs: const [
          Tab(text: 'نتائج'),
          Tab(text: 'نتیجہ درج کریں'),
        ],
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PageHeader(
              title: 'نتائج',
              description: 'امتحانی نتائج دیکھیں اور نئے نتائج درج کریں',
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildResultsTab(),
                _buildEntryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Results tab — class-filtered result cards
  // ─────────────────────────────────────────────────────────────

  Widget _buildResultsTab() {
    return Consumer(
      builder: (context, ref, _) {
        final classesAsync = ref.watch(teacherAssignedClassesProvider);
        final resultsAsync = ref.watch(allResultsProvider);

        if (classesAsync.isLoading || resultsAsync.isLoading) {
          return const M360LoadingState();
        }
        if (resultsAsync.hasError) {
          return M360ErrorState(
            message: 'نتائج لوڈ کرنے میں خطا',
            onRetry: () {
              ref.invalidate(allResultsProvider);
              ref.invalidate(teacherAssignedClassesProvider);
            },
          );
        }

        // The ONLY scope this teacher may see: their assigned classes and
        // the students inside them. Results for any other student are
        // dropped client-side (RLS enforces the same server-side).
        final classes = classesAsync.valueOrNull ?? const <AssignedClass>[];
        final allowedStudentIds = <String>{};
        final studentClassIds = <String, String>{};
        for (final c in classes) {
          final students =
              ref.watch(teacherClassStudentsProvider(c.id)).valueOrNull ??
                  const <Student>[];
          for (final s in students) {
            allowedStudentIds.add(s.id);
            studentClassIds[s.id] = c.id;
          }
        }

        // A revoked class id must never silently filter everything out —
        // fall back to "all assigned" when the selection is stale.
        final effectiveSelected = classes.any((c) => c.id == _selectedClassId)
            ? _selectedClassId
            : '';
        final filtered = (resultsAsync.valueOrNull ?? const <StudentResult>[])
            .where((r) => allowedStudentIds.contains(r.studentId))
            .where((r) =>
                effectiveSelected.isEmpty ||
                studentClassIds[r.studentId] == effectiveSelected)
            .toList();

        return Column(
          children: [
            // Class Filter (assigned classes only)
            _buildClassFilter(classes, effectiveSelected),

            // Results List
            Expanded(
              child: filtered.isEmpty
                  ? const M360EmptyState(
                      icon: Icons.assessment_outlined,
                      title: 'کوئی نتیجہ نہیں',
                      description: 'ابھی کوئی نتیجہ دستیاب نہیں',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _buildResultCard(filtered[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Class filter chips — built from the teacher's assignments only.
  /// Tapping the active chip again resets to "all assigned".
  Widget _buildClassFilter(List<AssignedClass> classes, String selected) {
    // Horizontal scroll + Row (instead of a fixed-height ListView) so the
    // strip grows naturally with large text scales instead of clipping.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (int index = 0; index < classes.length + 1; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Builder(builder: (context) {
              final isAll = index == 0;
              final classId = isAll ? '' : classes[index - 1].id;
              final className =
                  isAll ? 'تمام جماعتیں' : classes[index - 1].name;
              final isSelected = selected == classId;
              return FilterChip(
                label: Text(className),
                selected: isSelected,
                onSelected: (_) {
                  // Selection state → filtered query: the results list
                  // rebuilds from `studentClassIds` against the new id.
                  setState(() => _selectedClassId = isSelected ? '' : classId);
                },
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
                checkmarkColor: AppColors.primary,
                labelStyle: AppTypography.labelMedium.copyWith(
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard(StudentResult result) {
    return M360TappableCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _showResultDetails(result),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    result.studentName.isNotEmpty
                        ? result.studentName.substring(0, 1)
                        : '؟',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.studentName,
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      '${result.className} - ${result.examName}',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              _buildGradeBadge(result.grade, result.percentage),
            ],
          ),

          const Divider(height: 24),

          // Subject Preview (First 3 subjects)
          ...result.subjects.take(3).map((subject) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildSubjectRow(subject),
            );
          }),

          if (result.subjects.length > 3)
            Center(
              child: Text(
                'مزید ${result.subjects.length - 3} مضامین...',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectRow(SubjectResult subject) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            subject.subject,
            style: AppTypography.bodyMedium,
          ),
        ),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: subject.percentage / 100,
              backgroundColor: AppColors.background,
              color: _getGradeColor(subject.grade),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // No fixed width: the marks text sizes itself so it never clips
        // or wraps mid-number at large text scales.
        M360LatinText(
          '${subject.marksObtained.toInt()}/${subject.totalMarks.toInt()}',
        ),
      ],
    );
  }

  Widget _buildGradeBadge(String grade, double percentage) {
    final color = _getGradeColor(grade);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            grade,
            style: AppTypography.headingSmall.copyWith(
              color: color,
            ),
          ),
          Text(
            '٪${percentage.toInt()}',
            style: AppTypography.labelSmall.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Grade → semantic color. Complete mapping for all six grades the
  /// result model produces: distinction grades (الف+، الف) → success,
  /// pass grades (ب → primary, ج → warning), fail grades (د، فیل) →
  /// error. Unknown labels fall back to muted text (never invented).
  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'الف+':
      case 'الف':
        return AppColors.success;
      case 'ب':
        return AppColors.primary;
      case 'ج':
        return AppColors.warning;
      case 'د':
      case 'فیل':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Result details sheet — view, print, share, delete
  // ─────────────────────────────────────────────────────────────

  void _showResultDetails(StudentResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Result Card Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Phase 4 — tenant name (was hard-coded institution).
                        TenantNameText(
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'نتیجہ کارڈ',
                          style: AppTypography.headingMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          result.examName,
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Student Info
                  M360Card(
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              result.studentName.isNotEmpty
                                  ? result.studentName.substring(0, 1)
                                  : '؟',
                              style: AppTypography.headingSmall.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result.studentName,
                                style: AppTypography.titleLarge,
                              ),
                              Text(
                                result.className,
                                style: AppTypography.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        _buildGradeBadge(result.grade, result.percentage),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Subject Results
                  const M360SectionHeader(title: 'مضامین کی تفصیل'),
                  const SizedBox(height: 12),

                  // Subject Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'مضمون',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'نمبر',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.primary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'گریڈ',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.primary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Subject Rows
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: result.subjects.map((subject) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: result.subjects.last != subject
                                  ? const BorderSide(color: AppColors.divider)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  subject.subject,
                                  style: AppTypography.bodyMedium,
                                ),
                              ),
                              Expanded(
                                child: M360LatinText(
                                  '${subject.marksObtained.toInt()}/${subject.totalMarks.toInt()}',
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getGradeColor(subject.grade)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    subject.grade,
                                    style: AppTypography.labelMedium.copyWith(
                                      color: _getGradeColor(subject.grade),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Print Button
                  M360SecondaryButton(
                    label: 'نتیجہ پرنٹ کریں',
                    icon: Icons.print,
                    fullWidth: true,
                    onPressed: () => _showPrintDialog(sheetContext),
                  ),
                  const SizedBox(height: 12),
                  M360SecondaryButton(
                    label: 'شیئر کریں',
                    icon: Icons.share,
                    fullWidth: true,
                    onPressed: () => _shareResult(result),
                  ),
                  const SizedBox(height: 12),
                  M360DangerButton(
                    label: 'امتحان حذف کریں',
                    icon: Icons.delete_outline,
                    fullWidth: true,
                    onPressed: () => _deleteExam(sheetContext, result),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Deletes the exam behind [result] after an explicit confirmation.
  /// Local-first soft delete via [ResultNotifier.deleteExam]; the sheet
  /// closes, a snackbar confirms, and provider invalidation refreshes
  /// the results list.
  Future<void> _deleteExam(
      BuildContext sheetContext, StudentResult result) async {
    final confirmed = await showM360ConfirmDialog(
      sheetContext,
      title: 'امتحان حذف کریں',
      message:
          '«${result.examName}» حذف کر دیا جائے گا — اس امتحان کے تمام طلبہ کے نتائج بھی ہٹ جائیں گے۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(resultNotifierProvider.notifier).deleteExam(result.examId);
      if (!mounted) return;
      if (!sheetContext.mounted) return;
      Navigator.of(sheetContext).pop(); // close the details sheet
      showM360SnackBar(context, 'امتحان حذف کر دیا گیا');
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'امتحان حذف کرنے میں خطا', isError: true);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Entry tab — class + exam type + per-student subject marks
  // ─────────────────────────────────────────────────────────────

  Widget _buildEntryTab() {
    return Consumer(
      builder: (context, ref, _) {
        final classesAsync = ref.watch(teacherAssignedClassesProvider);
        final assignmentsAsync = ref.watch(teacherAssignmentsProvider);

        if (classesAsync.isLoading || assignmentsAsync.isLoading) {
          return const M360LoadingState();
        }
        if (classesAsync.hasError || assignmentsAsync.hasError) {
          return M360ErrorState(
            message: 'جماعتیں لوڈ کرنے میں خطا',
            onRetry: () {
              ref.invalidate(teacherAssignedClassesProvider);
              ref.invalidate(teacherAssignmentsProvider);
            },
          );
        }

        final classes = classesAsync.valueOrNull ?? const <AssignedClass>[];
        final assignments =
            assignmentsAsync.valueOrNull ?? const <TeacherClassAssignment>[];
        // Phase 4: only the teacher's assigned classes are offered.
        final validEntryValue =
            classes.any((c) => c.id == _entryClassId) ? _entryClassId : null;
        final subjects = _entrySubjects(assignments);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Class + exam type selection
              M360Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const M360SectionHeader(title: 'جماعت اور امتحان'),
                    const SizedBox(height: 12),
                    M360Dropdown<String>(
                      label: 'جماعت منتخب کریں',
                      items: [
                        for (final c in classes)
                          M360DropdownItem(value: c.id, label: c.name),
                      ],
                      value: validEntryValue,
                      onChanged: (v) => setState(() => _entryClassId = v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    M360Dropdown<String>(
                      label: 'امتحان کی قسم',
                      items: const [
                        M360DropdownItem(
                            value: 'ماہانہ امتحان', label: 'ماہانہ امتحان'),
                        M360DropdownItem(
                            value: 'ہفتہ وار ٹیسٹ', label: 'ہفتہ وار ٹیسٹ'),
                        M360DropdownItem(
                            value: 'سالانہ امتحان', label: 'سالانہ امتحان'),
                      ],
                      value: _entryExamType,
                      onChanged: (v) => setState(() => _entryExamType = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Student Entry Cards — real roster of the selected class,
              // subjects from the teacher's assignments (never hard-coded).
              const M360SectionHeader(title: 'طلباء کے نمبرات'),
              const SizedBox(height: 12),

              if (_entryClassId.isEmpty)
                const M360EmptyState(
                  icon: Icons.class_outlined,
                  title: 'جماعت منتخب کریں',
                  description: 'نمبرات درج کرنے کے لیے پہلے جماعت منتخب کریں',
                )
              else if (subjects.isEmpty)
                const M360EmptyState(
                  icon: Icons.subject_outlined,
                  title: 'کوئی مضمون درج نہیں',
                  description:
                      'اس جماعت کے لیے آپ کی اسائنمنٹ میں کوئی مضمون درج نہیں — منتظم سے رابطہ کریں',
                )
              else
                Consumer(
                  builder: (context, ref, _) {
                    final studentsAsync =
                        ref.watch(teacherClassStudentsProvider(_entryClassId));
                    return studentsAsync.when(
                      loading: () => const M360LoadingState(),
                      error: (_, __) => M360ErrorState(
                        message: 'طلباء لوڈ کرنے میں خطا',
                        onRetry: () => ref.invalidate(
                            teacherClassStudentsProvider(_entryClassId)),
                      ),
                      data: (students) => students.isEmpty
                          ? const M360EmptyState(
                              icon: Icons.people_outline,
                              title: 'کوئی طالب علم نہیں',
                              description:
                                  'اس جماعت میں کوئی طالب علم درج نہیں',
                            )
                          : Column(
                              children: [
                                for (final s in students)
                                  _buildStudentEntryCard(s, subjects),
                              ],
                            ),
                    );
                  },
                ),

              const SizedBox(height: 24),

              // Save — the single primary CTA of this screen (orange).
              M360PrimaryButton(
                label: 'نتائج محفوظ کریں',
                icon: Icons.save,
                fullWidth: true,
                isLoading: _savingEntry,
                onPressed:
                    (_entryClassId.isEmpty || subjects.isEmpty || _savingEntry)
                        ? null
                        : _saveEntryResults,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentEntryCard(Student student, List<String> subjects) {
    final name = student.name;
    final rollNo = student.rollNo;
    return M360Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name.substring(0, 1) : '؟',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTypography.titleMedium),
                    Text(
                      'رول نمبر: $rollNo',
                      style: AppTypography.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Subject Input Fields — one per assigned subject; controllers
          // captured per student so the save button can persist real marks.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final subject in subjects)
                SizedBox(
                  width: 104,
                  child: _buildMarksInput(student.id, subject),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarksInput(String studentId, String subject) {
    return M360TextField(
      label: subject,
      hint: '0',
      controller: _marksController(studentId, subject),
      keyboardType: TextInputType.number,
    );
  }

  /// Persists the entry tab: creates the exam header (class + exam type
  /// are required) and upserts one SubjectResult row per student ×
  /// subject — all tenant-scoped through [ResultNotifier].
  Future<void> _saveEntryResults() async {
    final classId = _entryClassId;
    final examType = _entryExamType;
    if (classId.isEmpty || examType == null) {
      showM360SnackBar(
        context,
        'براہ کرم جماعت اور امتحان کی قسم منتخب کریں',
        isError: true,
      );
      return;
    }
    final subjects = _entrySubjects(
        ref.read(teacherAssignmentsProvider).valueOrNull ??
            const <TeacherClassAssignment>[]);
    if (subjects.isEmpty) {
      showM360SnackBar(
        context,
        'اس جماعت کے لیے کوئی مضمون درج نہیں',
        isError: true,
      );
      return;
    }
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      showM360SnackBar(context, 'کوئی فعال ادارہ نہیں', isError: true);
      return;
    }
    final classes = ref.read(teacherAssignedClassesProvider).valueOrNull ??
        const <AssignedClass>[];
    String className = '';
    for (final c in classes) {
      if (c.id == classId) className = c.name;
    }
    final students =
        ref.read(teacherClassStudentsProvider(classId)).valueOrNull ??
            const <Student>[];

    final marks = <({String studentId, String subject, double value})>[];
    for (final s in students) {
      for (final subject in subjects) {
        final text = _marksControllers['${s.id}::$subject']?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final value = double.tryParse(text);
        if (value == null || value < 0) continue;
        marks.add((studentId: s.id, subject: subject, value: value));
      }
    }
    if (marks.isEmpty) {
      showM360SnackBar(context, 'کوئی نمبر درج نہیں کیے گئے', isError: true);
      return;
    }

    setState(() => _savingEntry = true);
    try {
      final notifier = ref.read(resultNotifierProvider.notifier);
      final now = DateTime.now();
      final examName = '$examType — $className';
      // Reuse the existing exam header for this class + exam type instead
      // of creating a duplicate header on every save.
      final existingExams = await ref.read(allExamsProvider.future);
      Exam? exam;
      for (final e in existingExams) {
        if (e.classId == classId && e.name == examName) {
          exam = e;
          break;
        }
      }
      exam ??= await notifier.createExam(
        name: examName,
        classId: classId,
        examDate:
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        totalMarks: subjects.length * 100,
      );
      // Reuse existing result row ids so re-saving updates the same rows
      // instead of duplicating them.
      final resultIds = <String, Map<String, String>>{};
      try {
        final existing = await ref.read(examResultsProvider(exam.id).future);
        for (final sr in existing) {
          for (final sub in sr.subjects) {
            (resultIds[sr.studentId] ??= {})[sub.subject] = sub.id;
          }
        }
      } catch (_) {
        // Prefill is best-effort; new rows still save correctly.
      }
      for (final m in marks) {
        final rowId = resultIds[m.studentId]?[m.subject] ?? const Uuid().v4();
        await notifier.save(SubjectResult(
          id: rowId,
          tenantId: tenantId,
          examId: exam.id,
          studentId: m.studentId,
          subject: m.subject,
          marksObtained: m.value,
          totalMarks: 100,
        ));
      }
      for (final c in _marksControllers.values) {
        c.clear();
      }
      if (!mounted) return;
      showM360SnackBar(context, '${marks.length} نتائج محفوظ ہو گئے');
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'نتائج محفوظ کرنے میں خطا', isError: true);
    } finally {
      if (mounted) setState(() => _savingEntry = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Print / share (report pipeline unchanged)
  // ─────────────────────────────────────────────────────────────

  void _showPrintDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => M360Dialog(
        title: 'نتیجہ پرنٹ کریں',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'براہ کرم پرنٹ کی قسم منتخب کریں:',
              style: AppTypography.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildPrintOption(
              icon: Icons.person,
              title: 'کل طلباء کے نتائج',
              subtitle: 'تمام طلباء کے نتائج پرنٹ کریں',
              onTap: () {
                _printResults('all');
                Navigator.pop(dialogContext);
              },
            ),
            const SizedBox(height: 12),
            _buildPrintOption(
              icon: Icons.star,
              title: 'ممتاز طلباء',
              subtitle: '90% سے زیادہ نمبر والے طلباء',
              onTap: () {
                _printResults('excellent');
                Navigator.pop(dialogContext);
              },
            ),
            const SizedBox(height: 12),
            _buildPrintOption(
              icon: Icons.warning,
              iconColor: AppColors.warning,
              title: 'ناکام طلباء',
              subtitle: '50% سے کم نمبر والے طلباء',
              onTap: () {
                _printResults('failed');
                Navigator.pop(dialogContext);
              },
            ),
          ],
        ),
        actions: [
          M360TertiaryButton(
            label: 'منسوخ کریں',
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  Widget _buildPrintOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return M360TappableCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            icon,
            color: iconColor ?? AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyLarge
                      .copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_left,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  /// Shares one student's result card as a PDF through the system
  /// share sheet.
  Future<void> _shareResult(StudentResult result) async {
    try {
      final tenantId = ref.read(currentTenantIdProvider);
      final db = ref.read(appDatabaseProvider);
      final branding = await loadReportBranding(db, tenantId ?? '');
      final bytes = await ResultDocuments.resultCard(
        branding: branding,
        urdu: UrduPdf(),
        result: result,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'result_${result.studentId}.pdf',
      );
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'شیئر کرنے میں خرابی', isError: true);
    }
  }

  /// Prints the teacher-scoped results list (all / excellent / failed)
  /// as a branded Urdu PDF.
  Future<void> _printResults(String type) async {
    final classes = ref.read(teacherAssignedClassesProvider).valueOrNull ??
        const <AssignedClass>[];
    final allowed = <String>{};
    for (final c in classes) {
      final students =
          ref.read(teacherClassStudentsProvider(c.id)).valueOrNull ??
              const <Student>[];
      for (final s in students) {
        allowed.add(s.id);
      }
    }
    final all =
        ref.read(allResultsProvider).valueOrNull ?? const <StudentResult>[];
    var list = all.where((r) => allowed.contains(r.studentId)).toList();
    late final String titleUr;
    late final String titleEn;
    switch (type) {
      case 'excellent':
        list = list.where((r) => r.percentage >= 90).toList();
        titleUr = 'ممتاز طلباء کے نتائج';
        titleEn = 'Excellent results';
      case 'failed':
        list = list.where((r) => r.percentage < 50).toList();
        titleUr = 'ناکام طلباء کے نتائج';
        titleEn = 'Failed students results';
      default:
        titleUr = 'کل طلباء کے نتائج';
        titleEn = 'All results';
    }
    try {
      final tenantId = ref.read(currentTenantIdProvider);
      final db = ref.read(appDatabaseProvider);
      final branding = await loadReportBranding(db, tenantId ?? '');
      final bytes = await ResultDocuments.resultsSummary(
        branding: branding,
        urdu: UrduPdf(),
        titleUr: titleUr,
        titleEn: titleEn,
        results: list,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'پرنٹ میں خرابی', isError: true);
    }
  }
}
