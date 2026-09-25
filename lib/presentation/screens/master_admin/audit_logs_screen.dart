/// آڈٹ لاگز
/// Master Admin — platform-wide audit trail, filterable by tenant and
/// action. The audit_logs table is owned by a parallel worker; if it is
/// not provisioned yet the screen says so instead of crashing.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

const _pageSize = 30;

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _missingTable;

  String? _tenantFilter; // tenant_id or null = all
  String? _actionFilter; // action string or null = all
  final List<Map<String, dynamic>> _logs = [];

  List<Map<String, dynamic>> _tenants = [];
  List<String> _actions = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_loadTenantOptions(), _loadActionOptions()]);
    await _refresh();
  }

  Future<void> _loadTenantOptions() async {
    try {
      final rows = await _client
          .from('tenants')
          .select('id, name, tenant_code')
          .order('name')
          .limit(200);
      _tenants = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      _tenants = [];
    }
  }

  Future<void> _loadActionOptions() async {
    try {
      // distinct actions — best effort
      final rows = await _client.from('audit_logs').select('action').limit(500);
      _actions = {for (final r in rows) (r['action'] as String?)}
          .whereType<String>()
          .toList()
        ..sort();
    } catch (_) {
      _actions = [];
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _missingTable = null;
      _logs.clear();
      _hasMore = true;
    });
    await _loadPage();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPage() async {
    try {
      var q = _client.from('audit_logs').select('''
        id, tenant_id, user_id, action, entity, entity_id,
        old_data, new_data, metadata, created_at,
        tenants ( name, tenant_code )
      ''');
      if (_tenantFilter != null) q = q.eq('tenant_id', _tenantFilter!);
      if (_actionFilter != null) q = q.eq('action', _actionFilter!);
      final rows = await q
          .order('created_at', ascending: false)
          .range(_logs.length, _logs.length + _pageSize - 1);
      if (rows.length < _pageSize) _hasMore = false;
      _logs.addAll(List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('audit_logs') &&
          (msg.contains('does not exist') ||
              msg.contains('relation') ||
              msg.contains('pgrst'))) {
        _missingTable = e.toString();
      } else {
        _error = e.toString();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _loadPage();
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _filtersBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String?>(
              value: _tenantFilter,
              decoration: const InputDecoration(
                labelText: 'مدرسہ / Tenant',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All tenants')),
                for (final t in _tenants)
                  DropdownMenuItem<String?>(
                    value: t['id'] as String,
                    child: Text(
                      '${t['name']} (${t['tenant_code'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                setState(() => _tenantFilter = v);
                _refresh();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              value: _actionFilter,
              decoration: const InputDecoration(
                labelText: 'Action',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All actions')),
                for (final a in _actions)
                  DropdownMenuItem<String?>(value: a, child: Text(a)),
              ],
              onChanged: (v) {
                setState(() => _actionFilter = v);
                _refresh();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingWidget(message: 'لاگز لوڈ ہو رہے ہیں…');
    }
    if (_missingTable != null) {
      return const EmptyStateWidget(
        icon: Icons.receipt_long_outlined,
        title: 'audit_logs table not provisioned',
        message: 'The audit_logs table is built by a parallel worker. '
            'This screen will light up once the migration lands.',
      );
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'خرابی / Error',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _refresh,
      );
    }
    if (_logs.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.receipt_long_outlined,
        title: 'کوئی لاگ نہیں',
        message: 'No audit entries match the current filters.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _logs.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == _logs.length) {
          _loadMore();
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final l = _logs[i];
        final tenant = l['tenants'] as Map<String, dynamic>?;
        return Card(
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            leading:
                const Icon(Icons.history, color: AppColors.primary, size: 28),
            title: Text(
              '${l['action'] ?? '—'}  •  ${l['entity'] ?? '—'}',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${(tenant?['name'] as String?) ?? 'platform'}  •  '
              '${(l['created_at'] as String?)?.replaceAll('T', ' ').substring(0, 19) ?? '—'}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('Tenant', tenant?['name']),
                    _kv('User ID', l['user_id']),
                    _kv('Entity ID', l['entity_id']),
                    _kv(
                        'Metadata',
                        (l['metadata'] ?? '').toString().isEmpty
                            ? null
                            : l['metadata'].toString()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: SelectableText((value ?? '—').toString(),
                style: AppTypography.bodySmall),
          ),
        ],
      ),
    );
  }
}
