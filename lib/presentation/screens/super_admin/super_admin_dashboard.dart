/// سپر ایڈمن ڈیش بورڈ
/// Super Admin dashboard — all tenants/madaaris with SaaS status.
///
/// Lists every tenant with active / suspended / expired indicators,
/// search + status filter, and tap-to-manage navigation. Gated: non
/// super-admins see an access-denied panel (fails closed).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../services/super_admin_service.dart';
import 'tenant_detail_screen.dart';

enum _TenantFilter { all, active, suspended, expired }

class SuperAdminDashboard extends ConsumerStatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  ConsumerState<SuperAdminDashboard> createState() =>
      _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends ConsumerState<SuperAdminDashboard> {
  late Future<bool> _accessFuture;
  Future<List<Tenant>>? _tenantsFuture;
  String _query = '';
  _TenantFilter _filter = _TenantFilter.all;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _accessFuture = _checkAccess();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _checkAccess() async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final ok =
        await ref.read(superAdminServiceProvider).isSuperAdmin(uid);
    if (ok && mounted) {
      setState(() => _tenantsFuture = _loadTenants());
    }
    return ok;
  }

  Future<List<Tenant>> _loadTenants() =>
      ref.read(superAdminServiceProvider).getAllTenants();

  void _refresh() {
    setState(() => _tenantsFuture = _loadTenants());
  }

  List<Tenant> _applyFilter(List<Tenant> tenants) {
    var list = tenants;
    if (_filter == _TenantFilter.active) {
      list = list.where((t) => t.isUsable).toList();
    } else if (_filter == _TenantFilter.suspended) {
      list = list.where((t) => t.isSuspended).toList();
    } else if (_filter == _TenantFilter.expired) {
      list = list.where((t) => t.isExpired).toList();
    }
    final q = _query.trim();
    if (q.isNotEmpty) {
      list = list
          .where((t) =>
              t.name.contains(q) ||
              t.urduName.contains(q) ||
              t.id.toLowerCase().contains(q.toLowerCase()))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('سپر ایڈمن پینل', style: AppTypography.appBarTitle),
        centerTitle: true,
      ),
      body: FutureBuilder<bool>(
        future: _accessFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.data != true) return _accessDenied();
          return _tenantList();
        },
      ),
    );
  }

  Widget _accessDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined,
                size: 72, color: AppColors.error),
            const SizedBox(height: 16),
            Text('رسائی ممنوع ہے',
                style: AppTypography.headingSmall
                    .copyWith(color: AppColors.error)),
            const SizedBox(height: 8),
            Text(
              'یہ پینل صرف سپر ایڈمن کے لیے ہے۔',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: Text('واپس جائیں', style: AppTypography.buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tenantList() {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<Tenant>>(
        future: _tenantsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _errorState(snap.error.toString());
          }
          final tenants = snap.data ?? [];
          final filtered = _applyFilter(tenants);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _statsRow(tenants)),
              SliverToBoxAdapter(child: _searchBar()),
              SliverToBoxAdapter(child: _filterChips()),
              if (filtered.isEmpty)
                SliverFillRemaining(child: _emptyState())
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _tenantCard(filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  Widget _errorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text('ڈیٹا لوڈ نہیں ہو سکا',
                style: AppTypography.titleMedium),
            const SizedBox(height: 6),
            Text(error,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: Text('دوبارہ کوشش کریں',
                  style: AppTypography.buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_outlined,
              size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('کوئی مدرسہ نہیں ملا',
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _statsRow(List<Tenant> tenants) {
    final total = tenants.length;
    final active = tenants.where((t) => t.isUsable).length;
    final suspended = tenants.where((t) => t.isSuspended).length;
    final expired = tenants.where((t) => t.isExpired).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _statChip('کل', '$total', AppColors.primary),
          const SizedBox(width: 8),
          _statChip('فعال', '$active', AppColors.success),
          const SizedBox(width: 8),
          _statChip('معطل', '$suspended', AppColors.error),
          const SizedBox(width: 8),
          _statChip('میعاد ختم', '$expired', AppColors.warning),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(value,
                style: AppTypography.headingSmall.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTypography.labelNastaliq
                    .copyWith(fontSize: 15, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'مدرسہ تلاش کریں…',
          hintStyle: AppTypography.bodyMedium
              .copyWith(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    const labels = {
      _TenantFilter.all: 'تمام',
      _TenantFilter.active: 'فعال',
      _TenantFilter.suspended: 'معطل شدہ',
      _TenantFilter.expired: 'میعاد ختم',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: _TenantFilter.values.map((f) {
          final selected = _filter == f;
          return ChoiceChip(
            label: Text(labels[f]!,
                style: AppTypography.labelNastaliq.copyWith(
                  fontSize: 15,
                  color: selected ? Colors.white : AppColors.textPrimary,
                )),
            selected: selected,
            selectedColor: AppColors.primary,
            onSelected: (_) => setState(() => _filter = f),
          );
        }).toList(),
      ),
    );
  }

  Widget _tenantCard(Tenant t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        elevation: 1,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TenantDetailScreen(tenantId: t.id),
              ),
            );
            _refresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statusDot(t),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.displayName,
                          style: AppTypography.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (t.name.isNotEmpty && t.urduName.isNotEmpty)
                        Text(t.name,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        _statusBadge(t),
                        if (!t.isSuspended && t.expiresAt != null)
                          _expiryBadge(t),
                        _memberBadge(t),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusDot(Tenant t) {
    final color = t.isSuspended
        ? AppColors.error
        : t.isExpired
            ? AppColors.warning
            : AppColors.success;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _statusBadge(Tenant t) {
    final label = t.isSuspended
        ? 'معطل'
        : t.isExpired
            ? 'میعاد ختم'
            : 'فعال';
    final color = t.isSuspended
        ? AppColors.error
        : t.isExpired
            ? AppColors.warning
            : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: AppTypography.labelNastaliq
              .copyWith(fontSize: 15, color: color)),
    );
  }

  Widget _expiryBadge(Tenant t) {
    final days = t.daysRemaining;
    final label = days == null
        ? ''
        : days < 0
            ? 'میعاد ختم'
            : days == 0
                ? 'آج آخری دن'
                : '$days دن باقی';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: AppTypography.labelNastaliq
              .copyWith(fontSize: 15, color: AppColors.warning)),
    );
  }

  Widget _memberBadge(Tenant t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline,
              size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text('${t.memberCount}',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.primary)),
        ],
      ),
    );
  }
}
