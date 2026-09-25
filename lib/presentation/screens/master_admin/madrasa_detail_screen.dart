/// مدرسے کی تفصیل
/// Master Admin — tenant detail: editable info, module toggles, and
/// lifecycle actions (suspend / reactivate / archive) via the manage-tenant
/// Edge Function. Destructive actions require TYPED confirmation
/// (mission §49/§50): the operator must type the tenant name exactly.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

class MadrasaDetailScreen extends StatefulWidget {
  final String tenantId;

  const MadrasaDetailScreen({super.key, required this.tenantId});

  @override
  State<MadrasaDetailScreen> createState() => _MadrasaDetailScreenState();
}

class _MadrasaDetailScreenState extends State<MadrasaDetailScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _tenant;
  bool _saving = false;

  // editable controllers
  final _name = TextEditingController();
  final _nameUrdu = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _province = TextEditingController();
  final _principal = TextEditingController();
  final _regNumber = TextEditingController();

  // modules
  List<Map<String, dynamic>> _catalog = [];
  Map<String, bool> _moduleState = {};
  bool _modulesSaving = false;

  // subscription snapshot (best effort — table may not exist yet)
  Map<String, dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _nameUrdu,
      _phone,
      _email,
      _website,
      _address,
      _city,
      _district,
      _province,
      _principal,
      _regNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenant = await _client
          .from('tenants')
          .select()
          .eq('id', widget.tenantId)
          .single();
      _tenant = Map<String, dynamic>.from(tenant);
      _fillControllers();

      try {
        final catalog = await _client
            .from('modules_catalog')
            .select('module, name, name_urdu')
            .order('module');
        _catalog = List<Map<String, dynamic>>.from(catalog);
        final mods = await _client
            .from('tenant_modules')
            .select('module, enabled')
            .eq('tenant_id', widget.tenantId);
        _moduleState = {
          for (final m in mods)
            (m['module'] as String): (m['enabled'] as bool? ?? false),
        };
      } catch (_) {
        _catalog = [];
      }

      try {
        final sub = await _client
            .from('tenant_subscriptions')
            .select('status, started_at, expires_at, plan_id')
            .eq('tenant_id', widget.tenantId)
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (sub != null) _subscription = Map<String, dynamic>.from(sub);
      } catch (_) {
        _subscription = null;
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _fillControllers() {
    final t = _tenant!;
    _name.text = (t['name'] ?? '').toString();
    _nameUrdu.text = (t['name_urdu'] ?? '').toString();
    _phone.text = (t['phone'] ?? '').toString();
    _email.text = (t['email'] ?? '').toString();
    _website.text = (t['website'] ?? '').toString();
    _address.text = (t['address'] ?? '').toString();
    _city.text = (t['city'] ?? '').toString();
    _district.text = (t['district'] ?? '').toString();
    _province.text = (t['province'] ?? '').toString();
    _principal.text = (t['principal_name'] ?? '').toString();
    _regNumber.text = (t['registration_number'] ?? '').toString();
  }

  // ── Save editable fields (direct update — platform-admin RLS) ─────────
  Future<void> _saveInfo() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final updates = {
        'name': _name.text.trim(),
        'name_urdu':
            _nameUrdu.text.trim().isEmpty ? null : _nameUrdu.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'website': _website.text.trim().isEmpty ? null : _website.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'district':
            _district.text.trim().isEmpty ? null : _district.text.trim(),
        'province':
            _province.text.trim().isEmpty ? null : _province.text.trim(),
        'principal_name':
            _principal.text.trim().isEmpty ? null : _principal.text.trim(),
        'registration_number':
            _regNumber.text.trim().isEmpty ? null : _regNumber.text.trim(),
      };
      final updated = await _client
          .from('tenants')
          .update(updates)
          .eq('id', widget.tenantId)
          .select()
          .single();
      _tenant = Map<String, dynamic>.from(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('محفوظ ہو گیا / Saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  // ── Module toggle (upsert into tenant_modules) ────────────────────────
  Future<void> _toggleModule(String module, bool enabled) async {
    setState(() {
      _moduleState[module] = enabled;
      _modulesSaving = true;
    });
    try {
      await _client.from('tenant_modules').upsert(
        {
          'tenant_id': widget.tenantId,
          'module': module,
          'enabled': enabled,
        },
        onConflict: 'tenant_id,module',
      );
    } catch (e) {
      // revert on failure
      setState(() => _moduleState[module] = !enabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Module update failed: $e')),
        );
      }
    }
    if (mounted) setState(() => _modulesSaving = false);
  }

  // ── Lifecycle actions via manage-tenant ──────────────────────────────
  Future<void> _confirmAndRunLifecycle(
      String action, String actionLabelUrdu) async {
    final tenantName = (_tenant?['name'] as String?) ?? '';
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text('$actionLabelUrdu — تصدیق'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'آگے بڑھنے کے لیے مدرسے کا نام بالکل ویسے ہی لکھیں:\n"$tenantName"',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'مدرسے کا نام لکھیں',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('منسوخ'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                onPressed: ctrl.text.trim() == tenantName
                    ? () => Navigator.of(ctx).pop(ctrl.text.trim())
                    : null,
                child: Text(actionLabelUrdu),
              ),
            ],
          ),
        );
      },
    );
    if (typed == null) return; // cancelled

    setState(() => _saving = true);
    try {
      await _client.functions.invoke('manage-tenant', body: {
        'tenant_id': widget.tenantId,
        'action': action,
      });
      await _load(); // refresh status
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$actionLabelUrdu — مکمل')),
        );
      }
    } on FunctionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Action failed: ${e.reasonPhrase ?? e.toString()}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaLoadingScaffold(message: 'تفصیل لوڈ ہو رہی ہے…');
    }
    if (_error != null || _tenant == null) {
      return MaErrorScaffold(
          message: _error ?? 'Tenant not found', onRetry: _load);
    }

    final t = _tenant!;
    final status = (t['status'] as String?) ?? 'unknown';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (t['name'] as String?) ?? 'Madrasa',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [MaStatusChip(status: status)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(t),
            const SizedBox(height: 8),
            _infoCard(),
            const SizedBox(height: 8),
            _subscriptionCard(),
            const SizedBox(height: 8),
            _modulesCard(),
            const SizedBox(height: 8),
            _lifecycleCard(status),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(Map<String, dynamic> t) {
    return MaSectionCard(
      title: (t['name_urdu'] as String?)?.isNotEmpty == true
          ? (t['name_urdu'] as String)
          : (t['name'] as String? ?? '—'),
      subtitle: 'Tenant code: ${t['tenant_code'] ?? '—'}',
      child: Column(
        children: [
          _kv('Slug', t['slug']),
          _kv('Registration #', t['registration_number']),
          _kv('Principal', t['principal_name']),
          _kv('Created', (t['created_at'] as String?)?.substring(0, 10)),
        ],
      ),
    );
  }

  Widget _kv(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              (value ?? '—').toString(),
              style: AppTypography.bodyMedium
                  .copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return MaSectionCard(
      title: 'ادارے کی معلومات / Institution info',
      subtitle: 'Direct update under platform-admin RLS',
      actions: [
        _saving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(
                onPressed: _saveInfo, child: const Text('محفوظ کریں')),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _editField(_name, 'نام / Name *', required: true),
            _editField(_nameUrdu, 'نام (اردو)'),
            Row(
              children: [
                Expanded(child: _editField(_phone, 'فون')),
                const SizedBox(width: 12),
                Expanded(child: _editField(_email, 'ای میل')),
              ],
            ),
            _editField(_website, 'ویب سائٹ'),
            _editField(_address, 'پتہ'),
            Row(
              children: [
                Expanded(child: _editField(_city, 'شہر')),
                const SizedBox(width: 12),
                Expanded(child: _editField(_district, 'ضلع')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _editField(_province, 'صوبہ')),
                const SizedBox(width: 12),
                Expanded(child: _editField(_principal, 'پرنسپل')),
              ],
            ),
            _editField(_regNumber, 'رجسٹریشن نمبر'),
          ],
        ),
      ),
    );
  }

  Widget _editField(TextEditingController c, String label,
      {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'یہ خانہ ضروری ہے' : null
            : null,
      ),
    );
  }

  Widget _subscriptionCard() {
    final sub = _subscription;
    return MaSectionCard(
      title: 'Subscription',
      subtitle: sub == null
          ? 'No subscription record (table may not be provisioned yet)'
          : null,
      child: sub == null
          ? const Text('—', style: TextStyle(color: AppColors.textSecondary))
          : Column(
              children: [
                _kv('Status', sub['status']),
                _kv('Started',
                    (sub['started_at'] as String?)?.substring(0, 10)),
                _kv('Expires',
                    (sub['expires_at'] as String?)?.substring(0, 10)),
                _kv('Plan ID', sub['plan_id']),
              ],
            ),
    );
  }

  Widget _modulesCard() {
    return MaSectionCard(
      title: 'ماڈیولز / Modules',
      subtitle: _modulesSaving ? 'Saving…' : 'Toggle per-tenant modules',
      child: _catalog.isEmpty
          ? const Text('Module catalog unavailable.',
              style: TextStyle(color: AppColors.textSecondary))
          : Column(
              children: [
                for (final m in _catalog)
                  SwitchListTile(
                    value: _moduleState[m['module']] ?? false,
                    onChanged: (v) => _toggleModule(m['module'] as String, v),
                    title:
                        Text((m['name'] as String?) ?? (m['module'] as String)),
                    subtitle: (m['name_urdu'] as String?)?.isNotEmpty == true
                        ? Text(m['name_urdu'] as String,
                            textDirection: TextDirection.rtl)
                        : null,
                    dense: true,
                  ),
              ],
            ),
    );
  }

  Widget _lifecycleCard(String status) {
    return MaSectionCard(
      title: 'Lifecycle',
      subtitle: 'Actions run server-side via the manage-tenant function',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (status == 'suspended')
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reactivate'),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: _saving
                  ? null
                  : () => _confirmAndRunLifecycle('reactivate', 'بحال کریں'),
            )
          else
            ElevatedButton.icon(
              icon: const Icon(Icons.pause),
              label: const Text('Suspend'),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: _saving
                  ? null
                  : () => _confirmAndRunLifecycle('suspend', 'معطل کریں'),
            ),
          ElevatedButton.icon(
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: _saving
                ? null
                : () => _confirmAndRunLifecycle('archive', 'آرکائیو کریں'),
          ),
        ],
      ),
    );
  }
}
