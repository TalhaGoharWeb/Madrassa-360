/// مدرسہ 360 — مرکزی نیویگیشن شیل (AppShell)
///
/// The responsive navigation scaffold that hosts the whole post-login app:
///
/// * Desktop (width ≥ 1100): persistent RIGHT-side [AppNavRail].
/// * Tablet (600–1099): navigation via drawer (same rail content).
/// * Mobile (< 600): [MobileNavBar] bottom navigation + drawer.
///
/// The top app bar always shows WHERE the user is: a breadcrumb
/// (group › destination) in Nastaleeq, a back affordance on non-root
/// destinations, a global command-search trigger (Ctrl+K), the tenant
/// chip, a notifications bell (badge = unread count), and the user
/// profile chip.
///
/// Wiring: [AuthGate] renders [AppShell] after login. [AppShell] does not
/// replace the role router — the "ڈیش بورڈ" destination's builder IS
/// [RoleHomeScreen], so every role keeps its existing dashboard. No
/// business logic is changed here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'package:madrasa_360/core/design/m360.dart';
import 'package:madrasa_360/core/notifications/notification_providers.dart'
    show unreadNotificationsCountProvider;
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/core/services/tenant_context.dart'
    show tenantMembershipsProvider;
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:madrasa_360/presentation/screens/auth/tenant_picker_screen.dart'
    show TenantPickerScreen;

import 'app_nav_rail.dart';
import 'command_palette.dart';
import 'mobile_nav.dart';
import 'nav_destinations.dart';
import 'shell_nav.dart';

/// Desktop breakpoint: persistent rail at ≥ 1100px logical width.
const double kDesktopBreakpoint = 1100;

/// Mobile breakpoint: bottom navigation below 600px logical width.
const double kMobileBreakpoint = 600;

/// Pseudo-destination id for the logout action (intercepted by [_select]).
const String kLogoutDestinationId = 'logout';

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

  /// Guards against stacking the command palette (Ctrl+K while open).
  bool _searchOpen = false;

  void _select(String id) {
    if (id == kLogoutDestinationId) {
      _confirmLogout();
      return;
    }
    setState(() => _selectedId = id);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'لاگ آؤٹ',
      message: 'کیا آپ واقعی لاگ آؤٹ کرنا چاہتے ہیں؟',
      confirmLabel: 'لاگ آؤٹ',
    );
    if (confirmed && mounted) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  void _openSearch(List<NavDestination> visible) {
    if (_searchOpen) return;
    _searchOpen = true;
    CommandPalette.show(
      context,
      visibleDestinations: visible,
      onSelectDestination: _select,
    ).whenComplete(() {
      _searchOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(userPermissionsProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    // Hub-driven navigation requests (e.g. the finance hub's tab bar
    // switching between destinations). Consumed once, on the next frame.
    final navRequest = ref.watch(shellNavRequestProvider);
    if (navRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(shellNavRequestProvider.notifier).state = null;
        if (navRequest != _selectedId &&
            findDestination(navRequest) != null &&
            navRequest != kLogoutDestinationId) {
          _select(navRequest);
        }
      });
    }

    // Permission-filtered flat destination list for this user.
    final visible = [
      for (final d in kAllDestinations)
        if (d.isVisible(permissions, roleKeys)) d,
    ];
    if (visible.isEmpty) {
      // Failsafe: never a blank shell (mirrors role_home's "never blank"
      // contract). This path is unreachable in practice because the
      // dashboard destination has no permission requirements.
      return Scaffold(
          body: Center(
              child:
                  Text('رسائی دستیاب نہیں', style: AppTypography.titleSmall)));
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
                    destinationId: active,
                    onSelect: _select,
                    onOpenSearch: () => _openSearch(visible),
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

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                _openSearch(visible),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                _openSearch(visible),
          },
          child: Scaffold(
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
          ),
        );
      },
    );
  }
}

// ── Top app bar ─────────────────────────────────────────────────────────────

/// App bar with back affordance (non-root destinations), breadcrumb title
/// (group › destination), global search trigger (Ctrl+K), tenant chip,
/// notifications bell, and user profile chip.
class _ShellAppBar extends ConsumerWidget {
  const _ShellAppBar({
    required this.groupLabel,
    required this.destinationLabel,
    required this.destinationId,
    required this.onSelect,
    required this.onOpenSearch,
  });

