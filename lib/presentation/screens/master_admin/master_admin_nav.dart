/// پلیٹ فارم کنسول — نیویگیشن ریل
///
/// Persistent RIGHT-side navigation rail for the platform console on
/// desktop (width ≥ 1100px), reused inside the drawer on smaller screens —
/// the same responsive pattern as the tenant [AppNavRail] (ONE NAVIGATION
/// SYSTEM): first child of the shell's Row, so the forced-RTL layout puts
/// it on the RIGHT, with an explicit RTL [Directionality] so it stays
/// correct wherever it is reused.
///
/// Destinations are grouped by console concern (Overview / Madrasas /
/// Licensing / Platform) with Nastaleeq Urdu labels. The 'create-madrasa'
/// destination is an action: selecting it pushes the [CreateMadrasaWizard]
/// instead of swapping the inline screen.

import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'package:madrasa_360/core/design/design_tokens.dart';

/// Width of the desktop console rail (matches the tenant rail).
const double kConsoleRailWidth = 264;

/// A single console destination.
class MaNavDestination {
  final String id;
  final String urduLabel;
  final String englishLabel;
  final IconData icon;

  /// When true, selecting this destination pushes a route instead of
  /// swapping the shell's inline screen.
  final bool isAction;

  const MaNavDestination({
    required this.id,
    required this.urduLabel,
    required this.englishLabel,
    required this.icon,
    this.isAction = false,
  });
}

/// A labelled group of console destinations.
class MaNavGroup {
  final String id;
  final String urduLabel;
  final List<MaNavDestination> destinations;

  const MaNavGroup({
    required this.id,
    required this.urduLabel,
    required this.destinations,
  });
}

/// All console destinations, grouped by concern.
const List<MaNavGroup> kConsoleNavGroups = [
  MaNavGroup(
    id: 'overview',
    urduLabel: 'جائزہ',
    destinations: [
      MaNavDestination(
        id: 'dashboard',
        urduLabel: 'ڈیش بورڈ',
        englishLabel: 'Dashboard',
        icon: Icons.dashboard_outlined,
      ),
    ],
  ),
  MaNavGroup(
    id: 'madrasas',
    urduLabel: 'مدارس',
    destinations: [
      MaNavDestination(
        id: 'madrasas',
        urduLabel: 'مدارس کی فہرست',
        englishLabel: 'Madrasas',
        icon: Icons.account_balance_outlined,
      ),
      MaNavDestination(
        id: 'create-madrasa',
        urduLabel: 'نیا مدرسہ بنائیں',
        englishLabel: 'New Madrasa',
        icon: Icons.add_business_outlined,
        isAction: true,
      ),
    ],
  ),
  MaNavGroup(
    id: 'licensing',
    urduLabel: 'لائسنسنگ',
    destinations: [
      MaNavDestination(
        id: 'plans',
        urduLabel: 'پلانز',
        englishLabel: 'Plans',
        icon: Icons.card_membership_outlined,
      ),
      MaNavDestination(
        id: 'subscriptions',
        urduLabel: 'سبسکرپشنز',
        englishLabel: 'Subscriptions',
        icon: Icons.autorenew_outlined,
      ),
      MaNavDestination(
        id: 'licenses',
        urduLabel: 'لائسنسز',
        englishLabel: 'Licenses',
        icon: Icons.verified_outlined,
      ),
    ],
  ),
  MaNavGroup(
    id: 'platform',
    urduLabel: 'پلیٹ فارم',
    destinations: [
      MaNavDestination(
        id: 'modules',
        urduLabel: 'ماڈیولز',
        englishLabel: 'Modules',
        icon: Icons.extension_outlined,
      ),
      MaNavDestination(
        id: 'audit-logs',
        urduLabel: 'آڈٹ لاگز',
        englishLabel: 'Audit Logs',
        icon: Icons.receipt_long_outlined,
      ),
      MaNavDestination(
        id: 'platform-users',
        urduLabel: 'پلیٹ فارم صارفین',
        englishLabel: 'Platform Users',
        icon: Icons.admin_panel_settings_outlined,
      ),
    ],
  ),
];

