/// ماسٹر ڈیش بورڈ
/// Master Admin dashboard — platform-wide KPIs + honest system health checks.
///
/// Licensing tables (license_plans / licenses / tenant_subscriptions) are
/// owned by a parallel worker; every licensing query is guarded so the
/// dashboard degrades to "—" instead of crashing if a table is missing.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'madrasa_detail_screen.dart';
import 'madrasa_list_screen.dart';
import 'widgets/ma_widgets.dart';

class MasterDashboardScreen extends StatefulWidget {
  const MasterDashboardScreen({super.key});

  @override
  State<MasterDashboardScreen> createState() => _MasterDashboardScreenState();
}

class _TenantStats {
  int total = 0;
  final Map<String, int> byStatus = {};
}

class _MasterDashboardScreenState extends State<MasterDashboardScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  _TenantStats _tenants = _TenantStats();
  int? _students;
  int? _staff;
  int? _users;
  int? _activeSubs;
  int? _expiringSubs;

  final Map<String, _HealthResult> _health = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([
        _loadTenantStats(),
        _loadPeopleCounts(),
        _loadSubscriptionStats(),
      ]);
      await _runHealthChecks();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Tenant stats: one query, grouped client-side ──────────────────────
  Future<void> _loadTenantStats() async {
    final stats = _TenantStats();
    final rows = await _client.from('tenants').select('status');
    for (final r in rows) {
      final status = (r['status'] as String?) ?? 'unknown';
      stats.total++;
      stats.byStatus[status] = (stats.byStatus[status] ?? 0) + 1;
    }
    _tenants = stats;
  }

  // ── People counts via platform-admin RLS ──────────────────────────────
  Future<void> _loadPeopleCounts() async {
    // students / staff: platform admins pass the "platform admins only"
    // policy on every business table, so direct counts are allowed.
    final students = await _client.from('students').select('id');
    final staff = await _client.from('staff').select('id');
    final memberships =
        await _client.from('tenant_memberships').select('user_id');

    _students = students.length;
    _staff = staff.length;
    _users = {
      for (final m in memberships) (m['user_id'] as String?)
    }.whereType<String>().length;
  }

  // ── Subscription stats (Worker 4's tables — may not exist yet) ───────
  Future<void> _loadSubscriptionStats() async {
    try {
      final rows = await _client
          .from('tenant_subscriptions')
          .select('status, expires_at');
      final cutoff = DateTime.now().add(const Duration(days: 30));
      var active = 0;
      var expiring = 0;
      for (final r in rows) {
        final status = (r['status'] as String?) ?? '';
        if (status != 'active') continue;
        active++;
        final exp = r['expires_at'];
        if (exp is String) {
          final dt = DateTime.tryParse(exp);
          if (dt != null && dt.isBefore(cutoff)) expiring++;
        }
      }
      _activeSubs = active;
      _expiringSubs = expiring;
    } catch (_) {
      // Table not provisioned yet — leave null ("—").
      _activeSubs = null;
      _expiringSubs = null;
    }
  }

  // ── System health checks ─────────────────────────────────────────────
  Future<void> _runHealthChecks() async {
    // 1. Database: a trivial select through the platform-admin RLS path.
    try {
      await _client.from('tenants').select('id').limit(1);
      _health['Database'] =
          const _HealthResult(MaHealth.ok, 'PostgREST reachable');
    } catch (e) {
      _health['Database'] = _HealthResult(MaHealth.down, 'Query failed: $e');
    }

    // 2. Auth: a live session must exist (we are behind the guard).
    final session = _client.auth.currentSession;
    _health['Auth'] = session != null
        ? const _HealthResult(MaHealth.ok, 'Session valid')
        : const _HealthResult(
            MaHealth.down, 'No active session — re-login required');

    // 3. Storage: list buckets (platform-level check).
    try {
      final buckets = await _client.storage.listBuckets();
      _health['Storage'] = _HealthResult(
          MaHealth.ok, '${buckets.length} bucket(s) reachable');
    } catch (e) {
      _health['Storage'] =
          _HealthResult(MaHealth.down, 'listBuckets failed: $e');
    }

    // 4. Edge Functions: there is no safe no-op endpoint, so we probe the
    //    provision-tenant function with a deliberately invalid payload and
    //    interpret the result HONESTLY — never a faked green.
    try {
      final res = await _client.functions
          .invoke('provision-tenant', body: const {'__health_probe': true});
      _health['Functions'] = _HealthResult(
        MaHealth.warning,
        'provision-tenant responded (HTTP ${res.status}); probe payload '
        'rejected or accepted upstream — treat as "reachable, unverified".',
      );
    } on FunctionException catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('404') || msg.contains('not found')) {
        _health['Functions'] = const _HealthResult(
            MaHealth.unknown, 'provision-tenant not deployed (404)');
      } else {
        _health['Functions'] = _HealthResult(
          MaHealth.unknown,
          'Function exists but probe failed: ${e.reasonPhrase ?? e}',
        );
      }
    } catch (e) {
      _health['Functions'] =
          _HealthResult(MaHealth.unknown, 'Uncheckable: $e');
    }

    // 5. API (PostgREST) — already proven by the database check above, but
    //    reported separately for the panel.
    _health['API'] = _health['Database']?.status == MaHealth.ok
        ? const _HealthResult(MaHealth.ok, 'PostgREST responding')
        : const _HealthResult(MaHealth.down, 'See database check');
  }

  String _stat(String? v) => v ?? '—';

  void _goToMadrasas() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Madrasas')),
          body: MadrasaListScreen(
            onOpenDetail: (tenantId) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MadrasaDetailScreen(tenantId: tenantId),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingWidget(message: 'ڈیش بورڈ لوڈ ہو رہا ہے…');
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'خرابی / Error',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _load,
      );
    }

    final t = _tenants;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('پلیٹ فارم جائزہ',
                style: AppTypography.headingSmall.copyWith(
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 12),

            // ── Madrasa stats ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 170,
                  child: MaStatCard(
                    label: 'Total madrasas',
                    value: '${t.total}',
                    icon: Icons.account_balance,
                    color: AppColors.primary,
                    onTap: _goToMadrasas,
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: MaStatCard(
                    label: 'Active',
                    value: '${t.byStatus['active'] ?? 0}',
                    icon: Icons.check_circle_outline,
                    color: AppColors.success,
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: MaStatCard(
                    label: 'Trial',
                    value: '${t.byStatus['trial'] ?? 0}',
                    icon: Icons.science_outlined,
                    color: AppColors.info,
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: MaStatCard(
                    label: 'Expired',
                    value: '${t.byStatus['expired'] ?? 0}',
                    icon: Icons.timer_off_outlined,
                    color: AppColors.error,
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: MaStatCard(
                    label: 'Suspended',
                    value: '${t.byStatus['suspended'] ?? 0}',
                    icon: Icons.pause_circle_outline,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── People stats ──
            MaSectionCard(
              title: 'People across all tenants',
              subtitle: 'Counts via platform-admin RLS',
              child: Row(
                children: [
                  Expanded(
                    child: MaStatCard(
                      label: 'Students',
                      value: _stat(_students?.toString()),
                      icon: Icons.school_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  Expanded(
                    child: MaStatCard(
                      label: 'Staff',
                      value: _stat(_staff?.toString()),
                      icon: Icons.badge_outlined,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  Expanded(
                    child: MaStatCard(
                      label: 'Users',
                      value: _stat(_users?.toString()),
                      icon: Icons.people_outline,
                      color: AppColors.info,
                    ),
                  ),
                ],
              ),
            ),

            // ── Subscription stats ──
            MaSectionCard(
              title: 'Subscriptions',
              subtitle: _activeSubs == null
                  ? 'tenant_subscriptions table not provisioned yet'
                  : 'Active vs expiring within 30 days',
              child: Row(
                children: [
                  Expanded(
                    child: MaStatCard(
                      label: 'Active subscriptions',
                      value: _stat(_activeSubs?.toString()),
                      icon: Icons.autorenew,
                      color: AppColors.success,
                    ),
                  ),
                  Expanded(
                    child: MaStatCard(
                      label: 'Expiring ≤ 30 days',
                      value: _stat(_expiringSubs?.toString()),
                      icon: Icons.schedule,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),

            // ── System health ──
            MaSectionCard(
              title: 'System health',
              subtitle: 'Live checks — statuses are never faked',
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: AppColors.textSecondary),
                  tooltip: 'Re-run checks',
                  onPressed: () async {
                    await _runHealthChecks();
                    if (mounted) setState(() {});
                  },
                ),
              ],
              child: Column(
                children: [
                  for (final entry in _health.entries)
                    MaHealthTile(
                      label: entry.key,
                      status: entry.value.status,
                      detail: entry.value.detail,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthResult {
  final MaHealth status;
  final String detail;
  const _HealthResult(this.status, this.detail);
}
