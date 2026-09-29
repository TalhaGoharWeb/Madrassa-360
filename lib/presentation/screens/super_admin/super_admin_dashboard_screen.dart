import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/madrasa_provider.dart';
import '../../../providers/auth_provider.dart';
import '../common/dashboard_guide_screen.dart';
import 'madrasa_management_screen.dart';

/// @deprecated Phase-3 replacement: the legacy single-tenant Super Admin
/// dashboard is superseded by the multi-tenant Master Admin console at
/// lib/presentation/screens/master_admin/ (route '/master', gated by
/// MasterAdminGuard). Kept only because other code may still reference it —
/// do not build new features here; use MasterDashboardScreen instead.
///
/// Phase 10: visuals moved onto the m360 component language; the provider
/// wiring and navigation logic are unchanged.
@Deprecated('Use MasterDashboardScreen instead')
class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});
  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  WidgetRef? _ref;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref?.read(madrasaProvider.notifier).loadAll();
    });
  }

  void _openManagement() {
    // Pushed deep page: MadrasaManagementScreen is a shell destination, so
    // the push site provides the deep-page root (app bar + back
    // navigation). Navigation logic is unchanged.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const Scaffold(
          appBar: M360AppBar(title: 'مدارس کا انتظام'),
          body: MadrasaManagementScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      _ref = ref;
      final madrasaState = ref.watch(madrasaProvider);
      final user = ref.watch(authProvider).user;
      final madrasas = madrasaState.madrasas;

      final total = madrasas.length;
      final active = madrasas.where((m) => m.isActive).length;
      final premium =
          madrasas.where((m) => m.subscriptionPlan == 'premium').length;
      final standard =
          madrasas.where((m) => m.subscriptionPlan == 'standard').length;

      // Shell destination hosted by SuperAdminMainScreen: no Scaffold of
      // its own — PageContainer/PageHeader is the only chrome a page may
      // use inside a shell. The old teal banner folds into the PageHeader;
      // provider wiring and navigation are unchanged.
      return PageContainer(
        header: const PageHeader(
          title: 'سپر ایڈمن پینل',
          description: 'مدرسہ 360 — فرنچائز نیٹ ورک',
          actions: [
            DashboardGuideButton(roleKey: 'super_admin'),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: M360Email(
                  user.email,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            Text('نیٹ ورک خلاصہ', style: AppTypography.titleMedium),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                M360StatCard(
                  value: total.toString(),
                  label: 'کل مدارس',
                  icon: Icons.account_balance,
                  iconBackground: AppColors.primary.withValues(alpha: 0.12),
                  valueColor: AppColors.primary,
                ),
                M360StatCard(
                  value: active.toString(),
                  label: 'فعال',
                  icon: Icons.check_circle_outline,
                  iconBackground: AppColors.success.withValues(alpha: 0.12),
                  valueColor: AppColors.success,
                ),
                M360StatCard(
                  value: premium.toString(),
                  label: 'پریمیم',
                  icon: Icons.star_outline,
                  iconBackground: AppColors.warning.withValues(alpha: 0.12),
                  valueColor: AppColors.warning,
                ),
                M360StatCard(
                  value: standard.toString(),
                  label: 'اسٹینڈرڈ',
                  icon: Icons.grade_outlined,
                  iconBackground: AppColors.info.withValues(alpha: 0.12),
                  valueColor: AppColors.info,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('مدارس کی فہرست', style: AppTypography.titleMedium),
                const Spacer(),
                M360SecondaryButton(
                  label: 'سب دیکھیں',
                  icon: Icons.arrow_forward,
                  onPressed: _openManagement,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Loading
            if (madrasaState.isLoading)
              const M360LoadingState(itemCount: 4, padding: EdgeInsets.zero),

            // Empty
            if (!madrasaState.isLoading && madrasas.isEmpty)
              M360EmptyState(
                icon: Icons.account_balance_outlined,
                title: 'کوئی مدرسہ نہیں',
                description: '',
                actionLabel: 'پہلا مدرسہ شامل کریں',
                onAction: _openManagement,
              ),

            // List
            for (final m in madrasas)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: M360Card(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Text(
                        m.nameUrdu.isNotEmpty ? m.nameUrdu[0] : 'م',
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    title: Text(m.nameUrdu, style: AppTypography.bodyLarge),
                    subtitle: Text(
                      '${m.cityUrdu} • ${m.planLabel}',
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    trailing: M360Badge.custom(
                      label: m.isActive ? 'فعال' : 'غیرفعال',
                      color: m.isActive ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
