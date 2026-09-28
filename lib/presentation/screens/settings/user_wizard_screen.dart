/// نیا صارف بنائیں / ذمہ داریاں تبدیل کریں — 5 مرحلہ وِزارڈ (Phase 8a)
/// Five-step creation / edit wizard, plain Urdu throughout:
///
/// 1. نام، موبائل، ای میل، پاس ورڈ
/// 2. "یہ صاحب کیا ذمہ داری سنبھالیں گے؟" (real tenant_roles)
/// 3. curated plain-sentence permission checklist + `مزید اختیارات`
/// 4. "یہ اختیارات کن لوگوں پر لاگو ہوں گے؟" (scope choices)
/// 5. خلاصہ: grants + meaningful exclusions + `محفوظ کریں`
///
/// Writes: edge `create_user` -> RPC `assign_tenant_role` ->
/// `set_user_permission` overrides -> `permission_scopes` (RLS).
/// "department" scope is NOT server-enforced (020 is fail-closed for it),
/// so the UI says this honestly and writes no row — it behaves as
/// whole-madrassa for now, exactly like `all`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/role_ux_repository.dart';
import '../../../providers/role_ux_provider.dart';
import 'role_ux_widgets.dart';

class UserWizardScreen extends ConsumerStatefulWidget {
  const UserWizardScreen({super.key}) : user = null;

  const UserWizardScreen.edit({super.key, required this.user});

  /// Null = create mode; non-null = edit mode (user detail "ذمہ داریاں تبدیل کریں").
  final TenantUser? user;

  bool get isEdit => user != null;

  @override
  ConsumerState<UserWizardScreen> createState() => _UserWizardScreenState();
}

