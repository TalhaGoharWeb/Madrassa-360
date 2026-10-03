/// نیا مدرسہ وِزارڈ
/// Master Admin — 5-step tenant provisioning wizard.
///
/// Step 1: institution details · Step 2: defaults · Step 3: license plan ·
/// Step 4: modules · Step 5: tenant admin account → provision-tenant Edge
/// Function → progress → success (tenant_code + admin email; the password is
/// NEVER shown back) / error state carrying the function's message.
///
/// Phase 10: pushed wizard flow — keeps its root Scaffold (a stepper needs
/// its own scaffold scope), but the chrome moved to M360AppBar and the
/// fields, dropdowns, buttons, and states use the m360 components. Step
/// validation, the exact provision-tenant payload, password clearing, and
/// success/error semantics are unchanged.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:madrasa_360/core/design/m360.dart';
import 'package:madrasa_360/core/errors/error_boundary.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

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
      showM360SnackBar(
        context,
        'براہ کرم ایک پلان منتخب کریں — پلان کے بغیر مدرسہ نہیں بن سکتا',
        isError: true,
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
    } on FunctionException catch (e, st) {
      setState(() {
        _provisioning = false;
        _provisionError =
            ErrorBoundary.handleErrorSimple(e, st, tag: 'master/provision');
      });
    } catch (e, st) {
      setState(() {
        _provisioning = false;
        _provisionError =
            ErrorBoundary.handleErrorSimple(e, st, tag: 'master/provision');
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Pushed wizard flow: keeps its root Scaffold — a stepper with its own
    // nav bar needs its own scaffold scope. Only the chrome moved to the
    // m360 deep-screen app bar.
    return Scaffold(
      appBar: const M360AppBar(title: 'نیا مدرسہ / New Madrasa'),
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
                    child: M360SecondaryButton(
                      label: 'واپس',
                      onPressed: () => setState(() => _step--),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: M360PrimaryButton(
                    label: _step == 4 ? 'مدرسہ بنائیں' : 'آگے',
                    onPressed: _next,
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
      child: M360TextField(
        controller: c,
        label: label,
        keyboardType: keyboard,
        validator: validator ??
            (required
                ? (v) =>
                    (v == null || v.trim().isEmpty) ? 'یہ خانہ ضروری ہے' : null
                : null),
      ),
    );
  }

  /// Password field with a show/hide toggle. [M360TextField] has no suffix
  /// widget slot, so this uses the shared [m360FieldDecoration] — the same
  /// decoration every design-system field uses — instead of building its
  /// own InputDecoration.
  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
        style: AppTypography.bodyLarge,
        decoration: m360FieldDecoration(
          label: label,
          suffixIcon: IconButton(
            tooltip: obscure ? 'پاس ورڈ دکھائیں' : 'پاس ورڈ چھپائیں',
            icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: onToggleVisibility,
          ),
        ),
        validator: validator,
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
        M360Dropdown<String>(
          label: 'زبان / Language',
          value: _language,
          items: const [
            M360DropdownItem(value: 'ur', label: 'اردو (Urdu)'),
            M360DropdownItem(value: 'en', label: 'English'),
            M360DropdownItem(value: 'ar', label: 'العربية'),
          ],
          onChanged: (v) => setState(() => _language = v ?? 'ur'),
        ),
        const SizedBox(height: 12),
        _field(_timezone, 'ٹائم زون / Timezone *', required: true),
        const SizedBox(height: 12),
        M360Dropdown<String>(
          label: 'کرنسی / Currency',
          value: _currency,
          items: const [
            M360DropdownItem(value: 'PKR', label: 'PKR — روپیہ'),
            M360DropdownItem(value: 'USD', label: 'USD — ڈالر'),
            M360DropdownItem(value: 'SAR', label: 'SAR — ریال'),
            M360DropdownItem(value: 'AED', label: 'AED — درہم'),
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
        child: M360LoadingState(itemCount: 3),
      );
    }
    if (_plans.isEmpty) {
      return const M360EmptyState(
        icon: Icons.card_membership_outlined,
        title: 'کوئی پلان نہیں',
        description: 'provision-tenant requires a plan_id, so a plan must '
            'exist before provisioning. Create one first in the Plans '
            'section, then return here.',
      );
    }
    return RadioGroup<String>(
      groupValue: _planId,
      onChanged: (v) => setState(() => _planId = v),
      child: Column(
        children: [
          for (final p in _plans)
            M360Card(
              margin: const EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.zero,
              child: RadioListTile<String>(
                value: p['id'] as String,
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
      ),
    );
  }

  Widget _modulesStep() {
    if (_catalogLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: M360LoadingState(itemCount: 4),
      );
    }
    if (_catalog.isEmpty) {
      return const M360EmptyState(
        icon: Icons.extension_outlined,
        title: 'ماڈیول کیٹلاگ دستیاب نہیں',
        description: 'modules_catalog could not be loaded. Continuing with '
            'the platform defaults.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            M360TertiaryButton(
              label: 'سب منتخب کریں',
              onPressed: () => setState(() =>
                  _modules.addAll(_catalog.map((m) => m['module'] as String))),
            ),
            M360TertiaryButton(
              label: 'سب ہٹائیں',
              onPressed: () => setState(() => _modules.clear()),
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
        _passwordField(
          controller: _adminPassword,
          label: 'پاس ورڈ / Password *',
          obscure: _obscure1,
          onToggleVisibility: () => setState(() => _obscure1 = !_obscure1),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.isEmpty) return 'یہ خانہ ضروری ہے';
            if (v.length < 8) return 'کم از کم 8 حروف';
            if (_passwordStrength(v) < 3) {
              return 'مزید مضبوط پاس ورڈ رکھیں (بڑے/چھوٹے حروف، ہندسے)';
            }
            return null;
          },
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
        _passwordField(
          controller: _adminPasswordConfirm,
          label: 'پاس ورڈ کی تصدیق / Confirm *',
          obscure: _obscure2,
          onToggleVisibility: () => setState(() => _obscure2 = !_obscure2),
          validator: (v) =>
              v != _adminPassword.text ? 'پاس ورڈ مماثل نہیں' : null,
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
            M360Card(
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
            const SizedBox(height: 16),
            Text(
              'حفاظتی نوٹ: ایڈمن کا پاس ورڈ یہاں ظاہر نہیں کیا گیا۔ '
              'اسے محفوظ طریقے سے مدرسے کے منتظم تک پہنچائیں۔',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            M360PrimaryButton(
              label: 'فہرست پر واپس جائیں',
              onPressed: () => Navigator.of(context).pop(),
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
          const SizedBox(width: 12),
          Flexible(
            child: SelectableText(value,
                textAlign: TextAlign.end,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold)),
          ),
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
                M360SecondaryButton(
                  label: 'تفصیلات درست کریں',
                  onPressed: () => setState(() => _provisionError = null),
                ),
                const SizedBox(width: 12),
                M360PrimaryButton(
                  label: 'دوبارہ کوشش کریں',
                  onPressed: _provision,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
