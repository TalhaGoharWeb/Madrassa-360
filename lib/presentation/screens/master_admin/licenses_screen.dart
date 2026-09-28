/// لائسنسز
/// Master Admin — licenses table view (issued by provision-tenant).
/// Read-mostly: issue/revoke are server-side actions; the screen surfaces
/// records with status + expiry.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

const _licenseStatuses = ['all', 'active', 'expired', 'revoked', 'suspended'];

class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String _status = 'all';
  List<Map<String, dynamic>> _rows = [];

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
      var q = _client.from('licenses').select('''
        tenant_id, plan_id, status, issued_at, expires_at,
        max_users, max_students, enabled_modules,
        tenants ( name, tenant_code ),
        license_plans ( name )
      ''');
      if (_status != 'all') q = q.eq('status', _status);
      final rows =
          await q.order('expires_at', ascending: true, nullsFirst: false);
      _rows = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _licenseStatuses.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = _licenseStatuses[i];
              final selected = s == _status;
              return ChoiceChip(
                label: Text(s == 'all' ? 'All' : s),
                selected: selected,
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                onSelected: (_) {
                  setState(() => _status = s);
                  _load();
                },
              );
            },
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingWidget(message: 'لائسنس لوڈ ہو رہے ہیں…');
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'licenses دستیاب نہیں',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _load,
      );
    }
    if (_rows.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.verified_outlined,
        title: 'کوئی لائسنس نہیں',
        message: 'Licenses are issued automatically by provision-tenant.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final r = _rows[i];
          final tenant = r['tenants'] as Map<String, dynamic>?;
          final plan = r['license_plans'] as Map<String, dynamic>?;
          final status = (r['status'] as String?) ?? 'unknown';
          final modules = (r['enabled_modules'] as List?)?.join(', ') ?? '—';
          return Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.verified,
                  color: AppColors.primary, size: 32),
              title: Text(
                (tenant?['name'] as String?) ??
                    (r['tenant_id'] as String? ?? '—'),
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'پلان: ${(plan?['name'] as String?) ?? '—'}  •  '
                'اختتام: ${(r['expires_at'] as String?)?.substring(0, 10) ?? '—'}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              trailing: MaStatusChip(status: status),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv('Tenant code', tenant?['tenant_code']),
                      _kv('Issued',
                          (r['issued_at'] as String?)?.substring(0, 10)),
                      _kv('Max users', r['max_users']),
                      _kv('Max students', r['max_students']),
                      _kv('Enabled modules', modules),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          Flexible(
            child: Text((value ?? '—').toString(),
                style: AppTypography.bodySmall
                    .copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
