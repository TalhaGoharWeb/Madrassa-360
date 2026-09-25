/// لائسنس پلانز
/// Master Admin — full CRUD on license_plans. Master Admins can create,
/// edit, activate/deactivate and delete plans (deletion blocked by FK when
/// subscriptions/licenses reference the plan — the DB error is surfaced).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = [];

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
      final rows =
          await _client.from('license_plans').select().order('price_monthly');
      _plans = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openEditor({Map<String, dynamic>? plan}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanEditorDialog(plan: plan),
    );
    if (changed == true) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> plan) async {
    try {
      await _client
          .from('license_plans')
          .update({'is_active': !(plan['is_active'] as bool? ?? true)}).eq(
              'id', plan['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> plan) async {
    final name = (plan['name'] as String?) ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پلان حذف کریں؟'),
        content:
            Text('Delete plan "$name"? This is blocked if any subscription or '
                'license references it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('منسوخ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف کریں'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _client.from('license_plans').delete().eq('id', plan['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingWidget(message: 'پلان لوڈ ہو رہے ہیں…');
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'license_plans دستیاب نہیں',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _load,
      );
    }
    return Scaffold(
      body: _plans.isEmpty
          ? EmptyStateWidget(
              icon: Icons.card_membership_outlined,
              title: 'کوئی پلان نہیں',
              message: 'Create the first license plan.',
              actionLabel: 'نیا پلان',
              onAction: () => _openEditor(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _plans.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = _plans[i];
                  final active = p['is_active'] as bool? ?? true;
                  final modules =
                      (p['enabled_modules'] as List?)?.join(', ') ?? '—';
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: (active
                                  ? AppColors.success
                                  : AppColors.textSecondary)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.card_membership,
                            color: active
                                ? AppColors.success
                                : AppColors.textSecondary),
                      ),
                      title: Text(
                        (p['name'] as String?) ?? '—',
                        style: AppTypography.titleMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${p['description'] ?? ''}\n'
                        'طلبہ: ${p['max_students'] ?? '—'} • '
                        'اساتذہ: ${p['max_teachers'] ?? '—'} • '
                        'صارفین: ${p['max_users'] ?? '—'}\n'
                        'ماڈیولز: $modules\n'
                        'قیمت: ${p['price_monthly'] ?? '—'}/ماہ',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _openEditor(plan: p);
                          if (v == 'toggle') _toggleActive(p);
                          if (v == 'delete') _delete(p);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('ترمیم')),
                          PopupMenuItem(
                              value: 'toggle',
                              child:
                                  Text(active ? 'غیر فعال کریں' : 'فعال کریں')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('حذف کریں')),
                        ],
                      ),
                      onTap: () => _openEditor(plan: p),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('نیا پلان'),
      ),
    );
  }
}

class _PlanEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? plan;
  const _PlanEditorDialog({this.plan});

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _maxStudents;
  late final TextEditingController _maxTeachers;
  late final TextEditingController _maxUsers;
  late final TextEditingController _price;
  late final TextEditingController _modules;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _name = TextEditingController(text: (p?['name'] ?? '').toString());
    _description =
        TextEditingController(text: (p?['description'] ?? '').toString());
    _maxStudents =
        TextEditingController(text: (p?['max_students'] ?? '').toString());
    _maxTeachers =
        TextEditingController(text: (p?['max_teachers'] ?? '').toString());
    _maxUsers = TextEditingController(text: (p?['max_users'] ?? '').toString());
    _price =
        TextEditingController(text: (p?['price_monthly'] ?? '').toString());
    final mods = p?['enabled_modules'];
    _modules = TextEditingController(text: mods is List ? mods.join(', ') : '');
    _isActive = p?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _maxStudents,
      _maxTeachers,
      _maxUsers,
      _price,
      _modules
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _asInt(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());
  double? _asDouble(String s) =>
      s.trim().isEmpty ? null : double.tryParse(s.trim());

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final payload = {
      'name': _name.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'max_students': _asInt(_maxStudents.text),
      'max_teachers': _asInt(_maxTeachers.text),
      'max_users': _asInt(_maxUsers.text),
      'price_monthly': _asDouble(_price.text),
      'enabled_modules': _modules.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'is_active': _isActive,
    };
    try {
      final client = Supabase.instance.client;
      if (widget.plan == null) {
        await client.from('license_plans').insert(payload);
      } else {
        await client
            .from('license_plans')
            .update(payload)
            .eq('id', widget.plan!['id']);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.plan == null ? 'نیا پلان' : 'پلان میں ترمیم'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'نام / Name *'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'یہ خانہ ضروری ہے'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  decoration:
                      const InputDecoration(labelText: 'تفصیل / Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _maxStudents,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Max students'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _maxTeachers,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Max teachers'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _maxUsers,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Max users'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'قیمت/ماہ / Price monthly'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _modules,
                  decoration: const InputDecoration(
                    labelText: 'ماڈیولز / Enabled modules',
                    hintText: 'students, teachers, fees, … (comma separated)',
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('فعال / Active'),
                  dense: true,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('منسوخ'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('محفوظ کریں'),
        ),
      ],
    );
  }
}
