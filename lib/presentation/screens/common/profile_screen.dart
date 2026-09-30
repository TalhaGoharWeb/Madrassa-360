/// پروفائل سکرین
/// Profile — identity hero, settings groups, support and sign-out.
///
/// Renders inside [AppShell] via [ShellPageBody] (no nested Scaffold).
/// All values are real session data (auth provider, role service, tenant
/// branding); SharedPreferences holds only locally-edited phone/photo
/// fallbacks. Sign-out keeps its exact flow, confirmed via the
/// design-system dialog.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/services/role_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../../shell/shell_page_body.dart';
import '../auth/login_screen.dart';
import '../settings/user_management_hub.dart';
import '../settings/delegation_screen.dart';
import 'about_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Profile values — loaded from SharedPreferences; empty until user saves them
  String _name = '';
  String _phone = '';
  String _email = '';
  String? _photoPath;

  static const _kName = 'profile_name';
  static const _kPhone = 'profile_phone';
  static const _kEmail = 'profile_email';
  static const _kPhoto = 'profile_photo_path';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name = prefs.getString(_kName) ?? '';
      _phone = prefs.getString(_kPhone) ?? '';
      _email = prefs.getString(_kEmail) ?? '';
      _photoPath = prefs.getString(_kPhoto);
    });
  }

  Future<void> _saveProfile(
      String name, String phone, String email, String? photoPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, name);
    await prefs.setString(_kPhone, phone);
    await prefs.setString(_kEmail, email);
    if (photoPath != null) await prefs.setString(_kPhoto, photoPath);
    if (!mounted) return;
    setState(() {
      _name = name;
      _phone = phone;
      _email = email;
      if (photoPath != null) _photoPath = photoPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(roleServiceProvider).canManageUsers();
    final canDelegate = ref.watch(roleServiceProvider).canManageRoles();

    return ShellPageBody(
      backgroundColor: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProfileHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                // Account group
                const M360SectionHeader(
                  title: 'اکاؤنٹ',
                  padding: EdgeInsets.only(bottom: 4),
                ),
                _SettingsGroup(children: [
                  _SettingsTile(
                    icon: Icons.manage_accounts_outlined,
                    label: 'پروفائل ترتیبات',
                    subtitle: 'نام، فون، تصویر تبدیل کریں',
                    onTap: () => _showEditProfileSheet(context),
                  ),
                  _SettingsTile(
                    icon: Icons.notifications_outlined,
                    label: 'اطلاعات',
                    subtitle: 'پش نوٹیفکیشن کنٹرول کریں',
                    onTap: () => _showNotificationSettings(context),
                  ),
                  _SettingsTile(
                    icon: Icons.language_outlined,
                    label: 'زبان',
                    subtitle: 'اردو / English',
                    onTap: () => _showLanguageSettings(context),
                    isLast: true,
                  ),
                ]),
                const SizedBox(height: 12),

                // Administration group (permission-gated)
                if (canManage) ...[
                  const M360SectionHeader(
                    title: 'انتظام',
                    padding: EdgeInsets.only(bottom: 4),
                  ),
                  _SettingsGroup(children: [
                    _SettingsTile(
                      icon: Icons.people_alt_outlined,
                      label: 'صارفین اور ذمہ داریاں',
                      subtitle: 'صارفین بنائیں، ذمہ داریاں سونپیں',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UserManagementHubScreen(),
                        ),
                      ),
                      isLast: !canDelegate,
                    ),
                    if (canDelegate)
                      _SettingsTile(
                        icon: Icons.handshake_outlined,
                        label: 'اختیار سونپنا',
                        subtitle: 'کسی صارف کو عارضی اختیار دیں',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DelegationScreen(),
                          ),
                        ),
                        isLast: true,
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],

                // Support group
                const M360SectionHeader(
                  title: 'معاونت',
                  padding: EdgeInsets.only(bottom: 4),
                ),
                _SettingsGroup(children: [
                  _SettingsTile(
                    icon: Icons.help_outline,
                    label: 'مدد اور رہنمائی',
                    subtitle: 'استعمال کرنے کا طریقہ',
                    onTap: () => _showHelpDialog(context),
                  ),
                  _SettingsTile(
                    icon: Icons.info_outline,
                    label: 'ایپ کے بارے میں',
                    subtitle: 'ڈویلپر معلومات، منصوبے کی تفصیل',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                    isLast: true,
                  ),
                ]),
                const SizedBox(height: 12),

                // Sign out
                _SettingsGroup(children: [
                  _SettingsTile(
                    icon: Icons.logout,
                    label: 'لاگ آؤٹ',
                    subtitle: 'اپنے اکاؤنٹ سے باہر نکلیں',
                    onTap: () => _showLogoutConfirmation(context),
                    isDestructive: true,
                    isLast: true,
                  ),
                ]),

                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Madrasa 360',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    // Real session data — never mock: name/email from the auth provider,
    // Urdu role label from the role service (tenant's own display_urdu
    // wins), institution name from tenant branding. SharedPreferences
    // values are only fallbacks for locally-edited phone/photo.
    final user = ref.watch(currentUserProvider);
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    final authName = (user?.name ?? '').trim();
    final displayName = authName.isNotEmpty
        ? authName
        : (_name.isNotEmpty ? _name : 'اپنا نام شامل کریں');
    final authEmail = (user?.email ?? '').trim();
    final displayEmail = authEmail.isNotEmpty ? authEmail : _email;
    final authPhone = (user?.phone ?? '').trim();
    final displayPhone = authPhone.isNotEmpty ? authPhone : _phone;
    final hasRealName = displayName != 'اپنا نام شامل کریں';
    final initial = hasRealName ? displayName.trim()[0] : '';

    final roleKey =
        roleKeys.isNotEmpty ? roleKeys.first : (user?.role.name ?? '');
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            children: [
              // Header row
              Row(
                children: [
                  Text(
                    AppStrings.profile,
                    style: AppTypography.headingSmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  M360IconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'پروفائل ترمیم',
                    color: Colors.white70,
                    onPressed: () => _showEditProfileSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Avatar
              GestureDetector(
                onTap: () => _showEditProfileSheet(context),
                child: Stack(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.2),
                        border: Border.all(color: Colors.white54, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _photoPath != null
                            ? Image.file(File(_photoPath!), fit: BoxFit.cover)
                            : initial.isNotEmpty
                                ? Center(
                                    child: Text(
                                      initial,
                                      style: AppTypography.titleLarge.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.person,
                                    size: 48, color: Colors.white),
                      ),
                    ),
                    // Directional badge position so it mirrors with the
                    // app-wide RTL layout.
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

              // Name
              Text(
                displayName,
                style: AppTypography.titleLarge.copyWith(
                  color: hasRealName ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),

              // Role badge — real Urdu label from the role service
              // (tenant's own display_urdu wins over template labels).
              FutureBuilder<String>(
                future: roleKey.isEmpty
                    ? Future.value('مہمان')
                    : roleService.roleUrduLabel(roleKey),
                builder: (context, snap) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Text(
                    snap.data ?? '…',
                    style: AppTypography.labelNastaliq.copyWith(
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Institution / tenant name
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mosque, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      madrasaName,
                      style: AppTypography.labelNastaliq
                          .copyWith(color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Contact info pills
              if (displayPhone.isNotEmpty || displayEmail.isNotEmpty)
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (displayPhone.isNotEmpty)
                      _ContactPill(
                          icon: Icons.phone_outlined, label: displayPhone),
                    if (displayEmail.isNotEmpty)
                      _ContactPill(
                          icon: Icons.email_outlined, label: displayEmail),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditProfileSheet(BuildContext context) {
    // Prefill from the signed-in user first; locally saved values are the
    // fallback (e.g. device-local phone/photo customisations).
    final user = ref.read(currentUserProvider);
    final nameCtrl =
        TextEditingController(text: _name.isNotEmpty ? _name : user?.name);
    final phoneCtrl =
        TextEditingController(text: _phone.isNotEmpty ? _phone : user?.phone);
    final emailCtrl =
        TextEditingController(text: _email.isNotEmpty ? _email : user?.email);
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
                // Drag handle
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

                // Photo picker
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
                const SizedBox(height: 12),
                M360TextField(
                  label: 'ای میل',
                  hint: 'example@mail.com',
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                ),
                const SizedBox(height: 24),

                M360PrimaryButton(
                  label: 'محفوظ کریں',
                  icon: Icons.check,
                  fullWidth: true,
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final phone = phoneCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    Navigator.pop(sheetContext);
                    await _saveProfile(name, phone, email, tempPhotoPath);
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

  void _showNotificationSettings(BuildContext context) {
    showM360Dialog<void>(
      context,
      title: 'اطلاعات کی ترتیبات',
      icon: Icons.notifications_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSwitchRow('کلاس کی اطلاعات', true),
          _buildSwitchRow('امتحانات کی اطلاعات', true),
          _buildSwitchRow('فیس کی اطلاعات', true),
          _buildSwitchRow('تقسیمات کی اطلاعات', false),
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: 'بند کریں',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _showLanguageSettings(BuildContext context) {
    showM360Dialog<void>(
      context,
      title: 'زبان منتخب کریں',
      icon: Icons.language_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLanguageOption('اردو', true),
          _buildLanguageOption('انگریزی', false),
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: 'بند کریں',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _showHelpDialog(BuildContext context) {
    // Contact section is tenant-driven (was hard-coded institution
    // email/phone via AppConfig).
    showM360Dialog<void>(
      context,
      title: 'مدد اور معاونت',
      icon: Icons.help_outline,
      content: Consumer(
        builder: (context, ref, _) {
          final branding = ref.watch(tenantBrandingProvider).valueOrNull;
          final contactLines = [
            if (branding?.phone?.isNotEmpty == true) branding!.phone!,
            if (branding?.email?.isNotEmpty == true) branding!.email!,
          ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'استعمال کرنے کے طریقے:',
                style: AppTypography.labelNastaliq
                    .copyWith(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '• ڈیش بورڈ: اپنی کلاسوں اور طلباء کی معلومات دیکھیں\n'
                '• حاضری: طلباء کی حاضری مارک کریں\n'
                '• نتائج: امتحانات کے نتائج درج اور دیکھیں\n'
                '• پروفائل: اپنی معلومات دیکھیں اور ترتیبات تبدیل کریں',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'رابطہ کریں:',
                style: AppTypography.labelNastaliq
                    .copyWith(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                contactLines.isNotEmpty ? contactLines.join('\n') : '—',
                style: AppTypography.bodyMedium,
              ),
            ],
          );
        },
      ),
      actions: [
        M360TertiaryButton(
          label: 'بند کریں',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showM360ConfirmDialog(
      context,
      title: 'لاگ آؤٹ کی تصدیق',
      message: 'کیا آپ واقعی لاگ آؤٹ کرنا چاہتے ہیں؟',
      confirmLabel: 'لاگ آؤٹ',
      danger: true,
    ).then((confirmed) async {
      if (!confirmed) return;
      // Real sign-out: revoke the Supabase session + clear tenant
      // context (handled inside the auth provider).
      await ref.read(authProvider.notifier).logout();
      if (!context.mounted) return;
      // Navigate back to login screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  Widget _buildSwitchRow(String label, bool initialValue) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool value = initialValue;
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: AppTypography.labelNastaliq),
          value: value,
          onChanged: (newValue) => setState(() => value = newValue),
          activeThumbColor: AppColors.primary,
        );
      },
    );
  }

  Widget _buildLanguageOption(String language, bool isSelected) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(language,
          style: AppTypography.isUrduText(language)
              ? AppTypography.labelNastaliq
                  .copyWith(fontSize: 17, fontWeight: FontWeight.normal)
              : AppTypography.bodyLarge),
      trailing:
          isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () => showM360SnackBar(context, '$language منتخب کی گئی'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return M360Card(
      padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.isDestructive = false,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final bool isDestructive;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colour = isDestructive ? AppColors.error : AppColors.primary;
    final textColour = isDestructive ? AppColors.error : AppColors.textPrimary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colour, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTypography.labelNastaliq.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.normal,
                          color: textColour,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppTypography.labelNastaliq.copyWith(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left,
                    color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Padding(
            // Inset the divider to align with the text column (below the
            // 40px icon + 14px gap + 16px outer padding). Direction-aware
            // so it stays aligned in RTL.
            padding: EdgeInsetsDirectional.only(start: 70),
            child: Divider(height: 1, color: AppColors.divider),
          ),
      ],
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
