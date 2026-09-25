/// صارف انتظام اسکرین
/// User Management Screen — admin CRUD for user accounts and roles/permissions

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user_account.dart';
import '../../../providers/user_management_provider.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      // Load data once on first build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = ref.read(userManagementProvider);
        if (!state.isLoading && state.accounts.isEmpty) {
          ref.read(userManagementProvider.notifier).loadAll();
        }
      });

      return Scaffold(
        appBar: AppBar(
          title: const Text('صارف انتظام'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'صارفین', icon: Icon(Icons.manage_accounts, size: 18)),
              Tab(
                  text: 'کردار و اجازتیں',
                  icon: Icon(Icons.security, size: 18)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: const [
            _UserAccountsTab(),
            _RolesTab(),
          ],
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 1 — User Accounts
// ═══════════════════════════════════════════════════════════════

class _UserAccountsTab extends StatefulWidget {
  const _UserAccountsTab();

  @override
  State<_UserAccountsTab> createState() => _UserAccountsTabState();
}

class _UserAccountsTabState extends State<_UserAccountsTab> {
  WidgetRef? _ref;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      _ref = ref;
      final state = ref.watch(userManagementProvider);
      final accounts = state.accounts
          .where((a) =>
              _searchQuery.isEmpty ||
              a.name.contains(_searchQuery) ||
              a.email.contains(_searchQuery) ||
              a.roleNameUrdu.contains(_searchQuery))
          .toList();

      return Scaffold(
        body: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'نام یا ای میل تلاش کریں',
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.primary),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            // Count chip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'کل: ${accounts.length}',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : accounts.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: accounts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _AccountCard(
                            account: accounts[i],
                            onEdit: () =>
                                _showUpsertDialog(existing: accounts[i]),
                            onDelete: () => _confirmDelete(accounts[i]),
                            onToggle: () => ref
                                .read(userManagementProvider.notifier)
                                .toggleAccountStatus(accounts[i]),
                          ),
                        ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showUpsertDialog(),
          icon: const Icon(Icons.person_add),
          label: const Text('نیا صارف'),
          backgroundColor: AppColors.primary,
        ),
      );
    });
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline,
              size: 64, color: AppColors.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('کوئی صارف نہیں',
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('نیا صارف شامل کریں', style: AppTypography.bodySmall),
        ],
      ),
    );
  }

  void _showUpsertDialog({UserAccount? existing}) {
    final roles = (_ref?.read(appRolesProvider) ?? []).isNotEmpty
        ? _ref!.read(appRolesProvider)
        : AppRole.allSystemRoles;

    final nameCtrl = TextEditingController(text: existing?.name);
    final emailCtrl = TextEditingController(text: existing?.email);
    final passwordCtrl = TextEditingController();
    bool showPassword = false;
    AppRole selectedRole = existing != null
        ? roles.firstWhere(
            (r) => r.name == existing.roleName,
            orElse: () => AppRole.teacher,
          )
        : AppRole.teacher;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(existing == null ? Icons.person_add : Icons.edit,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(existing == null ? 'نیا صارف شامل کریں' : 'صارف کی ترمیم',
                  style: AppTypography.titleMedium),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    _DialogLabel('مکمل نام'),
                    const SizedBox(height: 6),
                    _DialogField(
                      controller: nameCtrl,
                      hint: 'جیسے: محمد یوسف',
                      icon: Icons.person,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'نام درج کریں'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Email
                    _DialogLabel('ای میل'),
                    const SizedBox(height: 6),
                    _DialogField(
                      controller: emailCtrl,
                      hint: 'user@madrasa.com',
                      icon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'ای میل درج کریں';
                        }
                        if (!v.contains('@')) return 'درست ای میل درج کریں';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password — only for new accounts
                    if (existing == null) ...[
                      _DialogLabel('پاس ورڈ'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: passwordCtrl,
                        obscureText: !showPassword,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          hintText: 'کم از کم 6 حروف',
                          prefixIcon: const Icon(Icons.lock_outline,
                              color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(showPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setLocal(() => showPassword = !showPassword),
                          ),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'پاس ورڈ درج کریں';
                          if (v.length < 6) return 'کم از کم 6 حروف';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Role
                    _DialogLabel('کردار'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AppRole>(
                          value: selectedRole,
                          isExpanded: true,
                          items: roles
                              .map((r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r.nameUrdu,
                                        style: AppTypography.bodyMedium),
                                  ))
                              .toList(),
                          onChanged: (r) {
                            if (r != null) setLocal(() => selectedRole = r);
                          },
                        ),
                      ),
                    ),

                    // Permission preview
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('اجازتیں (${selectedRole.permissions.length})',
                              style: AppTypography.labelMedium
                                  .copyWith(color: AppColors.primary)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: selectedRole.permissions
                                .map((p) => _PermChip(label: p.urduLabel))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('منسوخ'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 18),
              label: Text(existing == null ? 'شامل کریں' : 'محفوظ کریں'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);

                final notifier = _ref?.read(userManagementProvider.notifier);
                if (notifier == null) return;

                final account = UserAccount(
                  id: existing?.id,
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  roleName: selectedRole.name,
                  roleNameUrdu: selectedRole.nameUrdu,
                  password: existing == null ? passwordCtrl.text : null,
                );

                final err = existing == null
                    ? await notifier.createAccount(account)
                    : await notifier.updateAccount(account);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(err == null
                      ? (existing == null
                          ? 'صارف شامل ہو گیا'
                          : 'تبدیلیاں محفوظ ہو گئیں')
                      : 'خرابی: $err'),
                  backgroundColor:
                      err == null ? AppColors.success : AppColors.error,
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(UserAccount account) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('صارف حذف کریں؟'),
        content: Text(
          '"${account.name}" کو مستقل طور پر حذف کر دیا جائے گا۔',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('منسوخ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              await _ref
                  ?.read(userManagementProvider.notifier)
                  .deleteAccount(account.id!);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('صارف حذف ہو گیا'),
                  backgroundColor: AppColors.error,
                ),
              );
            },
            child:
                const Text('حذف کریں', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 2 — Roles & Permissions
// ═══════════════════════════════════════════════════════════════

class _RolesTab extends StatefulWidget {
  const _RolesTab();

  @override
  State<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<_RolesTab> {
  WidgetRef? _ref;

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      _ref = ref;
      final state = ref.watch(userManagementProvider);
      final roles = state.roles;

      return Scaffold(
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : roles.isEmpty
                ? const Center(child: Text('کوئی کردار نہیں'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: roles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _RoleCard(
                      role: roles[i],
                      onEdit: () => _showPermissionsSheet(roles[i]),
                      onDelete: roles[i].isSystem
                          ? null
                          : () => _confirmDeleteRole(roles[i]),
                    ),
                  ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showNewRoleDialog,
          icon: const Icon(Icons.add),
          label: const Text('نیا کردار'),
          backgroundColor: AppColors.primary,
        ),
      );
    });
  }

  void _showPermissionsSheet(AppRole role) {
    // Make a mutable copy of current permissions
    var permissions = Set<Permission>.from(role.permissions);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setLocal) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
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
                const SizedBox(height: 16),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          const Icon(Icons.security, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('اجازتیں — ${role.nameUrdu}',
                              style: AppTypography.titleMedium),
                          if (role.isSystem)
                            Text('بنیادی کردار',
                                style: AppTypography.labelSmall
                                    .copyWith(color: AppColors.info)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: _buildPermissionGroups(
                      permissions,
                      readOnly: role.isSystem,
                      onToggle: role.isSystem
                          ? null
                          : (p, v) => setLocal(() {
                                if (v) {
                                  permissions.add(p);
                                } else {
                                  permissions.remove(p);
                                }
                              }),
                    ),
                  ),
                ),

                if (!role.isSystem) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('اجازتیں محفوظ کریں'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _ref
                            ?.read(userManagementProvider.notifier)
                            .updateRole(
                                role.copyWith(permissions: permissions));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('اجازتیں محفوظ ہو گئیں'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPermissionGroups(
    Set<Permission> current, {
    bool readOnly = false,
    void Function(Permission, bool)? onToggle,
  }) {
    // Group permissions into categories
    const groups = <String, List<Permission>>{
      'طلباء': [Permission.viewStudents, Permission.editStudents],
      'عملہ': [Permission.viewStaff, Permission.editStaff],
      'فیس': [Permission.viewFees, Permission.editFees],
      'حاضری': [Permission.viewAttendance, Permission.markAttendance],
      'نتائج': [Permission.viewResults, Permission.editResults],
      'انتظامیہ': [Permission.manageUsers],
    };

    return groups.entries.map((entry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(entry.key,
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
          ...entry.value.map((perm) {
            final enabled = current.contains(perm);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: enabled
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: enabled
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.divider,
                ),
              ),
              child: SwitchListTile(
                value: enabled,
                onChanged: readOnly ? null : (v) => onToggle?.call(perm, v),
                activeThumbColor: AppColors.primary,
                title: Text(perm.urduLabel, style: AppTypography.bodyMedium),
                secondary: Icon(perm.icon,
                    color:
                        enabled ? AppColors.primary : AppColors.textSecondary,
                    size: 20),
                dense: true,
              ),
            );
          }),
          const Divider(height: 8),
        ],
      );
    }).toList();
  }

  void _showNewRoleDialog() {
    final nameCtrl = TextEditingController();
    final nameUrduCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.add_moderator, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('نیا کردار بنائیں', style: AppTypography.titleMedium),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogLabel('کردار کا نام (انگریزی)'),
              const SizedBox(height: 6),
              _DialogField(
                controller: nameCtrl,
                hint: 'e.g. librarian',
                icon: Icons.label,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'نام درج کریں' : null,
              ),
              const SizedBox(height: 12),
              _DialogLabel('کردار کا نام (اردو)'),
              const SizedBox(height: 6),
              _DialogField(
                controller: nameUrduCtrl,
                hint: 'جیسے: لائبریرین',
                icon: Icons.label_outline,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'اردو نام درج کریں'
                    : null,
              ),
              const SizedBox(height: 12),
              _DialogLabel('تفصیل (اختیاری)'),
              const SizedBox(height: 6),
              _DialogField(
                controller: descCtrl,
                hint: 'مختصر تفصیل',
                icon: Icons.info_outline,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('منسوخ')),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('بنائیں'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context);

              final newRole = AppRole(
                name: nameCtrl.text.trim().toLowerCase().replaceAll(' ', '_'),
                nameUrdu: nameUrduCtrl.text.trim(),
                description:
                    descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              );
              await _ref
                  ?.read(userManagementProvider.notifier)
                  .createRole(newRole);

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('نیا کردار بن گیا — اجازتیں ترتیب دیں'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRole(AppRole role) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('کردار حذف کریں؟'),
        content: Text(
          '"${role.nameUrdu}" کو مستقل طور پر حذف کر دیا جائے گا۔',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('منسوخ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              final err = await _ref
                  ?.read(userManagementProvider.notifier)
                  .deleteRole(role);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(err ?? 'کردار حذف ہو گیا'),
                backgroundColor:
                    err == null ? AppColors.error : AppColors.warning,
              ));
            },
            child:
                const Text('حذف کریں', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Reusable Card widgets
// ═══════════════════════════════════════════════════════════════

class _AccountCard extends StatelessWidget {
  final UserAccount account;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _AccountCard({
    required this.account,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final active = account.isActive;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.divider
              : AppColors.error.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: active
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.divider,
            child: Text(
              account.initials,
              style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(account.name,
                          style: AppTypography.titleMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    _RoleBadge(label: account.roleNameUrdu),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  account.email,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!active)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('غیر فعال',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.error)),
                  ),
              ],
            ),
          ),

          // Actions menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'toggle') onToggle();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.edit_outlined, size: 18),
                      title: Text('ترمیم'))),
              PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                      dense: true,
                      leading: Icon(
                          active ? Icons.block : Icons.check_circle_outline,
                          size: 18,
                          color:
                              active ? AppColors.warning : AppColors.success),
                      title: Text(active ? 'غیر فعال کریں' : 'فعال کریں'))),
              const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline,
                          color: AppColors.error, size: 18),
                      title: Text('حذف کریں',
                          style: TextStyle(color: AppColors.error)))),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final AppRole role;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _RoleCard({
    required this.role,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shield_outlined,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(role.nameUrdu, style: AppTypography.titleMedium),
                        if (role.isSystem) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('بنیادی',
                                style: AppTypography.labelSmall
                                    .copyWith(color: AppColors.info)),
                          ),
                        ],
                      ],
                    ),
                    if (role.description != null)
                      Text(role.description!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    color: AppColors.primary,
                    tooltip: 'اجازتیں',
                    onPressed: onEdit,
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: AppColors.error,
                      tooltip: 'حذف',
                      onPressed: onDelete,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: role.permissions
                .map((p) => _PermChip(label: p.urduLabel))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Small shared widgets
// ═══════════════════════════════════════════════════════════════

class _PermChip extends StatelessWidget {
  final String label;
  const _PermChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: AppTypography.labelSmall.copyWith(color: AppColors.primary)),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  const _RoleBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: AppTypography.labelSmall.copyWith(color: AppColors.success)),
    );
  }
}

class _DialogLabel extends StatelessWidget {
  final String text;
  const _DialogLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTypography.labelLarge);
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _DialogField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      validator: validator,
      style: AppTypography.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
