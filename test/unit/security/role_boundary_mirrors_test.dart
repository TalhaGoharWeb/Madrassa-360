/// Role-boundary policy mirrors — deny-by-default contract tests.
///
/// These tests pin the INTENDED authorization policy as pure-Dart mirrors of
/// the SQL/Edge-Function enforcement the security audit requires
/// (SEC-C1, SEC-C4, SEC-C5, SEC-H6).
///
/// MIRROR 1 is kept byte-for-byte consistent with the landed implementation
/// `public.sync_required_permission(p_entity, p_op)` in
/// `supabase/migrations/032_sync_apply_permissions.sql` — the SQL migration
/// is the source of truth; this mirror exists so the policy table cannot
/// drift silently between the SQL layer and this test suite. If the
/// migration changes, update this mirror in the same commit.
///
/// MIRRORs 2–4 document the contract for fixes not yet landed as SQL
/// (platform_admins trigger, tenants column guard) or living in TypeScript
/// (manage-users). Their runnable-against-staging assertions are in
/// `test/db/*.sql`.
///
/// Convention: a `null` return means DENY (fail closed). A non-null return
/// is the required permission code / action allowance.

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// MIRROR 1 — sync_required_permission(p_entity, p_op)
// Source of truth: supabase/migrations/032_sync_apply_permissions.sql:34.
// Unknown entity or op → null (DENY); the RPC then returns
// ok:false + reason 'forbidden:unknown_entity_or_op'.
// ─────────────────────────────────────────────────────────────

/// Required permission code for a sync write, or null = DENY.
/// Mirrors 032 exactly (including its per-entity op folding).
String? syncRequiredPermission(String entity, String op) {
  switch (entity) {
    case 'darjas':
    case 'classes':
    case 'darja_sections':
      return 'academics.manage';
    case 'students':
      switch (op) {
        case 'insert':
          return 'students.create';
        case 'update':
          return 'students.update';
        case 'delete':
          return 'students.delete';
      }
    case 'staff':
      switch (op) {
        case 'insert':
          return 'staff.create';
        case 'update':
          return 'staff.update';
        case 'delete':
          return 'staff.delete';
      }
    case 'attendance':
      switch (op) {
        case 'insert':
          return 'attendance.mark';
        case 'update':
          return 'attendance.edit';
        case 'delete':
          return 'attendance.delete';
      }
    case 'fees':
      switch (op) {
        case 'insert':
          return 'fees.create';
        case 'update':
          return 'fees.collect';
        case 'delete':
          return 'fees.delete';
      }
    case 'exams':
      switch (op) {
        case 'insert':
          return 'exams.create';
        case 'update':
          return 'exams.update';
        case 'delete':
          return 'exams.delete';
      }
    case 'results':
      if (op == 'insert') return 'results.enter';
      if (op == 'update' || op == 'delete') return 'results.edit';
    case 'announcements':
      return 'announcements.send';
    case 'library_books':
    case 'book_issues':
      return 'library.manage';
    case 'finance_transactions':
    case 'transactions':
    case 'accounts':
    case 'expenses':
    case 'income':
      switch (op) {
        case 'insert':
          return 'finance.create';
        case 'update':
          return 'finance.update';
        case 'delete':
          return 'finance.delete';
      }
    case 'fee_structures':
    case 'fee_items':
      if (op == 'delete') return 'fees.delete';
      if (op == 'insert' || op == 'update') return 'fees.create';
    case 'invoices':
    case 'invoice_items':
      switch (op) {
        case 'insert':
          return 'fees.create';
        case 'update':
          return 'fees.collect';
        case 'delete':
          return 'fees.delete';
      }
    case 'payments':
    case 'payment_allocations':
      if (op == 'delete') return 'fees.delete';
      if (op == 'insert' || op == 'update') return 'fees.collect';
    case 'refunds':
      if (op == 'delete') return 'fees.delete';
      if (op == 'insert' || op == 'update') return 'fees.refund';
    case 'discounts':
    case 'scholarships':
      switch (op) {
        case 'insert':
          return 'fees.create';
        case 'update':
          return 'fees.collect';
        case 'delete':
          return 'fees.delete';
      }
  }
  return null;
}

/// The 26 entities whitelisted in the sync CASE (032: ~:210-238).
const syncWhitelistedEntities = <String>{
  'darjas',
  'classes',
  'students',
  'staff',
  'attendance',
  'fees',
  'exams',
  'results',
  'announcements',
  'darja_sections',
  'library_books',
  'book_issues',
  'finance_transactions',
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
};