class _UserWizardScreenState extends ConsumerState<UserWizardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _studentSearch = TextEditingController();
  bool _passwordVisible = false;

  int _step = 0;
  bool _saving = false;
  String? _savingError;

  String? _roleKey;
  Set<String> _selectedCodes = {};
  Set<String> _templateCodes = {};
  bool _moreOpen = false;

  String _scopeType = 'all';
  Set<String> _classIds = {};
  Set<String> _studentIds = {};
  List<StudentRef> _studentResults = const [];
  bool _studentSearching = false;

  bool _loaded = false;
  Future<_WizardData>? _future;
  String? _futureTenant;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _studentSearch.dispose();
    super.dispose();
  }

  // ── curated checklist (plain-sentence cards; rest under "مزید اختیارات")
  static const _curatedCodes = <String>[
    'attendance.mark',
    'attendance.edit',
    'results.enter',
    'results.edit',
    'students.view',
    'students.create',
    'classes.view',
    'teachers.view',
    'fees.view',
    'fees.collect',
    'staff.create',
    'users.view',
  ];

  static const _exclusionSentences = <String, String>{
    'attendance.mark': 'یہ صارف حاضری درج نہیں کر سکے گا۔',
    'results.enter': 'یہ صارف نتائج درج نہیں کر سکے گا۔',
    'students.create': 'یہ صارف نئے طلبہ کے ریکارڈ نہیں بنا سکے گا۔',
    'fees.view': 'ان کو مالی لین دین تک رسائی نہیں ہوگی۔',
    'fees.collect': 'ان کو مالی لین دین تک رسائی نہیں ہوگی۔',
    'users.view': 'یہ صارف دوسرے صارفین کی فہرست نہیں دیکھ سکے گا۔',
    'users.create': 'یہ صارف نئے صارفین نہیں بنا سکے گا۔',
    'roles.assign': 'یہ صارف کسی کو ذمہ داری نہیں سونپ سکے گا۔',
    'staff.create': 'یہ صارف عملے کے ریکارڈ نہیں بنا سکے گا۔',
  };

  static bool _isTeaching(String key) =>
      key.contains('ustad') ||
      key.contains('teacher') ||
      key == 'nazim_taleem' ||
      key == 'mumtahin' ||
      key == 'nazim_hifz';

  String _scopeSummaryUrdu() {
    switch (_scopeType) {
      case 'classes':
        return _classIds.isEmpty
            ? 'ابھی کوئی جماعت منتخب نہیں — کم از کم ایک جماعت منتخب کریں۔'
            : 'صرف مقرر کردہ ${_classIds.length} جماعتوں کے افراد پر۔';
      case 'students':
        return _studentIds.isEmpty
            ? 'ابھی کوئی طالب علم منتخب نہیں۔'
            : 'صرف منتخب کردہ ${_studentIds.length} طلبہ پر۔';
      case 'department':
        return 'فی الحال سرور شعبے کا دائرہ الگ سے نافذ نہیں کرتا — '
            'یہ انتخاب بھی پورے مدرسے پر لاگو ہوگا۔';
      case 'all':
      default:
        return 'پورے مدرسے کے افراد پر۔';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(currentTenantIdProvider);
    if (tenantId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('نیا صارف')),
        body: const UxEmptyState(
          icon: Icons.business_outlined,
          title: 'پہلے کوئی مدرسہ منتخب کریں',
        ),
      );
    }
    return FutureBuilder<_WizardData>(
      future: _futureFor(tenantId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
                title:
                    Text(widget.isEdit ? 'ذمہ داریاں تبدیل کریں' : 'نیا صارف')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Scaffold(
            appBar: AppBar(
                title:
                    Text(widget.isEdit ? 'ذمہ داریاں تبدیل کریں' : 'نیا صارف')),
            body: UxEmptyState(
              icon: Icons.error_outline,
              title: roleUxErrorMessage(snap.error ?? 'load'),
              hint: 'واپس جا کر دوبارہ کوشش کریں۔',
            ),
          );
        }
        final data = snap.data!;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(widget.isEdit ? 'ذمہ داریاں تبدیل کریں' : 'نیا صارف'),
            centerTitle: true,
          ),
          body: Column(
            children: [
              _stepper(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _stepBody(data),
                ),
              ),
              _navBar(data),
            ],
          ),
        );
      },
    );
  }

  Future<_WizardData> _futureFor(String tenantId) {
    if (_future == null || _futureTenant != tenantId) {
      _futureTenant = tenantId;
      _loaded = false;
      _future = _load(tenantId);
    }
    return _future!;
  }

  Future<_WizardData> _load(String tenantId) async {
    final repo = ref.read(roleUxRepositoryProvider);
    final roles = await repo.listRoles(tenantId);
    final catalog = await repo.permissionCatalog();
    if (_loaded) {
      return _WizardData(
          roles: roles,
          catalog: catalog,
          classes: const [],
          overrides: const {});
    }
    _loaded = true;
    final classes = await repo.listClasses(tenantId);
    Map<String, String> overrides = const {};
    Map<String, ScopeSelection> scopes = const {};
    if (widget.isEdit) {
      _roleKey = widget.user!.roleKey;
      overrides =
          await repo.userOverrides(tenantId: tenantId, userId: widget.user!.id);
      scopes =
          await repo.userScopes(tenantId: tenantId, userId: widget.user!.id);
    } else {
      // sensible first-run default: a teaching responsibility if present
      final teaching = roles.where((r) => _isTeaching(r.key));
      _roleKey = teaching.isNotEmpty ? teaching.first.key : null;
    }
    // Direct field assignment (no setState): the FutureBuilder rebuilds
    // when this future completes anyway.
    _initRoleTemplate(roles, catalog, overrides);
    if (widget.isEdit && scopes.isNotEmpty) {
      // reuse the first scoped code's selection for the wizard step
      final first = scopes.values.first;
      _scopeType = first.type;
      _classIds = first.classIds;
      _studentIds = first.studentIds;
    } else if (_roleKey != null) {
      if (_isTeaching(_roleKey!)) {
        _scopeType = 'classes';
      } else {
        _scopeType = 'all';
      }
    }
    return _WizardData(
        roles: roles, catalog: catalog, classes: classes, overrides: overrides);
  }

  /// Applies the chosen role's template: selected = template ∪ grants − denies.
  void _applyRoleTemplate(
    List<TenantRoleInfo> roles,
    List<PermissionInfo> catalog, {
    required Map<String, String> overrides,
  }) {
    _initRoleTemplate(roles, catalog, overrides);
    setState(() {});
  }

  void _initRoleTemplate(
    List<TenantRoleInfo> roles,
    List<PermissionInfo> catalog,
    Map<String, String> overrides,
  ) {
    final role = roles.where((r) => r.key == _roleKey).firstOrNull;
    _templateCodes = role?.permissionCodes ?? const {};
    final next = <String>{};
    for (final p in catalog) {
      final o = overrides[p.code];
      final on =
          o == 'grant' || (o != 'deny' && _templateCodes.contains(p.code));
      if (on) next.add(p.code);
    }
    _selectedCodes = next;
  }

  // ── stepper ──

  static const _stepTitles = [
    'بنیادی معلومات',
    'ذمہ داری',
    'اختیارات',
    'دائرۂ کار',
    'خلاصہ',
  ];

  Widget _stepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surface,
      child: Row(
        children: List.generate(_stepTitles.length * 2 - 1, (i) {
          if (i.isOdd) {
            final done = (i ~/ 2) < _step;
            return Expanded(
              child: Container(
                height: 2,
                color: done ? AppColors.primary : AppColors.divider,
              ),
            );
          }
          final n = i ~/ 2;
          final done = n < _step;
          final current = n == _step;
          return Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppColors.success
                      : current
                          ? AppColors.primary
                          : AppColors.divider,
                ),
                child: done
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text('${n + 1}',
                        style: AppTypography.labelSmall.copyWith(
                            color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 2),
              Text(
                _stepTitles[n],
                style: AppTypography.labelSmall.copyWith(
                    color:
                        current ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: current ? FontWeight.bold : FontWeight.normal),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ── step bodies ──

  Widget _stepBody(_WizardData data) {
    switch (_step) {
      case 0:
        return _stepIdentity();
      case 1:
        return _stepRole(data);
      case 2:
        return _stepPermissions(data);
      case 3:
        return _stepScope(data);
      default:
        return _stepSummary(data);
    }
  }

  Widget _stepIdentity() {
    if (widget.isEdit) {
      return UxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const UxSectionTitle('صارف', icon: Icons.person_outline),
            const SizedBox(height: 8),
            Text(widget.user!.name, style: AppTypography.titleMedium),
            if (widget.user!.email.isNotEmpty)
              Text(widget.user!.email,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              'نام، ای میل اور پاس ورڈ یہاں تبدیل نہیں ہوتے — صرف ذمہ داری، اختیارات اور دائرۂ کار تبدیل ہوں گے۔',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      );
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UxSectionTitle('بنیادی معلومات', icon: Icons.person_outline),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'نام *',
              hintText: 'مثلاً محمد احمد',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'نام درج کرنا ضروری ہے۔'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'موبائل',
              hintText: 'مثلاً 03001234567',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'ای میل *',
              hintText: 'مثلاً ahmad@madrassa.com',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'ای میل درج کرنا ضروری ہے۔';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                return 'درست ای میل درج کریں۔';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: !_passwordVisible,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'پاس ورڈ *',
              hintText: 'کم از کم 6 حروف',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _passwordVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
              ),
            ),
            validator: (v) => (v == null || v.length < 6)
                ? 'پاس ورڈ کم از کم 6 حروف کا ہو۔'
                : null,
          ),
        ],
      ),
    );
  }

  Widget _stepRole(_WizardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UxSectionTitle('یہ صاحب کیا ذمہ داری سنبھالیں گے؟',
            icon: Icons.badge_outlined),
        const SizedBox(height: 12),
        if (data.roles.isEmpty)
          const Text('اس مدرسے میں ابھی کوئی ذمہ داری درج نہیں۔'),
        RadioGroup<String>(
          groupValue: _roleKey,
          onChanged: (v) {
            if (v == null) return;
            setState(() => _roleKey = v);
            _applyRoleTemplate(data.roles, data.catalog, overrides: const {});
          },
          child: Column(
            children: [
              for (final r in data.roles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: UxCard(
                    onTap: () {
                      setState(() => _roleKey = r.key);
                      _applyRoleTemplate(data.roles, data.catalog,
                          overrides: const {});
                    },
                    child: Row(
                      children: [
                        Radio<String>(value: r.key),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.displayUrdu,
                                  style: AppTypography.titleSmall),
                              if (r.description != null &&
                                  r.description!.isNotEmpty)
                                Text(r.description!,
                                    style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textSecondary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              Text('${r.permissionCodes.length} اختیارات',
                                  style: AppTypography.labelSmall
                                      .copyWith(color: AppColors.primary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepPermissions(_WizardData data) {
    final catalog = data.catalog;
    final curated = [
      for (final p in catalog)
        if (_curatedCodes.contains(p.code)) p,
    ];
    final rest = [
      for (final p in catalog)
        if (!_curatedCodes.contains(p.code)) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UxSectionTitle('ان کو یہ اختیارات حاصل ہوں گے',
            icon: Icons.key_outlined),
        const SizedBox(height: 4),
        Text(
          'منتخب ذمہ داری کے اختیارات پہلے سے ٹک ہیں — ضرورت ہو تو کم یا زیادہ کریں۔',
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        for (final p in curated) _permissionTile(p),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: Icon(_moreOpen ? Icons.expand_less : Icons.expand_more),
          label: Text(_moreOpen ? 'کم اختیارات دیکھیں' : 'مزید اختیارات'),
          onPressed: () => setState(() => _moreOpen = !_moreOpen),
        ),
        if (_moreOpen) ...[
          const SizedBox(height: 8),
          for (final p in rest) _permissionTile(p),
        ],
      ],
    );
  }

  Widget _permissionTile(PermissionInfo p) {
    final on = _selectedCodes.contains(p.code);
    final fromTemplate = _templateCodes.contains(p.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: UxCard(
        onTap: () => setState(() {
          if (on) {
            _selectedCodes.remove(p.code);
          } else {
            _selectedCodes.add(p.code);
          }
        }),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: on,
              onChanged: (_) => setState(() {
                if (on) {
                  _selectedCodes.remove(p.code);
                } else {
                  _selectedCodes.add(p.code);
                }
              }),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.labelUrdu, style: AppTypography.bodyMedium),
                  Text(
                    '${p.categoryUrdu}${fromTemplate ? ' • ذمہ داری کا اختیار' : ''}',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepScope(_WizardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UxSectionTitle('یہ اختیارات کن لوگوں پر لاگو ہوں گے؟',
            icon: Icons.people_outline),
        const SizedBox(height: 12),
        RadioGroup<String>(
          groupValue: _scopeType,
          onChanged: (v) => setState(() => _scopeType = v ?? 'all'),
          child: Column(
            children: [
              _scopeOption(
                  'all', 'پورا مدرسہ', 'تمام طلبہ اور عملے پر لاگو ہوگا۔'),
              _scopeOption('department', 'صرف میرے شعبے کے افراد',
                  'فی الحال سرور یہ دائرہ الگ سے نافذ نہیں کرتا — یہ بھی پورے مدرسے پر لاگو ہوگا۔'),
              _scopeOption('classes', 'صرف میری مقرر کردہ جماعتیں',
                  'حاضری اور نتائج صرف ان جماعتوں کے لیے درج ہو سکیں گے۔'),
              _scopeOption('students', 'صرف میرے طلبہ',
                  'حاضری اور نتائج صرف ان طلبہ کے لیے درج ہو سکیں گے۔'),
            ],
          ),
        ),
        if (_scopeType == 'classes') ...[
          const SizedBox(height: 12),
          const UxSectionTitle('جماعتیں منتخب کریں',
              icon: Icons.class_outlined),
          const SizedBox(height: 8),
          if (data.classes.isEmpty)
            const Text('اس مدرسے میں ابھی کوئی جماعت درج نہیں۔'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in data.classes)
                FilterChip(
                  label: Text(c.name),
                  selected: _classIds.contains(c.id),
                  onSelected: (s) => setState(() {
                    if (s) {
                      _classIds.add(c.id);
                    } else {
                      _classIds.remove(c.id);
                    }
                  }),
                ),
            ],
          ),
        ],
        if (_scopeType == 'students') ...[
          const SizedBox(height: 12),
          const UxSectionTitle('طلبہ تلاش کریں', icon: Icons.search),
          const SizedBox(height: 8),
          TextField(
            controller: _studentSearch,
            decoration: InputDecoration(
              hintText: 'نام لکھ کر تلاش کریں',
              suffixIcon: _studentSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchStudents(),
                    ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _searchStudents(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _studentResults)
                FilterChip(
                  label: Text(s.name),
                  selected: _studentIds.contains(s.id),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _studentIds.add(s.id);
                    } else {
                      _studentIds.remove(s.id);
                    }
                  }),
                ),
            ],
          ),
          if (_studentIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${_studentIds.length} طالب علم منتخب',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.primary)),
            ),
        ],
      ],
    );
  }

  Widget _scopeOption(String value, String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: UxCard(
        onTap: () => setState(() => _scopeType = value),
        child: Row(
          children: [
            Radio<String>(value: value),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.titleSmall),
                  Text(hint,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchStudents() async {
    final q = _studentSearch.text.trim();
    if (q.isEmpty) return;
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return;
    setState(() => _studentSearching = true);
    try {
      final results =
          await ref.read(roleUxRepositoryProvider).searchStudents(tenantId, q);
      setState(() => _studentResults = results);
    } finally {
      if (mounted) setState(() => _studentSearching = false);
    }
  }

  Widget _stepSummary(_WizardData data) {
    final catalog = data.catalog;
    final grants = [
      for (final p in catalog)
        if (_selectedCodes.contains(p.code)) p,
    ];
    final exclusions = <String>{
      for (final code in _curatedCodes)
        if (!_selectedCodes.contains(code) && _exclusionSentences[code] != null)
          _exclusionSentences[code]!,
    }.toList();
    final role = data.roles.where((r) => r.key == _roleKey).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UxSectionTitle('خلاصہ', icon: Icons.summarize_outlined),
        const SizedBox(height: 12),
        if (!widget.isEdit) ...[
          UxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name.text.trim(), style: AppTypography.titleMedium),
                Text(_email.text.trim(),
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        UxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ذمہ داری: ${role?.displayUrdu ?? _roleKey ?? '—'}',
                  style: AppTypography.titleSmall),
              const SizedBox(height: 4),
              Text('دائرۂ کار: ${_scopeSummaryUrdu()}',
                  style: AppTypography.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const UxSectionTitle('اس صارف کو یہ اختیارات حاصل ہوں گے:',
            icon: Icons.check_circle_outline),
        const SizedBox(height: 8),
        if (grants.isEmpty)
          const Text('کوئی خاص اختیار منتخب نہیں — صرف بنیادی رسائی ہوگی۔'),
        for (final p in grants)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.check, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(p.labelUrdu, style: AppTypography.bodyMedium)),
              ],
            ),
          ),
        if (exclusions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const UxSectionTitle('اہم وضاحتیں', icon: Icons.info_outline),
                const SizedBox(height: 6),
                for (final e in exclusions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $e', style: AppTypography.bodySmall),
                  ),
              ],
            ),
          ),
        ],
        if (_savingError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_savingError!,
                style:
                    AppTypography.bodyMedium.copyWith(color: AppColors.error)),
          ),
        ],
      ],
    );
  }

  // ── navigation ──

  bool _canAdvance(_WizardData data) {
    switch (_step) {
      case 0:
        if (widget.isEdit) return true;
        return _formKey.currentState?.validate() ?? false;
      case 1:
        return _roleKey != null;
      case 3:
        if (_scopeType == 'classes') return _classIds.isNotEmpty;
        return true;
      default:
        return true;
    }
  }

  Widget _navBar(_WizardData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_step > 0)
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _step--;
                          _savingError = null;
                        }),
                child: const Text('پیچھے'),
              ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving
                  ? null
                  : () async {
                      if (_step < 4) {
                        if (_canAdvance(data)) {
                          setState(() {
                            _step++;
                            _savingError = null;
                          });
                        }
                      } else {
                        await _save();
                      }
                    },
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_step == 4 ? 'محفوظ کریں' : 'آگے'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_roleKey == null) return;
    setState(() {
      _saving = true;
      _savingError = null;
    });
    final controller = ref.read(roleUxControllerProvider.notifier);
    final scope = ScopeSelection(
      type: _scopeType,
      classIds: _classIds,
      studentIds: _studentIds,
    );
    // Only scoped codes (attendance/results) get scope rows; other grants
    // are enforced without a data dimension.
    final scopeCodes = _selectedCodes.intersection(ScopeSelection.scopedCodes);
    String? error;
    if (widget.isEdit) {
      final roles = await ref.read(tenantRolesUxProvider.future);
      final holders = {
        for (final r in roles)
          if (r.permissionCodes.contains('roles.assign')) r.key,
      };
      error = await controller.updateUserSetup(
        user: widget.user!,
        roleKey: _roleKey!,
        templateCodes: _templateCodes,
        selectedCodes: _selectedCodes,
        scopeCodes: scopeCodes,
        scope: scope,
        assignHolderKeys: holders,
      );
    } else {
      final res = await controller.createUserFull(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        roleKey: _roleKey!,
        templateCodes: _templateCodes,
        selectedCodes: _selectedCodes,
        scopeCodes: scopeCodes,
        scope: scope,
      );
      error = res.error;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _savingError = error);
    }
  }
}

class _WizardData {
  _WizardData({
    required this.roles,
    required this.catalog,
    required this.classes,
    required this.overrides,
  });

  final List<TenantRoleInfo> roles;
  final List<PermissionInfo> catalog;
  final List<ClassRef> classes;
  final Map<String, String> overrides;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
