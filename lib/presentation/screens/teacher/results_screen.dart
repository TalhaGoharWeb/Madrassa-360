import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/result.dart';
import '../../../providers/result_provider.dart';
import '../../widgets/common/app_widgets.dart';

/// نتائج کی سکرین
/// Results Screen with Grades and Result Cards
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedClass = 'درجہ اولیٰ (اول سال)';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        final resultsAsync = ref.watch(allResultsProvider);
        final results = resultsAsync.valueOrNull ?? [];
        final filtered = _selectedClass.isEmpty
            ? results
            : results.where((r) => r.className == _selectedClass).toList();

        if (resultsAsync.isLoading) return const Center(child: CircularProgressIndicator());
        if (resultsAsync.hasError) {
          return Center(
            child: Text('نتائج لوڈ کرنے میں خطا', style: AppTypography.bodyMedium),
          );
        }

        return Column(
          children: [
            // Class Filter
            _buildClassFilter(),

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

  Widget _buildClassFilter() {
    final classes = [
      'درجہ اولیٰ (اول سال)',
      'درجہ ثانیہ (دوسرا سال)',
      'درجہ ثالثہ (تیسرا سال)',
      'درجہ رابعہ (چوتھا سال)',
      'درجہ خامسہ (پانچواں سال)',
      'درجہ سادسہ (چھٹا سال)',
      'درجہ سابِعہ (ساتواں سال)',
      'دورہ حدیث (آٹھواں سال/آخری سال)',
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: classes.length,
        itemBuilder: (context, index) {
          final className = classes[index];
          final isSelected = _selectedClass == className;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(className),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedClass = className);
              },
              selectedColor: AppColors.primary.withOpacity(0.2),
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
                  color: AppColors.primary.withOpacity(0.1),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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
                        Text(
                          AppConfig.appName,
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
                                color: AppColors.primary.withOpacity(0.1),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
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
                                        .withOpacity(0.1),
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
                      onPressed: () {},
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
                _buildDropdownField(
                  hint: 'جماعت',
                  items: [
                    'درجہ اولیٰ (اول سال)',
                    'درجہ ثانیہ (دوسرا سال)',
                    'درجہ ثالثہ (تیسرا سال)',
                    'درجہ رابعہ (چوتھا سال)',
                    'درجہ خامسہ (پانچواں سال)',
                    'درجہ سادسہ (چھٹا سال)',
                    'درجہ سابِعہ (ساتواں سال)',
                    'دورہ حدیث (آٹھواں سال/آخری سال)',
                  ],
                ),
                const SizedBox(height: 12),
                _buildDropdownField(
                  hint: 'امتحان کی قسم',
                  items: ['ماہانہ امتحان', 'ہفتہ وار ٹیسٹ', 'سالانہ امتحان'],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Student Entry Cards
          Text(
            'طلباء کے نمبرات',
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: 12),
          
          ...List.generate(3, (index) {
            final students = ['محمد احمد', 'عبداللہ خان', 'حافظ عمر'];
            return _buildStudentEntryCard(students[index], '${index + 1}');
          }),
          
          const SizedBox(height: 24),
          
          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
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

  Widget _buildDropdownField({
    required String hint,
    required List<String> items,
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
        underline: const SizedBox(),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(item, style: AppTypography.bodyMedium),
          );
        }).toList(),
        onChanged: (value) {},
      ),
    );
  }

  Widget _buildStudentEntryCard(String name, String rollNo) {
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
                  color: AppColors.primary.withOpacity(0.1),
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
          
          // Subject Input Fields
          Row(
            children: [
              Expanded(
                child: _buildMarksInput('قرآن'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMarksInput('حدیث'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMarksInput('فقہ'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarksInput(String subject) {
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
                    style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
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

  void _printResults(String type) {
    String message;
    switch (type) {
      case 'all':
        message = 'تمام طلباء کے نتائج پرنٹ ہو رہے ہیں...';
        break;
      case 'excellent':
        message = 'ممتاز طلباء کے نتائج پرنٹ ہو رہے ہیں...';
        break;
      case 'failed':
        message = 'ناکام طلباء کے نتائج پرنٹ ہو رہے ہیں...';
        break;
      default:
        message = 'نتائج پرنٹ ہو رہے ہیں...';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
