/// پروفائل بٹن — ہر ڈیش بورڈ کی AppBar میں
/// Tappable avatar shown in every dashboard AppBar (via [DashboardScaffold]).
/// Opens the [ProfileScreen] where the user can view their account and
/// log out. Shows the user's first initial; falls back to a person icon
/// when no signed-in user is available.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../screens/common/profile_screen.dart';

class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = (user?.name ?? '').trim();
    final initial = name.isNotEmpty ? name[0] : '';

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        child: Tooltip(
          message: 'پروفائل',
          child: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: initial.isNotEmpty
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  )
                : const Icon(
                    Icons.person_outline,
                    size: 20,
                    color: AppColors.primary,
                  ),
          ),
        ),
      ),
    );
  }
}
