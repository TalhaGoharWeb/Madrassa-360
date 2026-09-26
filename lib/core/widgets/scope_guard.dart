// ── Madrasa 360 — ScopeGuard ─────────────────────────────────────────────────
// Hides [child] unless the user's DATA SCOPE for [permission] covers
// [classId] (when given).
//
// UI-ONLY GATE (same caveat as PermissionGuard): hiding a class from a
// list is a courtesy — `scope_allows()` in RLS is what actually rejects an
// out-of-scope write. While the scope is loading (or on error) the guard
// fails closed and hides the child.
//
// Example — a class-scoped teacher only sees the attendance button for
// their own classes:
//   ScopeGuard(
//     permission: AppPermissions.markAttendance,
//     classId: klass.id,
//     child: markAttendanceButton,
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/scope_service.dart';

class ScopeGuard extends ConsumerStatefulWidget {
  /// Canonical permission code whose scope is checked.
  final String permission;

  /// When set, the child shows only if the scope covers this class.
  /// When null, the child shows unless the scope is narrower than `all`
  /// (mirrors `scope_allows()` failing closed on an unverifiable target).
  final String? classId;

  /// Shown when the scope allows.
  final Widget child;

  /// Shown otherwise (defaults to nothing).
  final Widget? fallback;

  const ScopeGuard({
    super.key,
    required this.permission,
    this.classId,
    required this.child,
    this.fallback,
  });

  @override
  ConsumerState<ScopeGuard> createState() => _ScopeGuardState();
}

class _ScopeGuardState extends ConsumerState<ScopeGuard> {
  late Future<bool> _allowed;

  @override
  void initState() {
    super.initState();
    _allowed = _check();
  }

  @override
  void didUpdateWidget(covariant ScopeGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.permission != widget.permission ||
        oldWidget.classId != widget.classId) {
      _allowed = _check();
    }
  }

  Future<bool> _check() => ref.read(scopeServiceProvider).scopeAllows(
        widget.permission,
        classId: widget.classId,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _allowed,
      builder: (context, snapshot) {
        if (snapshot.data == true) return widget.child;
        return widget.fallback ?? const SizedBox.shrink();
      },
    );
  }
}
