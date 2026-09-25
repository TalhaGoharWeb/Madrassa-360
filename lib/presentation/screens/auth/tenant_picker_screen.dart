import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../providers/auth_provider.dart';
import '../main_screen.dart';
import 'login_screen.dart';

/// ادارے کا انتخاب
/// Tenant Picker — shown when the signed-in user has >1 active membership.
/// Tapping an institution selects it via [TenantContext] and enters the app.

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
  ConsumerState<TenantPickerScreen> createState() =>
      _TenantPickerScreenState();
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
        MaterialPageRoute(builder: (_) => const MainScreen()),
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
          IconButton(
            tooltip: 'لاگ آؤٹ',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: memberships.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 56, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  'اداروں کی فہرست لوڈ نہیں ہو سکی',
                  style: AppTypography.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.invalidate(tenantMembershipsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('دوبارہ کوشش کریں'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                'کوئی ادارہ دستیاب نہیں',
                style: AppTypography.bodyLarge,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final m = items[i];
              final switching = _switchingId == m.tenantId;
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: m.logoUrl != null && m.logoUrl!.isNotEmpty
                      ? CircleAvatar(
                          backgroundImage: NetworkImage(m.logoUrl!),
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                        )
                      : CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withOpacity(0.1),
                          child: const Icon(Icons.mosque,
                              color: AppColors.primary),
                        ),
                  title: Text(m.tenantName,
                      style: AppTypography.titleMedium),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.tenantNameUrdu != null &&
                          m.tenantNameUrdu!.isNotEmpty)
                        Text(m.tenantNameUrdu!,
                            style: AppTypography.bodyMedium),
                      const SizedBox(height: 4),
                      Chip(
                        label: Text(
                          _roleLabel(m.role),
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  trailing: switching
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_ios,
                          color: AppColors.primary),
                  onTap: switching ? null : () => _select(m.tenantId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