  final String? groupLabel;
  final String destinationLabel;
  final String destinationId;
  final ValueChanged<String> onSelect;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRoot = destinationId == 'dashboard';
    // Compact app bar below 600px: the full tenant chip + search pill +
    // profile chip do not fit in 360px, so search collapses to an icon,
    // the tenant name shortens, and the profile chip keeps only the avatar.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Material(
      color: AppColors.primary,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            // Back affordance on non-root destinations → dashboard.
            if (!isRoot)
              IconButton(
                tooltip: 'واپس ڈیش بورڈ',
                onPressed: () => onSelect('dashboard'),
                // arrow_back auto-mirrors in RTL (points right).
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            _TenantChip(compact: compact),
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
            _SearchTrigger(onOpen: onOpenSearch, compact: compact),
            _NotificationsBell(onSelect: onSelect),
            _ProfileChip(onSelect: onSelect, compact: compact),
          ],
        ),
      ),
    );
  }
}

// ── Global search trigger (Ctrl+K) ──────────────────────────────────────────

class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.onOpen, this.compact = false});

  final VoidCallback onOpen;

  /// At <600px the pill does not fit — collapse to an icon-only button.
  /// [M360IconButton] already provides the 48px target, Urdu tooltip, and
  /// button semantics.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return M360IconButton(
        icon: Icons.search,
        tooltip: 'تلاش (Ctrl+K)',
        color: Colors.white,
        onPressed: onOpen,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      // Semantics + Tooltip: a screen reader must announce this as a
      // button with a purpose (the visible «تلاش» text alone is vague).
      // The Container's minHeight guarantees the 48px touch target.
      child: Semantics(
        button: true,
        label: 'تلاش (Ctrl+K)',
        child: Tooltip(
          message: 'تلاش (Ctrl+K)',
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: M360TouchTarget.minHeight,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'تلاش',
                    style: AppTypography.labelNastaliq.copyWith(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Ctrl+K',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tenant chip (institution logo/name; switcher when multi-tenant) ─────────

class _TenantChip extends ConsumerWidget {
  const _TenantChip({this.compact = false});

  /// At <600px the name shortens and the swap affordance hides — the chip
  /// stays tappable (switcher) with full semantics.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(tenantMembershipsProvider).valueOrNull ?? [];
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final name = branding?.displayName() ?? 'مدرسہ';
    final multi = memberships.length > 1;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      // Semantics + Tooltip + 48px minimum height: the chip must announce
      // as a button («ادارہ تبدیل کریں») and be a full touch target.
      child: Semantics(
        button: true,
        label: multi ? 'ادارہ تبدیل کریں' : 'موجودہ ادارہ',
        child: Tooltip(
          message: multi ? 'ادارہ تبدیل کریں' : name,
          child: InkWell(
            onTap: multi
                ? () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TenantPickerScreen(),
                      ),
                    );
                  }
                : null,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: M360TouchTarget.minHeight,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 72 : 120),
                    child: Text(
                      name,
                      style: AppTypography.labelNastaliq.copyWith(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (multi && !compact) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.swap_horiz, color: Colors.white, size: 16),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Notifications bell with unread badge ────────────────────────────────────

class _NotificationsBell extends ConsumerWidget {
  const _NotificationsBell({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    // Bell navigates inside the shell (no duplicate pushed screen).
    return IconButton(
      tooltip: 'اطلاعات',
      onPressed: () => onSelect('notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        backgroundColor: AppColors.error,
        child: const Icon(Icons.notifications_outlined, color: Colors.white),
      ),
    );
  }
}

// ── User profile chip ───────────────────────────────────────────────────────

class _ProfileChip extends ConsumerWidget {
  const _ProfileChip({required this.onSelect, this.compact = false});

  final ValueChanged<String> onSelect;

  /// At <600px only the avatar shows — the name/role column does not fit.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);
    final roleService = ref.watch(roleServiceProvider);

    final name = user?.name ?? 'مہمان';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      // Semantics + Tooltip + 48px minimum height: announces as a button
      // («پروفائل») and meets the touch-target minimum.
      child: Semantics(
        button: true,
        label: 'پروفائل',
        child: Tooltip(
          message: 'پروفائل',
          child: InkWell(
            onTap: () => onSelect('profile'),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: M360TouchTarget.minHeight,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    child: Text(
                      name.isNotEmpty ? name.characters.first : 'م',
                      style: AppTypography.labelNastaliq.copyWith(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 90),
                          child: Text(
                            name,
                            style: AppTypography.labelNastaliq.copyWith(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        FutureBuilder<String>(
                          future: roleKeys.isEmpty
                              ? Future.value('مہمان')
                              : roleService.roleUrduLabel(roleKeys.first),
                          builder: (context, snap) => Text(
                            snap.data ?? '…',
                            style: AppTypography.labelSmall.copyWith(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