/// Console navigation rail. Shared by [MasterAdminShell] (persistent on
/// desktop) and its mobile drawer; pass [inDrawer] to adapt the header.
class MasterAdminNavRail extends StatelessWidget {
  const MasterAdminNavRail({
    super.key,
    required this.selectedId,
    required this.onSelect,
    this.inDrawer = false,
    this.onCloseDrawer,
    this.role,
    this.operatorEmail,
    this.onBackToApp,
  });

  /// Currently active destination id.
  final String selectedId;

  /// Called with the destination id when the operator taps a destination.
  final ValueChanged<String> onSelect;

  /// True when rendered inside the mobile drawer.
  final bool inDrawer;

  /// Called to close the drawer (only used when [inDrawer] is true).
  final VoidCallback? onCloseDrawer;

  /// 'platform_owner' | 'platform_support' | null (still loading).
  final String? role;

  /// Signed-in operator's email, shown in the footer.
  final String? operatorEmail;

  /// Leaves the console for the normal app shell.
  final VoidCallback? onBackToApp;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: inDrawer ? null : kConsoleRailWidth,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: Column(
          children: [
            _ConsoleBrandHeader(
              role: role,
              inDrawer: inDrawer,
              onCloseDrawer: onCloseDrawer,
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: kConsoleNavGroups.length,
                itemBuilder: (context, i) {
                  final group = kConsoleNavGroups[i];
                  return _NavGroupSection(
                    group: group,
                    selectedId: selectedId,
                    onSelect: onSelect,
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            _OperatorFooter(
              email: operatorEmail,
              role: role,
              onBackToApp: onBackToApp,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsoleBrandHeader extends StatelessWidget {
  const _ConsoleBrandHeader(
      {this.role, this.inDrawer = false, this.onCloseDrawer});

  final String? role;
  final bool inDrawer;
  final VoidCallback? onCloseDrawer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Row(
          children: [
            // Product logo tile.
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(M360Radius.md),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/images/app_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.shield_outlined,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'پلیٹ فارم کنسول',
                    style: AppTypography.labelNastaliq.copyWith(
                      color: Colors.white,
                      fontSize: 19,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(M360Radius.sm),
                    ),
                    child: Text(
                      role == 'platform_owner' ? 'مالک' : 'منتظم',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (inDrawer)
              IconButton(
                tooltip: 'بند کریں',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onCloseDrawer,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavGroupSection extends StatelessWidget {
  const _NavGroupSection({
    required this.group,
    required this.selectedId,
    required this.onSelect,
  });

  final MaNavGroup group;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              group.urduLabel,
              style: AppTypography.labelNastaliq.copyWith(
                color: Colors.white60,
                fontSize: 14,
                height: 1.8,
              ),
            ),
          ),
          for (final dest in group.destinations)
            _NavTile(
              destination: dest,
              selected: dest.id == selectedId && !dest.isAction,
              onTap: () => onSelect(dest.id),
            ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final MaNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primary : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(M360Radius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(M360Radius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  size: 22,
                  color: selected ? AppColors.primary : Colors.white70,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.urduLabel,
                        style: AppTypography.navLabel.copyWith(color: fg),
                      ),
                      Text(
                        destination.englishLabel,
                        style: AppTypography.labelSmall.copyWith(
                          color: selected
                              ? AppColors.textSecondary
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (destination.isAction)
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: Colors.white54,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OperatorFooter extends StatelessWidget {
  const _OperatorFooter({this.email, this.role, this.onBackToApp});

  final String? email;
  final String? role;
  final VoidCallback? onBackToApp;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Operator identity.
            Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.person_outline,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email ?? '…',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                      ),
                      Text(
                        role == 'platform_owner'
                            ? 'Platform Owner'
                            : 'Platform Admin',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Exit back to the tenant app.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onBackToApp,
                icon: const Icon(Icons.home_outlined, size: 18),
                label: const Text('واپس ایپ پر'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(M360Radius.md),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Product mark — same footer as the tenant sidebar.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'مدرسہ 360',
                  style: AppTypography.labelNastaliq.copyWith(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
