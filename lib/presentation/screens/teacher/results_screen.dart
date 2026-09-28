import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/reports/documents/result_documents.dart';
import '../../../core/reports/report_branding.dart';
import '../../../core/reports/urdu_pdf.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../data/models/result.dart';
import '../../../data/models/student.dart';
import '../../../providers/result_provider.dart';
import '../../../core/widgets/tenant_logo.dart';
import '../../../providers/teacher_portal_provider.dart';
import '../../widgets/common/app_widgets.dart';

/// نتائج کی سکرین
/// Results Screen with Grades and Result Cards
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
  /// class — never the old hard-coded name list.
  String _entryClassId = '';

  /// Exam type picked in the ENTRY tab (null = not picked yet).
  String? _entryExamType;

  /// Fixed subject set for the entry tab (each out of 100).
  static const _entrySubjects = ['قرآن', 'حدیث', 'فقہ'];

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.results),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelStyle: AppTypography.labelLarge,
          tabs: const [
            Tab(text: 'نتائج'),
            Tab(text: 'نتیجہ درج کریں'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildResultsTab(),
          _buildEntryTab(),
        ],
      ),
    );
  }

  Widget _buildResultsTab() {
    return Consumer(
      builder: (context, ref, _) {
        final classesAsync = ref.watch(teacherAssignedClassesProvider);
        final resultsAsync = ref.watch(allResultsProvider);

        if (classesAsync.isLoading || resultsAsync.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (resultsAsync.hasError) {
          return Center(
            child:
                Text('نتائج لوڈ کرنے میں خطا', style: AppTypography.bodyMedium),
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

        final filtered = (resultsAsync.valueOrNull ?? const <StudentResult>[])
            .where((r) => allowedStudentIds.contains(r.studentId))
            .where((r) =>
                _selectedClassId.isEmpty ||
                studentClassIds[r.studentId] == _selectedClassId)
            .toList();

        return Column(
          children: [
            // Class Filter (assigned classes only)
            _buildClassFilter(classes),

            // Results List
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.assessment,
                      title: 'کوئی نتیجہ نہیں',
                      subtitle: 'ابھی کوئی نتیجہ دستیاب نہیں',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
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
  Widget _buildClassFilter(List<AssignedClass> classes) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: classes.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final classId = isAll ? '' : classes[index - 1].id;
          final className = isAll ? 'تمام جماعتیں' : classes[index - 1].name;
          final isSelected = _selectedClassId == classId;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(className),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedClassId = classId);
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: AppTypography.labelMedium.copyWith(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultCard(StudentResult result) {
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    result.studentName.substring(0, 1),
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
        SizedBox(
          width: 50,
          child: Text(
            '${subject.marksObtained.toInt()}/${subject.totalMarks.toInt()}',
            style: AppTypography.labelMedium.copyWith(
              color: _getGradeColor(subject.grade),
            ),
            textAlign: TextAlign.left,
          ),
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

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'الف':
        return AppColors.success;
      case 'ب':
        return AppColors.primary;
      case 'ج':
        return AppColors.warning;
      case 'د':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  void _showResultDetails(StudentResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
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
                  AppCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Row(
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
                                  result.studentName.substring(0, 1),
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
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Subject Results
                  Text(
                    'مضامین کی تفصیل',
                    style: AppTypography.titleMedium,
                  ),
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
                                child: Text(
                                  '${subject.marksObtained.toInt()}/${subject.totalMarks.toInt()}',
                                  style: AppTypography.bodyMedium,
                                  textAlign: TextAlign.center,
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showPrintDialog(context),
                      icon: const Icon(Icons.print),
                      label: const Text('نتیجہ پرنٹ کریں'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _shareResult(result),
                      icon: const Icon(Icons.share),
                      label: const Text('شیئر کریں'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEntryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class Selection
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'جماعت منتخب کریں',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: 12),
                // Phase 4: only the teacher's assigned classes are offered.
                // Phase 6: the selection actually drives the roster below.
                Consumer(
                  builder: (context, ref, _) {
                    final classes =
                        ref.watch(teacherAssignedClassesProvider).valueOrNull ??
                            const <AssignedClass>[];
                    final nameToId = <String, String>{
                      for (final c in classes) c.name: c.id
                    };
                    String? selectedName;
                    for (final c in classes) {
                      if (c.id == _entryClassId) selectedName = c.name;
                    }
                    return _buildDropdownField(
                      hint: 'جماعت',
                      items: classes.map((c) => c.name).toList(),
                      value: selectedName,
                      onChanged: (name) => setState(() => _entryClassId =
                          name == null ? '' : (nameToId[name] ?? '')),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildDropdownField(
                  hint: 'امتحان کی قسم',
                  items: const [
                    'ماہانہ امتحان',
                    'ہفتہ وار ٹیسٹ',
                    'سالانہ امتحان'
                  ],
                  value: _entryExamType,
                  onChanged: (v) => setState(() => _entryExamType = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Student Entry Cards — real roster of the selected class.
          Text(
            'طلباء کے نمبرات',
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: 12),

          if (_entryClassId.isEmpty)
            _buildEmptyState(
                'براہ کرم پہلے جماعت منتخب کریں', Icons.class_outlined)
          else
            Consumer(
              builder: (context, ref, _) {
                final studentsAsync =
                    ref.watch(teacherClassStudentsProvider(_entryClassId));
                return studentsAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (_, __) => _buildEmptyState(
                      'طلباء لوڈ کرنے میں خطا', Icons.error_outline),
                  data: (students) => students.isEmpty
                      ? _buildEmptyState('اس جماعت میں کوئی طالب علم نہیں',
                          Icons.people_outline)
                      : Column(
                          children: [
                            for (final s in students) _buildStudentEntryCard(s),
                          ],
                        ),
                );
              },
            ),

          const SizedBox(height: 24),

          // Save Button — persists through ResultNotifier (exam header +
          // one SubjectResult row per student × subject).
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveEntryResults,
              icon: const Icon(Icons.save),
              label: const Text('نتائج محفوظ کریں'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Explicit empty state — never invented rows.
  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(icon,
                size: 48,
                color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String hint,
    required List<String> items,
    String? value,
    ValueChanged<String?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButton<String>(
        isExpanded: true,
        hint: Text(hint, style: AppTypography.bodyMedium),
        value: value,
        underline: const SizedBox(),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(item, style: AppTypography.bodyMedium),
          );
        }).toList(),
        onChanged: onChanged ?? (value) {},
      ),
    );
  }

  Widget _buildStudentEntryCard(Student student) {
    final name = student.name;
    final rollNo = student.rollNo;
    return AppCard(
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
                    name.substring(0, 1),
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

          // Subject Input Fields — controllers captured per student so
          // the save button can persist real marks.
          Row(
            children: [
              Expanded(
                child: _buildMarksInput(student.id, _entrySubjects[0]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMarksInput(student.id, _entrySubjects[1]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMarksInput(student.id, _entrySubjects[2]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarksInput(String studentId, String subject) {
    return Column(
      children: [
        Text(
          subject,
          style: AppTypography.labelSmall,
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextField(
            controller: _marksController(studentId, subject),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium,
            decoration: InputDecoration(
              hintText: '0',
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showPrintDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Text(
                'نتیجہ پرنٹ کریں',
                style: AppTypography.headingMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Print Options
              Text(
                'براہ کرم پرنٹ کی قسم منتخب کریں:',
                style: AppTypography.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Print Options
              _buildPrintOption(
                icon: Icons.person,
                title: 'کل طلباء کے نتائج',
                subtitle: 'تمام طلباء کے نتائج پرنٹ کریں',
                onTap: () {
                  _printResults('all');
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 12),
              _buildPrintOption(
                icon: Icons.star,
                title: 'ممتاز طلباء',
                subtitle: '90% سے زیادہ نمبر والے طلباء',
                onTap: () {
                  _printResults('excellent');
                  Navigator.pop(context);
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
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 24),

              // Cancel Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('منسوخ کریں'),
                ),
              ),
            ],
          ),
        ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(8),
        ),
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
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// Persists the entry tab: creates the exam header (class + exam type
  /// are required) and upserts one SubjectResult row per student ×
  /// subject — all tenant-scoped through [ResultNotifier].
  Future<void> _saveEntryResults() async {
    final classId = _entryClassId;
    final examType = _entryExamType;
    if (classId.isEmpty || examType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('براہ کرم جماعت اور امتحان کی قسم منتخب کریں'),
        ),
      );
      return;
    }
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کوئی فعال ادارہ نہیں')),
      );
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
      for (final subject in _entrySubjects) {
        final text = _marksControllers['${s.id}::$subject']?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final value = double.tryParse(text);
        if (value == null || value < 0) continue;
        marks.add((studentId: s.id, subject: subject, value: value));
      }
    }
    if (marks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کوئی نمبر درج نہیں کیے گئے')),
      );
      return;
    }

    try {
      final notifier = ref.read(resultNotifierProvider.notifier);
      final now = DateTime.now();
      final exam = await notifier.createExam(
        name: '$examType — $className',
        classId: classId,
        examDate:
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        totalMarks: _entrySubjects.length * 100,
      );
      for (final m in marks) {
        await notifier.save(SubjectResult(
          id: const Uuid().v4(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${marks.length} نتائج محفوظ ہو گئے')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('محفوظ کرنے میں خرابی: $e')),
      );
    }
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('شیئر کرنے میں خرابی: $e')),
      );
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('پرنٹ میں خرابی: $e')),
      );
    }
  }
}
