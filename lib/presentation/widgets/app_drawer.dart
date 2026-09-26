import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/widgets/tenant_logo.dart';
import '../../providers/tenant_branding_provider.dart';

/// ایپ ڈراور
/// Common App Drawer — available for use in any role screen.
///
/// Phase 4: the header strip shows the active tenant's logo + name
/// ([tenantBrandingProvider]) and tints with the tenant's primary colour.
/// Menu entries can carry a [DrawerMenuItem.module] key; when
/// [enabledModules] is provided, entries whose module the tenant has not
/// enabled are hidden (original indices are preserved, so [onMenuTap] and
/// [selectedIndex] keep referring to the caller's [menuItems] list).
class AppDrawer extends ConsumerWidget {
  final String role;
  final String userName;
  final String? profileImageUrl; // optional; shows initial avatar if null
  final List<DrawerMenuItem> menuItems;
  final void Function(int) onMenuTap;
  final int selectedIndex;

  /// When non-null, menu items whose [DrawerMenuItem.module] is not in
  /// this set are hidden. Null = modules not loaded yet → show all.
  final Set<String>? enabledModules;

  const AppDrawer({
    super.key,
    required this.role,
    required this.userName,
    this.profileImageUrl,
    required this.menuItems,
    required this.onMenuTap,
    required this.selectedIndex,
    this.enabledModules,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Visible entries with their ORIGINAL indices, so onMenuTap and
    // selectedIndex keep referring to the caller's menuItems list even
    // when module gating hides some entries.
    final entries = <({int index, DrawerMenuItem item})>[];
    for (var i = 0; i < menuItems.length; i++) {
      final item = menuItems[i];
      if (enabledModules == null ||
          item.module == null ||
          enabledModules!.contains(item.module)) {
        entries.add((index: i, item: item));
      }
    }
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final headerColor = branding?.primaryColor ?? AppColors.primary;

    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTenantStrip(branding, headerColor),
          _buildHeader(headerColor),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, listIndex) {
                final entry = entries[listIndex];
                final item = entry.item;
                final isSelected = selectedIndex == entry.index;
                return ListTile(
                  leading: Icon(item.icon,
                      color:
                          isSelected ? headerColor : AppColors.textSecondary),
                  title: Text(
                    item.label,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isSelected ? headerColor : AppColors.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onTap: () => onMenuTap(entry.index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Slim tenant branding strip: logo + institution name, tinted with the
  /// tenant's primary colour. Neutral placeholder while loading.
  Widget _buildTenantStrip(TenantBranding? branding, Color headerColor) {
    return Container(
      color: headerColor,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
      child: Row(
        children: [
          const TenantLogo(size: 40, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: branding == null
                ? const SizedBox.shrink()
                : TenantNameText(
                    style:
                        AppTypography.titleMedium.copyWith(color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color headerColor) {
    final initial = userName.isNotEmpty ? userName[0] : '?';
    return UserAccountsDrawerHeader(
      decoration: BoxDecoration(
        color: headerColor,
      ),
      currentAccountPicture: CircleAvatar(
        backgroundImage: profileImageUrl != null && profileImageUrl!.isNotEmpty
            ? NetworkImage(profileImageUrl!)
            : null,
        backgroundColor: Colors.white24,
        child: profileImageUrl == null || profileImageUrl!.isEmpty
            ? Text(
                initial,
                style: AppTypography.custom(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
            : null,
      ),
      accountName: Text(userName,
          style: AppTypography.appBarTitle.copyWith(color: Colors.white)),
      accountEmail: Text(role,
          style: AppTypography.titleMedium.copyWith(color: Colors.white70)),
    );
  }
}

class DrawerMenuItem {
  final IconData icon;
  final String label;

  /// Module key from `modules_catalog` (e.g. 'library', 'hostel').
  /// Null = core entry, never module-gated.
  final String? module;

  const DrawerMenuItem({
    required this.icon,
    required this.label,
    this.module,
  });
}
