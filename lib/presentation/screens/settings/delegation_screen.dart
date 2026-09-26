/// اختیار سونپنا — انتظام اسکرین (Phase 8b)
/// Delegation management for principals / role managers (`roles.assign`):
/// lists active delegations (who delegated what to whom, expiry), revokes
/// with confirmation, and routes to the create flow.
///
/// Reads go through RLS as the authenticated user; when offline the list
/// falls back to the last-known cache and the UI says so honestly.
/// Revocation is immediate: the row is deleted, so the delegatee's next
/// effective-permission load no longer includes the code.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../../data/delegation_repository.dart';
import '../../../providers/delegation_provider.dart';
import '../../../providers/role_ux_provider.dart';
import 'delegation_create_screen.dart';
import 'role_ux_widgets.dart';

class DelegationScreen extends ConsumerWidget {
  const DelegationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDelegate = ref.watch(roleServiceProvider).canManageRoles();
    if (!canDelegate) {
      return Scaffold(
        appBar: AppBar(title: const Text('اختیار سونپنا')),
        body: const UxEmptyState(
          icon: Icons.lock_outline,
          title: 'آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے',
          hint: 'اختیار سونپنے کے لیے آپ کے پاس متعلقہ اجازت ہونی ضروری ہے۔',
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('اختیار سونپنا'),
        centerTitle: true,
      ),
      body: const _DelegationList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DelegationCreateScreen()),
          );
          if (created == true && context.mounted) {
            showUxSnack(context, 'اختیار کامیابی سے سونپ دیا گیا');
          }
        },
        icon: const Icon(Icons.handshake_outlined),
        label: const Text('اختیار سونپیں'),
      ),
    );
  }
}

class _DelegationList extends ConsumerWidget {
  const _DelegationList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(delegationsProvider);
    return listAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => UxEmptyState(
        icon: Icons.error_outline,
        title: delegationErrorMessage(e),
        hint: 'تازہ کریں — سوائپ کریں یا واپس آ کر دوبارہ دیکھیں۔',
      ),
      data: (result) {
        final now = DateTime.now();
        final active = result.items.where((d) => d.isActiveAt(now)).toList()
          ..sort(_byExpiry);
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(delegationsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (result.fromCache) _offlineBanner(),
              if (active.isEmpty)
                const UxEmptyState(
                  icon: Icons.handshake_outlined,
                  title: 'ابھی کوئی اختیار نہیں سونپا گیا',
                  hint: 'نیچے والے بٹن سے کسی صارف کو عارضی اختیار سونپیں۔',
                )
              else
                for (final d in active) _DelegationCard(delegation: d),
            ],
          ),
        );
      },
    );
  }

  /// Expiring soon first; no-expiry rows last.
  int _byExpiry(DelegationInfo a, DelegationInfo b) {
    if (a.expiresAt == null && b.expiresAt == null) return 0;
    if (a.expiresAt == null) return 1;
    if (b.expiresAt == null) return -1;
    return a.expiresAt!.compareTo(b.expiresAt!);
  }

  Widget _offlineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'آف لائن — آخری محفوظ فہرست دکھائی جا رہی ہے',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DelegationCard extends ConsumerWidget {
  const _DelegationCard({required this.delegation});

  final DelegationInfo delegation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(permissionCatalogProvider);
    final usersAsync = ref.watch(tenantUsersProvider(''));
    final catalog = catalogAsync.valueOrNull ?? const [];
    var label = AppPermissions.urduLabelFor(delegation.permissionCode);
    for (final p in catalog) {
      if (p.code == delegation.permissionCode) {
        label = p.labelUrdu;
        break;
      }
    }
    final names = <String, String>{};
    final roles = <String, String>{};
    for (final u in usersAsync.valueOrNull ?? const []) {
      names[u.id] = u.name;
      roles[u.id] = u.roleUrdu;
    }
    final delegateeName = names[delegation.delegateeId] ?? 'نامعلوم صارف';
    final delegatorName = names[delegation.delegatorId] ?? 'نامعلوم صارف';
    final delegateeRole = roles[delegation.delegateeId];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: UxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    _initials(delegateeName),
                    style: AppTypography.titleSmall
                        .copyWith(color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(delegateeName, style: AppTypography.titleSmall),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (delegateeRole != null && delegateeRole.isNotEmpty)
                            RoleBadge(label: delegateeRole),
                          _expiryChip(),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'اختیار واپس لیں',
                  icon: const Icon(Icons.undo_outlined, color: AppColors.error),
                  onPressed: () => _revoke(context, ref, label),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.key_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label, style: AppTypography.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'سونپنے والا: $delegatorName',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expiryChip() {
    final expires = delegation.expiresAt;
    final text = expires == null
        ? 'بغیر میعاد'
        : 'میعاد: ${DateFormat('dd/MM/yyyy').format(expires.toLocal())}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String runes(String s) => String.fromCharCodes(s.runes.take(2));
    if (parts.length == 1) return runes(parts.first);
    return String.fromCharCodes(parts.first.runes.take(1)) +
        String.fromCharCodes(parts.last.runes.take(1));
  }

  Future<void> _revoke(
      BuildContext context, WidgetRef ref, String label) async {
    final ok = await confirmUxAction(
      context,
      title: 'اختیار واپس لیں',
      message: '"$label" کا اختیار فوری طور پر واپس لیا جائے گا — '
          'صارف یہ اختیار فوراً استعمال نہیں کر سکے گا۔',
      confirmLabel: 'جی ہاں، واپس لیں',
    );
    if (!ok || !context.mounted) return;
    final err = await ref
        .read(delegationControllerProvider.notifier)
        .revokeDelegation(delegation);
    if (!context.mounted) return;
    if (err == null) {
      showUxSnack(context, 'اختیار واپس لے لیا گیا');
    } else {
      showUxSnack(context, err, isError: true);
    }
  }
}
