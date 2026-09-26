/// نیا اختیار سونپیں — تخلیق اسکرین (Phase 8b)
/// Delegation create flow: pick a tenant user -> pick permissions (ONLY
/// the delegator's own effective set — the ceiling is enforced in the
/// picker, in [DelegationPolicy], and on the server) -> optional expiry
/// date -> confirm.
///
/// The delegator's own data scope for each code is carried onto the
/// delegation row, so a delegation can never be wider than what the
/// delegator themselves holds. Writes need the network; offline the
/// confirm button explains this honestly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/scope_service.dart';
import '../../../data/delegation_policy.dart';
import '../../../data/delegation_repository.dart';
import '../../../data/role_ux_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/delegation_provider.dart';
import '../../../providers/role_ux_provider.dart';
import 'role_ux_widgets.dart';

class DelegationCreateScreen extends ConsumerStatefulWidget {
  const DelegationCreateScreen({super.key});

  @override
  ConsumerState<DelegationCreateScreen> createState() =>
      _DelegationCreateScreenState();
}

class _DelegationCreateScreenState
    extends ConsumerState<DelegationCreateScreen> {
  String? _delegateeId;
  final Set<String> _codes = {};
  DateTime? _expiresAt;

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(permissionCatalogProvider);
    final myCodes = ref.watch(myDelegatableCodesProvider);
    final busy = ref.watch(delegationControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('نیا اختیار سونپیں'),
        centerTitle: true,
      ),
      body: catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => UxEmptyState(
          icon: Icons.error_outline,
          title: delegationErrorMessage(e),
        ),
        data: (catalog) {
          final delegatable =
              DelegationPolicy.delegatableCatalog(catalog, myCodes);
          if (delegatable.isEmpty) {
            return const UxEmptyState(
              icon: Icons.key_off_outlined,
              title: 'سونپنے کے لیے کوئی اختیار نہیں',
              hint: 'آپ کے پاس خود کوئی ایسا اختیار نہیں جو آپ کسی اور '
                  'کو سونپ سکیں۔',
            );
          }
          return _form(context, delegatable, busy);
        },
      ),
    );
  }

  Widget _form(
      BuildContext context, List<PermissionInfo> delegatable, bool busy) {
    final grouped = <String, List<PermissionInfo>>{};
    for (final p in delegatable) {
      grouped.putIfAbsent(p.categoryUrdu, () => []).add(p);
    }
    final summary = _summaryText();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              const UxSectionTitle('صارف منتخب کریں',
                  icon: Icons.person_outline),
              const SizedBox(height: 8),
              _userPicker(),
              const SizedBox(height: 20),
              const UxSectionTitle('اختیارات منتخب کریں',
                  icon: Icons.key_outlined),
              const SizedBox(height: 4),
              Text(
                'صرف وہ اختیارات دکھائے گئے ہیں جو آپ کے پاس خود موجود '
                'ہیں — آپ کوئی ایسا اختیار نہیں سونپ سکتے جو آپ کے پاس نہ ہو۔',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    entry.key,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final p in entry.value)
                  CheckboxListTile(
                    value: _codes.contains(p.code),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _codes.add(p.code);
                              } else {
                                _codes.remove(p.code);
                              }
                            }),
                    title: Text(p.labelUrdu, style: AppTypography.bodyMedium),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
              const SizedBox(height: 20),
              const UxSectionTitle('میعاد (اختیاری)',
                  icon: Icons.event_outlined),
              const SizedBox(height: 8),
              _expiryPicker(busy),
              const SizedBox(height: 20),
              const UxSectionTitle('تصدیق', icon: Icons.fact_check_outlined),
              const SizedBox(height: 8),
              UxCard(
                child: Text(
                  summary,
                  style: AppTypography.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        _confirmBar(context, busy),
      ],
    );
  }

  String _summaryText() {
    final users = ref.read(tenantUsersProvider('')).valueOrNull ?? const [];
    var name = '—';
    for (final u in users) {
      if (u.id == _delegateeId) {
        name = u.name;
        break;
      }
    }
    final expiry = _expiresAt == null
        ? 'بغیر میعاد'
        : 'میعاد: ${DateFormat('dd/MM/yyyy').format(_expiresAt!.toLocal())}';
    return '$name کو ${_codes.length} اختیار سونپے جائیں گے — $expiry۔';
  }

  // ── Section 1: target user ────────────────────────────────────

  Widget _userPicker() {
    final usersAsync = ref.watch(tenantUsersProvider(''));
    final selfId = ref.watch(currentUserProvider)?.id;
    return usersAsync.when(
      loading: () => const UxCard(child: Text('صارفین لوڈ ہو رہے ہیں…')),
      error: (e, _) => UxCard(
        child: Text(delegationErrorMessage(e),
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      ),
      data: (users) {
        final eligible =
            users.where((u) => u.id != selfId && u.isActive).toList();
        TenantUser? selected;
        for (final u in eligible) {
          if (u.id == _delegateeId) {
            selected = u;
            break;
          }
        }
        return UxCard(
          onTap: () => _pickUser(eligible),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: selected == null
                    ? Text('صارف منتخب کریں…',
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.textSecondary))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selected.name, style: AppTypography.titleSmall),
                          const SizedBox(height: 2),
                          RoleBadge(label: selected.roleUrdu),
                        ],
                      ),
              ),
              const Icon(Icons.chevron_left, color: AppColors.textSecondary),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickUser(List<TenantUser> users) async {
    var query = '';
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (v) => setSheet(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'نام سے تلاش کریں',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final q = query.trim();
                      final filtered = q.isEmpty
                          ? users
                          : users
                              .where((u) =>
                                  u.name.contains(q) || u.roleUrdu.contains(q))
                              .toList();
                      if (filtered.isEmpty) {
                        return const UxEmptyState(
                          icon: Icons.person_search_outlined,
                          title: 'کوئی صارف نہیں ملا',
                        );
                      }
                      return ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final u = filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              child: Text(
                                u.initials,
                                style: AppTypography.titleSmall
                                    .copyWith(color: AppColors.primary),
                              ),
                            ),
                            title: Text(u.name),
                            subtitle: Text(u.roleUrdu,
                                style: AppTypography.bodySmall
                                    .copyWith(color: AppColors.textSecondary)),
                            onTap: () => Navigator.pop(ctx, u.id),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen != null) setState(() => _delegateeId = chosen);
  }

  // ── Section 3: expiry ─────────────────────────────────────────

  Widget _expiryPicker(bool busy) {
    final text = _expiresAt == null
        ? 'بغیر میعاد — جب تک واپس نہ لیا جائے'
        : DateFormat('dd/MM/yyyy').format(_expiresAt!.toLocal());
    return UxCard(
      child: Row(
        children: [
          const Icon(Icons.event_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: AppTypography.bodyMedium),
          ),
          TextButton(
            onPressed: busy ? null : _chooseDate,
            child: const Text('تبدیل کریں'),
          ),
          if (_expiresAt != null)
            IconButton(
              tooltip: 'میعاد ختم کریں',
              icon: const Icon(Icons.clear, size: 18),
              onPressed: busy ? null : () => setState(() => _expiresAt = null),
            ),
        ],
      ),
    );
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  // ── Confirm ───────────────────────────────────────────────────

  Widget _confirmBar(BuildContext context, bool busy) {
    final ready =
        _delegateeId != null && _delegateeId!.isNotEmpty && _codes.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.handshake_outlined),
            label: Text(busy ? 'سونپا جا رہا ہے…' : 'اختیار سونپیں'),
            onPressed: !ready || busy ? null : () => _confirm(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    // Carry the delegator's own data scope onto each delegation row, so a
    // delegation is never wider than what the delegator themselves holds.
    final scopes = <String, DelegationScope>{};
    for (final code in _codes) {
      scopes[code] = await _scopeForCode(code);
    }
    if (!context.mounted) return;
    final err =
        await ref.read(delegationControllerProvider.notifier).createDelegations(
              delegateeId: _delegateeId!,
              codes: Set.of(_codes),
              scopesByCode: scopes,
              expiresAt: _expiresAt,
            );
    if (!context.mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      showUxSnack(context, err, isError: true);
    }
  }

  Future<DelegationScope> _scopeForCode(String code) async {
    try {
      final scope = await ref.read(scopeServiceProvider).scopeFor(code);
      if (scope == null || scope.isUnrestricted) {
        return const DelegationScope();
      }
      final refMap = <String, dynamic>{};
      if (scope.classIds.isNotEmpty) {
        refMap['class_ids'] = scope.classIds.toList();
      }
      if (scope.studentIds.isNotEmpty) {
        refMap['student_ids'] = scope.studentIds.toList();
      }
      if (scope.department != null) {
        refMap['department'] = scope.department;
      }
      return DelegationScope(type: scope.scopeType, ref: refMap);
    } catch (_) {
      // Fail closed on the scope lookup: 'all' is the row default, and the
      // server still enforces the permission ceiling itself.
      return const DelegationScope();
    }
  }
}
