import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:madrasa_360/core/design/m360.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money_format.dart';
import '../../../data/models/darja.dart';
import '../../../data/models/fee.dart';
import '../../../data/models/student.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/fee_provider.dart';
import '../../../providers/student_provider.dart';

/// Mutable holder for the darja picker's resolved selection (real row id +
/// Urdu display name). Mutated idempotently during build; the surrounding
/// [StatefulBuilder] rebuilds it via the picker's [onChanged] callback.
class DarjaSelection {
  String? id;
  String name = '';
}

/// Shared student dialogs — new-admission, edit, and fee collection.
///
/// Phase 10 (m360): visual/UX layer only — same providers, same fields,
/// same Urdu validation messages, same save flows. [AlertDialog] becomes
/// [M360Dialog], fields become [M360TextField]/[M360Dropdown], snackbars go
/// through [showM360SnackBar], and the blocking loader dialog is replaced
/// by the primary button's [isLoading] state.
///
/// Used by both the redesigned student list and the student profile screen
/// so the create/edit flow behaves identically everywhere. Public API is
/// unchanged (admin/student_list_screen.dart shares it).
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

  /// Class/darja picker bound to REAL darja rows.
  ///
  /// The chosen row's UUID is written into [selection] (id + Urdu name) so
  /// rosters, filters and attendance queries — which all join on real row
  /// ids — keep working. Never stores display strings as ids. [onChanged]
  /// must rebuild the surrounding [StatefulBuilder].
  static Widget darjaPicker({
    required DarjaSelection selection,
    required VoidCallback onChanged,
  }) {
    return Consumer(
      builder: (ctx, dref, _) {
        final darjasAsync = dref.watch(safeDarjaListProvider);
        return darjasAsync.when(
          data: (darjas) {
            final options = darjas
                .where((Darja d) => d.id != null && d.id!.isNotEmpty)
                .toList();
            if (options.isEmpty) {
              return Text(
                'کوئی درجہ دستیاب نہیں — پہلے درجات شامل کریں',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textSecondary),
              );
            }
            // Resolve the current selection idempotently (no rebuild).
            // A legacy display-string id simply won't match and falls back
            // to the first real darja.
            var current = options.first;
            if (selection.id != null) {
              final match = options.where((d) => d.id == selection.id);
              if (match.isNotEmpty) current = match.first;
            }
            selection.id = current.id;
            selection.name = current.nameUrdu;
            return M360Dropdown<String>(
              label: 'جماعت',
              prefixIcon: Icons.class_,
              items: [
                for (final d in options)
                  M360DropdownItem(value: d.id!, label: d.nameUrdu),
              ],
              value: current.id,
              onChanged: (value) {
                if (value == null) return;
                final chosen = options.firstWhere((d) => d.id == value,
                    orElse: () => options.first);
                selection.id = chosen.id;
                selection.name = chosen.nameUrdu;
                onChanged();
              },
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (_, __) => Text(
            'درجات لوڈ نہیں ہو سکے — دوبارہ کوشش کریں',
            style: AppTypography.labelMedium.copyWith(color: AppColors.error),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // New admission dialog (same fields, same validation, same save flow)
  // ─────────────────────────────────────────────────────────────

  static void showNewAdmission(BuildContext context, WidgetRef ref) {
    final screenContext = context;
    final nameController = TextEditingController();
    final fatherNameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final darjaSelection = DarjaSelection();
    String selectedSection = sectionOptions.first;
    XFile? pickedPhoto;
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => M360Dialog(
          title: 'نیا طالب علم',
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
                M360TextField(
                  controller: nameController,
                  label: 'طالب علم کا نام',
                  prefixIcon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                M360TextField(
                  controller: fatherNameController,
                  label: 'والد کا نام',
                  prefixIcon: Icons.family_restroom,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'والد کا نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                M360TextField(
                  controller: phoneController,
                  label: 'فون نمبر',
                  prefixIcon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'فون نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                darjaPicker(
                  selection: darjaSelection,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 16),
                M360Dropdown<String>(
                  label: 'سیکشن',
                  prefixIcon: Icons.group,
                  items: [
                    for (final v in sectionOptions)
                      M360DropdownItem(value: v, label: v),
                  ],
                  value: selectedSection,
                  onChanged: (value) => setState(
                      () => selectedSection = value ?? sectionOptions.first),
                ),
                const SizedBox(height: 16),
                M360TextField(
                  controller: addressController,
                  label: 'پتہ (اختیاری)',
                  prefixIcon: Icons.location_on,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            M360TertiaryButton(
              label: 'منسوخ کریں',
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
            ),
            M360PrimaryButton(
              label: 'داخلہ لیں',
              isLoading: saving,
              onPressed: saving
                  ? null
                  : () => _submitNewAdmission(
                        screenContext,
                        dialogContext,
                        ref,
                        () => setState(() => saving = true),
                        () {
                          if (dialogContext.mounted) {
                            setState(() => saving = false);
                          }
                        },
                        nameController: nameController,
                        fatherNameController: fatherNameController,
                        phoneController: phoneController,
                        addressController: addressController,
                        darjaId: darjaSelection.id ?? '',
                        darjaName: darjaSelection.name,
                        pickedPhoto: pickedPhoto,
                      ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _submitNewAdmission(
    BuildContext screenContext,
    BuildContext dialogContext,
    WidgetRef ref,
    VoidCallback setSaving,
    VoidCallback clearSaving, {
    required TextEditingController nameController,
    required TextEditingController fatherNameController,
    required TextEditingController phoneController,
    required TextEditingController addressController,
    required String darjaId,
    required String darjaName,
    required XFile? pickedPhoto,
  }) async {
    if (nameController.text.isEmpty || fatherNameController.text.isEmpty) {
      return;
    }
    setSaving();
    try {
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
        darjaId: darjaId,
        darjaName: darjaName,
        classId: darjaId,
        className: darjaName,
        phone: phoneController.text.trim().isEmpty
            ? null
            : phoneController.text.trim(),
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
      if (dialogContext.mounted) Navigator.pop(dialogContext); // close dialog
      if (screenContext.mounted) {
        showM360SnackBar(
            screenContext, '${nameController.text} کا داخلہ کامیابی سے ہو گیا');
      }
    } catch (_) {
      clearSaving();
      if (screenContext.mounted) {
        showM360SnackBar(screenContext, 'داخلہ میں خطا', isError: true);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Edit student dialog (same fields, same validation, same save flow)
  // ─────────────────────────────────────────────────────────────

  static void showEditStudent(
      BuildContext context, WidgetRef ref, Student student) {
    final screenContext = context;
    final nameController = TextEditingController(text: student.name);
    final fatherNameController =
        TextEditingController(text: student.fatherName);
    final phoneController = TextEditingController(text: student.phone ?? '');

    // Preselect the student's real darja row id; a legacy display-string id
    // won't match any row and falls back to the first real darja.
    final darjaSelection = DarjaSelection()
      ..id = student.classId.isNotEmpty ? student.classId : null
      ..name = student.className;
    XFile? pickedPhoto;
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => M360Dialog(
          title: 'طالب علم کی معلومات ترمیم کریں',
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
                M360TextField(
                  controller: nameController,
                  label: 'طالب علم کا نام',
                  prefixIcon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                M360TextField(
                  controller: fatherNameController,
                  label: 'والد کا نام',
                  prefixIcon: Icons.family_restroom,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'والد کا نام درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                M360TextField(
                  controller: phoneController,
                  label: 'فون نمبر',
                  prefixIcon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'فون نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                darjaPicker(
                  selection: darjaSelection,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            M360TertiaryButton(
              label: 'منسوخ کریں',
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
            ),
            M360PrimaryButton(
              label: 'ترمیم کریں',
              isLoading: saving,
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.isEmpty ||
                          fatherNameController.text.isEmpty) {
                        return;
                      }
                      setState(() => saving = true);
                      try {
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
                          darjaId: darjaSelection.id ?? '',
                          darjaName: darjaSelection.name,
                          classId: darjaSelection.id ?? '',
                          className: darjaSelection.name,
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
                          Navigator.pop(dialogContext); // close dialog
                        }
                        if (screenContext.mounted) {
                          showM360SnackBar(screenContext,
                              '${nameController.text} کی معلومات ترمیم کر دی گئیں');
                        }
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setState(() => saving = false);
                        }
                        if (screenContext.mounted) {
                          showM360SnackBar(screenContext, 'ترمیم میں خطا',
                              isError: true);
                        }
                      }
                    },
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
    final screenContext = context;
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
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, innerRef, _) => StatefulBuilder(
          builder: (context, setState) => M360Dialog(
            title: '${student.name} کی فیس',
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
                  M360Dropdown<String>(
                    label: 'فیس کی قسم',
                    prefixIcon: Icons.category,
                    items: [
                      for (final v in feeTypeOptions)
                        M360DropdownItem(value: v, label: v),
                    ],
                    value: selectedFeeType,
                    onChanged: (value) => setState(
                        () => selectedFeeType = value ?? feeTypeOptions.first),
                  ),
                  const SizedBox(height: 16),
                  M360Dropdown<String>(
                    label: 'ماہ',
                    prefixIcon: Icons.calendar_month,
                    items: [
                      for (final v in monthOptions)
                        M360DropdownItem(value: v, label: v),
                    ],
                    value: selectedMonth,
                    onChanged: (value) => setState(
                        () => selectedMonth = value ?? monthOptions.first),
                  ),
                  const SizedBox(height: 16),
                  M360TextField(
                    controller: amountController,
                    label: 'رقم',
                    prefixIcon: Icons.attach_money,
                    keyboardType: TextInputType.number,
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
                  M360TextField(
                    controller: descriptionController,
                    label: 'تفصیل (اختیاری)',
                    prefixIcon: Icons.description,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              M360TertiaryButton(
                label: 'منسوخ کریں',
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
              ),
              M360PrimaryButton(
                label: 'وصول کریں',
                isLoading: saving,
                onPressed: saving
                    ? null
                    : () async {
                        final amount = double.tryParse(amountController.text);
                        if (amount == null || amount <= 0) {
                          showM360SnackBar(screenContext, 'درست رقم درج کریں',
                              isError: true);
                          return;
                        }
                        setState(() => saving = true);
                        try {
                          final monthIdx = monthOptions.indexOf(selectedMonth);
                          final monthValue =
                              monthValues[monthIdx < 0 ? 0 : monthIdx];
                          final fees = innerRef
                                  .read(feesByStudentProvider(student.id))
                                  .valueOrNull ??
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
                          final Fee record;
                          if (existing != null) {
                            record = existing.copyWith(
                              amountPaid: existing.amountPaid + amount,
                              paidDate: todayStr,
                            );
                          } else {
                            final tenantId =
                                innerRef.read(currentTenantIdProvider);
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
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (screenContext.mounted) {
                            showM360SnackBar(screenContext,
                                'ر ${formatPK(amount)} کی $selectedFeeType کامیابی سے وصول کر لی گئی');
                          }
                        } catch (_) {
                          if (dialogContext.mounted) {
                            setState(() => saving = false);
                          }
                          if (screenContext.mounted) {
                            showM360SnackBar(
                                screenContext, 'فیس وصول کرنے میں خطا',
                                isError: true);
                          }
                        }
                      },
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
            ? CachedNetworkImageProvider(currentPhotoUrl!,
                maxWidth: 256, maxHeight: 256) as ImageProvider
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
                  color: AppColors.gold,
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
