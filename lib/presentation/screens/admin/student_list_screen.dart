import 'dart:io';
import 'package:flutter/material.dart' hide DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/student.dart';
import '../../../data/models/fee.dart';
import '../../../providers/student_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../widgets/common/app_widgets.dart';

/// طلباء کی فہرست
/// Student List Screen for Admin
class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  String _selectedFilter = 'all';
  final _searchController = TextEditingController();
  WidgetRef? _ref;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      _ref = ref;
      final studentsAsync = ref.watch(allStudentsProvider);
      final students = studentsAsync.valueOrNull ?? [];

      return Scaffold(
        appBar: AppBar(
          title: Text(AppStrings.students),
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _showFilterSheet,
            ),
          ],
        ),
        body: studentsAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : studentsAsync.hasError
                ? Center(
                    child: Text(
                      'طلباء لوڈ کرنے میں خطا',
                      style: AppTypography.bodyMedium,
                    ),
                  )
                : Column(
                    children: [
                      // Search Bar
                      SearchField(
                        controller: _searchController,
                        hintText: 'طالب علم تلاش کریں...',
                        onChanged: (value) => setState(() {}),
                        onFilterTap: _showFilterSheet,
                      ),

                      // Filter Chips
                      _buildFilterChips(),

                      // Stats Row
                      _buildStatsRow(students),

                      // Student List
                      Expanded(
                        child: _buildStudentList(students),
                      ),
                    ],
                  ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'student_list_add_fab',
          onPressed: _showNewAdmissionDialog,
          icon: const Icon(Icons.person_add),
          label: Text(
            'نیا داخلہ',
            style: AppTypography.buttonText,
          ),
        ),
      );
    });
  }

  Widget _buildFilterChips() {
    final filters = [
      {'id': 'all', 'label': 'سب'},
      {'id': 'درجہ اولیٰ (اول سال)', 'label': 'درجہ اولیٰ'},
      {'id': 'درجہ ثانیہ (دوسرا سال)', 'label': 'درجہ ثانیہ'},
      {'id': 'درجہ ثالثہ (تیسرا سال)', 'label': 'درجہ ثالثہ'},
      {'id': 'درجہ رابعہ (چوتھا سال)', 'label': 'درجہ رابعہ'},
      {'id': 'درجہ خامسہ (پانچواں سال)', 'label': 'درجہ خامسہ'},
      {'id': 'درجہ سادسہ (چھٹا سال)', 'label': 'درجہ سادسہ'},
      {'id': 'درجہ سابِعہ (ساتواں سال)', 'label': 'درجہ سابِعہ'},
      {'id': 'دورہ حدیث (آٹھواں سال/آخری سال)', 'label': 'دورہ حدیث'},
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['id'];
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(filter['label']!),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedFilter = filter['id']!);
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

  Widget _buildStatsRow(List<Student> students) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildMiniStat(Icons.people, '${students.length}', 'کل طلباء',
              AppColors.primary),
          const SizedBox(width: 12),
          _buildMiniStat(
              Icons.check_circle, '—', 'فیس مکمل', AppColors.success),
          const SizedBox(width: 12),
          _buildMiniStat(Icons.warning, '—', 'فیس باقی', AppColors.error),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTypography.titleSmall.copyWith(color: color),
                ),
                Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentList(List<Student> students) {
    var filteredStudents = students;

    // Apply class filter
    if (_selectedFilter != 'all') {
      filteredStudents = filteredStudents
          .where((s) => s.className == _selectedFilter)
          .toList();
    }

    // Apply search filter
    final searchQuery = _searchController.text.toLowerCase();
    if (searchQuery.isNotEmpty) {
      filteredStudents = filteredStudents.where((s) {
        return s.name.toLowerCase().contains(searchQuery) ||
            s.fatherName.toLowerCase().contains(searchQuery);
      }).toList();
    }

    if (filteredStudents.isEmpty) {
      return const EmptyState(
        icon: Icons.person_off,
        title: 'کوئی طالب علم نہیں ملا',
        subtitle: 'تلاش یا فلٹر تبدیل کریں',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final student = filteredStudents[index];
        return _buildStudentTile(student);
      },
    );
  }

  Widget _buildStudentTile(Student student) {
    return AppCard(
      onTap: () => _showStudentDetails(student),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                student.name.substring(0, 1),
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: AppTypography.titleMedium,
                ),
                Text(
                  'بن ${student.fatherName}',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildTag(student.className, AppColors.primary),
                    const SizedBox(width: 8),
                    _buildTag(
                        'رول: ${student.rollNo}', AppColors.textSecondary),
                  ],
                ),
              ],
            ),
          ),

          // Darja badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              student.darjaName.isEmpty ? '---' : student.darjaName,
              style: AppTypography.labelSmall.copyWith(color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontSize: 10,
        ),
      ),
    );
  }

  void _showFilterSheet() {
    String tempSelectedClass = _selectedFilter;
    List<String> tempSelectedFeeStatuses = [];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'فلٹر کریں',
                    style: AppTypography.headingSmall,
                  ),
                  const SizedBox(height: 16),
                  Text('جماعت', style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      {'id': 'all', 'label': 'سب'},
                      {'id': 'درجہ اولیٰ (اول سال)', 'label': 'درجہ اولیٰ'},
                      {'id': 'درجہ ثانیہ (دوسرا سال)', 'label': 'درجہ ثانیہ'},
                      {'id': 'درجہ ثالثہ (تیسرا سال)', 'label': 'درجہ ثالثہ'},
                      {'id': 'درجہ رابعہ (چوتھا سال)', 'label': 'درجہ رابعہ'},
                      {'id': 'درجہ خامسہ (پانچواں سال)', 'label': 'درجہ خامسہ'},
                      {'id': 'درجہ سادسہ (چھٹا سال)', 'label': 'درجہ سادسہ'},
                      {
                        'id': 'درجہ سابِعہ (ساتواں سال)',
                        'label': 'درجہ سابِعہ'
                      },
                      {
                        'id': 'دورہ حدیث (آٹھواں سال/آخری سال)',
                        'label': 'دورہ حدیث'
                      },
                    ].map((classItem) {
                      final isSelected = tempSelectedClass == classItem['id'];
                      return FilterChip(
                        label: Text(classItem['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            tempSelectedClass =
                                selected ? classItem['id']! : 'all';
                          });
                        },
                        selectedColor: AppColors.primary.withValues(alpha: 0.2),
                        checkmarkColor: AppColors.primary,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('فیس کی حالت', style: AppTypography.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      {
                        'label': 'ادا شدہ',
                        'value': 'paid',
                        'color': AppColors.success
                      },
                      {
                        'label': 'جزوی',
                        'value': 'partial',
                        'color': AppColors.warning
                      },
                      {
                        'label': 'زیر التواء',
                        'value': 'pending',
                        'color': AppColors.info
                      },
                      {
                        'label': 'واجب الادا',
                        'value': 'pastDue',
                        'color': AppColors.error
                      },
                    ].map((feeItem) {
                      final isSelected =
                          tempSelectedFeeStatuses.contains(feeItem['value']);
                      return FilterChip(
                        label: Text(feeItem['label'] as String),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              tempSelectedFeeStatuses
                                  .add(feeItem['value'] as String);
                            } else {
                              tempSelectedFeeStatuses
                                  .remove(feeItem['value'] as String);
                            }
                          });
                        },
                        selectedColor:
                            (feeItem['color'] as Color).withValues(alpha: 0.2),
                        checkmarkColor: feeItem['color'] as Color,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              tempSelectedClass = 'all';
                              tempSelectedFeeStatuses.clear();
                            });
                          },
                          child: const Text('کلئیر'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // Apply filters
                            this.setState(() {
                              _selectedFilter = tempSelectedClass;
                            });
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('فلٹر لاگو کر دیا گیا'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          child: const Text('فلٹر لاگو کریں'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showStudentDetails(Student student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
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

                  // Profile
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        student.name.substring(0, 1),
                        style: AppTypography.headingLarge.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(student.name, style: AppTypography.headingSmall),
                  Text(
                    'بن ${student.fatherName}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),

                  // Info Tiles
                  InfoTile(
                    icon: Icons.class_,
                    label: 'جماعت',
                    value: student.className,
                  ),
                  InfoTile(
                    icon: Icons.format_list_numbered,
                    label: 'رول نمبر',
                    value: student.rollNo,
                  ),
                  if (student.phone != null)
                    InfoTile(
                      icon: Icons.phone,
                      label: 'والد کا فون',
                      value: student.phone!,
                    ),
                  if (student.address != null)
                    InfoTile(
                      icon: Icons.location_on,
                      label: 'پتہ',
                      value: student.address!,
                    ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showEditStudentDialog(student),
                          icon: const Icon(Icons.edit),
                          label: const Text('ترمیم'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showFeeDialog(student),
                          icon: const Icon(Icons.receipt),
                          label: const Text('فیس'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showNewAdmissionDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController fatherNameController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController addressController = TextEditingController();

    String selectedClass = 'درجہ اولیٰ (اول سال)';
    String selectedSection = 'الف';
    XFile? pickedPhoto;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'نیا داخلہ',
            style: AppTypography.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo Picker
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final img = await ImagePicker().pickImage(
                          source: ImageSource.gallery, imageQuality: 70);
                      if (img != null) setState(() => pickedPhoto = img);
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      backgroundImage: pickedPhoto != null
                          ? FileImage(File(pickedPhoto!.path))
                          : null,
                      child: pickedPhoto == null
                          ? const Icon(Icons.add_a_photo,
                              color: AppColors.primary, size: 30)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Student Name
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'طالب علم کا نام',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Father Name
                TextFormField(
                  controller: fatherNameController,
                  decoration: const InputDecoration(
                    labelText: 'والد کا نام',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.family_restroom),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'والد کا نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone Number
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'فون نمبر',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'فون نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Class Selection
                DropdownButtonFormField<String>(
                  value: selectedClass,
                  decoration: const InputDecoration(
                    labelText: 'جماعت',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_),
                  ),
                  items: [
                    'درجہ اولیٰ (اول سال)',
                    'درجہ ثانیہ (دوسرا سال)',
                    'درجہ ثالثہ (تیسرا سال)',
                    'درجہ رابعہ (چوتھا سال)',
                    'درجہ خامسہ (پانچواں سال)',
                    'درجہ سادسہ (چھٹا سال)',
                    'درجہ سابِعہ (ساتواں سال)',
                    'دورہ حدیث (آٹھواں سال/آخری سال)',
                  ].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedClass = value!),
                ),
                const SizedBox(height: 16),

                // Section Selection
                DropdownButtonFormField<String>(
                  value: selectedSection,
                  decoration: const InputDecoration(
                    labelText: 'سیکشن',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.group),
                  ),
                  items: ['الف', 'ب', 'ج', 'د'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) =>
                      setState(() => selectedSection = value!),
                ),
                const SizedBox(height: 16),

                // Address (Optional)
                TextFormField(
                  controller: addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'پتہ (اختیاری)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('منسوخ کریں'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    fatherNameController.text.isNotEmpty) {
                  try {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    final tenantId = _ref!.read(currentTenantIdProvider);
                    if (tenantId == null) {
                      throw StateError('No active tenant');
                    }
                    final student = Student(
                      id: const Uuid().v4(),
                      tenantId: tenantId,
                      rollNo: '',
                      name: nameController.text.trim(),
                      fatherName: fatherNameController.text.trim(),
                      darjaId: selectedClass,
                      darjaName: selectedClass,
                      classId: selectedClass,
                      className: selectedClass,
                      phone: phoneController.text.trim().isEmpty
                          ? null
                          : phoneController.text.trim(),
                      address: addressController.text.trim().isEmpty
                          ? null
                          : addressController.text.trim(),
                    );
                    final saved = await _ref!
                        .read(studentNotifierProvider.notifier)
                        .save(student);
                    if (pickedPhoto != null) {
                      await _ref!
                          .read(studentNotifierProvider.notifier)
                          .uploadPhoto(saved.id, pickedPhoto!);
                    }
                    if (context.mounted) {
                      Navigator.pop(context); // close loader
                      Navigator.pop(context); // close dialog
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '${nameController.text} کا داخلہ کامیابی سے ہو گیا'),
                        backgroundColor: Colors.green,
                      ));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context); // close loader
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('خطا: $e'),
                        backgroundColor: Colors.red,
                      ));
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('داخلہ لیں'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditStudentDialog(Student student) {
    final TextEditingController nameController =
        TextEditingController(text: student.name);
    final TextEditingController fatherNameController =
        TextEditingController(text: student.fatherName);
    final TextEditingController phoneController =
        TextEditingController(text: student.phone ?? '');

    const validClasses = [
      'درجہ اولیٰ (اول سال)',
      'درجہ ثانیہ (دوسرا سال)',
      'درجہ ثالثہ (تیسرا سال)',
      'درجہ رابعہ (چوتھا سال)',
      'درجہ خامسہ (پانچواں سال)',
      'درجہ سادسہ (چھٹا سال)',
      'درجہ سابِعہ (ساتواں سال)',
      'دورہ حدیث (آٹھواں سال/آخری سال)',
    ];
    String selectedClass = validClasses.contains(student.className)
        ? student.className
        : validClasses.first;

    // ignore: unused_local_variable
    String selectedSection = 'الف'; // track section selection

    XFile? pickedPhoto;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'طالب علم کی معلومات ترمیم کریں',
            style: AppTypography.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo Picker
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final img = await ImagePicker().pickImage(
                          source: ImageSource.gallery, imageQuality: 70);
                      if (img != null) setState(() => pickedPhoto = img);
                    },
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          backgroundImage: pickedPhoto != null
                              ? FileImage(File(pickedPhoto!.path))
                              : (student.photoUrl != null
                                  ? NetworkImage(student.photoUrl!)
                                      as ImageProvider
                                  : null),
                          child:
                              (pickedPhoto == null && student.photoUrl == null)
                                  ? Text(student.name[0],
                                      style: AppTypography.headingMedium
                                          .copyWith(color: AppColors.primary))
                                  : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.edit,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'طالب علم کا نام',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Father Name
                TextFormField(
                  controller: fatherNameController,
                  decoration: const InputDecoration(
                    labelText: 'والد کا نام',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.family_restroom),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'والد کا نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone Number
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'فون نمبر',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'فون نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Class Selection
                DropdownButtonFormField<String>(
                  value: selectedClass,
                  decoration: const InputDecoration(
                    labelText: 'جماعت',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_),
                  ),
                  items: validClasses.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedClass = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('منسوخ کریں'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    fatherNameController.text.isNotEmpty) {
                  try {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    final tenantId = _ref!.read(currentTenantIdProvider);
                    if (tenantId == null) {
                      throw StateError('No active tenant');
                    }
                    final updated = Student(
                      id: student.id,
                      tenantId: tenantId,
                      rollNo: student.rollNo,
                      name: nameController.text.trim(),
                      fatherName: fatherNameController.text.trim(),
                      darjaId: selectedClass,
                      darjaName: selectedClass,
                      classId: selectedClass,
                      className: selectedClass,
                      phone: phoneController.text.trim().isEmpty
                          ? null
                          : phoneController.text.trim(),
                      address: student.address,
                      photoUrl: student.photoUrl,
                      isActive: student.isActive,
                    );
                    final saved = await _ref!
                        .read(studentNotifierProvider.notifier)
                        .save(updated);
                    if (pickedPhoto != null) {
                      await _ref!
                          .read(studentNotifierProvider.notifier)
                          .uploadPhoto(saved.id, pickedPhoto!);
                    }
                    if (context.mounted) {
                      Navigator.pop(context); // close loader
                      Navigator.pop(context); // close dialog
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '${nameController.text} کی معلومات ترمیم کر دی گئیں'),
                        backgroundColor: Colors.green,
                      ));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('خطا: $e'),
                        backgroundColor: Colors.red,
                      ));
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('ترمیم کریں'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFeeDialog(Student student) {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();

    String selectedFeeType = 'ماہانہ فیس';
    // Phase 4: month list is generated from the current date instead of a
    // frozen 2026 list.
    final now = DateTime.now();
    final monthOptions = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${DateUtils.formatMonthName(d)} ${d.year}';
    });
    // Parallel 'YYYY-MM' values for the DB (display names are localized).
    final monthValues = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
    String selectedMonth = monthOptions.first;
    // Outer screen context — used for snackbars after the dialog is popped.
    final screenContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              '${student.name} کی فیس',
              style: AppTypography.titleLarge,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current Fee Status
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'طالب علم: ${student.name}',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Fee Type
                  DropdownButtonFormField<String>(
                    value: selectedFeeType,
                    decoration: const InputDecoration(
                      labelText: 'فیس کی قسم',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: [
                      'ماہانہ فیس',
                      'داخلہ فیس',
                      'امتحان فیس',
                      'دیگر',
                    ].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => selectedFeeType = value!),
                  ),
                  const SizedBox(height: 16),

                  // Month
                  DropdownButtonFormField<String>(
                    value: selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'ماہ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_month),
                    ),
                    items: monthOptions.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => selectedMonth = value!),
                  ),
                  const SizedBox(height: 16),

                  // Amount
                  TextFormField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'رقم',
                      border: OutlineInputBorder(),
                      prefixText: 'ر ',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'رقم درج کریں';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'درست رقم درج کریں';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'تفصیل (اختیاری)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('منسوخ کریں'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(screenContext).showSnackBar(
                      const SnackBar(content: Text('درست رقم درج کریں')),
                    );
                    return;
                  }
                  // Phase 6 (mock purge): real collection — persists the payment
                  // through FeeNotifier (local Drift DB + sync queue). Never a
                  // fake success snackbar again.
                  final monthIdx = monthOptions.indexOf(selectedMonth);
                  final monthValue = monthValues[monthIdx < 0 ? 0 : monthIdx];
                  final fees =
                      ref.read(feesByStudentProvider(student.id)).valueOrNull ??
                          const <Fee>[];
                  Fee? existing;
                  for (final f in fees) {
                    if (f.month == monthValue) {
                      existing = f;
                      break;
                    }
                  }
                  final nowPaid = DateTime.now();
                  final todayStr =
                      '${nowPaid.year}-${nowPaid.month.toString().padLeft(2, '0')}-${nowPaid.day.toString().padLeft(2, '0')}';
                  final messenger = ScaffoldMessenger.of(screenContext);
                  try {
                    final Fee record;
                    if (existing != null) {
                      record = existing.copyWith(
                        amountPaid: existing.amountPaid + amount,
                        paidDate: todayStr,
                      );
                    } else {
                      final tenantId = ref.read(currentTenantIdProvider);
                      if (tenantId == null) {
                        throw StateError('No active tenant');
                      }
                      record = Fee(
                        id: const Uuid().v4(),
                        tenantId: tenantId,
                        studentId: student.id,
                        studentName: student.name,
                        studentClass: student.className,
                        month: monthValue,
                        amountDue: amount,
                        amountPaid: amount,
                        dueDate: todayStr,
                        paidDate: todayStr,
                        status: FeeStatus.paid,
                      );
                    }
                    await ref.read(feeNotifierProvider.notifier).save(record);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                            'ر $amount کی $selectedFeeType کامیابی سے وصول کر لی گئی'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('فیس وصول کرنے میں خطا')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                child: const Text('وصول کریں'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
