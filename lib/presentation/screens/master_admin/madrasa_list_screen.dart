/// مدارس کی فہرست
/// Master Admin — searchable, filterable, paginated tenant list.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'create_madrasa_wizard.dart';
import 'madrasa_detail_screen.dart';
import 'widgets/ma_widgets.dart';

const _statusFilters = [
  'all',
  'active',
  'trial',
  'expired',
  'suspended',
  'archived',
];

const _pageSize = 25;

class MadrasaListScreen extends StatefulWidget {
  /// When set, tapping a tenant calls this instead of pushing the detail
  /// screen (used by the shell which owns navigation).
  final void Function(String tenantId)? onOpenDetail;

  const MadrasaListScreen({super.key, this.onOpenDetail});

  @override
  State<MadrasaListScreen> createState() => _MadrasaListScreenState();
}

class _MadrasaListScreenState extends State<MadrasaListScreen> {
  final _client = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  String _status = 'all';
  String _query = '';
  final List<Map<String, dynamic>> _tenants = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q != _query) {
        _query = q;
        _refreshDebounced();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void>? _pending;
  void _refreshDebounced() {
    _pending ??= Future.delayed(const Duration(milliseconds: 400), () {
      _pending = null;
      _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _tenants.clear();
      _hasMore = true;
    });
    await _loadPage();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _loadPage();
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _loadPage() async {
    try {
      var query = _client
          .from('tenants')
          .select(
              'id, tenant_code, name, name_urdu, city, status, created_at')
          .order('created_at', ascending: false);

      if (_status != 'all') {
        query = query.eq('status', _status);
      }
      if (_query.isNotEmpty) {
        final q = _query.replaceAll('%', '');
        query = query.or(
            'name.ilike.%$q%,name_urdu.ilike.%$q%,tenant_code.ilike.%$q%,city.ilike.%$q%');
      }

      final from = _tenants.length;
      final rows = await query.range(from, from + _pageSize - 1);
      if (rows.length < _pageSize) _hasMore = false;
      _tenants.addAll(rows);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _openDetail(String tenantId) {
    if (widget.onOpenDetail != null) {
      widget.onOpenDetail!(tenantId);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MadrasaDetailScreen(tenantId: tenantId),
      ),
    );
  }

  void _openWizard() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateMadrasaWizard()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'نام، کوڈ یا شہر سے تلاش کریں…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _statusFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = _statusFilters[i];
              final selected = s == _status;
              return ChoiceChip(
                label: Text(s == 'all' ? 'All' : s),
                selected: selected,
                selectedColor: AppColors.primary.withOpacity(0.15),
                onSelected: (_) {
                  setState(() => _status = s);
                  _refresh();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingWidget(message: 'مدارس لوڈ ہو رہے ہیں…');
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
    if (_tenants.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.account_balance_outlined,
        title: 'کوئی مدرسہ نہیں ملا',
        message: 'No madrasas match the current search and filters.',
        actionLabel: 'نیا مدرسہ بنائیں',
        onAction: _openWizard,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _tenants.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == _tenants.length) {
          // Trigger next page once, then show a loader row.
          _loadMore();
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final t = _tenants[i];
        final status = (t['status'] as String?) ?? 'unknown';
        final nameUrdu = (t['name_urdu'] as String?) ?? '';
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance,
                  color: AppColors.primary),
            ),
            title: Text(
              (t['name'] as String?) ?? '—',
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nameUrdu.isNotEmpty)
                  Text(nameUrdu,
                      style: AppTypography.bodyMedium,
                      textDirection: TextDirection.rtl),
                Text(
                  '${t['tenant_code'] ?? ''}  •  ${t['city'] ?? ''}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            trailing: MaStatusChip(status: status),
            onTap: () => _openDetail(t['id'] as String),
          ),
        );
      },
    );
  }
}
