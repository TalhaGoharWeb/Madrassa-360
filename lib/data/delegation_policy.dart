/// اختیار سونپنے کے خالص قواعد (Phase 8b)
/// Pure, unit-tested validation for delegation creation.
///
/// This is the CLIENT-SIDE ceiling pre-check (fast, honest UX): a user can
/// never be offered — let alone granted — a permission they do not
/// themselves hold. The server (`delegate_permission` RPC + the 019
/// `delegation_ceiling_check` trigger) is the real enforcement; this only
/// shapes what the UI allows.

import 'role_ux_repository.dart';

class DelegationPolicy {
  /// Returns a plain-Urdu refusal, or null when the request may proceed.
  ///
  /// [myCodes] is the delegator's own effective permission set — the
  /// ceiling no delegation may exceed. [now] is injected for tests.
  static String? validateCreate({
    required String? selfId,
    required String delegateeId,
    required Set<String> codes,
    required Set<String> myCodes,
    DateTime? expiresAt,
    required DateTime now,
  }) {
    if (selfId == null || selfId.isEmpty) {
      return 'لاگ اِن کی معلومات نہیں ملیں — دوبارہ لاگ اِن کریں۔';
    }
    if (delegateeId.isEmpty) {
      return 'پہلے کوئی صارف منتخب کریں۔';
    }
    if (delegateeId == selfId) {
      return 'آپ خود کو اختیار نہیں سونپ سکتے۔';
    }
    if (codes.isEmpty) {
      return 'کم از کم ایک اختیار منتخب کریں۔';
    }
    // The ceiling: every delegated code must be in the delegator's own
    // effective set (server re-checks this; delegations never chain).
    if (!myCodes.containsAll(codes)) {
      return 'یہ اختیار آپ کے پاس خود موجود نہیں — آپ صرف وہی اختیار '
          'سونپ سکتے ہیں جو آپ کو حاصل ہو۔';
    }
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      return 'میعاد کی تاریخ آج سے آگے کی ہونی چاہیے۔';
    }
    return null;
  }

  /// Filters the permission catalog down to what the delegator may
  /// actually delegate: their own effective codes. The picker UI only
  /// ever shows this subset, so an unheld permission cannot even be
  /// selected.
  static List<PermissionInfo> delegatableCatalog(
    List<PermissionInfo> catalog,
    Set<String> myCodes,
  ) {
    return catalog.where((p) => myCodes.contains(p.code)).toList();
  }
}
