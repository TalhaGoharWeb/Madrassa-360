/// آڈٹ لاگز — انسانی اردو
/// Master Admin — platform-wide audit trail, rendered as human-readable
/// Urdu: "who did what to what, when".
///
/// Filters: tenant, action, actor (user), date range. Paginated list with
/// an expandable per-entry detail view (before/after values in readable
/// form, never raw JSON).
///
/// Tenant isolation: every query below goes through the authenticated
/// Supabase client, so the `audit_logs` RLS policies in
/// `supabase/migrations/012_audit_logs.sql` are the enforcement point —
/// platform admins see all rows, tenant admins/owners see only their own
/// tenant's rows, and `tenant_id` NULL (platform-level) rows are visible
/// to platform admins only. This screen never bypasses RLS.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/audit_urdu.dart';
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

  String? _tenantFilter; // tenant_id or null = all (RLS still applies)
  String? _actionFilter; // action code or null = all
  String? _actorFilter; // user_id or null = all
  DateTime? _fromDay; // Karachi calendar day, inclusive
  DateTime? _toDay; // Karachi calendar day, inclusive
  final List<Map<String, dynamic>> _logs = [];

  List<Map<String, dynamic>> _tenants = [];
  List<String> _actions = [];
  final Map<String, String> _actorNames = {}; // user_id -> display name

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
      // RLS on tenants: a non-platform viewer only sees their own
      // tenant(s), so the dropdown degrades honestly.
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
      // NOTE: plain table query on the authenticated client — the
      // 012_audit_logs RLS policies decide which rows come back.
      final params = auditFilterParams(
        tenantId: _tenantFilter,
        action: _actionFilter,
        actorId: _actorFilter,
        fromDay: _fromDay,
        toDay: _toDay,
      );
      var q = _client.from('audit_logs').select('''
        id, tenant_id, user_id, action, entity, entity_id,
        old_data, new_data, metadata, created_at,
        tenants ( name, tenant_code )
      ''');
      final tenantId = params['tenant_id'];
      if (tenantId != null) q = q.eq('tenant_id', tenantId);
      final action = params['action'];
      if (action != null) q = q.eq('action', action);
      final actorId = params['user_id'];
      if (actorId != null) q = q.eq('user_id', actorId);
      final from = params['created_from'];
      if (from != null) q = q.gte('created_at', from);
      final to = params['created_to'];
      if (to != null) q = q.lt('created_at', to);
      final rows = await q
          .order('created_at', ascending: false)
          .range(_logs.length, _logs.length + _pageSize - 1);
      if (rows.length < _pageSize) _hasMore = false;
      _logs.addAll(List<Map<String, dynamic>>.from(rows));
      await _resolveActorNames();
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

  /// Best-effort actor display names via profiles (RLS-gated). Rows whose
  /// actor has no readable profile keep rendering — with the passive
  /// Urdu voice — instead of breaking the list.
  Future<void> _resolveActorNames() async {
    final ids = {for (final l in _logs) l['user_id'] as String?}
        .whereType<String>()
        .where((id) => !_actorNames.containsKey(id))
        .toList();
    if (ids.isEmpty) return;
    try {
      final rows =
          await _client.from('profiles').select('id, name').inFilter('id', ids);
      for (final m in rows) {
        final id = m['id'] as String?;
        final name = (m['name'] as String?)?.trim();
        if (id != null && name != null && name.isNotEmpty) {
          _actorNames[id] = name;
        }
      }
    } catch (_) {
      // Names stay unresolved; the list still renders.
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _loadPage();
    if (mounted) setState(() => _loadingMore = false);
  }

  List<String> get _actorIds {
    final ids = {for (final l in _logs) l['user_id'] as String?}
        .whereType<String>()
        .toList();
    ids.sort((a, b) => _actorLabel(a).compareTo(_actorLabel(b)));
    return ids;
  }

  String _actorLabel(String id) =>
      _actorNames[id] ?? 'صارف ${id.substring(0, 8)}…';

  Future<void> _pickDay(bool isFrom) async {
    final now = toKarachiTime(DateTime.now());
    final initial = isFrom
        ? _fromDay ?? now.subtract(const Duration(days: 7))
        : _toDay ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: isFrom ? 'شروع کی تاریخ' : 'اختتام کی تاریخ',
      cancelText: 'منسوخ',
      confirmText: 'منتخب کریں',
    );
    if (picked == null) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (isFrom) {
        _fromDay = day;
        if (_toDay != null && _toDay!.isBefore(day)) _toDay = day;
      } else {
        _toDay = day;
        if (_fromDay != null && _fromDay!.isAfter(day)) _fromDay = day;
      }
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Urdu-first: the whole screen reads right-to-left.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _filtersBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  initialValue: _tenantFilter,
                  decoration: const InputDecoration(
                    labelText: 'مدرسہ',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('تمام مدارس')),
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
                  initialValue: _actionFilter,
                  decoration: const InputDecoration(
                    labelText: 'عمل کی قسم',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('تمام اعمال')),
                    for (final a in _actions)
                      DropdownMenuItem<String?>(
                          value: a, child: Text(auditActionLabelUrdu(a))),
                  ],
                  onChanged: (v) {
                    setState(() => _actionFilter = v);
                    _refresh();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  initialValue: _actorFilter,
                  decoration: const InputDecoration(
                    labelText: 'صارف',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('تمام صارفین')),
                    for (final id in _actorIds)
                      DropdownMenuItem<String?>(
                        value: id,
                        child: Text(_actorLabel(id),
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _actorFilter = v);
                    _refresh();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDay(true),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _fromDay == null
                              ? 'از تاریخ'
                              : formatAuditDayUrdu(_fromDay!),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDay(false),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _toDay == null
                              ? 'تک تاریخ'
                              : formatAuditDayUrdu(_toDay!),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    if (_fromDay != null || _toDay != null)
                      IconButton(
                        tooltip: 'تاریخ صاف کریں',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _fromDay = null;
                            _toDay = null;
                          });
                          _refresh();
                        },
                      ),
                  ],
                ),
              ),
            ],
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
        message: 'موجودہ فلٹرز سے کوئی ریکارڈ نہیں ملا۔',
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
        return _logCard(_logs[i]);
      },
    );
  }

  Widget _logCard(Map<String, dynamic> l) {
    final tenant = l['tenants'] as Map<String, dynamic>?;
    final action = (l['action'] as String?) ?? '';
    final userId = l['user_id'] as String?;
    final actorName = userId == null ? null : _actorNames[userId];
    final createdAt = _parseTime(l['created_at']);
    final message = auditMessageUrdu(
      action: action,
      actorName: actorName,
      tenantName: tenant?['name'] as String?,
      entity: l['entity'] as String?,
      entityId: l['entity_id'] as String?,
      oldData: _asMap(l['old_data']),
      newData: _asMap(l['new_data']),
      metadata: _asMap(l['metadata']),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(_iconFor(action), color: AppColors.primary, size: 28),
        title: Text(
          message,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          createdAt == null ? '—' : formatAuditDateUrdu(createdAt),
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('کس نے', actorName ?? 'نامعلوم'),
                _kv('مدرسہ', tenant?['name'] ?? 'پلیٹ فارم'),
                _kv('عمل کی قسم', auditActionLabelUrdu(action)),
                ..._diffRows(_asMap(l['old_data']), _asMap(l['new_data'])),
                ..._metadataRows(_asMap(l['metadata'])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _diffRows(
      Map<String, dynamic>? oldData, Map<String, dynamic>? newData) {
    final diffs = auditFieldDiffs(oldData, newData);
    if (diffs.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('تبدیلیاں',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      ),
      for (final d in diffs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(d.labelUrdu,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textPrimary),
                    children: [
                      TextSpan(
                        text: d.oldText,
                        style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: AppColors.textSecondary),
                      ),
                      const TextSpan(text: '  ←  '),
                      TextSpan(
                        text: d.newText,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _metadataRows(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata.isEmpty) return const [];
    final entries = metadata.entries
        .where((e) => e.key != 'source') // internal writer tag, not user info
        .toList();
    if (entries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('اضافی معلومات',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      ),
      for (final e in entries) _kv(fieldLabelUrdu(e.key), e.value),
    ];
  }

  IconData _iconFor(String action) {
    if (action.startsWith('tenant.')) return Icons.account_balance_outlined;
    if (action.startsWith('manage-users.')) {
      return Icons.person_add_alt_outlined;
    }
    if (action.startsWith('INSERT_') ||
        action.startsWith('UPDATE_') ||
        action.startsWith('DELETE_')) {
      return Icons.receipt_long_outlined;
    }
    if (action.contains('.created') ||
        action.contains('.updated') ||
        action.contains('.deleted')) {
      return Icons.admin_panel_settings_outlined;
    }
    return Icons.history;
  }

  DateTime? _parseTime(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Map<String, dynamic>? _asMap(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
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
