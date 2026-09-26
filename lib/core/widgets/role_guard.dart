// ── Madrasa 360 — RoleGuard ──────────────────────────────────────────────────
// Hides [child] unless the user holds ANY of [roleKeys] in the ACTIVE tenant.
//
// UI-ONLY GATE (same caveat as PermissionGuard): Supabase RLS remains the
// real enforcement. Prefer PermissionGuard for feature gating —
// permission checks express *what the user may do*, while role keys express
// *who the user is*. This guard exists for the few places where the role
// itself is the concept (e.g. showing a role badge), never to protect data.
//
// Example:
//   RoleGuard(
//     roleKeys: const {'tenant_owner', 'tenant_admin'},
//     child: dangerZoneSection,
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/role_service.dart';

class RoleGuard extends ConsumerWidget {
  /// `tenant_memberships.role` keys — the child shows when the user holds
  /// ANY of these in the active tenant.
  final Set<String> roleKeys;

  /// Shown when a required role is held.
  final Widget child;

  /// Shown otherwise (defaults to nothing).
  final Widget? fallback;

  const RoleGuard({
    super.key,
    required this.roleKeys,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = ref.watch(activeRoleKeysProvider);
    if (held.any(roleKeys.contains)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
