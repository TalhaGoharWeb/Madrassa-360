/// ادارے کا انتخاب
/// Tenant Picker — shown when the signed-in user has >1 active membership.
/// Tapping an institution selects it via [TenantContext] and enters the app.
///
/// VISUAL ONLY: m360 cards/states/buttons. The membership list, selection
/// flow and sign-out are unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/services/tenant_context.dart';
import '../../../providers/auth_provider.dart';
import '../../shell/app_shell.dart';
import 'login_screen.dart';

/// Short Urdu labels for common membership roles.
const _roleUrduLabels = <String, String>{
  'madrasa_admin': 'منتظم',
  'admin': 'منتظم',
  'super_admin': 'سپر ایڈمن',
  'teacher': 'استاد',
  'parent': 'والدین',
  'student': 'طالب علم',
  'accountant': 'محاسب',
};

String _roleLabel(String role) {
  final key = role.trim().toLowerCase();
  final urdu = _roleUrduLabels[key];
  final pretty = key.replaceAll('_', ' ');
  final capitalized =
      pretty.isEmpty ? pretty : pretty[0].toUpperCase() + pretty.substring(1);
  return urdu != null ? '$urdu ($capitalized)' : capitalized;
}

class TenantPickerScreen extends ConsumerStatefulWidget {
  const TenantPickerScreen({super.key});

  @override
  ConsumerState<TenantPickerScreen> createState() => _TenantPickerScreenState();
}

class _TenantPickerScreenState extends ConsumerState<TenantPickerScreen> {
  String? _switchingId;

  Future<void> _select(String tenantId) async {
    if (_switchingId != null) return;
    setState(() => _switchingId = tenantId);
    try {
      await ref.read(authProvider.notifier).selectTenant(tenantId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } finally {
      if (mounted) setState(() => _switchingId = null);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberships = ref.watch(tenantMembershipsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('ادارہ منتخب کریں', style: AppTypography.titleLarge),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          M360IconButton(
            icon: Icons.logout,
            tooltip: 'لاگ آؤٹ',
            color: Colors.white,
            onPressed: _signOut,
          ),
        ],
      ),
      body: memberships.when(
        loading: () => const M360LoadingState(),
        error: (e, _) => M360ErrorState(
          message: 'اداروں کی فہرست لوڈ نہیں ہو سکی',
          onRetry: () => ref.invalidate(tenantMembershipsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const M360EmptyState(
              icon: Icons.business_outlined,
              title: 'کوئی ادارہ دستیاب نہیں',
              description:
                  'آپ کے اکاؤنٹ سے کوئی ادارہ منسلک نہیں ہے۔ اپنے منتظم سے رابطہ کریں۔',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[i];
              final switching = _switchingId == m.tenantId;
              return M360TappableCard(
                margin: const EdgeInsets.only(bottom: 12),
                onTap: switching ? null : () => _select(m.tenantId),
                semanticLabel: m.tenantName,
                child: Row(
                  children: [
                    m.logoUrl != null && m.logoUrl!.isNotEmpty
                        ? CircleAvatar(
                            radius: 24,
                            backgroundImage: NetworkImage(m.logoUrl!),
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.1),
                          )
                        : CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.1),
                            // No uploaded logo → show the app icon itself as
                            // the brand mark, never a generic glyph.
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                semanticLabel: 'مدرسہ 360 لوگو',
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.mosque,
                                        color: AppColors.primary),
                              ),
                            ),
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.tenantName, style: AppTypography.titleMedium),
                          if (m.tenantNameUrdu != null &&
                              m.tenantNameUrdu!.isNotEmpty)
                            Text(m.tenantNameUrdu!,
                                style: AppTypography.bodyMedium),
                          const SizedBox(height: 6),
                          M360Badge.custom(
                            label: _roleLabel(m.role),
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (switching)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.chevron_left, color: AppColors.primary),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
