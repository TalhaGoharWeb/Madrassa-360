/// کردار کے مطابق ہوم — روٹر
/// Role-aware home router (Phases 7a + 7b).
///
/// [RoleHomeScreen] is the post-login destination (wired to
/// [AuthRoute.home]): it resolves the user's PRIMARY role in the active
/// tenant through [RoleService] and returns the matching dashboard:
///
///   clerk (daftar_dar)                        → ClerkDashboard (دفتر)
///   accountant / nazim_maliyat                → AccountantDashboard (مالیات)
///   academic admin (nazim_taleem, nazim_hifz)  → AcademicAdminDashboard
///   hostel (nazim_darul_iqama, warden,        → HostelDashboard (دارالاقامہ)
///     hostel_manager)
///   librarian                                 → LibraryDashboard (کتب خانہ)
///   exam staff (mumtahin)                     → ExamDashboard (امتحانات)
///   principal-level authority (permission-derived) → PrincipalDashboard
///   teacher-family role keys                      → TeacherHome (tabs)
///   parent / student role keys                     → GenericDashboard
///   any other staff role                           → PrincipalDashboard
///       (its sections self-gate on permissions + enabled modules, so an
///       unknown staff role still sees only what it may)
///   no role keys / unknown                        → GenericDashboard
///
/// Staff-dashboard mapping runs BEFORE the permission-derived principal
/// check: e.g. nazim_taleem technically satisfies isPrincipal(), but the
/// mission routes academic admins to the تعلیمی نظام dashboard.
///
/// The fallback is NEVER blank: greeting + latest announcements + profile.
/// Platform operators with zero tenant memberships also land here, with a
/// "پلیٹ فارم کنسول" entry into the guarded '/master' route.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../widgets/dashboard/alert_card.dart';
import '../../widgets/dashboard/dashboard_scaffold.dart';
import '../../widgets/dashboard/day_timeline.dart';
import '../../widgets/dashboard/quick_actions.dart';
import '../../../core/widgets/master_admin_guard.dart'
    show fetchPlatformAdminRole;
import '../../../providers/announcement_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../common/announcements_screen.dart';
import '../common/dashboard_guide_screen.dart';
import '../common/profile_screen.dart';
import 'academic_admin_dashboard.dart';
import 'accountant_dashboard.dart';
import 'clerk_dashboard.dart';
import 'exam_dashboard.dart';
import 'hostel_dashboard.dart';
import 'library_dashboard.dart';
import 'principal_dashboard.dart';
import 'teacher_home.dart';

/// Teacher-family role keys → teacher home. (Permission-derived
/// capabilities still gate every tab inside it.)
const _teacherRoleKeys = {'teacher', 'ustad', 'ustad_hifz'};

/// Learner-family role keys → generic dashboard.
const _learnerRoleKeys = {'parent', 'student'};

/// Phase 7b staff dashboards — checked before the permission-derived
/// principal check (see file doc comment).
const _clerkRoleKeys = {'daftar_dar'};
const _accountantRoleKeys = {'accountant', 'nazim_maliyat'};
const _academicRoleKeys = {'nazim_taleem', 'nazim_hifz'};
const _hostelRoleKeys = {'nazim_darul_iqama', 'warden', 'hostel_manager'};
const _librarianRoleKeys = {'librarian'};
const _examRoleKeys = {'mumtahin'};

class RoleHomeScreen extends ConsumerWidget {
  const RoleHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleService = ref.watch(roleServiceProvider);
    final roleKeys = ref.watch(activeRoleKeysProvider);

    if (roleKeys.isEmpty) {
      return const GenericDashboardScreen();
    }

    if (roleKeys.any(_teacherRoleKeys.contains)) {
      return const TeacherHomeScreen();
    }

    if (roleKeys.any(_learnerRoleKeys.contains)) {
      return const GenericDashboardScreen();
    }

    // Phase 7b staff dashboards (before the permission-derived
    // principal check — see the file doc comment).
    if (roleKeys.any(_clerkRoleKeys.contains)) {
      return const ClerkDashboardScreen();
    }
    if (roleKeys.any(_accountantRoleKeys.contains)) {
      return const AccountantDashboardScreen();
    }
    if (roleKeys.any(_academicRoleKeys.contains)) {
      return const AcademicAdminDashboardScreen();
    }
    if (roleKeys.any(_hostelRoleKeys.contains)) {
      return const HostelDashboardScreen();
    }
    if (roleKeys.any(_librarianRoleKeys.contains)) {
      return const LibraryDashboardScreen();
    }
    if (roleKeys.any(_examRoleKeys.contains)) {
      return const ExamDashboardScreen();
    }

    // Permission-derived principal authority — never role-name string
    // matching for feature gating (RoleService contract).
    if (roleService.isPrincipal()) {
      return const PrincipalDashboardScreen();
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
      schedule: const DayTimeline(),
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
        QuickActionItem(
          icon: Icons.help_outline,
          label: 'رہنمائی',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DashboardGuideScreen(roleKey: 'generic'),
            ),
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
