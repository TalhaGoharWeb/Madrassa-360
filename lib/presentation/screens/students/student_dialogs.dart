import 'dart:io';

import 'package:flutter/material.dart' hide DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/student.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/student_provider.dart';

/// Shared student dialogs — new-admission, edit, and fee collection.
///
/// Extracted from `admin/student_list_screen.dart` with the SAME providers,
/// the SAME fields and the SAME Urdu validation messages. Only the styling
/// was refreshed (Nastaleeq labels, teal/gold accents). Used by both the
/// redesigned student list and the student profile screen so the create/edit
/// flow behaves identically everywhere.
class StudentDialogs {
  StudentDialogs._();

  // ─────────────────────────────────────────────────────────────
  // Shared option lists (identical to the original screen)
  // ─────────────────────────────────────────────────────────────

  static const List<String> classOptions = [
    'درجہ اولیٰ (اول سال)',
    'درجہ ثانیہ (دوسرا سال)',
    'درجہ ثالثہ (تیسرا سال)',
    'درجہ رابعہ (چوتھا سال)',
    'درجہ خامسہ (پانچواں سال)',
    'درجہ سادسہ (چھٹا سال)',
    'درجہ سابِعہ (ساتواں سال)',
    'دورہ حدیث (آٹھواں سال/آخری سال)',
  ];

  static const List<String> sectionOptions = ['الف', 'ب', 'ج', 'د'];

  static const List<String> feeTypeOptions = [
    'ماہانہ فیس',
    'داخلہ فیس',
    'امتحان فیس',
    'دیگر',
  ];

  static const Color gold = Color(0xFFC9A227);

  // ─────────────────────────────────────────────────────────────
  // New admission dialog (same fields, same validation, same save flow)
  // ─────────────────────────────────────────────────────────────

