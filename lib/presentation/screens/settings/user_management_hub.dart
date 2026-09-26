/// صارفین اور ذمہ داریاں — مرکزی اسکرین (Phase 8a)
/// 8a user-management hub: tabs for `صارفین` and `ذمہ داریاں`.
///
/// Permission-gated: the settings entry only routes here when effective
/// `users.view` is granted; `roles.assign` additionally gates the bulk
/// role-change action. The detail FAB routes to the wizard.
///
/// Write paths: assign_tenant_role / set_active via [RoleUxController];
/// roles tab is read-only preview (full editing ships in 8b).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../../data/role_ux_repository.dart';
import '../../../providers/role_ux_provider.dart';
import 'role_ux_widgets.dart';
import 'user_detail_screen.dart';
import 'user_wizard_screen.dart';

class UserManagementHubScreen extends ConsumerStatefulWidget {
  const UserManagementHubScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<UserManagementHubScreen> createState() =>
      _UserManagementHubScreenState();
}

class _UserManagementHubScreenState
    extends ConsumerState<UserManagementHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(roleServiceProvider).canManageUsers();
    if (!canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('صارفین اور ذمہ داریاں')),
        body: const UxEmptyState(
          icon: Icons.lock_outline,
          title: 'آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے',
          hint: 'صارفین کی فہرست دیکھنے کے لیے آپ کے پاس اختیار ہونا ضروری ہے۔',
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('صارفین اور ذمہ داریاں'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'صارفین', icon: Icon(Icons.people_outline)),
            Tab(text: 'ذمہ داریاں', icon: Icon(Icons.badge_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _UsersTab(
            search: _search,
            onSearch: (v) => setState(() => _search = v),
          ),
          const _RolesTab(),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => _tabs.index == 0
            ? FloatingActionButton.extended(
                onPressed: () async {
                  final created = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserWizardScreen()),
                  );
                  if (created == true && context.mounted) {
                    showUxSnack(context, 'نیا صارف کامیابی سے بن گیا');
                  }
                },
                icon: const Icon(Icons.person_add_alt),
                label: const Text('نیا صارف'),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

final _canManageUsersProvider = FutureProvider<bool>((ref) async {
  return RoleService.canManageUsers();
});

// ─────────────────────────────────────────────────────────────
// Users tab
// ─────────────────────────────────────────────────────────────

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab({required this.search, required this.onSearch});

  final String search;
  final ValueChanged<String> onSearch;

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final Set<String> _selected = {};
  bool _selectionMode = false;

  void _toggleSelect(TenantUser u) {
    setState(() {
      if (_selected.contains(u.id)) {
        _selected.remove(u.id);
      } else {
        _selected.add(u.id);
      }
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(tenantUsersProvider(widget.search));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: widget.onSearch,
                  decoration: InputDecoration(
                    hintText: 'نام یا ذمہ داری سے تلاش کریں',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _selectionMode ? 'ختم کریں' : 'منتخب کریں',
                icon: Icon(
                    _selectionMode ? Icons.close : Icons.checklist_outlined),
                onPressed: () => setState(() {
                  _selectionMode = !_selectionMode;
                  if (!_selectionMode) _selected.clear();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => UxEmptyState(
              icon: Icons.error_outline,
              title: roleUxErrorMessage(e),
              hint: 'تازہ کریں — سوائپ کریں یا واپس آ کر دوبارہ دیکھیں۔',
            ),
            data: (users) {
              if (users.isEmpty) {
                return UxEmptyState(
                  icon: Icons.people_outline,
                  title: widget.search.isEmpty
                      ? 'ابھی کوئی صارف درج نہیں'
                      : 'کوئی صارف نہیں ملا',
                  hint: widget.search.isEmpty
                      ? 'اوپر والے بٹن سے نیا صارف بنائیں۔'
                      : 'تلاش کے الفاظ بدل کر دیکھیں۔',
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(tenantUsersProvider);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _userTile(users[i]),
                ),
              );
            },
          ),
        ),
        if (_selectionMode && _selected.isNotEmpty) _bulkBar(),
      ],
    );
  }

  Widget _userTile(TenantUser u) {
    final selected = _selected.contains(u.id);
    final roleLabel =
        ref.watch(_roleUrduProvider).valueOrNull?[u.roleKey] ?? u.roleKey;
    return UxCard(
      onTap: _selectionMode
          ? () => _toggleSelect(u)
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UserDetailScreen(user: u)),
              ),
      child: Row(
        children: [
          if (_selectionMode)
            Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelect(u),
            )
          else
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                u.initials,
                style:
                    AppTypography.titleSmall.copyWith(color: AppColors.primary),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.name, style: AppTypography.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    RoleBadge(label: roleLabel),
                    ActiveBadge(active: u.isActive),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _bulkBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text('${_selected.length} منتخب', style: AppTypography.titleSmall),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('ذمہ داری تبدیل کریں'),
              onPressed: () => _bulkRoleChange(),
            ),
            PopupMenuButton<bool>(
              icon: const Icon(Icons.power_settings_new),
              tooltip: 'فعال / غیر فعال',
              onSelected: (active) => _bulkSetActive(active),
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: true, child: Text('فعال کریں')),
                PopupMenuItem(value: false, child: Text('غیر فعال کریں')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkSetActive(bool active) async {
    final users = ref
            .read(tenantUsersProvider(widget.search))
            .valueOrNull
            ?.where((u) => _selected.contains(u.id))
            .toList() ??
        const [];
    if (users.isEmpty) return;
    final ok = await confirmUxAction(
      context,
      title: active ? 'صارفین فعال کریں' : 'صارفین غیر فعال کریں',
      message: active
          ? '${users.length} صارفین کو فعال کیا جائے گا۔'
          : '${users.length} صارفین کو غیر فعال کیا جائے گا — وہ لاگ اِن نہیں کر سکیں گے۔',
      confirmLabel: 'جی ہاں، جاری رکھیں',
    );
    if (!ok || !mounted) return;
    final err = await ref
        .read(roleUxControllerProvider.notifier)
        .bulkSetActive(users, active);
    if (!mounted) return;
    if (err == null) {
      showUxSnack(context, 'عمل مکمل ہو گیا');
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
    } else {
      showUxSnack(context, err, isError: true);
    }
  }

  Future<void> _bulkRoleChange() async {
    final can = ref.read(roleServiceProvider).canManageRoles();
    if (!can && mounted) {
      showUxSnack(context, 'آپ کے پاس ذمہ داریاں سونپنے کی اجازت نہیں ہے۔',
          isError: true);
      return;
    }
    final rolesAsync = await ref.read(tenantRolesUxProvider.future);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const UxSectionTitle('نئی ذمہ داری منتخب کریں',
                icon: Icons.badge_outlined),
            const SizedBox(height: 8),
            for (final r in rolesAsync)
              ListTile(
                title: Text(r.displayUrdu),
                subtitle: r.description != null && r.description!.isNotEmpty
                    ? Text(r.description!,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                onTap: () => Navigator.pop(ctx, r.key),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final users = ref
            .read(tenantUsersProvider(widget.search))
            .valueOrNull
            ?.where((u) => _selected.contains(u.id))
            .toList() ??
        const [];
    if (users.isEmpty) return;
    final ok = await confirmUxAction(
      context,
      title: 'ذمہ داری تبدیل کریں',
      message:
          '${users.length} صارفین کی ذمہ داری تبدیل کی جائے گی — ان کے اختیارات نئی ذمہ داری کے مطابق ہو جائیں گے۔',
      confirmLabel: 'جی ہاں، جاری رکھیں',
    );
    if (!ok || !mounted) return;
    final holders = await _assignHolderKeys();
    final err = await ref
        .read(roleUxControllerProvider.notifier)
        .bulkAssignRole(users, chosen, holders);
    if (!mounted) return;
    if (err == null) {
      showUxSnack(context, 'ذمہ داریاں تبدیل ہو گئیں');
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
    } else {
      showUxSnack(context, err, isError: true);
    }
  }

  Future<Set<String>> _assignHolderKeys() async {
    final roles = await ref.read(tenantRolesUxProvider.future);
    return {
      for (final r in roles)
        if (r.permissionCodes.contains('roles.assign')) r.key,
    };
  }
}

// ─────────────────────────────────────────────────────────────
// Roles tab — real working list + read-only permission preview.
// (The permission editor ships in Phase 8b.)
// ─────────────────────────────────────────────────────────────

class _RolesTab extends ConsumerWidget {
  const _RolesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(tenantRolesUxProvider);
    final catalogAsync = ref.watch(permissionCatalogProvider);
    final countsAsync = ref.watch(roleMemberCountsProvider);
    return rolesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => UxEmptyState(
        icon: Icons.error_outline,
        title: roleUxErrorMessage(e),
      ),
      data: (roles) {
        if (roles.isEmpty) {
          return const UxEmptyState(
            icon: Icons.badge_outlined,
            title: 'ابھی کوئی ذمہ داری درج نہیں',
          );
        }
        final counts = countsAsync.valueOrNull ?? const {};
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(tenantRolesUxProvider);
            ref.invalidate(roleMemberCountsProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: roles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _roleCard(
              context,
              roles[i],
              catalogAsync,
              counts[roles[i].key],
            ),
          ),
        );
      },
    );
  }

  Widget _roleCard(
    BuildContext context,
    TenantRoleInfo role,
    AsyncValue<List<PermissionInfo>> catalogAsync,
    int? memberCount,
  ) {
    return UxCard(
      onTap: () => _showRolePreview(context, role, catalogAsync),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(role.displayUrdu, style: AppTypography.titleSmall),
              ),
              _chip('${role.permissionCodes.length} اختیارات'),
              // Only show the member chip when the count is actually
              // readable (RLS may hide memberships) — never fabricate.
              if (memberCount != null) ...[
                const SizedBox(width: 6),
                _chip('$memberCount ارکان'),
              ],
            ],
          ),
          if (role.description != null && role.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              role.description!,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// One permission row: granted (✓) or not granted (✗).
  Widget _previewRow(PermissionInfo p, TenantRoleInfo role) {
    final granted = role.permissionCodes.contains(p.code);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 18,
            color: granted
                ? AppColors.success
                : AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.labelUrdu,
              style: AppTypography.bodyMedium.copyWith(
                color:
                    granted ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: AppColors.primary),
      ),
    );
  }

  /// Full permission preview: every catalog permission with ✓ granted /
  /// ✗ not granted, grouped by category. Read-only.
  void _showRolePreview(
    BuildContext context,
    TenantRoleInfo role,
    AsyncValue<List<PermissionInfo>> catalogAsync,
  ) {
    final catalog = catalogAsync.valueOrNull ?? const [];
    final grouped = <String, List<PermissionInfo>>{};
    for (final p in catalog) {
      grouped.putIfAbsent(p.categoryUrdu, () => []).add(p);
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => SafeArea(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(role.displayUrdu,
                  style: AppTypography.titleLarge
                      .copyWith(color: AppColors.primary)),
              if (role.description != null && role.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(role.description!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 12),
              UxSectionTitle(
                  'اختیارات کا جائزہ (${role.permissionCodes.length}/${catalog.length})',
                  icon: Icons.key_outlined),
              const SizedBox(height: 4),
              Text(
                '✓ حاصل ہے — ✗ حاصل نہیں ہے',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              if (grouped.isEmpty)
                const Text('اختیارات کی فہرست لوڈ نہیں ہو سکی۔'),
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(entry.key,
                      style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold)),
                ),
                for (final p in entry.value) _previewRow(p, role),
              ],
              const SizedBox(height: 16),
              Text(
                'اختیارات کی ترمیم اگلے مرحلے میں شامل کی جائے گی۔',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Role key -> Urdu label (resolved from live tenant roles).
final _roleUrduProvider = FutureProvider<Map<String, String>>((ref) async {
  final roles = await ref.watch(tenantRolesUxProvider.future);
  return {for (final r in roles) r.key: r.displayUrdu};
});
