/// کردار کے مطابق ہوم — روٹر
/// Role-aware home router (Phase 7a).
///
/// [RoleHomeScreen] is the post-login destination (wired to
/// [AuthRoute.home]): it resolves the user's PRIMARY role in the active
/// tenant through [RoleService] and returns the matching dashboard:
///
///   principal-level authority (permission-derived) → PrincipalDashboard
///   teacher-family role keys                      → TeacherHome (tabs)
///   parent / student role keys                     → GenericDashboard
///   any other staff role                           → PrincipalDashboard
///       (its sections self-gate on permissions + enabled modules, so an
///       accountant sees only finance, a librarian only the library, …)
///   no role keys / unknown                        → GenericDashboard
///
/// The fallback is NEVER blank: greeting + latest announcements + profile.
/// Platform operators with zero tenant memberships also land here, with a
/// "پلیٹ فارم کنسول" entry into the guarded '/master' route.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/services/role_service.dart';
import '../../core/widgets/dashboard/alert_card.dart';
import '../../core/widgets/dashboard/dashboard_scaffold.dart';
import '../../core/widgets/dashboard/quick_actions.dart';
import '../../core/widgets/master_admin_guard.dart' show fetchPlatformAdminRole;
import '../../providers/announcement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tenant_branding_provider.dart';
import '../common/announcements_screen.dart';
import '../common/profile_screen.dart';
import 'principal_dashboard.dart';
import 'teacher_home.dart';

/// Teacher-family role keys → teacher home. (Permission-derived
/// capabilities still gate every tab inside it.)
const _teacherRoleKeys = {'teacher', 'ustad', 'ustad_hifz'};

/// Learner-family role keys → generic dashboard.
const _learnerRoleKeys = {'parent', 'student'};

class RoleHomeScreen extends ConsumerWidget {
  const RoleHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    // Permission-derived principal authority — never role-name string
    // matching for feature gating (RoleService contract).
    if (roleService.isPrincipal()) {
      return const PrincipalDashboardScreen();
    }

    if (roleKeys.isEmpty) {
      return const GenericDashboardScreen();
    }

    if (roleKeys.any(_teacherRoleKeys.contains)) {
      return const TeacherHomeScreen();
    }

    if (roleKeys.any(_learnerRoleKeys.contains)) {
      return const GenericDashboardScreen();
    }

    // Any other staff role: the principal dashboard's sections gate
    // themselves on permissions + enabled modules.
    return const PrincipalDashboardScreen();
  }
}

/// Safe fallback dashboard: greeting + latest announcements + profile.
/// Rendered for unknown/no-role users — never a blank screen.
class GenericDashboardScreen extends ConsumerWidget {
  const GenericDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'مہمان';
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final madrasaName = branding?.displayName() ?? 'مدرسہ 360';
    final announcements = ref.watch(announcementListProvider).take(5).toList();

    return DashboardScaffold(
      greeting: 'السلام علیکم ورحمۃ اللہ',
      userName: userName,
      madrasaName: madrasaName,
      stats: _RoleInfoCard(),
      alertsTitle: 'تازہ اعلانات',
      alerts: announcements.isEmpty
          ? const _EmptyAnnouncementsNote()
          : Column(
              children: announcements
                  .map((a) => AlertCard(
                        icon: Icons.campaign_outlined,
                        message: a.title,
                        actionLabel: 'دیکھیں',
                        onAction: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AnnouncementsScreen(),
                          ),
                        ),
                        severity: AlertSeverity.info,
                      ))
                  .toList(),
            ),
      quickActionsTitle: 'فوری عمل',
      quickActions: QuickActionGrid(items: [
        QuickActionItem(
          icon: Icons.campaign_outlined,
          label: 'اعلانات',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
          ),
        ),
        QuickActionItem(
          icon: Icons.person_outline,
          label: 'میری پروفائل',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
        ),
        // Platform console — visible only to platform operators.
        QuickActionItem(
          icon: Icons.admin_panel_settings_outlined,
          label: 'پلیٹ فارم',
          color: AppColors.warning,
          onTap: () async {
            final role = await fetchPlatformAdminRole();
            if (!context.mounted) return;
            if (role != null) {
              Navigator.of(context).pushNamed('/master');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('آپ کو رسائی حاصل نہیں')),
              );
            }
          },
        ),
      ]),
    );
  }
}

/// Shows the user's Urdu role label (or 'مہمان' when none).
class _RoleInfoCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<String>(
              future: roleKeys.isEmpty
                  ? Future.value('مہمان')
                  : roleService.roleUrduLabel(roleKeys.first),
              builder: (context, snap) => Text(
                'آپ کا کردار: ${snap.data ?? '…'}',
                style: AppTypography.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAnnouncementsNote extends StatelessWidget {
  const _EmptyAnnouncementsNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'ابھی کوئی اعلان نہیں',
        style: AppTypography.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Clean placeholder for features that don't exist yet.
/// Used ONLY where no real screen exists — never a dead button: the tap
/// always lands here with the feature's own title.
class ComingSoonScreen extends StatelessWidget {
  /// Urdu feature title, e.g. 'امتحانات'.
  final String title;

  /// When embedded as a tab (the shell already has an AppBar), hide this
  /// screen's own AppBar.
  final bool showAppBar;

  const ComingSoonScreen({
    super.key,
    required this.title,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.construction_outlined,
                color: AppColors.primary,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTypography.headingSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'جلد آ رہا ہے',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'یہ سہولت جلد دستیاب ہوگی',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}