  static void showNewAdmission(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final fatherNameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    String selectedClass = classOptions.first;
    String selectedSection = sectionOptions.first;
    XFile? pickedPhoto;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('+ نیا طالب علم', style: AppTypography.titleLarge),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhotoPicker(
                  currentPhotoUrl: null,
                  fallbackLetter: '',
                  onPicked: (img) => setState(() => pickedPhoto = img),
                  pickedPhoto: pickedPhoto,
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  controller: nameController,
                  label: 'طالب علم کا نام',
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  controller: fatherNameController,
                  label: 'والد کا نام',
                  icon: Icons.family_restroom,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'والد کا نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  controller: phoneController,
                  label: 'فون نمبر',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'فون نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedClass,
                  decoration: const InputDecoration(
                    labelText: 'جماعت',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_),
                  ),
                  items: classOptions
                      .map((v) => DropdownMenuItem<String>(
                            value: v,
                            child: Text(v),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => selectedClass = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedSection,
                  decoration: const InputDecoration(
                    labelText: 'سیکشن',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.group),
                  ),
                  items: sectionOptions
                      .map((v) => DropdownMenuItem<String>(
                            value: v,
                            child: Text(v),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => selectedSection = value!),
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  controller: addressController,
                  label: 'پتہ (اختیاری)',
                  icon: Icons.location_on,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('منسوخ کریں', style: AppTypography.labelNastaliq),
            ),
            ElevatedButton(
              onPressed: () => _submitNewAdmission(
                dialogContext,
                ref,
                nameController: nameController,
                fatherNameController: fatherNameController,
                phoneController: phoneController,
                addressController: addressController,
                selectedClass: selectedClass,
                pickedPhoto: pickedPhoto,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: Text('داخلہ لیں', style: AppTypography.buttonText),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _submitNewAdmission(
    BuildContext dialogContext,
    WidgetRef ref, {
    required TextEditingController nameController,
    required TextEditingController fatherNameController,
    required TextEditingController phoneController,
    required TextEditingController addressController,
    required String selectedClass,
    required XFile? pickedPhoto,
  }) async {
    if (nameController.text.isEmpty || fatherNameController.text.isEmpty) {
      return;
    }
    try {
      showDialog(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      final tenantId = ref.read(currentTenantIdProvider);
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
        phone:
            phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
        address: addressController.text.trim().isEmpty
            ? null
            : addressController.text.trim(),
      );
      final saved =
          await ref.read(studentNotifierProvider.notifier).save(student);
      final photoToUpload = pickedPhoto;
      if (photoToUpload != null) {
        await ref
            .read(studentNotifierProvider.notifier)
            .uploadPhoto(saved.id, photoToUpload);
      }
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext); // close loader
        Navigator.pop(dialogContext); // close dialog
        ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
          content: Text('${nameController.text} کا داخلہ کامیابی سے ہو گیا'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext); // close loader
        ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
          content: Text('خطا: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Edit student dialog (same fields, same validation, same save flow)
  // ─────────────────────────────────────────────────────────────

  static void showEditStudent(
      BuildContext context, WidgetRef ref, Student student) {
    final nameController = TextEditingController(text: student.name);
    final fatherNameController =
        TextEditingController(text: student.fatherName);
    final phoneController = TextEditingController(text: student.phone ?? '');

    String selectedClass = classOptions.contains(student.className)
        ? student.className
        : classOptions.first;
    XFile? pickedPhoto;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'طالب علم کی معلومات ترمیم کریں',
            style: AppTypography.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhotoPicker(
                  currentPhotoUrl: student.photoUrl,
                  fallbackLetter: student.name.isNotEmpty
                      ? student.name.substring(0, 1)
                      : '',
                  onPicked: (img) => setState(() => pickedPhoto = img),
                  pickedPhoto: pickedPhoto,
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  controller: nameController,
                  label: 'طالب علم کا نام',
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  controller: fatherNameController,
                  label: 'والد کا نام',
                  icon: Icons.family_restroom,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'والد کا نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  controller: phoneController,
                  label: 'فون نمبر',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'فون نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedClass,
                  decoration: const InputDecoration(
                    labelText: 'جماعت',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.class_),
                  ),
                  items: classOptions
                      .map((v) => DropdownMenuItem<String>(
                            value: v,
                            child: Text(v),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => selectedClass = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('منسوخ کریں', style: AppTypography.labelNastaliq),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    fatherNameController.text.isNotEmpty) {
                  try {
                    showDialog(
                      context: dialogContext,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    final tenantId = ref.read(currentTenantIdProvider);
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
                    final saved = await ref
                        .read(studentNotifierProvider.notifier)
                        .save(updated);
                    final photoToUpload = pickedPhoto;
                    if (photoToUpload != null) {
                      await ref
                          .read(studentNotifierProvider.notifier)
                          .uploadPhoto(saved.id, photoToUpload);
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext); // close loader
                      Navigator.pop(dialogContext); // close dialog
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                        content: Text(
                            '${nameController.text} کی معلومات ترمیم کر دی گئیں'),
                        backgroundColor: Colors.green,
                      ));
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
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
              child: Text('ترمیم کریں', style: AppTypography.buttonText),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Fee collection dialog (same month list, same save flow)
  // ─────────────────────────────────────────────────────────────

  static void showFeeCollection(
      BuildContext context, WidgetRef ref, Student student) {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    String selectedFeeType = feeTypeOptions.first;
    final now = DateTime.now();
    final monthOptions = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${DateUtils.formatMonthName(d)} ${d.year}';
    });
    final monthValues = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
    String selectedMonth = monthOptions.first;
    final screenContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, innerRef, _) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(
              '${student.name} کی فیس',
              style: AppTypography.titleLarge,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info,
                            color: AppColors.primary, size: 20),
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
                  DropdownButtonFormField<String>(
                    initialValue: selectedFeeType,
                    decoration: const InputDecoration(
                      labelText: 'فیس کی قسم',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: feeTypeOptions
                        .map((v) => DropdownMenuItem<String>(
                              value: v,
                              child: Text(v),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedFeeType = value!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'ماہ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_month),
                    ),
                    items: monthOptions
                        .map((v) => DropdownMenuItem<String>(
                              value: v,
                              child: Text(v),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedMonth = value!),
                  ),
                  const SizedBox(height: 16),
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
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('منسوخ کریں', style: AppTypography.labelNastaliq),
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
                  final monthIdx = monthOptions.indexOf(selectedMonth);
                  final monthValue = monthValues[monthIdx < 0 ? 0 : monthIdx];
                  final fees =
                      innerRef.read(feesByStudentProvider(student.id)).valueOrNull ??
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
                      final tenantId = innerRef.read(currentTenantIdProvider);
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
                    await innerRef
                        .read(feeNotifierProvider.notifier)
                        .save(record);
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
                child: Text('وصول کریں', style: AppTypography.buttonText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Private UI helpers for the dialogs
// ─────────────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLines;
  final String? Function(String?)? validator;

  const _LabeledField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: AppTypography.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            AppTypography.labelNastaliq.copyWith(fontSize: 15),
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon, color: AppColors.primary),
      ),
      validator: validator,
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final String? currentPhotoUrl;
  final String fallbackLetter;
  final XFile? pickedPhoto;
  final ValueChanged<XFile> onPicked;

  const _PhotoPicker({
    required this.currentPhotoUrl,
    required this.fallbackLetter,
    required this.pickedPhoto,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider? image = pickedPhoto != null
        ? FileImage(File(pickedPhoto!.path))
        : (currentPhotoUrl != null
            ? NetworkImage(currentPhotoUrl!) as ImageProvider
            : null);
    return Center(
      child: GestureDetector(
        onTap: () async {
          final img = await ImagePicker()
              .pickImage(source: ImageSource.gallery, imageQuality: 70);
          if (img != null) onPicked(img);
        },
        child: Stack(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              backgroundImage: image,
              child: image == null
                  ? Text(
                      fallbackLetter.isEmpty ? '؟' : fallbackLetter,
                      style: AppTypography.headingMedium
                          .copyWith(color: AppColors.primary),
                    )
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: StudentDialogs.gold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_a_photo,
                    color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
