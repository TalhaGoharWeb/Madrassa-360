import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../providers/madrasa_provider.dart';
import '../../../providers/auth_provider.dart';
import 'madrasa_management_screen.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});
  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
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

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      _ref = ref;
      final madrasaState = ref.watch(madrasaProvider);
      final user = ref.watch(authProvider).user;
      final madrasas = madrasaState.madrasas;

      final total   = madrasas.length;
      final active  = madrasas.where((m) => m.isActive).length;
      final premium = madrasas.where((m) => m.subscriptionPlan == 'premium').length;
      final standard = madrasas.where((m) => m.subscriptionPlan == 'standard').length;

      return Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF283593)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.account_balance, color: Colors.white70, size: 28),
                          const SizedBox(width: 10),
                          Text('سپر ایڈمن پینل',
                              style: AppTypography.headingSmall.copyWith(color: Colors.white)),
                        ]),
                        const SizedBox(height: 6),
                        Text('مدرسہ 360 — فرنچائز نیٹ ورک',
                            style: AppTypography.bodyMedium.copyWith(color: Colors.white60)),
                        if (user != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(user.email,
                                style: AppTypography.labelSmall.copyWith(
                                    color: Colors.white38)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Stat cards ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        _StatCard('کل مدارس', total.toString(),
                            Icons.account_balance, const Color(0xFF1A237E)),
                        _StatCard('فعال', active.toString(),
                            Icons.check_circle_outline, AppColors.success),
                        _StatCard('پریمیم', premium.toString(),
                            Icons.star_outline, Colors.amber[700]!),
                        _StatCard('اسٹینڈرڈ', standard.toString(),
                            Icons.grade_outlined, AppColors.info),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Madrasas list preview ─────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Row(
                  children: [
                    Text('مدارس کی فہرست', style: AppTypography.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('سب دیکھیں'),
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const MadrasaManagementScreen())),
                    ),
                  ],
                ),
              ),
            ),

            // Loading
            if (madrasaState.isLoading)
              const SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ))),

            // Empty
            if (!madrasaState.isLoading && madrasas.isEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.account_balance_outlined,
                          size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text('کوئی مدرسہ نہیں',
                          style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('پہلا مدرسہ شامل کریں'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white),
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const MadrasaManagementScreen())),
                      ),
                    ]),
                  ),
                ),
              ),

            // List
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final m = madrasas[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1A237E),
                          child: Text(
                            m.nameUrdu.isNotEmpty
                                ? m.nameUrdu[0]
                                : 'م',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(m.nameUrdu,
                            style: AppTypography.bodyLarge),
                        subtitle: Text(
                          '${m.cityUrdu} • ${m.planLabel}',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: m.isActive
                                ? AppColors.success.withOpacity(0.1)
                                : AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            m.isActive ? 'فعال' : 'غیرفعال',
                            style: AppTypography.labelSmall.copyWith(
                                color: m.isActive
                                    ? AppColors.success
                                    : AppColors.error),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: madrasas.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: AppTypography.headingSmall.copyWith(color: color)),
          Text(label,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }
}
