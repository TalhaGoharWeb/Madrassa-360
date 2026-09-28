/// مدرسہ 360 — مرکزی نیویگیشن شیل (AppShell)
///
/// The responsive navigation scaffold that hosts the whole post-login app:
///
/// * Desktop (width ≥ 1100): persistent RIGHT-side [AppNavRail].
/// * Tablet (600–1099): navigation via drawer (same rail content).
/// * Mobile (< 600): [MobileNavBar] bottom navigation + drawer.
///
/// The top app bar always shows WHERE the user is: a breadcrumb
/// (group › destination) in Nastaleeq, plus a notifications bell (badge =
/// unread count) and a madrassa switcher — but only when the user
/// actually belongs to more than one tenant. There is intentionally NO
/// global-search trigger: no global search exists in the repo (see
/// INTEGRATION.md § future hooks).
///
/// Wiring: [AuthGate] renders [AppShell] instead of [RoleHomeScreen] after
/// login (see INTEGRATION.md). [AppShell] does not replace the role router —
/// the "ڈیش بورڈ" destination's builder IS [RoleHomeScreen], so every role
/// keeps its existing dashboard. No business logic is changed here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'package:madrasa_360/core/notifications/notification_providers.dart'
    show unreadNotificationsCountProvider;
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart'
    show tenantMembershipsProvider;
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:madrasa_360/presentation/screens/auth/tenant_picker_screen.dart'
    show TenantPickerScreen;
import 'package:madrasa_360/presentation/screens/common/notifications_screen.dart'
    show NotificationsScreen;

import 'app_nav_rail.dart';
import 'mobile_nav.dart';
import 'nav_destinations.dart';

/// Desktop breakpoint: persistent rail at ≥ 1100px logical width.
const double kDesktopBreakpoint = 1100;

/// Mobile breakpoint: bottom navigation below 600px logical width.
const double kMobileBreakpoint = 600;

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PageStorageBucket _bucket = PageStorageBucket();

  /// Currently selected destination id. Defaults to the dashboard; the
  /// build method falls back to the first visible destination if the
  /// stored id is not visible to the current user.
  String _selectedId = 'dashboard';

  void _select(String id) => setState(() => _selectedId = id);

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(userPermissionsProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    // Permission-filtered flat destination list for this user.
    final visible = [
      for (final d in kAllDestinations)
        if (d.isVisible(permissions, roleKeys)) d,
    ];
    if (visible.isEmpty) {
      // Failsafe: never a blank shell (mirrors role_home's "never blank"
      // contract). This path is unreachable in practice because the
      // dashboard destination has no permission requirements.
      return const Scaffold(body: Center(child: Text('رسائی دستیاب نہیں')));
    }

    final active = visible.any((d) => d.id == _selectedId)
        ? _selectedId
        : visible.first.id;
    final destination = findDestination(active)!;
    final group = findGroupOf(active);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= kDesktopBreakpoint;
        final isMobile = width < kMobileBreakpoint;

        final drawer = Drawer(
          child: Builder(
            builder: (drawerContext) => AppNavRail(
              selectedId: active,
              onSelect: _select,
              inDrawer: true,
              onCloseDrawer: () => Navigator.of(drawerContext).pop(),
            ),
          ),
        );

        final body = Row(
          children: [
            // RTL: the first child of a Row renders on the RIGHT in the
            // app's forced-RTL Directionality — the rail sits on the right.
            if (isDesktop) AppNavRail(selectedId: active, onSelect: _select),
            Expanded(
              child: Column(
                children: [
                  _ShellAppBar(
                    groupLabel: group?.labelUr,
                    destinationLabel: destination.labelUr,
                  ),
                  Expanded(
                    child: PageStorage(
                      bucket: _bucket,
                      child: KeyedSubtree(
                        key: PageStorageKey<String>('dest-$active'),
                        child: destination.builder(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        return Scaffold(
          key: _scaffoldKey,
          // Desktop uses the persistent rail; smaller screens use the drawer.
          drawer: isDesktop ? null : drawer,
          body: SafeArea(child: body),
          bottomNavigationBar: isMobile
              ? MobileNavBar(
                  selectedId: active,
                  onSelect: _select,
                  onMore: () => _scaffoldKey.currentState?.openDrawer(),
                )
              : null,
        );
      },
    );
  }
}

// ── Top app bar ─────────────────────────────────────────────────────────────

/// App bar with breadcrumb title (group › destination), madrassa switcher
/// (multi-tenant only) and the notifications bell.
class _ShellAppBar extends ConsumerWidget {
  const _ShellAppBar({
    required this.groupLabel,
    required this.destinationLabel,
  });

  final String? groupLabel;
  final String destinationLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.primary,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (groupLabel != null)
                    Text(
                      groupLabel!,
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  Text(
                    destinationLabel,
                    style: AppTypography.appBarTitle.copyWith(fontSize: 22),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const _TenantSwitcher(),
            _NotificationsBell(),
          ],
        ),
      ),
    );
  }
}

// ── Madrassa switcher (only when the user has > 1 membership) ───────────────

class _TenantSwitcher extends ConsumerWidget {
  const _TenantSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(tenantMembershipsProvider).valueOrNull ?? [];
    if (memberships.length < 2) return const SizedBox.shrink();

    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final name = branding?.displayName() ?? 'مدرسہ';

    return TextButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TenantPickerScreen()),
        );
      },
      icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 20),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Text(
          name,
          style: AppTypography.labelNastaliq.copyWith(
            fontSize: 15,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

// ── Notifications bell with unread badge ────────────────────────────────────

class _NotificationsBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: 'اطلاعات',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        backgroundColor: AppColors.error,
        child: const Icon(Icons.notifications_outlined, color: Colors.white),
      ),
    );
  }
}