// ─────────────────────────────────────────────────────────────
// MIRROR 2 — platform_admins trigger (SEC-C5, not yet landed)
// Planned BEFORE INSERT OR UPDATE OR DELETE trigger on
// public.platform_admins: only a current platform_owner may change a
// row's role to/from platform_owner or delete an owner row; the last
// platform_owner can never be deleted/demoted.
// Returns null = ALLOW, otherwise a denial reason.
// ─────────────────────────────────────────────────────────────

String? platformAdminsGuard({
  required String callerRole, // 'platform_owner' | 'platform_support'
  required String action, // 'insert' | 'update_role' | 'delete'
  required String targetRole, // role of the affected row
  required int ownerCount, // current number of platform_owner rows
  String? newRole, // for update_role
}) {
  if (callerRole != 'platform_owner') {
    return 'only platform_owner may modify platform_admins';
  }
  if (action == 'delete' && targetRole == 'platform_owner' && ownerCount <= 1) {
    return 'cannot delete the last platform_owner';
  }
  if (action == 'update_role' &&
      (targetRole == 'platform_owner' || newRole == 'platform_owner') &&
      ownerCount <= 1 &&
      newRole != 'platform_owner') {
    return 'cannot demote the last platform_owner';
  }
  return null;
}

// ─────────────────────────────────────────────────────────────
// MIRROR 3 — tenants column guard (SEC-H6, not yet landed)
// Planned BEFORE UPDATE trigger on public.tenants: holders of
// `settings.update` may write only the allow-listed branding/contact
// columns; platform-owned columns (status, suspension, expiry, identity,
// URLs) are platform-admin-only. Returns true = writable.
// ─────────────────────────────────────────────────────────────

/// Columns a tenant admin (settings.update) may write.
const tenantMemberWritableColumns = <String>{
  'name',
  'name_urdu',
  'phone',
  'email',
  'address',
  'address_urdu',
  'use_logo_on_reports',
};

/// Columns reserved for platform admins (suspension, billing, identity).
const tenantPlatformOnlyColumns = <String>{
  'status',
  'suspended',
  'expires_at',
  'tenant_code',
  'slug',
  'registration_number',
  'logo_url',
  'admin_message',
  'admin_message_urdu',
};

bool tenantColumnWritable(
    {required bool isPlatformAdmin, required String column}) {
  if (isPlatformAdmin) return true;
  if (tenantPlatformOnlyColumns.contains(column)) return false;
  return tenantMemberWritableColumns.contains(column);
}

// ─────────────────────────────────────────────────────────────
// MIRROR 4 — manage-users action → required right (SEC-C4)
// Mirrors: supabase/functions/manage-users/index.ts.
// update_user MUST require a write right (users.update), never the read
// set that callerCan("users") currently accepts.
// ─────────────────────────────────────────────────────────────

String manageUsersRequiredRight(String action) {
  switch (action) {
    case 'list_users':
    case 'safety_check':
      return 'users.view';
    case 'create_user':
      return 'users.create';
    case 'update_user':
      return 'users.update'; // SEC-C4: was gated on the read set ("users")
    case 'set_active':
      return 'users.deactivate';
    case 'delete_user':
      return 'users.deactivate'; // + legacy owner/admin or platform admin
    case 'assign_membership':
    case 'remove_membership':
      return 'roles.assign';
    case 'set_platform_role':
      return 'platform_owner';
    default:
      throw ArgumentError('unknown manage-users action: $action');
  }
}

