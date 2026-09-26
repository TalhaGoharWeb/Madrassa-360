/// آڈٹ لاگز — انسانی اردو
///
/// Central human-Urdu rendering for `audit_logs` rows: "who did what to
/// what, when" in plain Urdu. Pure Dart (no Flutter import) so it stays
/// unit-testable.
///
/// Action-code inventory (grep-verified 2026-09-26):
/// * Edge functions: `tenant.provisioned`, `tenant.suspend` | `reactivate` |
///   `archive`, `tenant.export`, `manage-users.<create_user|update_user|
///   set_active|delete_user|assign_membership|remove_membership|
///   safety_check|set_platform_role>`
/// * Finance triggers (014): `INSERT|UPDATE|DELETE_<table>` for 13 tables
/// * Role/UX triggers (019): `<table>.created|updated|deleted` for 6 tables
///
/// Unknown codes NEVER render as raw codes: [auditMessageUrdu] falls back
/// to a clean generic Urdu sentence, and [auditActionLabelUrdu] falls back
/// to «دیگر عمل».

// ── Asia/Karachi time ────────────────────────────────────────────────
// Pakistan observes no daylight saving: UTC+5 year-round.

/// Convert any instant to Asia/Karachi wall time (UTC+5, no DST).
DateTime toKarachiTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 5));

const _urduMonths = [
  '',
  'جنوری',
  'فروری',
  'مارچ',
  'اپریل',
  'مئی',
  'جون',
  'جولائی',
  'اگست',
  'ستمبر',
  'اکتوبر',
  'نومبر',
  'دسمبر'
];

/// "26 ستمبر 2026، دوپہر 2:19" — timestamp in Asia/Karachi, Urdu phrasing.
String formatAuditDateUrdu(DateTime instant) {
  final k = toKarachiTime(instant);
  final String period;
  if (k.hour < 5) {
    period = 'رات';
  } else if (k.hour < 12) {
    period = 'صبح';
  } else if (k.hour < 17) {
    period = 'دوپہر';
  } else if (k.hour < 20) {
    period = 'شام';
  } else {
    period = 'رات';
  }
  final h12 = k.hour % 12 == 0 ? 12 : k.hour % 12;
  final mm = k.minute.toString().padLeft(2, '0');
  return '${k.day} ${_urduMonths[k.month]} ${k.year}، $period $h12:$mm';
}

/// Short day label for filter chips: "26 ستمبر 2026".
String formatAuditDayUrdu(DateTime day) {
  final k = toKarachiTime(DateTime.utc(day.year, day.month, day.day));
  return '${k.day} ${_urduMonths[k.month]} ${k.year}';
}

/// UTC instant of midnight starting [karachiDay] in Asia/Karachi.
/// Used for date-range query bounds so a selected calendar day matches
/// what the viewer saw in Karachi wall time.
DateTime karachiDayStartUtc(DateTime karachiDay) =>
    DateTime.utc(karachiDay.year, karachiDay.month, karachiDay.day)
        .subtract(const Duration(hours: 5));

// ── Entities & roles ───────────────────────────────────────────────

const _entityUrdu = <String, String>{
  'tenants': 'مدرسہ',
  'auth_user': 'صارف',
  'user': 'صارف',
  'tenant_membership': 'رکنیت',
  'tenant_memberships': 'رکنیت',
  'platform_admin': 'پلیٹ فارم منتظم',
  'accounts': 'کھاتہ',
  'fee_structures': 'فیس اسٹرکچر',
  'fee_items': 'فیس آئٹم',
  'invoices': 'انوائس',
  'invoice_items': 'انوائس آئٹم',
  'payments': 'ادائیگی',
  'payment_allocations': 'ادائیگی کی تقسیم',
  'refunds': 'رقم کی واپسی',
  'discounts': 'رعایت',
  'scholarships': 'اسکالرشپ',
  'expenses': 'اخراجات',
  'income': 'آمدنی',
  'transactions': 'لین دین',
  'tenant_roles': 'کردار',
  'tenant_role_permissions': 'کردار کی اجازت',
  'user_permissions': 'صارف کی اجازت',
  'permission_delegations': 'اجازت کی منتقلی',
  'permission_scopes': 'اجازت کا دائرہ کار',
};

