/// رسائی نہیں ہے
/// No Access — the signed-in account has no active tenant membership
/// (and is not a platform admin). The only way forward is contacting the
/// institution administrator, or signing out.
///
/// VISUAL ONLY: the m360 button language and [M360Email] for the account
/// address. Sign-out flow and navigation are unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../providers/auth_provider.dart';
import 'login_screen.dart';

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
              Center(
                child: Container(
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
                M360Email(
                  email,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              M360PrimaryButton(
                label: 'لاگ آؤٹ',
                icon: Icons.logout,
                fullWidth: true,
                onPressed: () => _signOut(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
