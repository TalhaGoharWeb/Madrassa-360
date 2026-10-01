/// پروفائل — پلیٹ فارم کنسول
/// Console operator profile — view and edit the superadmin's own
/// identity (name, phone, photo).
///
/// Pushed from the console rail footer's profile button (replaces the old
/// "back to app" button there; the app-bar home icon remains the exit).
/// Keeps its own Scaffold (pushed-route pattern, like CreateMadrasaWizard).
///
/// Storage matches [ProfileScreen]: SharedPreferences holds the locally
/// edited name/phone/photo, and the shared [localProfileNameProvider] is
/// updated on save so every display-name chip refreshes immediately.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../providers/auth_provider.dart';

class ConsoleProfileScreen extends ConsumerStatefulWidget {
  const ConsoleProfileScreen({super.key, this.role});

  /// 'platform_owner' | 'platform_support' | null (still loading).
  final String? role;

  @override
  ConsumerState<ConsoleProfileScreen> createState() =>
      _ConsoleProfileScreenState();
}

class _ConsoleProfileScreenState extends ConsumerState<ConsoleProfileScreen> {
  // Same keys as ProfileScreen so both screens share one profile store.
  static const _kPhone = 'profile_phone';
  static const _kPhoto = 'profile_photo_path';

  String _phone = '';
  String? _photoPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _phone = prefs.getString(_kPhone) ?? '';
      _photoPath = prefs.getString(_kPhoto);
      _loading = false;
    });
  }

  Future<void> _saveProfile(
      String name, String phone, String? photoPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLocalProfileNameKey, name);
    await prefs.setString(_kPhone, phone);
    if (photoPath != null) await prefs.setString(_kPhoto, photoPath);
    // Keep the shared display-name provider in sync so every chip and
    // greeting refreshes without a restart.
    ref.read(localProfileNameProvider.notifier).state = name;
    if (!mounted) return;
    setState(() {
      _phone = phone;
      if (photoPath != null) _photoPath = photoPath;
    });
  }

  String get _roleLabel => widget.role == 'platform_owner' ? 'مالک' : 'منتظم';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final displayName = ref.watch(displayNameProvider('اپنا نام شامل کریں'));
    final email = (user?.email ?? '').trim();
    final authPhone = (user?.phone ?? '').trim();
    final displayPhone = authPhone.isNotEmpty ? authPhone : _phone;
    final hasRealName = displayName != 'اپنا نام شامل کریں';
    final initial = hasRealName ? displayName.trim()[0] : '';

    return Scaffold(
      appBar: const M360AppBar(title: 'پروفائل'),
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                // Identity hero.
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => _showEditSheet(context),
                          child: Stack(
                            children: [
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.2),
                                  border: Border.all(
                                      color: Colors.white54, width: 3),
                                ),
                                child: ClipOval(
                                  child: _photoPath != null
                                      ? Image.file(File(_photoPath!),
                                          fit: BoxFit.cover,
                                          semanticLabel: 'پروفائل تصویر')
                                      : initial.isNotEmpty
                                          ? Center(
                                              child: Text(
                                                initial,
                                                style: AppTypography.titleLarge
                                                    .copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          : const Icon(Icons.person,
                                              size: 48, color: Colors.white),
                                ),
                              ),
                              Positioned.directional(
                                textDirection: Directionality.of(context),
                                end: 2,
                                bottom: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt,
                                      color: AppColors.primary, size: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          displayName,
                          style: AppTypography.titleLarge.copyWith(
                            color: hasRealName ? Colors.white : Colors.white60,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Text(
                            _roleLabel,
                            style: AppTypography.labelNastaliq.copyWith(
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (displayPhone.isNotEmpty || email.isNotEmpty)
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              if (displayPhone.isNotEmpty)
                                _ContactPill(
                                    icon: Icons.phone_outlined,
                                    label: displayPhone),
                              if (email.isNotEmpty)
                                _ContactPill(
                                    icon: Icons.email_outlined, label: email),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Edit action — the single primary CTA.
                M360PrimaryButton(
                  label: 'پروفائل ترمیم کریں',
                  icon: Icons.edit_outlined,
                  fullWidth: true,
                  onPressed: () => _showEditSheet(context),
                ),
                const SizedBox(height: 12),

                // Read-only account facts.
                M360Card(
                  child: Column(
                    children: [
                      _FactRow(
                        icon: Icons.email_outlined,
                        label: 'ای میل',
                        value: email.isNotEmpty ? email : '—',
                      ),
                      _FactRow(
                        icon: Icons.badge_outlined,
                        label: 'صارف ID',
                        value: Supabase.instance.client.auth.currentUser?.id
                                .substring(0, 8) ??
                            '—',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _showEditSheet(BuildContext context) {
    final user = ref.read(currentUserProvider);
    final currentDisplayName = ref.read(displayNameProvider(''));
    final nameCtrl = TextEditingController(text: currentDisplayName);
    final phoneCtrl =
        TextEditingController(text: _phone.isNotEmpty ? _phone : user?.phone);
    String? tempPhotoPath = _photoPath;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  'پروفائل ترتیبات',
                  style: AppTypography.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await ImagePicker().pickImage(
                          source: ImageSource.gallery, imageQuality: 70);
                      if (picked != null) {
                        setSheetState(() => tempPhotoPath = picked.path);
                      }
                    },
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          backgroundImage: tempPhotoPath != null
                              ? FileImage(File(tempPhotoPath!)) as ImageProvider
                              : null,
                          child: tempPhotoPath == null
                              ? const Icon(Icons.person,
                                  size: 45, color: AppColors.primary)
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                M360TextField(
                  label: 'نام',
                  hint: 'اپنا نام لکھیں',
                  controller: nameCtrl,
                  prefixIcon: Icons.person_outline,
                ),
                const SizedBox(height: 12),
                M360TextField(
                  label: 'فون نمبر',
                  hint: '03xx-xxxxxxx',
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                ),
                const SizedBox(height: 24),
                M360PrimaryButton(
                  label: 'محفوظ کریں',
                  icon: Icons.check,
                  fullWidth: true,
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final phone = phoneCtrl.text.trim();
                    Navigator.pop(sheetContext);
                    await _saveProfile(name, phone, tempPhotoPath);
                    if (!context.mounted) return;
                    showM360SnackBar(context, 'پروفائل محفوظ کر دیا گیا');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactPill extends StatelessWidget {
  const _ContactPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: AppTypography.labelSmall
                  .copyWith(fontSize: 15, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(M360Radius.md),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.labelNastaliq.copyWith(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      value,
                      style: AppTypography.bodyMedium,
                      textDirection:
                          label == 'ای میل' ? TextDirection.ltr : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 70),
            child: Divider(height: 1, color: AppColors.divider),
          ),
      ],
    );
  }
}
