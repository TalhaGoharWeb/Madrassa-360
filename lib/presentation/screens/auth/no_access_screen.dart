import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/auth_provider.dart';
import 'login_screen.dart';

/// رسائی نہیں ہے
/// No Access — the signed-in account has no active tenant membership
/// (and is not a platform admin). The only way forward is contacting the
/// institution administrator, or signing out.

class NoAccessScreen extends ConsumerWidget {
  const NoAccessScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authProvider.notifier).logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authProvider).user?.email;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.no_accounts_outlined,
                  size: 48,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'رسائی دستیاب نہیں',
                style: AppTypography.headingSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'آپ کے اکاؤنٹ کو کسی ادارے تک رسائی حاصل نہیں ہے۔ براہ کرم اپنے ادارے کے منتظم سے رابطہ کریں۔',
                style: AppTypography.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (email != null && email.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  email,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                ),
              ],
              const SizedBox(height: 40),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _signOut(context, ref),
                  icon: const Icon(Icons.logout),
                  label: Text(
                    'لاگ آؤٹ',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
