/// ڈیٹا حدود — تنگ کرنے کی پالیسی (Phase 9)
///
/// Narrow-only grant policy for the Data Scopes manager: a granter can
/// never grant a scope wider than their own effective scope for that
/// permission area. Pure Dart (no imports at all) so it stays unit-
/// testable; the UI and [audit_urdu.dart] reuse the Urdu labels here.
///
/// Enforcement itself stays server-side: `permission_scopes` writes go
/// through RLS (`roles.assign`, migration 020) and `scope_allows()` is
/// the real gate. This policy is the client-side guardrail that refuses
/// over-wide grants *before* they are sent — and it fails closed: when
/// the granter's own scope cannot be determined, the grant is refused.

/// Scope type code → plain Urdu label (never shown as a raw code).
String scopeTypeUrdu(String type) {
  switch (type.trim()) {
    case 'all':
      return 'پورا مدرسہ';
    case 'department':
      return 'صرف شعبہ';
    case 'classes':
      return 'مقرر کردہ جماعتیں';
    case 'students':
      return 'مخصوص طلبہ';
    default:
      return 'پورا مدرسہ';
  }
}

/// Honest one-line hint per scope type, shown under the picker.
/// The department note matches the user wizard: the server does not
/// enforce it separately, so choosing it behaves like 'all'.
String scopeTypeHintUrdu(String type) {
  switch (type.trim()) {
    case 'all':
      return 'تمام طلبہ اور عملے پر لاگو ہوگا۔';
    case 'department':
      return 'فی الحال سرور یہ دائرہ الگ سے نافذ نہیں کرتا — '
          'یہ پورے مدرسے جیسا برتے گا۔';
    case 'classes':
      return 'حاضری اور نتائج صرف منتخب جماعتوں کے لیے درج ہو سکیں گے۔';
    case 'students':
      return 'حاضری اور نتائج صرف منتخب طلبہ کے لیے درج ہو سکیں گے۔';
    default:
      return 'تمام طلبہ اور عملے پر لاگو ہوگا۔';
  }
}

/// Short summary for list rows, e.g. "مقرر کردہ جماعتیں (۲ جماعتیں)".
/// Counts use plain digits, matching the rest of the app.
String scopeSummaryUrdu(
  String type, {
  int classCount = 0,
  int studentCount = 0,
}) {
  final t = type.trim();
  if (t == 'classes') {
    if (classCount <= 0) return 'مقرر کردہ جماعتیں (کوئی جماعت منتخب نہیں)';
    return 'مقرر کردہ جماعتیں ($classCount)';
  }
  if (t == 'students') {
    if (studentCount <= 0) return 'مخصوص طلبہ (کوئی طالب علم منتخب نہیں)';
    return 'مخصوص طلبہ ($studentCount)';
  }
  return scopeTypeUrdu(t);
}

/// Narrow-only grant validation.
///
/// [granterKnown] is false when the granter's own scope rows could not be
/// loaded — the grant is then refused (fail closed: no scope = no grant,
/// never a silent widen to "all").
///
/// A missing granter row for the permission area means "all" per the data
/// model (019 seeds rows only for narrowed users), so callers pass
/// `granterType: 'all'` with empty id sets in that case.
///
/// Returns null when the grant is allowed, otherwise a plain-Urdu refusal
/// that never leaks codes or server text.
class ScopePolicy {
  const ScopePolicy._();

  static String? validateGrant({
    required bool granterKnown,
    required String granterType,
    required Set<String> granterClassIds,
    required Set<String> granterStudentIds,
    required String requestedType,
    required Set<String> requestedClassIds,
    required Set<String> requestedStudentIds,
    required Set<String> requestedStudentClassIds,
  }) {
    if (!granterKnown) {
      return 'آپ کا اپنا دائرہ کار معلوم نہیں ہو سکا۔ '
          'حفاظتی طور پر کوئی تبدیلی محفوظ نہیں کی گئی — دوبارہ کوشش کریں۔';
    }

    final g = granterType.trim();
    final r = requestedType.trim();

    // Unrestricted granter may grant anything.
    if (g == 'all') return null;

    // 'all' and 'department' both behave as unrestricted server-side
    // (department is not enforced by 020), so a narrowed granter can
    // never grant them.
    if (r == 'all' || r == 'department') {
      return '«${scopeTypeUrdu(r)}» کا دائرہ آپ کے اپنے دائرہ کار سے وسیع ہے — '
          'تبدیلی محفوظ نہیں کی گئی۔';
    }

    // A department-scoped granter cannot be evaluated against classes or
    // students client-side: fail closed.
    if (g == 'department') {
      return 'آپ کا اپنا دائرہ کار شعبے تک محدود ہے — '
          'یہاں سے دائرہ کار تبدیل نہیں کیا جا سکتا۔';
    }

    switch (g) {
      case 'classes':
        switch (r) {
          case 'classes':
            if (requestedClassIds.isEmpty) {
              return 'کم از کم ایک جماعت منتخب کریں۔';
            }
            if (!granterClassIds.containsAll(requestedClassIds)) {
              return 'آپ صرف ان جماعتوں کا دائرہ دے سکتے ہیں '
                  'جو آپ کے اپنے دائرہ کار میں ہیں۔';
            }
            return null;
          case 'students':
            if (requestedStudentIds.isEmpty) {
              return 'کم از کم ایک طالب علم منتخب کریں۔';
            }
            if (!granterClassIds.containsAll(requestedStudentClassIds)) {
              return 'آپ صرف ان طلبہ کا دائرہ دے سکتے ہیں '
                  'جو آپ کی اپنی جماعتوں میں ہیں۔';
            }
            return null;
          default:
            return 'نامعلوم دائرہ کار — تبدیلی محفوظ نہیں کی گئی۔';
        }
      case 'students':
        switch (r) {
          case 'students':
            if (requestedStudentIds.isEmpty) {
              return 'کم از کم ایک طالب علم منتخب کریں۔';
            }
            if (!granterStudentIds.containsAll(requestedStudentIds)) {
              return 'آپ صرف ان طلبہ کا دائرہ دے سکتے ہیں '
                  'جو آپ کے اپنے دائرہ کار میں ہیں۔';
            }
            return null;
          case 'classes':
            return 'آپ کا اپنا دائرہ کار مخصوص طلبہ تک محدود ہے — '
                'جماعتوں کا دائرہ نہیں دیا جا سکتا۔';
          default:
            return 'نامعلوم دائرہ کار — تبدیلی محفوظ نہیں کی گئی۔';
        }
      default:
        return 'آپ کا اپنا دائرہ کار پہچانا نہیں گیا — '
            'حفاظتی طور پر تبدیلی محفوظ نہیں کی گئی۔';
    }
  }
}
