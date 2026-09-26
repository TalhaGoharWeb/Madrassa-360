import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../auth/login_screen.dart';
import '../settings/user_management_hub.dart';
import '../settings/delegation_screen.dart';
import 'about_screen.dart';

/// پروفائل سکرین
/// Profile Screen (Placeholder for Phase 1)
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Gradient header ──────────────────────────────
          SliverToBoxAdapter(child: _buildProfileHeader()),

          // ── Settings groups ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Account group
                  _GroupLabel('اکاؤنٹ'),
                  const SizedBox(height: 8),
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

                  const SizedBox(height: 20),

                  // Administration group (Phase 8a — permission-gated)
                  Builder(
                    builder: (context) {
                      final canManage =
                          ref.watch(roleServiceProvider).canManageUsers();
                      if (!canManage) {
                        return const SizedBox.shrink();
                      }
                      // Delegation management needs `roles.assign` (Phase 8b).
                      final canDelegate =
                          ref.watch(roleServiceProvider).canManageRoles();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GroupLabel('انتظام'),
                          const SizedBox(height: 8),
                          _SettingsGroup(children: [
                            _SettingsTile(
                              icon: Icons.people_alt_outlined,
                              label: 'صارفین اور ذمہ داریاں',
                              subtitle: 'صارفین بنائیں، ذمہ داریاں سونپیں',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const UserManagementHubScreen(),
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
                          const SizedBox(height: 20),
                        ],
                      );
                    },
                  ),

                  // Support group
                  _GroupLabel('معاونت'),
                  const SizedBox(height: 8),
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

                  const SizedBox(height: 20),

                  // Danger zone
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

                  const SizedBox(height: 32),

                  // Footer
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
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            children: [
              // AppBar row
              Row(
                children: [
                  Text(
                    AppStrings.profile,
                    style: AppTypography.headingSmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white70, size: 22),
                    onPressed: () => _showEditProfileSheet(context),
                    tooltip: 'پروفائل ترمیم',
                  ),
                ],
              ),
              const SizedBox(height: 16),

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
                    // app-wide RTL layout (Phase 13).
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
                    style:
                        AppTypography.labelMedium.copyWith(color: Colors.white),
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
                      style: AppTypography.labelMedium
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('پروفائل ترتیبات', style: AppTypography.titleLarge),
              const SizedBox(height: 20),

              // Photo picker
              GestureDetector(
                onTap: () async {
                  final picked = await ImagePicker()
                      .pickImage(source: ImageSource.gallery, imageQuality: 70);
                  if (picked != null) {
                    setSheetState(() => tempPhotoPath = picked.path);
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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
              const SizedBox(height: 20),

              // Name
              TextField(
                controller: nameCtrl,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: 'نام',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Phone
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'فون نمبر',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Email
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'ای میل',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final phone = phoneCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(sheetContext);
                    await _saveProfile(name, phone, email, tempPhotoPath);
                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('پروفائل محفوظ کر دیا گیا'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child:
                      Text('محفوظ کریں', style: AppTypography.labelLarge),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('اطلاعات کی ترتیبات', style: AppTypography.titleLarge),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('محفوظ کریں'),
          ),
        ],
      ),
    );
  }

  void _showLanguageSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('زبان منتخب کریں', style: AppTypography.titleLarge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption('اردو', true),
            _buildLanguageOption('انگریزی', false),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بند کریں'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      // Phase 4 — contact section is tenant-driven (was hard-coded
      // institution email/phone via AppConfig).
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final branding = ref.watch(tenantBrandingProvider).valueOrNull;
          final contactLines = [
            if (branding?.phone?.isNotEmpty == true) branding!.phone!,
            if (branding?.email?.isNotEmpty == true) branding!.email!,
          ];
          return AlertDialog(
            title: Text('مدد اور معاونت', style: AppTypography.titleLarge),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'استعمال کرنے کے طریقے:',
                    style: AppTypography.bodyLarge
                        .copyWith(fontWeight: FontWeight.bold),
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
                    style: AppTypography.bodyLarge
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    contactLines.isNotEmpty ? contactLines.join('\n') : '—',
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('بند کریں'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('لاگ آؤٹ کی تصدیق', style: AppTypography.titleLarge),
        content: Text(
          'کیا آپ واقعی لاگ آؤٹ کرنا چاہتے ہیں؟',
          style: AppTypography.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('منسوخ کریں'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              // Real sign-out: revoke the Supabase session + clear tenant
              // context (handled inside the auth provider).
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              // Navigate back to login screen
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: Text(
              'لاگ آؤٹ',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String label, bool initialValue) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool value = initialValue;
        return SwitchListTile(
          title: Text(label, style: AppTypography.bodyMedium),
          value: value,
          onChanged: (newValue) => setState(() => value = newValue),
          activeThumbColor: AppColors.primary,
        );
      },
    );
  }

  Widget _buildLanguageOption(String language, bool isSelected) {
    return ListTile(
      title: Text(language, style: AppTypography.bodyLarge),
      trailing: isSelected ? Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$language منتخب کی گئی')),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      // Directional indent so the label mirrors with RTL (Phase 13).
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
      child: Text(
        text,
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colour, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: AppTypography.bodyLarge
                              .copyWith(color: textColour)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: AppTypography.labelSmall
                                .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left,
                    color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 68,
            color: AppColors.divider,
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
          Text(label,
              style: AppTypography.labelSmall.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }
}
