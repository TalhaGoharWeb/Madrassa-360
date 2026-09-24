import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// ایپ ڈراور
/// Common App Drawer — available for use in any role screen
class AppDrawer extends StatelessWidget {
  final String role;
  final String userName;
  final String? profileImageUrl; // optional; shows initial avatar if null
  final List<DrawerMenuItem> menuItems;
  final void Function(int) onMenuTap;
  final int selectedIndex;

  const AppDrawer({
    super.key,
    required this.role,
    required this.userName,
    this.profileImageUrl,
    required this.menuItems,
    required this.onMenuTap,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                final item = menuItems[index];
                final isSelected = selectedIndex == index;
                return ListTile(
                  leading: Icon(item.icon, color: isSelected ? AppColors.primary : AppColors.textSecondary),
                  title: Text(
                    item.label,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onTap: () => onMenuTap(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final initial = userName.isNotEmpty ? userName[0] : '?';
    return UserAccountsDrawerHeader(
      decoration: const BoxDecoration(
        color: AppColors.primary,
      ),
      currentAccountPicture: CircleAvatar(
        backgroundImage: profileImageUrl != null && profileImageUrl!.isNotEmpty
            ? NetworkImage(profileImageUrl!)
            : null,
        backgroundColor: Colors.white24,
        child: profileImageUrl == null || profileImageUrl!.isEmpty
            ? Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      accountName: Text(userName, style: AppTypography.appBarTitle.copyWith(color: Colors.white)),
      accountEmail: Text(role, style: AppTypography.titleMedium.copyWith(color: Colors.white70)),
    );
  }
}

class DrawerMenuItem {
  final IconData icon;
  final String label;

  const DrawerMenuItem({
    required this.icon,
    required this.label,
  });
}