/// Table/entity key → plain Urdu name. Unknown entities fall back to a
/// prettified key (never shown as a raw code in the main message — the
/// message builder only uses this inside a full sentence).
String entityUrdu(String? entity) {
  if (entity == null || entity.trim().isEmpty) return '';
  return _entityUrdu[entity.trim()] ?? _prettifyKey(entity.trim());
}

String _prettifyKey(String key) => key.replaceAll('_', ' ').trim();

const _roleUrdu = <String, String>{
  'tenant_owner': 'مالک',
  'tenant_admin': 'ناظم اعلیٰ',
  'platform_owner': 'پلیٹ فارم مالک',
  'platform_support': 'پلیٹ فارم معاونت',
  'mohtamim': 'مہتمم',
  'naib_mohtamim': 'نائب مہتمم',
  'nazim_aala': 'ناظم اعلیٰ',
  'nazim_taleem': 'ناظم تعلیم',
  'nazim_intizamia': 'ناظم انتظامیہ',
  'nazim_maliyat': 'ناظم مالیات',
  'daftar_dar': 'دفتر دار',
  'ustad': 'استاد',
  'ustad_hifz': 'مدرس حفظ',
  'nazim_hifz': 'ناظم حفظ',
  'nazim_darul_iqama': 'ناظم دارالاقامہ',
  'warden': 'وارڈن',
  'mumtahin': 'ممتحن',
  'store_incharge': 'اسٹور انچارج',
  'hr_incharge': 'عملہ انچارج',
  'principal': 'پرنسپل',
  'accountant': 'محاسب',
  'teacher': 'استاد',
  'librarian': 'لائبریرین',
  'hostel_manager': 'ہاسٹل مینیجر',
  'staff': 'عملہ',
  'parent': 'والدین',
  'student': 'طالب علم',
};

/// Role key → Urdu. Unknown keys are prettified, never left raw where a
/// sentence is built (the caller always embeds the result in prose).
String roleKeyUrdu(String? key) {
  if (key == null || key.trim().isEmpty) return '';
  return _roleUrdu[key.trim()] ?? _prettifyKey(key.trim());
}

// ── Action inventory ───────────────────────────────────────────────

const _financeTables = [
  'accounts',
  'fee_structures',
  'fee_items',
  'invoices',
  'invoice_items',
  'payments',
  'payment_allocations',
  'refunds',
  'discounts',
  'scholarships',
  'expenses',
  'income',
  'transactions',
];

const _roleTables = [
  'tenant_memberships',
  'tenant_roles',
  'tenant_role_permissions',
  'user_permissions',
  'permission_delegations',
  'permission_scopes',
];

const _edgeActions = [
  'tenant.provisioned',
  'tenant.suspend',
  'tenant.reactivate',
  'tenant.archive',
  'tenant.export',
  'manage-users.create_user',
  'manage-users.update_user',
  'manage-users.set_active',
  'manage-users.delete_user',
  'manage-users.assign_membership',
  'manage-users.remove_membership',
  'manage-users.safety_check',
  'manage-users.set_platform_role',
];

/// Every action code the codebase can write (70 codes). Tests assert each
/// one renders without leaking the raw code.
final Set<String> knownAuditActions = {
  ..._edgeActions,
  for (final t in _financeTables) ...['INSERT_$t', 'UPDATE_$t', 'DELETE_$t'],
  for (final t in _roleTables) ...['$t.created', '$t.updated', '$t.deleted'],
};

bool isKnownAuditAction(String action) =>
    knownAuditActions.contains(action.trim());

// ── Main message mapper ────────────────────────────────────────────

String _q(String s) => s.isEmpty ? '' : '«$s»';

