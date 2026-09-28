/// سبسکرپشنز
/// Master Admin — tenant_subscriptions overview with status filter and
/// expiry highlighting (≤30 days amber, expired red).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

const _subStatuses = ['all', 'active', 'trial', 'expired', 'cancelled'];

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
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
      var q = _client.from('tenant_subscriptions').select('''
        tenant_id, plan_id, status, started_at, expires_at,
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

  Color _expiryColor(String? expiresAt, String status) {
    if (status == 'expired' || status == 'cancelled') return AppColors.error;
    if (expiresAt == null) return AppColors.textSecondary;
    final dt = DateTime.tryParse(expiresAt);
    if (dt == null) return AppColors.textSecondary;
    final days = dt.difference(DateTime.now()).inDays;
    if (days < 0) return AppColors.error;
    if (days <= 30) return AppColors.warning;
    return AppColors.success;
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
            itemCount: _subStatuses.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = _subStatuses[i];
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
      return const LoadingWidget(message: 'سبسکرپشنز لوڈ ہو رہی ہیں…');
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'tenant_subscriptions دستیاب نہیں',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _load,
      );
    }
    if (_rows.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.autorenew_outlined,
        title: 'کوئی سبسکرپشن نہیں',
        message: 'No subscriptions match this filter.',
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
          final expiresAt = r['expires_at'] as String?;
          final color = _expiryColor(expiresAt, status);
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.autorenew, color: color, size: 32),
              title: Text(
                (tenant?['name'] as String?) ??
                    (r['tenant_id'] as String? ?? '—'),
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'پلان: ${(plan?['name'] as String?) ?? '—'}  •  '
                'کوڈ: ${(tenant?['tenant_code'] as String?) ?? '—'}\n'
                'شروع: ${(r['started_at'] as String?)?.substring(0, 10) ?? '—'}  •  '
                'اختتام: ${expiresAt?.substring(0, 10) ?? '—'}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              isThreeLine: true,
              trailing: MaStatusChip(status: status),
            ),
          );
        },
      ),
    );
  }
}
