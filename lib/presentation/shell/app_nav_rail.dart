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
import 'package:madrasa_360/core/design/design_tokens.dart';
import 'package:madrasa_360/core/services/role_service.dart';
import 'package:madrasa_360/providers/auth_provider.dart';
import 'package:madrasa_360/providers/tenant_branding_provider.dart';

import 'nav_destinations.dart';

/// Width of the desktop rail.
const double kNavRailWidth = 264;

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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: Column(
          children: [
            _BrandingHeader(
              branding: branding,
              inDrawer: widget.inDrawer,
              onCloseDrawer: widget.onCloseDrawer,
            ),
            const Divider(height: 1, color: Colors.white24),
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
            const Divider(height: 1, color: Colors.white24),
            _UserFooter(
              // Display name contract: local profile edit wins; never an
              // email address ('مہمان' when nothing real is known).
              userName: ref.watch(displayNameProvider('مہمان')),
              roleKeys: roleKeys,
              onSelect: widget.onSelect,
              onCloseDrawer: widget.onCloseDrawer,
            ),
            const Divider(height: 1, color: Colors.white24),
            const _ProductFooter(),
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
      // Transparent over the rail's teal gradient; the logo tile carries
      // the brand.
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
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
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Flexible: the subtitle must ellipsize instead of
                    // pushing the header Row past the rail width.
                    Flexible(
                      child: Text(
                        'تعلیمی انتظام',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
        border: Border.all(color: AppColors.gold, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? Image.network(
              branding!.logoUrl!,
              fit: BoxFit.cover,
              semanticLabel: 'مدرسے کا لوگو',
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
    // No tenant logo set: show the actual Madrassa-360 product logo, never a
    // stale text mark.
    return Center(
      child: Image.asset(
        'assets/images/app_logo.png',
        width: 38,
        height: 38,
        fit: BoxFit.contain,
        semanticLabel: 'مدرسہ 360 لوگو',
        errorBuilder: (context, error, stackTrace) =>
            const SizedBox(width: 38, height: 38),
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
        // The collapse toggle must announce as a button with its expanded
        // state; the label text inside provides the group name. Min 48px
        // touch target.
        Semantics(
          button: true,
          expanded: !collapsed,
          child: InkWell(
            onTap: onToggle,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: M360TouchTarget.minHeight,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.labelUr,
                      style: AppTypography.navLabel.copyWith(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: collapsed ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
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
        ? Colors.white.withValues(alpha: 0.14)
        : _hovering
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.transparent;
    // Subtle mint/white on teal; selected state never a full-orange fill.
    final fg = selected ? Colors.white : Colors.white.withValues(alpha: 0.88);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      // The destination label text inside provides the accessible label;
      // we only add the button role and the selected state.
      child: Semantics(
        button: true,
        selected: selected,
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
              // Uniform border: a non-uniform Border with a borderRadius
              // throws at paint time («borderRadius can only be given on
              // borders with uniform colors»). The gold selected-edge is a
              // separate bar in the Row below.
              border: selected
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    )
                  : null,
            ),
            child: Row(
              children: [
                if (selected) ...[
                  Container(
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 9),
                ],
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
      ),
    );
  }
}

// ── Bottom user profile + settings ──────────────────────────────────────────

class _UserFooter extends ConsumerWidget {
  const _UserFooter({
    required this.userName,
    required this.roleKeys,
    required this.onSelect,
    this.onCloseDrawer,
  });

  final String userName;
  final List<String> roleKeys;

  /// Shell navigation (the gear now opens the in-shell profile destination
  /// instead of pushing a duplicate screen).
  final ValueChanged<String> onSelect;
  final VoidCallback? onCloseDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleService = ref.watch(roleServiceProvider);
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              userName.isNotEmpty ? userName.characters.first : 'م',
              style: AppTypography.labelNastaliq.copyWith(
                color: Colors.white,
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
                  userName,
                  style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 15,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                FutureBuilder<String>(
                  future: roleKeys.isEmpty
                      ? Future.value('مہمان')
                      : roleService.roleUrduLabel(roleKeys.first),
                  builder: (context, snap) => Text(
                    snap.data ?? '…',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            tooltip: 'ترتیبات',
            onPressed: () {
              onSelect('profile');
              onCloseDrawer?.call();
            },
          ),
        ],
      ),
    );
  }
}

// ── Product footer ──────────────────────────────────────────────────────────

/// Product identity footer: the Madrassa-360 brand mark. The branding header
/// above carries the *tenant's* identity (their logo, or the ۳۶۰ mark when
/// none is configured); this footer carries the *product* identity so the
/// app brand is present at the bottom of every dashboard sidebar, in drawer
/// and desktop-rail modes alike.
class _ProductFooter extends StatelessWidget {
  const _ProductFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/app_logo.png',
            width: 26,
            height: 26,
            fit: BoxFit.contain,
            semanticLabel: 'مدرسہ 360 لوگو',
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox(width: 26, height: 26),
          ),
          const SizedBox(width: 8),
          Text(
            'مدرسہ 360',
            style: AppTypography.labelNastaliq.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
