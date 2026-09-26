// ── Madrasa 360 — PermissionGuard ────────────────────────────────────────────
// Hides [child] unless the signed-in user holds [permission] in the ACTIVE
// tenant.
//
// UI-ONLY GATE: this guard never grants access to anything. Supabase RLS is
// the real enforcement — a hidden button means "not shown to this user",
// not "this user cannot do it". Never rely on a guard to protect data;
// always rely on the server rejecting unauthorized calls.
//
// Example:
//   PermissionGuard(
//     permission: AppPermissions.collectFees,
//     child: ElevatedButton(...), // "فیس وصول کریں"
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';

class PermissionGuard extends ConsumerWidget {
  /// Canonical permission code, e.g. [AppPermissions.collectFees].
  final String permission;

  /// Shown when the permission is held.
  final Widget child;

  /// Shown when it is not (defaults to nothing).
  final Widget? fallback;

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(hasPermissionProvider(permission));
    if (allowed) return child;
    return fallback ?? const SizedBox.shrink();
  }
}
