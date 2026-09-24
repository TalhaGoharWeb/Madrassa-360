import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/staff.dart';
import '../../../providers/staff_provider.dart';
import '../../widgets/common/app_widgets.dart';

/// عملہ کی فہرست
/// Staff List Screen for Admin
class StaffListScreen extends StatefulWidget {
  const StaffListScreen({super.key});

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  String _selectedDepartment = 'all';
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
    final staffAsync = ref.watch(allStaffProvider);
    final staffList = staffAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.staff),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
        ],
      ),
      body: staffAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : staffAsync.hasError
              ? Center(
                  child: Text(
                    'عملہ لوڈ کرنے میں خطا ہوئی',
                    style: AppTypography.bodyMedium,
                  ),
                )
              : Column(
          children: [
            // Search Bar
            SearchField(
              controller: _searchController,
              hintText: 'عملہ تلاش کریں...',
              onChanged: (value) => setState(() {}),
            ),
            
            // Department Filter
            _buildDepartmentFilter(),
            
            // Staff Stats
            _buildStaffStats(staffList),
            
            // Staff List
            Expanded(
              child: _buildStaffList(staffList),
            ),
          ],
        ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'staff_list_add_fab',
        onPressed: _showNewStaffDialog,
        icon: const Icon(Icons.person_add),
        label: Text(
          'نیا عملہ',
          style: AppTypography.buttonText,
        ),
      ),
    );
    });
  }

  Widget _buildDepartmentFilter() {
    final departments = [
      {'id': 'all', 'label': 'سب'},
      {'id': 'تعلیمی', 'label': 'تعلیمی'},
      {'id': 'انتظامیہ', 'label': 'انتظامیہ'},
      {'id': 'مالیات', 'label': 'مالیات'},
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: departments.length,
        itemBuilder: (context, index) {
          final dept = departments[index];
          final isSelected = _selectedDepartment == dept['id'];
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(dept['label']!),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedDepartment = dept['id']!);
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

  Widget _buildStaffStats(List<Staff> staffList) {
    final teachers = staffList.where((s) => s.department == 'تعلیمی').length;
    final totalSalary = staffList.fold<double>(0, (sum, s) => sum + (s.salary ?? 0));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStatChip(Icons.people, '${staffList.length}', 'کل عملہ', AppColors.primary),
          const SizedBox(width: 8),
          _buildStatChip(Icons.school, '$teachers', 'اساتذہ', AppColors.info),
          const SizedBox(width: 8),
          _buildStatChip(
            Icons.payments,
            '${(totalSalary / 1000).toInt()}K',
            'ماہانہ تنخواہ',
            AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.titleMedium.copyWith(color: color),
            ),
            Text(
              label,
              style: AppTypography.labelSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffList(List<Staff> staffList) {
    var filteredStaff = staffList;
    
    // Apply department filter
    if (_selectedDepartment != 'all') {
      filteredStaff = filteredStaff
          .where((s) => s.department == _selectedDepartment)
          .toList();
    }
    
    // Apply search filter
    final searchQuery = _searchController.text;
    if (searchQuery.isNotEmpty) {
      filteredStaff = filteredStaff.where((s) {
        return s.name.contains(searchQuery) ||
               s.designation.contains(searchQuery);
      }).toList();
    }

    if (filteredStaff.isEmpty) {
      return const EmptyState(
        icon: Icons.person_off,
        title: 'کوئی عملہ نہیں ملا',
        subtitle: 'تلاش یا فلٹر تبدیل کریں',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: filteredStaff.length,
      itemBuilder: (context, index) {
        final staff = filteredStaff[index];
        return _buildStaffTile(staff);
      },
    );
  }

  Widget _buildStaffTile(Staff staff) {
    return AppCard(
      onTap: () => _showStaffDetails(staff),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primaryDark,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                staff.name.substring(0, 1),
                style: AppTypography.titleLarge.copyWith(
                  color: Colors.white,
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
                  staff.name,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  staff.designation,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildInfoChip(Icons.apartment, staff.department ?? ''),
                    const SizedBox(width: 8),
                    _buildInfoChip(Icons.calendar_today, staff.joiningDate),
                  ],
                ),
              ],
            ),
          ),
          
          // Status & Actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: staff.isActive
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: staff.isActive ? AppColors.success : AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      staff.isActive ? 'فعال' : 'غیر فعال',
                      style: AppTypography.labelSmall.copyWith(
                        color: staff.isActive ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.phone, size: 20),
                color: AppColors.primary,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTypography.labelSmall,
        ),
      ],
    );
  }

  void _showStaffDetails(Staff staff) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
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
                  
                  // Profile Header
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        staff.name.substring(0, 1),
                        style: AppTypography.headingLarge.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(staff.name, style: AppTypography.headingSmall),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      staff.designation,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(),
                  
                  // Info Tiles
                  InfoTile(
                    icon: Icons.person,
                    label: 'والد کا نام',
                    value: staff.fatherName,
                  ),
                  InfoTile(
                    icon: Icons.apartment,
                    label: 'شعبہ',
                    value: staff.department ?? '---',
                  ),
                  InfoTile(
                    icon: Icons.phone,
                    label: 'فون نمبر',
                    value: staff.phone,
                  ),
                  InfoTile(
                    icon: Icons.calendar_today,
                    label: 'تاریخ شمولیت',
                    value: staff.joiningDate,
                  ),
                  InfoTile(
                    icon: Icons.payments,
                    label: 'ماہانہ تنخواہ',
                    value: '${(staff.salary ?? 0).toInt()} روپے',
                    iconColor: AppColors.success,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showEditStaffDialog(staff);
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('ترمیم'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.phone),
                          label: const Text('فون کریں'),
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

  void _showNewStaffDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController fatherNameController = TextEditingController();
    final TextEditingController designationController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController salaryController = TextEditingController();

    String selectedDepartment = 'تعلیمی';
    String selectedJoiningDate = DateTime.now().toString().split(' ')[0];
    XFile? pickedPhoto;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'نیا عملہ شامل کریں',
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
                      backgroundColor: AppColors.primary.withOpacity(0.1),
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
              // Name
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'نام',
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

              // Designation
              TextFormField(
                controller: designationController,
                decoration: const InputDecoration(
                  labelText: 'عہدہ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'عہدہ درج کریں';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone
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

              // Department
              DropdownButtonFormField<String>(
                value: selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'شعبہ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.apartment),
                ),
                items: [
                  'تعلیمی',
                  'انتظامیہ',
                  'مالیات',
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) => selectedDepartment = value!,
              ),
              const SizedBox(height: 16),

              // Salary
              TextFormField(
                controller: salaryController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ماہانہ تنخواہ',
                  border: OutlineInputBorder(),
                  prefixText: 'ر ',
                  prefixIcon: Icon(Icons.payments),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'تنخواہ درج کریں';
                  }
                  final salary = double.tryParse(value);
                  if (salary == null || salary <= 0) {
                    return 'درست تنخواہ درج کریں';
                  }
                  return null;
                },
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
                  fatherNameController.text.isNotEmpty &&
                  designationController.text.isNotEmpty &&
                  phoneController.text.isNotEmpty &&
                  salaryController.text.isNotEmpty) {
                final salary = double.tryParse(salaryController.text);
                if (salary != null && salary > 0) {
                  try {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );
                    final staff = Staff(
                      id: const Uuid().v4(),
                      name: nameController.text.trim(),
                      fatherName: fatherNameController.text.trim(),
                      designation: designationController.text.trim(),
                      phone: phoneController.text.trim(),
                      joiningDate: selectedJoiningDate,
                      department: selectedDepartment,
                      salary: salary,
                    );
                    final saved = await _ref!.read(staffNotifierProvider.notifier).save(staff);
                    if (pickedPhoto != null) {
                      await _ref!.read(staffNotifierProvider.notifier).uploadPhoto(saved.id, pickedPhoto!);
                    }
                    if (context.mounted) {
                      Navigator.pop(context); // close loader
                      Navigator.pop(context); // close dialog
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${nameController.text} کو عملہ میں شامل کر دیا گیا'),
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
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('شامل کریں'),
          ),
        ],
      ),
    ),
  );
  }

  void _showEditStaffDialog(Staff staff) {
    final nameCtrl = TextEditingController(text: staff.name);
    final fatherCtrl = TextEditingController(text: staff.fatherName);
    final desigCtrl = TextEditingController(text: staff.designation);
    final phoneCtrl = TextEditingController(text: staff.phone);
    final salaryCtrl = TextEditingController(text: staff.salary?.toInt().toString() ?? '');
    String selectedDept = staff.department ?? 'تعلیمی';
    XFile? pickedPhoto;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('عملہ معلومات ترمیم کریں',
              style: AppTypography.titleLarge),
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
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          backgroundImage: pickedPhoto != null
                              ? FileImage(File(pickedPhoto!.path))
                              : (staff.photoUrl != null
                                  ? NetworkImage(staff.photoUrl!) as ImageProvider
                                  : null),
                          child: (pickedPhoto == null && staff.photoUrl == null)
                              ? Text(staff.name[0],
                                  style: AppTypography.headingMedium
                                      .copyWith(color: AppColors.primary))
                              : null,
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'نام',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: fatherCtrl,
                  decoration: const InputDecoration(
                      labelText: 'والد کا نام',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.family_restroom)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: desigCtrl,
                  decoration: const InputDecoration(
                      labelText: 'عہدہ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.work)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'فون نمبر',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDept,
                  decoration: const InputDecoration(
                      labelText: 'شعبہ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.apartment)),
                  items: ['تعلیمی', 'انتظامیہ', 'مالیات']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedDept = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: salaryCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'ماہانہ تنخواہ',
                      border: OutlineInputBorder(),
                      prefixText: 'ر ',
                      prefixIcon: Icon(Icons.payments)),
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
                if (nameCtrl.text.isNotEmpty && desigCtrl.text.isNotEmpty) {
                  try {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    final updated = Staff(
                      id: staff.id,
                      name: nameCtrl.text.trim(),
                      fatherName: fatherCtrl.text.trim(),
                      designation: desigCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      joiningDate: staff.joiningDate,
                      department: selectedDept,
                      salary: double.tryParse(salaryCtrl.text) ?? staff.salary,
                      cnic: staff.cnic,
                      userId: staff.userId,
                      photoUrl: staff.photoUrl,
                      isActive: staff.isActive,
                    );
                    final saved = await _ref!
                        .read(staffNotifierProvider.notifier)
                        .save(updated);
                    if (pickedPhoto != null) {
                      await _ref!
                          .read(staffNotifierProvider.notifier)
                          .uploadPhoto(saved.id, pickedPhoto!);
                    }
                    if (context.mounted) {
                      Navigator.pop(context);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content:
                            Text('${nameCtrl.text} کی معلومات ترمیم کر دی گئیں'),
                        backgroundColor: Colors.green,
                      ));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('خطا: $e'), backgroundColor: Colors.red));
                    }
                  }
                }
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('ترمیم کریں'),
            ),
          ],
        ),
      ),
    );
  }
}
