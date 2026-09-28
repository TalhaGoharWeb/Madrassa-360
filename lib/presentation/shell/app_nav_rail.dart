/// مدرسہ 360 — ڈیسک ٹاپ نیویگیشن ریل (دائیں طرف)
///
/// Persistent RIGHT-side navigation rail for desktop (width ≥ 1100px):
/// madrassa branding header (logo + name), grouped destinations with
/// Nastaleeq section labels, active/hover states, collapsible groups,
/// permission-filtered destinations, badge counts, and a bottom
/// user-profile + settings block.
///
/// RTL: the rail is the FIRST child of the shell's Row, so in the app's
/// forced-RTL layout it renders on the RIGHT. This widget additionally
/// wraps itself in an explicit RTL [Directionality] so it stays correct
/// even if reused elsewhere.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';
import 'package:madrasa_360/presentation/screens/common/profile_screen.dart'
    show ProfileScreen;

import 'nav_destinations.dart';

/// Width of the desktop rail.
const double kNavRailWidth = 264;

/// Gold accent used with the teal brand.
const Color _kGold = Color(0xFFC9A227);

/// Normalise a watched badge value to an int? (see [NavBadges]).
int? _badgeValueOf(Object? watched) {
  if (watched == null) return null;
  if (watched is AsyncValue) {
    final v = watched.valueOrNull;
    if (v is int) return v;
    if (v is List) return v.length;
    return null;
  }
  if (watched is int) return watched;
  if (watched is List) return watched.length;
  return null;
}

/// Desktop navigation rail. Shared by [AppShell] (persistent) and the
/// tablet/mobile drawer (scrollable); pass [inDrawer] to adapt padding
/// and the header close behaviour.
class AppNavRail extends ConsumerStatefulWidget {
  const AppNavRail({
    super.key,
    required this.selectedId,
    required this.onSelect,
    this.inDrawer = false,
    this.onCloseDrawer,
  });

  /// Currently active destination id.
  final String selectedId;

  /// Called with the destination id when the user taps a destination.
  final ValueChanged<String> onSelect;

  /// True when rendered inside the tablet/mobile drawer.
  final bool inDrawer;

  /// Called to close the drawer (only used when [inDrawer] is true).
  final VoidCallback? onCloseDrawer;

  @override
  ConsumerState<AppNavRail> createState() => _AppNavRailState();
}

class _AppNavRailState extends ConsumerState<AppNavRail> {
  /// Collapsed group ids (persisted for the session only).
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(userPermissionsProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final user = ref.watch(currentUserProvider);

    final visibleGroups = [
      for (final g in kNavGroups)
        (
          group: g,
          destinations: g.visibleDestinations(permissions, roleKeys),
        )
    ].where((e) => e.destinations.isNotEmpty).toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: widget.inDrawer ? null : kNavRailWidth,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            // In RTL this is the rail's inner (left) edge.
            left: BorderSide(color: AppColors.divider.withValues(alpha: 0.5)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            _BrandingHeader(
              branding: branding,
              inDrawer: widget.inDrawer,
              onCloseDrawer: widget.onCloseDrawer,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: visibleGroups.length,
                itemBuilder: (context, i) {
                  final entry = visibleGroups[i];
                  return _NavGroupSection(
                    group: entry.group,
                    destinations: entry.destinations,
                    collapsed: _collapsed.contains(entry.group.id),
                    selectedId: widget.selectedId,
                    onToggle: () => setState(() {
                      if (_collapsed.contains(entry.group.id)) {
                        _collapsed.remove(entry.group.id);
                      } else {
                        _collapsed.add(entry.group.id);
                      }
                    }),
                    onSelect: (id) {
                      widget.onSelect(id);
                      widget.onCloseDrawer?.call();
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            _UserFooter(userName: user?.name, roleKeys: roleKeys),
          ],
        ),
      ),
    );
  }
}

// ── Branding header ─────────────────────────────────────────────────────────

class _BrandingHeader extends StatelessWidget {
  const _BrandingHeader({
    required this.branding,
    required this.inDrawer,
    this.onCloseDrawer,
  });