void main() {
  group('MIRROR 1 — sync_required_permission deny-by-default (SEC-C1)', () {
    test('all 26 whitelisted entities are enumerated', () {
      expect(syncWhitelistedEntities, hasLength(26));
    });

    test('every whitelisted entity maps all three ops to a code', () {
      for (final entity in syncWhitelistedEntities) {
        for (final op in ['insert', 'update', 'delete']) {
          expect(
            syncRequiredPermission(entity, op),
            isNotNull,
            reason: '$entity/$op must map to a permission code',
          );
        }
      }
    });

    test('unknown entity → deny', () {
      expect(syncRequiredPermission('platform_admins', 'insert'), isNull);
      expect(syncRequiredPermission('tenant_memberships', 'update'), isNull);
      expect(syncRequiredPermission('tenants', 'delete'), isNull);
      expect(syncRequiredPermission('', 'insert'), isNull);
    });

    test('unknown op → deny', () {
      expect(syncRequiredPermission('students', 'upsert'), isNull);
      expect(syncRequiredPermission('students', ''), isNull);
      expect(syncRequiredPermission('students', 'SELECT'), isNull);
    });

    test('spot checks mirror the landed 032 map exactly', () {
      // Money paths
      expect(syncRequiredPermission('payments', 'insert'), 'fees.collect');
      expect(syncRequiredPermission('payments', 'delete'), 'fees.delete');
      expect(syncRequiredPermission('refunds', 'insert'), 'fees.refund');
      expect(syncRequiredPermission('invoices', 'update'), 'fees.collect');
      expect(syncRequiredPermission('discounts', 'insert'), 'fees.create');
      expect(syncRequiredPermission('expenses', 'insert'), 'finance.create');
      expect(syncRequiredPermission('fee_structures', 'update'), 'fees.create');
      expect(syncRequiredPermission('fee_structures', 'delete'), 'fees.delete');
      // Academic paths
      expect(syncRequiredPermission('results', 'insert'), 'results.enter');
      expect(syncRequiredPermission('results', 'update'), 'results.edit');
      expect(syncRequiredPermission('attendance', 'insert'), 'attendance.mark');
      expect(syncRequiredPermission('students', 'delete'), 'students.delete');
      // Announcements use the send code for every op
      expect(syncRequiredPermission('announcements', 'delete'),
          'announcements.send');
    });
  });

  group('MIRROR 2 — platform_admins trigger (SEC-C5)', () {
    test('support cannot self-promote to owner', () {
      expect(
        platformAdminsGuard(
          callerRole: 'platform_support',
          action: 'update_role',
          targetRole: 'platform_support',
          ownerCount: 2,
          newRole: 'platform_owner',
        ),
        isNotNull,
      );
    });

    test('support cannot delete an owner', () {
      expect(
        platformAdminsGuard(
          callerRole: 'platform_support',
          action: 'delete',
          targetRole: 'platform_owner',
          ownerCount: 2,
        ),
        isNotNull,
      );
    });

    test('cannot delete the last platform_owner', () {
      expect(
        platformAdminsGuard(
          callerRole: 'platform_owner',
          action: 'delete',
          targetRole: 'platform_owner',
          ownerCount: 1,
        ),
        isNotNull,
      );
    });

    test('cannot demote the last platform_owner', () {
      expect(
        platformAdminsGuard(
          callerRole: 'platform_owner',
          action: 'update_role',
          targetRole: 'platform_owner',
          ownerCount: 1,
          newRole: 'platform_support',
        ),
        isNotNull,
      );
    });

    test('owner can manage support rows and non-last owners', () {
      expect(
        platformAdminsGuard(
          callerRole: 'platform_owner',
          action: 'delete',
          targetRole: 'platform_support',
          ownerCount: 1,
        ),
        isNull,
      );
      expect(
        platformAdminsGuard(
          callerRole: 'platform_owner',
          action: 'insert',
          targetRole: 'platform_support',
          ownerCount: 1,
        ),
        isNull,
      );
    });
  });

  group('MIRROR 3 — tenants column guard (SEC-H6)', () {
    test('tenant admin cannot touch suspension/billing/identity columns', () {
      for (final col in tenantPlatformOnlyColumns) {
        expect(
          tenantColumnWritable(isPlatformAdmin: false, column: col),
          isFalse,
          reason: 'tenant admin must not write $col',
        );
      }
    });

    test('tenant admin can write branding/contact columns', () {
      for (final col in tenantMemberWritableColumns) {
        expect(
          tenantColumnWritable(isPlatformAdmin: false, column: col),
          isTrue,
          reason: 'tenant admin should write $col',
        );
      }
    });

    test('unknown columns are denied for tenant admins', () {
      expect(
        tenantColumnWritable(isPlatformAdmin: false, column: 'deleted_at'),
        isFalse,
      );
    });

    test('platform admin bypasses the guard', () {
      expect(
        tenantColumnWritable(isPlatformAdmin: true, column: 'suspended'),
        isTrue,
      );
    });
  });

  group('MIRROR 4 — manage-users required rights (SEC-C4)', () {
    test('update_user requires users.update, never the read set', () {
      expect(manageUsersRequiredRight('update_user'), 'users.update');
      expect(manageUsersRequiredRight('update_user'), isNot('users.view'));
    });

    test('read actions stay on users.view', () {
      expect(manageUsersRequiredRight('list_users'), 'users.view');
      expect(manageUsersRequiredRight('safety_check'), 'users.view');
    });

    test('destructive actions need deactivate/owner rights', () {
      expect(manageUsersRequiredRight('set_active'), 'users.deactivate');
      expect(manageUsersRequiredRight('delete_user'), 'users.deactivate');
      expect(
        manageUsersRequiredRight('set_platform_role'),
        'platform_owner',
      );
    });

    test('unknown action throws (fail closed, no default-allow)', () {
      expect(
          () => manageUsersRequiredRight('promote_self'), throwsArgumentError);
    });
  });
}