/// Build the "who did what to what" sentence.
///
/// [actorName] is the human name of `user_id` (resolved via profiles;
/// null when unknown — the sentence then uses the passive voice).
/// [tenantName], [entity], [oldData], [newData], [metadata] feed the
/// target description. Never returns the raw action code.
String auditMessageUrdu({
  required String action,
  String? actorName,
  String? tenantName,
  String? entity,
  String? entityId,
  Map<String, dynamic>? oldData,
  Map<String, dynamic>? newData,
  Map<String, dynamic>? metadata,
}) {
  final a = action.trim();
  final actor = (actorName ?? '').trim();
  final hasActor = actor.isNotEmpty;
  final data = newData ?? oldData ?? const <String, dynamic>{};

  // "$actor نے <target> <verb>" when the actor is known, otherwise the
  // passive "<target> <passiveVerb>".
  String say(String verb, String passiveVerb, [String target = '']) {
    final t = target.trim();
    if (hasActor) {
      return t.isEmpty ? '$actor نے $verb' : '$actor نے $t $verb';
    }
    return t.isEmpty ? passiveVerb : '$t $passiveVerb';
  }

  final tenantQ = _q((tenantName ?? '').trim());

  switch (a) {
    case 'tenant.provisioned':
      final name = _q((data['name'] as String? ?? '').trim());
      return say('قائم کیا', 'قائم کیا گیا',
          name.isEmpty ? 'نیا مدرسہ' : 'مدرسہ $name');
    case 'tenant.suspend':
      return say('معطل کیا', 'معطل کیا گیا', 'مدرسہ $tenantQ');
    case 'tenant.reactivate':
      return say('بحال کیا', 'بحال کیا گیا', 'مدرسہ $tenantQ');
    case 'tenant.archive':
      return say('آرکائیو کیا', 'آرکائیو کیا گیا', 'مدرسہ $tenantQ');
    case 'tenant.export':
      return say(
          'کا ڈیٹا ایکسپورٹ کیا', 'کا ڈیٹا ایکسپورٹ کیا گیا', 'مدرسہ $tenantQ');
    case 'manage-users.create_user':
      return say('صارف اکاؤنٹ بنایا', 'صارف اکاؤنٹ بنایا گیا',
          _q((data['email'] as String? ?? '').trim()));
    case 'manage-users.update_user':
      return say('صارف اکاؤنٹ اپ ڈیٹ کیا', 'صارف اکاؤنٹ اپ ڈیٹ کیا گیا',
          _q((data['email'] as String? ?? '').trim()));
    case 'manage-users.set_active':
      final active = data['active'] == true;
      return say(active ? 'صارف اکاؤنٹ فعال کیا' : 'صارف اکاؤنٹ غیر فعال کیا',
          active ? 'صارف اکاؤنٹ فعال کیا گیا' : 'صارف اکاؤنٹ غیر فعال کیا گیا');
    case 'manage-users.delete_user':
      return say('صارف اکاؤنٹ حذف کیا', 'صارف اکاؤنٹ حذف کیا گیا');
    case 'manage-users.assign_membership':
      final role = roleKeyUrdu(data['role'] as String?);
      final target = role.isEmpty
          ? 'صارف کو مدرسے میں شامل کیا'
          : 'صارف کو «$role» کے طور پر شامل کیا';
      final passiveTarget = role.isEmpty
          ? 'صارف کو مدرسے میں شامل کیا گیا'
          : 'صارف کو «$role» کے طور پر شامل کیا گیا';
      return hasActor ? '$actor نے $target' : passiveTarget;
    case 'manage-users.remove_membership':
      return say('کی رکنیت ختم کی', 'کی رکنیت ختم کی گئی', 'صارف');
    case 'manage-users.safety_check':
      return say('حفاظتی جانچ کی', 'حفاظتی جانچ کی گئی');
    case 'manage-users.set_platform_role':
      final role = roleKeyUrdu(data['role'] as String?);
      return say('پلیٹ فارم کردار ${_q(role)} مقرر کیا',
          'پلیٹ فارم کردار ${_q(role)} مقرر کیا گیا');
  }

  // Finance triggers: INSERT|UPDATE|DELETE_<table>.
  final finance = RegExp(r'^(INSERT|UPDATE|DELETE)_([a-z_]+)$').firstMatch(a);
  if (finance != null) {
    final op = finance.group(1)!;
    final table = finance.group(2)!;
    final ent = entityUrdu(table.isEmpty ? entity : table);
    final hint = _q((_financeHint(table, data)).trim());
    final target = hint.isEmpty ? ent : '$ent $hint';
    switch (op) {
      case 'INSERT':
        return say('شامل کیا', 'شامل کیا گیا', target);
      case 'UPDATE':
        return say('اپ ڈیٹ کیا', 'اپ ڈیٹ کیا گیا', target);
      default:
        return say('حذف کیا', 'حذف کیا گیا', target);
    }
  }

  // Role/UX triggers: <table>.created|updated|deleted.
  final role = RegExp(r'^([a-z_]+)\.(created|updated|deleted)$').firstMatch(a);
  if (role != null) {
    final table = role.group(1)!;
    final suffix = role.group(2)!;
    final ent = entityUrdu(table.isEmpty ? entity : table);
    if (table == 'tenant_memberships') {
      switch (suffix) {
        case 'created':
          return say('کو رکنیت دی', 'کو رکنیت دی گئی', 'صارف');
        case 'updated':
          return say('کی رکنیت اپ ڈیٹ کی', 'کی رکنیت اپ ڈیٹ کی گئی', 'صارف');
        default:
          return say('کی رکنیت ختم کی', 'کی رکنیت ختم کی گئی', 'صارف');
      }
    }
    switch (suffix) {
      case 'created':
        return say('شامل کیا', 'شامل کیا گیا', ent);
      case 'updated':
        return say('اپ ڈیٹ کیا', 'اپ ڈیٹ کیا گیا', ent);
      default:
        return say('حذف کیا', 'حذف کیا گیا', ent);
    }
  }

  // Fallback: clean generic sentence — the raw code never leaks.
  final e = entityUrdu(entity);
  if (hasActor) {
    return e.isEmpty ? '$actor نے ایک عمل کیا' : '$actor نے $e پر عمل کیا';
  }
  return e.isEmpty ? 'ایک عمل کیا گیا' : '$e پر عمل کیا گیا';
}

