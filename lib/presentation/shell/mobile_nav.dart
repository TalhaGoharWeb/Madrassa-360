/// مدرسہ 360 — موبائل نچلی نیویگیشن (Bottom Navigation)
///
/// Mobile bottom navigation bar (< 600px): 4 primary destinations +
/// "مزید" which opens the full drawer containing the whole [AppNavRail].
///
/// Primary destinations (from [kMobilePrimaryIds] in nav_destinations.dart):
/// ڈیش بورڈ، طلبہ، حاضری، فیس — the four most common daily workflows.
/// Each is permission-filtered; when a primary destination is invisible
/// to the current user the bar falls back to the next visible one.
/// The "مزید" tab is always last and always visible.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/providers/auth_provider.dart';

import 'nav_destinations.dart';

/// Id of the pseudo-tab that opens the full drawer.
const String kMoreTabId = 'more';

/// Computes the mobile bottom-nav tabs for the current user:
/// the permission-visible primaries from [kMobilePrimaryIds].
List<NavDestination> mobilePrimaryTabs(
    Set<String> permissions, List<String> roleKeys) {
  final tabs = <NavDestination>[];
  for (final id in kMobilePrimaryIds) {
    final d = findDestination(id);
    if (d != null && d.isVisible(permissions, roleKeys)) {
      tabs.add(d);
    }
  }
  return tabs;
}

/// Bottom navigation bar with 4–5 items: primaries + "مزید".
///
/// This is a pure view: [AppShell] owns [selectedId] and [onSelect];
/// [onMore] opens the drawer's full navigation.
class MobileNavBar extends ConsumerWidget {
  const MobileNavBar({
    super.key,
    required this.selectedId,
    required this.onSelect,
    required this.onMore,
  });

  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(userPermissionsProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);
    final tabs = mobilePrimaryTabs(permissions, roleKeys);

    // If the current selection isn't among the visible tabs (e.g. the user
    // is on a drawer-only screen), the "more" tab renders active instead —
    // the bar never shows a wrong active state.
    final selectedIsPrimary = tabs.any((t) => t.id == selectedId);

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIsPrimary
          ? tabs.indexWhere((t) => t.id == selectedId)
          : tabs.length, // "مزید" index
      onTap: (i) {
        if (i < tabs.length) {
          onSelect(tabs[i].id);
        } else {
          onMore();
        }
      },
      selectedItemColor: AppColors.primaryDark,
      unselectedItemColor: AppColors.textSecondary,
      // Small labels render in Naskh: product policy keeps Nastaliq at
      // >= 15sp, and 12sp Nastaliq with a tight line height clips nuqtas.
      selectedLabelStyle:
          AppTypography.labelSmall.copyWith(color: AppColors.primaryDark),
      unselectedLabelStyle: AppTypography.labelSmall,
      items: [
        for (final t in tabs)
          BottomNavigationBarItem(
            icon: Icon(t.icon),
            activeIcon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(t.icon, color: AppColors.primaryDark),
            ),
            label: t.labelUr,
          ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.menu),
          label: 'مزید',
        ),
      ],
    );
  }
}
