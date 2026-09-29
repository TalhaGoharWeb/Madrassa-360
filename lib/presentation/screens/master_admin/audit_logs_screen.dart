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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/reports/documents/audit_log_report.dart';
import '../../../core/reports/export/csv_export.dart';
import '../../../core/reports/export/tabular_data.dart';
import '../../../core/utils/audit_urdu.dart';
import 'audit_export.dart';
import 'widgets/ma_widgets.dart';

const _pageSize = 30;

/// Cap for a single export — keeps one export from exhausting memory on
/// a huge platform log. The count is reported honestly in the UI.
const _exportCap = 5000;

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
  bool _exporting = false;
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
      await _resolveActorNamesFor(_logs);
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
  Future<void> _resolveActorNamesFor(List<Map<String, dynamic>> rows) async {
    final ids = {for (final l in rows) l['user_id'] as String?}
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
          _exportBar(),
          _filtersBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// Real export actions — both honour the ACTIVE filters (same query
  /// params as the list). Buttons are never decorative: they generate
  /// real files and report real success or failure.
  Widget _exportBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          M360SecondaryButton(
            icon: Icons.download_outlined,
            label: 'CSV ڈاؤن لوڈ',
            isLoading: _exporting,
            onPressed: _exporting ? null : _exportCsv,
          ),
          const SizedBox(width: 8),
          M360SecondaryButton(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF ایکسپورٹ',
            isLoading: _exporting,
            onPressed: _exporting ? null : _exportPdf,
          ),
        ],
      ),
    );
  }

  /// Fetches every row matching the ACTIVE filters (paged, capped).
  ///
  /// Uses the identical filter params as the list query — the export can
  /// never silently include rows the filters exclude.
  Future<List<Map<String, dynamic>>> _fetchAllForExport() async {
    final params = auditExportFilterParams(
      tenantId: _tenantFilter,
      action: _actionFilter,
      actorId: _actorFilter,
      fromDay: _fromDay,
      toDay: _toDay,
    );
    final out = <Map<String, dynamic>>[];
    while (out.length < _exportCap) {
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
          .range(out.length, out.length + _pageSize - 1);
      out.addAll(List<Map<String, dynamic>>.from(rows));
      if (rows.length < _pageSize) break;
    }
    await _resolveActorNamesFor(out);
    return out;
  }

  String _actorNameOf(Map<String, dynamic> log) {
    final id = log['user_id'] as String?;
    if (id == null) return 'نامعلوم';
    return _actorNames[id] ??
        'صارف ${id.length > 8 ? id.substring(0, 8) : id}…';
  }

  /// Urdu one-line summary of the active filters (used in the PDF).
  String _filterSummaryUr() {
    final parts = <String>[];
    String? tenantName;
    for (final t in _tenants) {
      if (t['id'] == _tenantFilter) {
        tenantName = t['name'] as String?;
        break;
      }
    }
    parts.add(
        _tenantFilter == null ? 'تمام مدارس' : (tenantName ?? 'منتخب مدرسہ'));
    parts.add(_actionFilter == null
        ? 'تمام اعمال'
        : auditActionLabelUrdu(_actionFilter!));
    parts.add(_actorFilter == null
        ? 'تمام صارفین'
        : _actorNameOf({'user_id': _actorFilter}));
    if (_fromDay != null || _toDay != null) {
      parts.add(
          '${_fromDay == null ? '…' : formatAuditDayUrdu(_fromDay!)} تا ${_toDay == null ? '…' : formatAuditDayUrdu(_toDay!)}');
    }
    return 'فلٹر: ${parts.join('، ')}';
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final logs = await _fetchAllForExport();
      if (logs.isEmpty) {
        showM360SnackBar(context, 'ایکسپورٹ کے لیے کوئی ریکارڈ نہیں ملا۔');
        return;
      }
      final networkCols = auditNetworkColumns(logs);
      final headers = buildAuditExportHeaders(networkCols);
      final data = [
        for (final l in logs)
          buildAuditExportRow(l,
              actorName: _actorNames[l['user_id'] as String?],
              networkColumns: networkCols),
      ];
      final csv = CsvExport.build([
        ReportTable(
            sheetName: 'audit_log',
            titleUr: 'آڈٹ لاگ',
            headers: headers,
            rows: data),
      ]);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/audit-log-${_stamp()}.csv');
      await file.writeAsString(csv);
      if (mounted) {
        showM360SnackBar(
            context, 'CSV محفوظ ہو گئی (${data.length} ریکارڈ): ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        showM360SnackBar(context, 'CSV ایکسپورٹ ناکام ہوا۔ دوبارہ کوشش کریں۔');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final logs = await _fetchAllForExport();
      if (logs.isEmpty) {
        showM360SnackBar(context, 'ایکسپورٹ کے لیے کوئی ریکارڈ نہیں ملا۔');
        return;
      }
      final networkCols = auditNetworkColumns(logs);
      final headers = buildAuditExportHeaders(networkCols);
      final data = [
        for (final l in logs)
          buildAuditExportRow(l,
              actorName: _actorNames[l['user_id'] as String?],
              networkColumns: networkCols),
      ];
      final bytes = await AuditLogReport.build(
        headers: headers,
        rows: data,
        filterSummaryUr: _filterSummaryUr(),
      );
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/audit-log-${_stamp()}.pdf');
      await file.writeAsBytes(bytes);
      // System share sheet (existing pattern from the certificates
      // screen); the saved file is the real artifact either way.
      await Printing.sharePdf(
          bytes: bytes, filename: 'audit-log-${_stamp()}.pdf');
      if (mounted) {
        showM360SnackBar(
            context, 'PDF محفوظ ہو گئی (${data.length} ریکارڈ): ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        showM360SnackBar(context, 'PDF ایکسپورٹ ناکام ہوا۔ دوبارہ کوشش کریں۔');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
                child: M360Dropdown<String?>(
                  label: 'مدرسہ',
                  value: _tenantFilter,
                  // isExpanded-style behaviour lives in the design system:
                  // long names ellipsize instead of overflowing.
                  items: [
                    const M360DropdownItem<String?>(
                        value: null, label: 'تمام مدارس'),
                    for (final t in _tenants)
                      M360DropdownItem<String?>(
                        value: t['id'] as String,
                        label: '${t['name']} (${t['tenant_code'] ?? ''})',
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
                child: M360Dropdown<String?>(
                  label: 'عمل کی قسم',
                  value: _actionFilter,
                  items: [
                    const M360DropdownItem<String?>(
                        value: null, label: 'تمام اعمال'),
                    for (final a in _actions)
                      M360DropdownItem<String?>(
                          value: a, label: auditActionLabelUrdu(a)),
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
                child: M360Dropdown<String?>(
                  label: 'صارف',
                  value: _actorFilter,
                  items: [
                    const M360DropdownItem<String?>(
                        value: null, label: 'تمام صارفین'),
                    for (final id in _actorIds)
                      M360DropdownItem<String?>(
                          value: id, label: _actorLabel(id)),
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
                // Wrap (not a squeezed Row of Expanded buttons): on a 360px
                // phone the two date buttons cannot share ~125px without
                // overflowing, so they stack; on wider screens they sit
                // side by side (Phase 13 responsiveness).
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    M360SecondaryButton(
                      onPressed: () => _pickDay(true),
                      icon: Icons.calendar_today,
                      label: _fromDay == null
                          ? 'از تاریخ'
                          : formatAuditDayUrdu(_fromDay!),
                    ),
                    M360SecondaryButton(
                      onPressed: () => _pickDay(false),
                      icon: Icons.calendar_today,
                      label: _toDay == null
                          ? 'تک تاریخ'
                          : formatAuditDayUrdu(_toDay!),
                    ),
                    if (_fromDay != null || _toDay != null)
                      M360IconButton(
                        tooltip: 'تاریخ صاف کریں',
                        icon: Icons.clear,
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
        title: 'آڈٹ ریکارڈ ابھی تیار نہیں',
        message: 'آڈٹ ریکارڈ رکھنے والا نظام ابھی تیار ہو رہا ہے — '
            'یہ صفحہ خود بخود فعال ہو جائے گا۔',
      );
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'خرابی ہو گئی',
        // Never surface raw server text to the user; the honest Urdu
        // message stays above the retry action.
        message: 'لاگز لوڈ نہیں ہو سکے — انٹرنیٹ چیک کریں اور دوبارہ '
            'کوشش کریں۔',
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
    return M360Card(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(_iconFor(action), color: AppColors.primary, size: 28),
        title: Text(
          message,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          createdAt == null ? '—' : formatAuditDateUrdu(createdAt),
          style:
              AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
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
            style: AppTypography.bodyMedium
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
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondary)),
              ),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    children: [
                      TextSpan(
                        text: d.oldText,
                        style: AppTypography.bodyMedium.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const TextSpan(text: '  ←  '),
                      TextSpan(
                        text: d.newText,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
            style: AppTypography.bodyMedium
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
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: SelectableText((value ?? '—').toString(),
                style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}