/// Readable identifier for finance rows: invoice / receipt numbers, names.
String _financeHint(String table, Map<String, dynamic> data) {
  String s(String key) => (data[key] as String? ?? '').trim();
  switch (table) {
    case 'invoices':
      return s('invoice_number');
    case 'payments':
    case 'income':
      return s('receipt_number');
    case 'accounts':
    case 'fee_structures':
      return s('name');
    default:
      final name = s('name');
      return name.isEmpty ? s('title') : name;
  }
}

// ── Short action labels (filter dropdowns) ──────────────────────────

const _edgeActionLabels = <String, String>{
  'tenant.provisioned': 'مدرسہ قائم',
  'tenant.suspend': 'مدرسہ معطل',
  'tenant.reactivate': 'مدرسہ بحال',
  'tenant.archive': 'مدرسہ آرکائیو',
  'tenant.export': 'ڈیٹا ایکسپورٹ',
  'manage-users.create_user': 'صارف بنایا',
  'manage-users.update_user': 'صارف اپ ڈیٹ',
  'manage-users.set_active': 'صارف فعال/غیر فعال',
  'manage-users.delete_user': 'صارف حذف',
  'manage-users.assign_membership': 'رکنیت دی',
  'manage-users.remove_membership': 'رکنیت ختم',
  'manage-users.safety_check': 'حفاظتی جانچ',
  'manage-users.set_platform_role': 'پلیٹ فارم کردار',
};

/// Short Urdu label for an action code (filter chips / dropdowns).
/// Never returns the raw code.
String auditActionLabelUrdu(String action) {
  final a = action.trim();
  final edge = _edgeActionLabels[a];
  if (edge != null) return edge;
  final finance = RegExp(r'^(INSERT|UPDATE|DELETE)_([a-z_]+)$').firstMatch(a);
  if (finance != null) {
    final op = finance.group(1)!;
    final ent = entityUrdu(finance.group(2));
    final opUrdu = op == 'INSERT'
        ? 'شامل'
        : op == 'UPDATE'
            ? 'اپ ڈیٹ'
            : 'حذف';
    return '$ent $opUrdu';
  }
  final role = RegExp(r'^([a-z_]+)\.(created|updated|deleted)$').firstMatch(a);
  if (role != null) {
    final ent = entityUrdu(role.group(1));
    final suffix = role.group(2)!;
    final sUrdu = suffix == 'created'
        ? 'شامل'
        : suffix == 'updated'
            ? 'اپ ڈیٹ'
            : 'حذف';
    return '$ent $sUrdu';
  }
  return 'دیگر عمل';
}

// ── Before/after diffs ─────────────────────────────────────────────

