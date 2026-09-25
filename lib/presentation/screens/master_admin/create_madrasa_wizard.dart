/// نیا مدرسہ وِزارڈ
/// Master Admin — 5-step tenant provisioning wizard.
///
/// Step 1: institution details · Step 2: defaults · Step 3: license plan ·
/// Step 4: modules · Step 5: tenant admin account → provision-tenant Edge
/// Function → progress → success (tenant_code + admin email; the password is
/// NEVER shown back) / error state carrying the function's message.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

class CreateMadrasaWizard extends StatefulWidget {
  const CreateMadrasaWizard({super.key});

  @override
  State<CreateMadrasaWizard> createState() => _CreateMadrasaWizardState();
}

class _CreateMadrasaWizardState extends State<CreateMadrasaWizard> {
  final _client = Supabase.instance.client;

  int _step = 0;
  final _formKeys = List.generate(5, (_) => GlobalKey<FormState>());

  // ── Step 1: institution ─────────────────────────────────────────────
  final _name = TextEditingController();
  final _nameUrdu = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _province = TextEditingController();
  final _country = TextEditingController(text: 'Pakistan');
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _principal = TextEditingController();
  final _regNumber = TextEditingController();

  // ── Step 2: defaults ────────────────────────────────────────────────
  String _language = 'ur';
  final _timezone = TextEditingController(text: 'Asia/Karachi');
  String _currency = 'PKR';

  // ── Step 3: plan ────────────────────────────────────────────────────
  List<Map<String, dynamic>> _plans = [];
  String? _planId;
  bool _plansLoading = true;

  // ── Step 4: modules ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _catalog = [];
  final Set<String> _modules = {};
  bool _catalogLoading = true;

  // ── Step 5: admin account ───────────────────────────────────────────
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  final _adminPasswordConfirm = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;

