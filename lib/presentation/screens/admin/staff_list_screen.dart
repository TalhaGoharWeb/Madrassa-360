import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:madrasa_360/core/design/m360.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/money_format.dart';
import '../../../data/models/staff.dart';
import '../../../providers/staff_provider.dart';

/// عملہ کی فہرست — m360 redesign (Phase 10)
///
/// Same providers and flows (list/search/filter → details → create/edit,
/// phone dial, photo upload). Rendered as an [AppShell] destination: no
/// Scaffold, no AppBar — [PageContainer]/[PageHeader] only. Deleting a
/// staff record goes through a destructive [showM360ConfirmDialog].
class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  String _selectedDepartment = 'all';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Dials the staff member's phone number (real device action).
  Future<void> _callStaff(String phone) async {
    final number = phone.trim();
    if (number.isEmpty) {
      if (!mounted) return;
      showM360SnackBar(context, 'فون نمبر درج نہیں', isError: true);
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      showM360SnackBar(context, 'کال شروع نہیں ہو سکی', isError: true);
    }
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
    final staffAsync = ref.watch(allStaffProvider);

    return PageContainer(
      scrollable: false,
      header: PageHeader(
        title: 'عملہ',
        breadcrumb: 'منتظم',
        description: 'اساتذہ اور انتظامی عملے کی فہرست',
        actions: _withBack(context, [
          M360PrimaryButton(
            label: 'نیا عملہ',
            icon: Icons.person_add,
            onPressed: _showNewStaffDialog,
          ),
        ]),
      ),
      child: staffAsync.when(
        loading: () => const M360LoadingState(),
        error: (e, _) => M360ErrorState(
          message: 'عملہ لوڈ کرنے میں خطا ہوئی',
          onRetry: () => ref.invalidate(allStaffProvider),
        ),
        data: (staffList) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: M360SearchField(
                controller: _searchController,
                hint: 'عملہ تلاش کریں…',
                onChanged: (_) => setState(() {}),
              ),
            ),
            _buildDepartmentFilter(),
            _buildStatsRow(staffList),
            Expanded(child: _buildStaffList(staffList)),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentFilter() {
    const departments = [
      ('all', 'سب'),
      ('تعلیمی', 'تعلیمی'),
      ('انتظامیہ', 'انتظامیہ'),
      ('مالیات', 'مالیات'),
    ];
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: departments.length,
        itemBuilder: (context, index) {
          final (id, label) = departments[index];
          final isSelected = _selectedDepartment == id;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedDepartment = id),
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

  Widget _buildStatsRow(List<Staff> staffList) {
    final teachers = staffList.where((s) => s.department == 'تعلیمی').length;
    final totalSalary =
        staffList.fold<double>(0, (sum, s) => sum + (s.salary ?? 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: M360StatCard(
              value: '${staffList.length}',
              label: 'کل عملہ',
              icon: Icons.people,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: M360StatCard(
              value: '$teachers',
              label: 'اساتذہ',
              icon: Icons.school,
              iconBackground: AppColors.info.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: M360StatCard(
              value: formatPK(totalSalary),
              label: 'ماہانہ تنخواہ (روپے)',
              icon: Icons.payments,
              iconBackground: AppColors.success.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffList(List<Staff> staffList) {
    var filtered = staffList;
    if (_selectedDepartment != 'all') {
      filtered =
          filtered.where((s) => s.department == _selectedDepartment).toList();
    }
    final q = _searchController.text.trim();
    if (q.isNotEmpty) {
      filtered = filtered
          .where((s) => s.name.contains(q) || s.designation.contains(q))
          .toList();
    }

    if (filtered.isEmpty) {
      final searching = q.isNotEmpty || _selectedDepartment != 'all';
      return M360EmptyState(
        icon: Icons.person_off,
        title: 'کوئی عملہ نہیں ملا',
        description: searching
            ? 'تلاش یا فلٹر تبدیل کر کے دوبارہ کوشش کریں۔'
            : 'پہلا رکن شامل کر کے شروع کریں۔',
        actionLabel: searching ? null : 'نیا عملہ شامل کریں',
        onAction: searching ? null : _showNewStaffDialog,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _staffTile(filtered[index]),
    );
  }

  Widget _staffTile(Staff staff) {
    return M360TappableCard(
      onTap: () => _showStaffDetails(staff),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _Avatar(name: staff.name, size: 55),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.name, style: AppTypography.titleMedium),
                const SizedBox(height: 2),
                Text(
                  staff.designation,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _infoChip(Icons.apartment, staff.department ?? ''),
                    const SizedBox(width: 8),
                    _infoChip(Icons.calendar_today, staff.joiningDate),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              M360StatusChip(
                status:
                    staff.isActive ? M360Status.active : M360Status.inactive,
              ),
              const SizedBox(height: 8),
              M360IconButton(
                icon: Icons.phone,
                tooltip: 'فون کریں',
                onPressed: () => _callStaff(staff.phone),
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: AppTypography.labelSmall),
      ],
    );
  }

  // ── Staff details bottom sheet ──────────────────────────────

  void _showStaffDetails(Staff staff) {
    final screenCtx = context;
    showModalBottomSheet(
      context: screenCtx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Avatar(name: staff.name, size: 90),
                  const SizedBox(height: 16),
                  Text(staff.name, style: AppTypography.headingSmall),
                  const SizedBox(height: 8),
                  _StaffRoleBadge(
                    label: staff.designation,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  M360StatusChip(
                    status: staff.isActive
                        ? M360Status.active
                        : M360Status.inactive,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  _DetailRow(
                    icon: Icons.person,
                    label: 'والد کا نام',
                    value: staff.fatherName,
                  ),
                  _DetailRow(
                    icon: Icons.apartment,
                    label: 'شعبہ',
                    value: staff.department ?? '—',
                  ),
                  _DetailRow(
                    icon: Icons.phone,
                    label: 'فون نمبر',
                    value: staff.phone,
                  ),
                  _DetailRow(
                    icon: Icons.calendar_today,
                    label: 'تاریخ شمولیت',
                    value: staff.joiningDate,
                  ),
                  _DetailRow(
                    icon: Icons.payments,
                    label: 'ماہانہ تنخواہ',
                    value: '${formatPK(staff.salary ?? 0)} روپے',
                    iconColor: AppColors.success,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: M360SecondaryButton(
                          label: 'ترمیم',
                          icon: Icons.edit,
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            _showEditStaffDialog(staff);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: M360PrimaryButton(
                          label: 'فون کریں',
                          icon: Icons.phone,
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            _callStaff(staff.phone);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  M360DangerButton(
                    label: 'حذف کریں',
                    icon: Icons.delete_outline,
                    fullWidth: true,
                    onPressed: () =>
                        _confirmDeleteStaff(sheetCtx, screenCtx, staff),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteStaff(
    BuildContext sheetCtx,
    BuildContext screenCtx,
    Staff staff,
  ) async {
    final confirmed = await showM360ConfirmDialog(
      sheetCtx,
      title: 'عملہ حذف کریں؟',
      message:
          '«${staff.name}» کو مستقل طور پر حذف کر دیا جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(staffNotifierProvider.notifier).delete(staff.id);
      if (!sheetCtx.mounted) return;
      Navigator.of(sheetCtx).pop();
      if (!screenCtx.mounted) return;
      showM360SnackBar(screenCtx, 'عملہ حذف کر دیا گیا');
    } catch (_) {
      if (!sheetCtx.mounted) return;
      showM360SnackBar(sheetCtx, 'حذف کرنے میں خطا ہوئی', isError: true);
    }
  }

  // ── Create / edit dialogs ──────────────────────────────────

  Future<void> _showNewStaffDialog() async {
    final screenCtx = context;
    final name = await showM360Dialog<String>(
      screenCtx,
      title: 'نیا عملہ شامل کریں',
      icon: Icons.person_add,
      content: const _StaffForm(),
    );
    if (name != null && screenCtx.mounted) {
      showM360SnackBar(screenCtx, '$name کو عملہ میں شامل کر دیا گیا');
    }
  }

  Future<void> _showEditStaffDialog(Staff staff) async {
    final screenCtx = context;
    final name = await showM360Dialog<String>(
      screenCtx,
      title: 'عملہ معلومات ترمیم کریں',
      icon: Icons.edit,
      content: _StaffForm(existing: staff),
    );
    if (name != null && screenCtx.mounted) {
      showM360SnackBar(screenCtx, '$name کی معلومات محفوظ ہو گئیں');
    }
  }
}

// ─────────────────────────────────────────────────────────────

/// Gradient initial avatar.
class _Avatar extends StatelessWidget {
  final String name;
  final double size;

  const _Avatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isEmpty ? '؟' : name.substring(0, 1),
          style: AppTypography.titleLarge.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.labelSmall),
                Text(value, style: AppTypography.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Create / edit form (shared). Pops the saved staff name on success.
// ─────────────────────────────────────────────────────────────

class _StaffForm extends ConsumerStatefulWidget {
  final Staff? existing;

  const _StaffForm({this.existing});

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _fatherCtrl;
  late final TextEditingController _desigCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _salaryCtrl;
  late String _department;
  DateTime? _joiningDate;
  XFile? _pickedPhoto;
  bool _saving = false;

  static const _departments = ['تعلیمی', 'انتظامیہ', 'مالیات'];

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl = TextEditingController(text: s?.name);
    _fatherCtrl = TextEditingController(text: s?.fatherName);
    _desigCtrl = TextEditingController(text: s?.designation);
    _phoneCtrl = TextEditingController(text: s?.phone);
    _salaryCtrl =
        TextEditingController(text: s?.salary?.toInt().toString() ?? '');
    _department = s?.department ?? 'تعلیمی';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fatherCtrl.dispose();
    _desigCtrl.dispose();
    _phoneCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img != null && mounted) setState(() => _pickedPhoto = img);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final salary = double.tryParse(_salaryCtrl.text.trim());
    if (salary == null || salary <= 0) return;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final staff = Staff(
        id: existing?.id ?? const Uuid().v4(),
        tenantId: existing?.tenantId ?? ref.read(currentTenantIdProvider) ?? '',
        name: _nameCtrl.text.trim(),
        fatherName: _fatherCtrl.text.trim(),
        designation: _desigCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        joiningDate:
            existing?.joiningDate ?? _isoDate(_joiningDate ?? DateTime.now()),
        department: _department,
        salary: salary,
        cnic: existing?.cnic,
        userId: existing?.userId,
        photoUrl: existing?.photoUrl,
        isActive: existing?.isActive ?? true,
      );
      final saved = await ref.read(staffNotifierProvider.notifier).save(staff);
      if (_pickedPhoto != null) {
        await ref
            .read(staffNotifierProvider.notifier)
            .uploadPhoto(saved.id, _pickedPhoto!);
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved.name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'محفوظ کرنے میں خطا ہوئی', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    backgroundImage: _pickedPhoto != null
                        ? FileImage(File(_pickedPhoto!.path))
                        : (existing?.photoUrl != null
                            ? NetworkImage(existing!.photoUrl!) as ImageProvider
                            : null),
                    child: (_pickedPhoto == null && existing?.photoUrl == null)
                        ? const Icon(Icons.add_a_photo,
                            color: AppColors.primary, size: 30)
                        : null,
                  ),
                  const Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.edit, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          M360TextField(
            label: 'نام',
            hint: 'پورا نام لکھیں',
            controller: _nameCtrl,
            prefixIcon: Icons.person,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'نام درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'والد کا نام',
            controller: _fatherCtrl,
            prefixIcon: Icons.family_restroom,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'والد کا نام درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'عہدہ',
            controller: _desigCtrl,
            prefixIcon: Icons.work,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'عہدہ درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'فون نمبر',
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'فون نمبر درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360Dropdown<String>(
            label: 'شعبہ',
            value: _department,
            prefixIcon: Icons.apartment,
            items: [
              for (final d in _departments)
                M360DropdownItem(value: d, label: d),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _department = v);
            },
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'ماہانہ تنخواہ (روپے)',
            hint: 'مثال: 30000',
            controller: _salaryCtrl,
            keyboardType: TextInputType.number,
            prefixIcon: Icons.payments,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'تنخواہ درج کریں';
              final parsed = double.tryParse(v.trim());
              if (parsed == null || parsed <= 0) return 'درست تنخواہ درج کریں';
              return null;
            },
          ),
          if (existing == null) ...[
            const SizedBox(height: 12),
            M360DatePicker(
              label: 'تاریخ شمولیت',
              value: _joiningDate ?? DateTime.now(),
              formatter: _isoDate,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
              onChanged: (d) => setState(() => _joiningDate = d),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: M360TertiaryButton(
                  label: 'منسوخ کریں',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M360PrimaryButton(
                  label: existing == null ? 'شامل کریں' : 'محفوظ کریں',
                  icon: Icons.save,
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// RTL-aware colored pill badge (staff redesign detail).
class _StaffRoleBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StaffRoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: AppTypography.labelMedium
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