const _fieldUrdu = <String, String>{
  'name': 'نام',
  'email': 'ای میل',
  'phone': 'فون',
  'status': 'حیثیت',
  'role': 'کردار',
  'is_active': 'فعال',
  'active': 'فعال',
  'amount': 'رقم',
  'total': 'کل رقم',
  'paid_amount': 'ادا شدہ رقم',
  'balance': 'بقایا',
  'invoice_number': 'انوائس نمبر',
  'receipt_number': 'رسید نمبر',
  'tenant_name': 'مدرسہ',
  'tenant_code': 'مدرسہ کوڈ',
  'reason': 'وجہ',
  'title': 'عنوان',
  'description': 'تفصیل',
  'display_urdu': 'اردو نام',
  'permission_id': 'اجازت',
  'user_id': 'صارف',
  'plan_name': 'پلان',
  'enabled_modules': 'فعال ماڈیولز',
  'admin_email': 'منتظم ای میل',
  'discount_percent': 'رعایت (%)',
  'due_date': 'واجب الادا تاریخ',
  'entry_date': 'تاریخ',
  'kind': 'قسم',
};

/// Field key → Urdu label. Unknown keys are prettified, never raw JSON.
String fieldLabelUrdu(String field) =>
    _fieldUrdu[field.trim()] ?? _prettifyKey(field);

/// Keys that add noise to a before/after view (surrogate ids, timestamps).
const _diffSkipKeys = {'id', 'tenant_id', 'created_at', 'updated_at'};

String _valueText(Object? v) {
  if (v == null) return '—';
  if (v is bool) return v ? 'ہاں' : 'نہیں';
  if (v is num) return v.toString();
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return '—';
    // ISO instant → Karachi Urdu date.
    final dt = DateTime.tryParse(t);
    if (dt != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) {
      return formatAuditDateUrdu(dt);
    }
    return t;
  }
  if (v is List) {
    if (v.isEmpty) return '—';
    final items = v.take(3).map(_valueText).join('، ');
    return v.length > 3 ? '$items وغیرہ (${v.length})' : items;
  }
  if (v is Map) {
    if (v.isEmpty) return '—';
    return '${v.length} خانے';
  }
  return v.toString();
}

/// One changed field between old_data and new_data.
class AuditFieldDiff {
  const AuditFieldDiff({
    required this.field,
    required this.labelUrdu,
    required this.oldText,
    required this.newText,
  });

  final String field;
  final String labelUrdu;
  final String oldText;
  final String newText;

  bool get isInsert => oldText == '—';
  bool get isDelete => newText == '—';
}

/// Changed fields only (unchanged and noisy keys skipped), capped at
/// [maxFields]. Readable «پرانی قدر ← نئی قدر» rows, never raw JSON.
List<AuditFieldDiff> auditFieldDiffs(
  Map<String, dynamic>? oldData,
  Map<String, dynamic>? newData, {
  int maxFields = 8,
}) {
  final oldM = oldData ?? const <String, dynamic>{};
  final newM = newData ?? const <String, dynamic>{};
  final keys = <String>{...oldM.keys, ...newM.keys}..removeAll(_diffSkipKeys);
  final diffs = <AuditFieldDiff>[];
  for (final k in keys) {
    final o = _valueText(oldM[k]);
    final n = _valueText(newM[k]);
    if (o == n) continue;
    diffs.add(AuditFieldDiff(
      field: k,
      labelUrdu: fieldLabelUrdu(k),
      oldText: o,
      newText: n,
    ));
    if (diffs.length >= maxFields) break;
  }
  return diffs;
}

// ── Query filter params (unit-testable) ─────────────────────────────

/// Pure mapping from screen filter state to audit_logs query constraints.
/// The tenant constraint is always carried verbatim when set — tenant
/// isolation itself is enforced server-side by RLS; this helper only
/// guarantees the UI never drops or alters it.
Map<String, String> auditFilterParams({
  String? tenantId,
  String? action,
  String? actorId,
  DateTime? fromDay, // Karachi calendar day (inclusive)
  DateTime? toDay, // Karachi calendar day (inclusive)
}) {
  final p = <String, String>{};
  if (tenantId != null && tenantId.isNotEmpty) p['tenant_id'] = tenantId;
  if (action != null && action.isNotEmpty) p['action'] = action;
  if (actorId != null && actorId.isNotEmpty) p['user_id'] = actorId;
  if (fromDay != null) {
    p['created_from'] = karachiDayStartUtc(fromDay).toIso8601String();
  }
  if (toDay != null) {
    p['created_to'] = karachiDayStartUtc(
      toDay.add(const Duration(days: 1)),
    ).toIso8601String();
  }
  return p;
}