  // ── Provisioning state ──────────────────────────────────────────────
  bool _provisioning = false;
  String? _provisionError;
  String? _provisionedCode;
  String? _provisionedEmail;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _nameUrdu,
      _address,
      _city,
      _district,
      _province,
      _country,
      _phone,
      _email,
      _website,
      _principal,
      _regNumber,
      _timezone,
      _adminName,
      _adminEmail,
      _adminPassword,
      _adminPasswordConfirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    try {
      final catalog = await _client
          .from('modules_catalog')
          .select('module, name, name_urdu, description')
          .order('module');
      _catalog = List<Map<String, dynamic>>.from(catalog);
      _modules.addAll(_catalog.map((m) => m['module'] as String));
    } catch (_) {
      // leave empty — user can provision with no explicit module list
    }
    try {
      final plans = await _client
          .from('license_plans')
          .select(
              'id, name, description, max_students, max_users, price_monthly')
          .eq('is_active', true)
          .order('price_monthly');
      _plans = List<Map<String, dynamic>>.from(plans);
      if (_plans.isNotEmpty) _planId = _plans.first['id'] as String?;
    } catch (_) {
      // plans table not provisioned yet — plan step shows a notice
    }
    if (mounted) {
      setState(() {
        _catalogLoading = false;
        _plansLoading = false;
      });
    }
  }

  // ── Password strength ───────────────────────────────────────────────
  int _passwordStrength(String v) {
    var s = 0;
    if (v.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(v)) s++;
    if (RegExp(r'[a-z]').hasMatch(v)) s++;
    if (RegExp(r'[0-9]').hasMatch(v)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(v)) s++;
    return s; // 0..5
  }

  String _strengthLabel(int s) =>
      const ['بہت کمزور', 'کمزور', 'درمیانی', 'اچھا', 'مضبوط', 'بہت مضبوط'][s];

  // ── Navigation ──────────────────────────────────────────────────────
  void _next() {
    final form = _formKeys[_step].currentState;
    if (form != null && !form.validate()) return;
    if (_step == 2 && _planId == null) {
      // plan_id is a required UUID server-side — provisioning cannot proceed
      // without a plan.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'براہ کرم ایک پلان منتخب کریں — پلان کے بغیر مدرسہ نہیں بن سکتا')),
      );
      return;
    }
    if (_step < 4) {
      setState(() => _step++);
    } else {
      _provision();
    }
  }

  // ── Provision ───────────────────────────────────────────────────────
  //
  // Body shape matches supabase/functions/provision-tenant (flat fields:
  // name, plan_id, admin{…}, optional institution fields, language/timezone/
  // currency, modules[]). Success: { tenant_id, tenant_code, admin_email }.
  Future<void> _provision() async {
    setState(() {
      _provisioning = true;
      _provisionError = null;
    });

    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    final body = {
      'name': _name.text.trim(),
      'name_urdu': opt(_nameUrdu),
      'address': opt(_address),
      'city': opt(_city),
      'district': opt(_district),
      'province': opt(_province),
      'country': _country.text.trim(),
      'phone': opt(_phone),
      'email': opt(_email),
      'website': opt(_website),
      'principal_name': opt(_principal),
      'registration_number': opt(_regNumber),
      'language': _language,
      'timezone': _timezone.text.trim(),
      'currency': _currency,
      'plan_id': _planId,
      'modules': _modules.toList(),
      'admin': {
        'name': _adminName.text.trim(),
        'email': _adminEmail.text.trim(),
        // NOTE: password goes to the Edge Function over HTTPS only and is
        // never stored client-side beyond this call or shown back.
        'password': _adminPassword.text,
      },
    };

    try {
      final res =
          await _client.functions.invoke('provision-tenant', body: body);
      final data = res.data;
      String? code;
      if (data is Map) {
        code = (data['tenant_code'] ?? data['code'])?.toString();
      }
      // Never echo the password back — clear it immediately.
      _adminPassword.clear();
      _adminPasswordConfirm.clear();
      setState(() {
        _provisioning = false;
        _provisionedCode = code ?? '—';
        _provisionedEmail = _adminEmail.text.trim();
      });
    } on FunctionException catch (e) {
      setState(() {
        _provisioning = false;
        _provisionError = e.reasonPhrase?.isNotEmpty == true
            ? e.reasonPhrase
            : 'Provisioning function failed: $e';
      });
    } catch (e) {
      setState(() {
        _provisioning = false;
        _provisionError = 'Unexpected error: $e';
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نیا مدرسہ / New Madrasa'),
      ),
      body: _provisioning
          ? _buildProgress()
          : _provisionError != null
              ? _buildError()
              : _provisionedCode != null
                  ? _buildSuccess()
                  : _buildSteps(),
    );
  }

  // ── Steps UI ────────────────────────────────────────────────────────
  Widget _buildSteps() {
    const titles = [
      'ادارہ / Institution',
      'پہلے سے طے شدہ / Defaults',
      'پلان / Plan',
      'ماڈیولز / Modules',
      'ایڈمن اکاؤنٹ / Admin',
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: List.generate(5, (i) {
              final done = i < _step;
              final current = i == _step;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: done || current
                              ? AppColors.primary
                              : AppColors.divider,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        titles[i],
                        style: AppTypography.labelSmall.copyWith(
                          color: current
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight:
                              current ? FontWeight.bold : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Form(
              key: _formKeys[_step],
              child: _stepContent(),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('واپس'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _next,
                    child: Text(_step == 4 ? 'مدرسہ بنائیں' : 'آگے'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case 0:
        return _institutionStep();
      case 1:
        return _defaultsStep();
      case 2:
        return _planStep();
      case 3:
        return _modulesStep();
      case 4:
        return _adminStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false,
      TextInputType? keyboard,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: validator ??
            (required
                ? (v) =>
                    (v == null || v.trim().isEmpty) ? 'یہ خانہ ضروری ہے' : null
                : null),
      ),
    );
  }

  Widget _institutionStep() {
    return Column(
      children: [
        _field(_name, 'مدرسے کا نام / Name *', required: true),
        _field(_nameUrdu, 'نام (اردو)'),
        _field(_address, 'پتہ / Address'),
        Row(
          children: [
            Expanded(child: _field(_city, 'شہر / City')),
            const SizedBox(width: 12),
            Expanded(child: _field(_district, 'ضلع / District')),
          ],
        ),
        Row(
          children: [
            Expanded(child: _field(_province, 'صوبہ / Province')),
            const SizedBox(width: 12),
            Expanded(child: _field(_country, 'ملک / Country')),
          ],
        ),
        _field(_phone, 'فون / Phone', keyboard: TextInputType.phone),
        _field(_email, 'ای میل / Email', keyboard: TextInputType.emailAddress,
            validator: (v) {
          if (v == null || v.trim().isEmpty) return null;
          return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())
              ? null
              : 'درست ای میل لکھیں';
        }),
        _field(_website, 'ویب سائٹ / Website'),
        _field(_principal, 'پرنسپل کا نام / Principal'),
        _field(_regNumber, 'رجسٹریشن نمبر'),
      ],
    );
  }

  Widget _defaultsStep() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _language,
          decoration: const InputDecoration(labelText: 'زبان / Language'),
          items: const [
            DropdownMenuItem(value: 'ur', child: Text('اردو (Urdu)')),
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'ar', child: Text('العربية')),
          ],
          onChanged: (v) => setState(() => _language = v ?? 'ur'),
        ),
        const SizedBox(height: 12),
        _field(_timezone, 'ٹائم زون / Timezone *', required: true),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _currency,
          decoration: const InputDecoration(labelText: 'کرنسی / Currency'),
          items: const [
            DropdownMenuItem(value: 'PKR', child: Text('PKR — روپیہ')),
            DropdownMenuItem(value: 'USD', child: Text('USD — ڈالر')),
            DropdownMenuItem(value: 'SAR', child: Text('SAR — ریال')),
            DropdownMenuItem(value: 'AED', child: Text('AED — درہم')),
          ],
          onChanged: (v) => setState(() => _currency = v ?? 'PKR'),
        ),
      ],
    );
  }

  Widget _planStep() {
    if (_plansLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: LoadingWidget(message: 'پلان لوڈ ہو رہے ہیں…'),
      );
    }
    if (_plans.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.card_membership_outlined,
        title: 'کوئی پلان نہیں',
        message: 'provision-tenant requires a plan_id, so a plan must exist '
            'before provisioning. Create one first in the Plans section, '
            'then return here.',
      );
    }
    return Column(
      children: [
        for (final p in _plans)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<String>(
              value: p['id'] as String,
              groupValue: _planId,
              onChanged: (v) => setState(() => _planId = v),
              title: Text((p['name'] as String?) ?? '—',
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${p['description'] ?? ''}\n'
                'طلبہ: ${p['max_students'] ?? '—'}  •  '
                'صارفین: ${p['max_users'] ?? '—'}  •  '
                '${p['price_monthly'] ?? '—'}/ماہ',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }

  Widget _modulesStep() {
    if (_catalogLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: LoadingWidget(message: 'ماڈیولز لوڈ ہو رہے ہیں…'),
      );
    }
    if (_catalog.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.extension_outlined,
        title: 'ماڈیول کیٹلاگ دستیاب نہیں',
        message: 'modules_catalog could not be loaded. Continuing with '
            'the platform defaults.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() =>
                  _modules.addAll(_catalog.map((m) => m['module'] as String))),
              child: const Text('سب منتخب کریں'),
            ),
            TextButton(
              onPressed: () => setState(() => _modules.clear()),
              child: const Text('سب ہٹائیں'),
            ),
          ],
        ),
        for (final m in _catalog)
          CheckboxListTile(
            value: _modules.contains(m['module']),
            onChanged: (v) => setState(() {
              if (v == true) {
                _modules.add(m['module'] as String);
              } else {
                _modules.remove(m['module'] as String);
              }
            }),
            title: Text((m['name'] as String?) ?? m['module'] as String),
            subtitle: (m['name_urdu'] as String?)?.isNotEmpty == true
                ? Text(m['name_urdu'] as String,
                    textDirection: TextDirection.rtl)
                : (m['description'] as String?)?.isNotEmpty == true
                    ? Text(m['description'] as String)
                    : null,
            dense: true,
          ),
      ],
    );
  }

  Widget _adminStep() {
    final strength = _passwordStrength(_adminPassword.text);
    return Column(
      children: [
        _field(_adminName, 'نام / Full name *', required: true),
        _field(_adminEmail, 'ای میل / Email *',
            keyboard: TextInputType.emailAddress, validator: (v) {
          if (v == null || v.trim().isEmpty) return 'یہ خانہ ضروری ہے';
          return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())
              ? null
              : 'درست ای میل لکھیں';
        }),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: _adminPassword,
            obscureText: _obscure1,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'پاس ورڈ / Password *',
              suffixIcon: IconButton(
                icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure1 = !_obscure1),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'یہ خانہ ضروری ہے';
              if (v.length < 8) return 'کم از کم 8 حروف';
              if (_passwordStrength(v) < 3) {
                return 'مزید مضبوط پاس ورڈ رکھیں (بڑے/چھوٹے حروف، ہندسے)';
              }
              return null;
            },
          ),
        ),
        if (_adminPassword.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: strength / 5,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      strength <= 1
                          ? AppColors.error
                          : strength <= 3
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_strengthLabel(strength), style: AppTypography.bodySmall),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: _adminPasswordConfirm,
            obscureText: _obscure2,
            decoration: InputDecoration(
              labelText: 'پاس ورڈ کی تصدیق / Confirm *',
              suffixIcon: IconButton(
                icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure2 = !_obscure2),
              ),
            ),
            validator: (v) =>
                v != _adminPassword.text ? 'پاس ورڈ مماثل نہیں' : null,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'یہ اکاؤنٹ نئے مدرسے کا tenant admin ہوگا۔ پاس ورڈ صرف '
                  'ایک بار یہیں درج ہوتا ہے — کامیابی کی اسکرین پر اسے '
                  'دوبارہ نہیں دکھایا جائے گا۔',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Progress / success / error ──────────────────────────────────────
  Widget _buildProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(strokeWidth: 5),
            ),
            const SizedBox(height: 24),
            Text('مدرسہ بنایا جا رہا ہے…',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Tenant, settings, modules, plan, licenses اور admin '
              'اکاؤنٹ تیار ہو رہے ہیں۔ یہ اسکرین بند نہ کریں۔',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.check, color: AppColors.success, size: 56),
            ),
            const SizedBox(height: 24),
            Text('مدرسہ تیار ہے!',
                style: AppTypography.headingMedium
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _successRow('Tenant code', _provisionedCode ?? '—'),
                    const Divider(),
                    _successRow('Admin email', _provisionedEmail ?? '—'),
                    const Divider(),
                    _successRow('Status', 'trial'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'حفاظتی نوٹ: ایڈمن کا پاس ورڈ یہاں ظاہر نہیں کیا گیا۔ '
              'اسے محفوظ طریقے سے مدرسے کے منتظم تک پہنچائیں۔',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('فہرست پر واپس جائیں'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _successRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          SelectableText(value,
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 72, color: AppColors.error),
            const SizedBox(height: 20),
            Text('مدرسہ نہیں بن سکا',
                style: AppTypography.headingSmall
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _provisionError ?? 'Unknown error',
                style: AppTypography.bodySmall,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _provisionError = null),
                  child: const Text('تفصیلات درست کریں'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _provision,
                  child: const Text('دوبارہ کوشش کریں'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