  final TenantBranding? branding;
  final bool inDrawer;
  final VoidCallback? onCloseDrawer;

  @override
  Widget build(BuildContext context) {
    final name = branding?.displayName() ?? 'مدرسہ 360';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: Row(
        children: [
          _LogoTile(branding: branding),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 19,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _kGold,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تعلیمی انتظام',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (inDrawer)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'بند کریں',
              onPressed: onCloseDrawer,
            ),
        ],
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.branding});

  final TenantBranding? branding;

  @override
  Widget build(BuildContext context) {
    final hasLogo = branding?.hasLogo ?? false;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGold, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? Image.network(
              branding!.logoUrl!,
              fit: BoxFit.cover,
              // Offline / broken logo must never break the shell.
              errorBuilder: (_, __, ___) => const _FallbackMark(),
            )
          : const _FallbackMark(),
    );
  }
}

class _FallbackMark extends StatelessWidget {
  const _FallbackMark();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '۳۶۰',
        style: TextStyle(
          fontFamily: 'JameelNooriNastaleeq',
          fontSize: 20,
          color: Color(0xFF009688),
          height: 2.0,
        ),
      ),
    );
  }
}

// ── Collapsible group section ───────────────────────────────────────────────

class _NavGroupSection extends StatelessWidget {
  const _NavGroupSection({
    required this.group,
    required this.destinations,
    required this.collapsed,
    required this.selectedId,
    required this.onToggle,
    required this.onSelect,
  });

  final NavGroup group;
  final List<NavDestination> destinations;
  final bool collapsed;
  final String selectedId;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.labelUr,
                    style: AppTypography.navLabel.copyWith(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: collapsed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            children: [
              for (final d in destinations)
                _NavItem(
                  destination: d,
                  selected: d.id == selectedId,
                  onTap: () => onSelect(d.id),
                ),
              const SizedBox(height: 4),
            ],
          ),
          crossFadeState:
              collapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

// ── Destination item (active / hover states, badge) ─────────────────────────

class _NavItem extends ConsumerStatefulWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  ConsumerState<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends ConsumerState<_NavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.destination;
    final selected = widget.selected;

    final badgeCount = d.badgeProvider == null
        ? null
        : _badgeValueOf(ref.watch(d.badgeProvider!()));

    final bg = selected
        ? AppColors.primary.withValues(alpha: 0.12)
        : _hovering
            ? AppColors.primary.withValues(alpha: 0.05)
            : Colors.transparent;
    final fg = selected ? AppColors.primaryDark : AppColors.textPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border(
                    right: const BorderSide(color: _kGold, width: 3),
                    top: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.25)),
                    bottom: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.25)),
                    left: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.25)),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(d.icon, size: 22, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  d.labelUr,
                  style: AppTypography.navLabel.copyWith(color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (d.planned)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'جلد',
                    style: AppTypography.labelSmall.copyWith(
                      color: const Color(0xFF8a6d1c),
                    ),
                  ),
                ),
              if (badgeCount != null && badgeCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
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

// ── Bottom user profile + settings ──────────────────────────────────────────

class _UserFooter extends ConsumerWidget {
  const _UserFooter({required this.userName, required this.roleKeys});

  final String? userName;
  final List<String> roleKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleService = ref.watch(roleServiceProvider);
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              (userName?.isNotEmpty ?? false) ? userName![0] : 'م',
              style: AppTypography.labelNastaliq.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  userName ?? 'مہمان',
                  style: AppTypography.labelNastaliq.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                FutureBuilder<String>(
                  future: roleKeys.isEmpty
                      ? Future.value('مہمان')
                      : roleService.roleUrduLabel(roleKeys.first),
                  builder: (context, snap) => Text(
                    snap.data ?? '…',
                    style: AppTypography.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: AppColors.textSecondary),
            tooltip: 'ترتیبات',
            onPressed: () {
              // Profile screen hosts the account settings tiles today.
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
