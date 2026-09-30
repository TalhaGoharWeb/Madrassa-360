/// صارف انتظام اسکرین — m360 redesign (Phase 10)
/// User Management Screen — admin CRUD for user accounts and roles/permissions.
///
/// Same provider flows ([userManagementProvider]): load, create/update/
/// delete/toggle accounts, create/update/delete roles. Destructive
/// actions go through destructive [showM360ConfirmDialog]. Rendered as
/// an [AppShell] destination: no Scaffold, no AppBar — [PageContainer]/
/// [PageHeader] only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/design/m360.dart';
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

  /// Back affordance for deep-pushed routes. Shell destinations get the
  /// shell's own back chevron, so this renders nothing for them.
  List<Widget> _withBack(BuildContext context, List<Widget> actions) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return [
      if (canPop)
        M360IconButton(
          icon: Icons.arrow_back,
          tooltip: 'واپس',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ...actions,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      // Load data once on first build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = ref.read(userManagementProvider);
        if (!state.isLoading && state.accounts.isEmpty) {
          ref.read(userManagementProvider.notifier).loadAll();
        }
      });

      return PageContainer(
        scrollable: false,
        header: PageHeader(
          title: 'صارف انتظام',
          breadcrumb: 'منتظم',
          description: 'صارفین بنائیں، کردار ترتیب دیں، اجازتیں دیں',
          actions: _withBack(context, []),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryDark,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(
                    text: 'صارفین',
                    icon: Icon(Icons.manage_accounts, size: 18)),
                Tab(
                    text: 'کردار و اجازتیں',
                    icon: Icon(Icons.security, size: 18)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _UserAccountsTab(),
                  _RolesTab(),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 1 — User Accounts
// ═══════════════════════════════════════════════════════════════

class _UserAccountsTab extends ConsumerStatefulWidget {
  const _UserAccountsTab();

  @override
  ConsumerState<_UserAccountsTab> createState() => _UserAccountsTabState();
}

class _UserAccountsTabState extends ConsumerState<_UserAccountsTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userManagementProvider);
    final accounts = state.accounts
        .where((a) =>
            _searchQuery.isEmpty ||
            a.name.contains(_searchQuery) ||
            a.email.contains(_searchQuery) ||
            a.roleNameUrdu.contains(_searchQuery))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: M360SearchField(
            hint: 'نام یا ای میل تلاش کریں…',
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: _PermBadge(
              label: 'کل: ${accounts.length}',
              color: AppColors.primary,
            ),
          ),
        ),
        Expanded(
          child: state.isLoading
              ? const M360LoadingState()
              : accounts.isEmpty
                  ? M360EmptyState(
                      icon: Icons.people_outline,
                      title: 'کوئی صارف نہیں',
                      description: _searchQuery.isEmpty
                          ? 'نیا صارف شامل کر کے شروع کریں۔'
                          : 'تلاش تبدیل کر کے دوبارہ کوشش کریں۔',
                      actionLabel:
                          _searchQuery.isEmpty ? 'نیا صارف شامل کریں' : null,
                      onAction: _searchQuery.isEmpty
                          ? () => _showUpsertDialog()
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: accounts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _AccountCard(
                        account: accounts[i],
                        onEdit: () => _showUpsertDialog(existing: accounts[i]),
                        onDelete: () => _confirmDelete(accounts[i]),
                        onToggle: () => _toggleStatus(accounts[i]),
                      ),
                    ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: M360PrimaryButton(
            label: 'نیا صارف',
            icon: Icons.person_add,
            fullWidth: true,
            onPressed: () => _showUpsertDialog(),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleStatus(UserAccount account) async {
    try {
      await ref
          .read(userManagementProvider.notifier)
          .toggleAccountStatus(account);
      if (!mounted) return;
      showM360SnackBar(
        context,
        account.isActive ? 'صارف غیر فعال کر دیا گیا' : 'صارف فعال کر دیا گیا',
      );
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'حالت تبدیل کرنے میں خطا ہوئی', isError: true);
    }
  }

  Future<void> _showUpsertDialog({UserAccount? existing}) async {
    final savedName = await showM360Dialog<String>(
      context,
      title: existing == null ? 'نیا صارف شامل کریں' : 'صارف کی ترمیم',
      icon: existing == null ? Icons.person_add : Icons.edit,
      content: _AccountForm(existing: existing),
    );
    if (savedName != null && mounted) {
      showM360SnackBar(
        context,
        existing == null
            ? '$savedName شامل ہو گیا'
            : '$savedName کی تبدیلیاں محفوظ ہو گئیں',
      );
    }
  }

  Future<void> _confirmDelete(UserAccount account) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'صارف حذف کریں؟',
      message:
          '"${account.name}" کو مستقل طور پر حذف کر دیا جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(userManagementProvider.notifier)
          .deleteAccount(account.id!);
      if (!mounted) return;
      showM360SnackBar(context, 'صارف حذف ہو گیا');
    } catch (_) {
      if (!mounted) return;
      showM360SnackBar(context, 'حذف کرنے میں خطا ہوئی', isError: true);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Account create/edit form. Pops the saved name on success.
// ─────────────────────────────────────────────────────────────

class _AccountForm extends ConsumerStatefulWidget {
  final UserAccount? existing;

  const _AccountForm({this.existing});

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  late AppRole _selectedRole;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name);
    _emailCtrl = TextEditingController(text: existing?.email);
    final roles = _roles();
    _selectedRole = existing != null
        ? roles.firstWhere(
            (r) => r.name == existing.roleName,
            orElse: () => AppRole.teacher,
          )
        : AppRole.teacher;
  }

  List<AppRole> _roles() {
    final loaded = ref.read(appRolesProvider);
    return loaded.isNotEmpty ? loaded : AppRole.allSystemRoles;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final notifier = ref.read(userManagementProvider.notifier);
      final account = UserAccount(
        id: existing?.id,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        roleName: _selectedRole.name,
        roleNameUrdu: _selectedRole.nameUrdu,
        password: existing == null ? _passwordCtrl.text : null,
      );
      final err = existing == null
          ? await notifier.createAccount(account)
          : await notifier.updateAccount(account);
      if (!mounted) return;
      if (err != null) {
        setState(() => _saving = false);
        showM360SnackBar(context, 'خرابی: $err', isError: true);
        return;
      }
      Navigator.of(context).pop(_nameCtrl.text.trim());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'محفوظ کرنے میں خطا ہوئی', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final roles = _roles();
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M360TextField(
            label: 'مکمل نام',
            hint: 'جیسے: محمد یوسف',
            controller: _nameCtrl,
            prefixIcon: Icons.person,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'نام درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'ای میل',
            hint: 'user@madrasa.com',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'ای میل درج کریں';
              if (!v.contains('@')) return 'درست ای میل درج کریں';
              return null;
            },
          ),
          if (existing == null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: M360TextField(
                    label: 'پاس ورڈ',
                    hint: 'کم از کم 6 حروف',
                    controller: _passwordCtrl,
                    obscureText: !_showPassword,
                    prefixIcon: Icons.lock_outline,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'پاس ورڈ درج کریں';
                      if (v.length < 6) return 'کم از کم 6 حروف';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: M360IconButton(
                    icon:
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                    tooltip: _showPassword ? 'چھپائیں' : 'دکھائیں',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          M360Dropdown<AppRole>(
            label: 'کردار',
            value: _selectedRole,
            prefixIcon: Icons.badge_outlined,
            items: [
              for (final r in roles)
                M360DropdownItem(value: r, label: r.nameUrdu),
            ],
            onChanged: (r) {
              if (r != null) setState(() => _selectedRole = r);
            },
          ),
          const SizedBox(height: 12),
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
                Text(
                  'اجازتیں (${_selectedRole.permissions.length})',
                  textDirection: TextDirection.rtl,
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedRole.permissions
                      .map((p) => _PermBadge(
                            label: p.urduLabel,
                            color: AppColors.primary,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: M360TertiaryButton(
                  label: 'منسوخ کریں',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M360PrimaryButton(
                  label: existing == null ? 'شامل کریں' : 'محفوظ کریں',
                  icon: Icons.save,
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab 2 — Roles & Permissions
// ═══════════════════════════════════════════════════════════════

class _RolesTab extends ConsumerStatefulWidget {
  const _RolesTab();

  @override
  ConsumerState<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends ConsumerState<_RolesTab> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userManagementProvider);
    final roles = state.roles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: state.isLoading
              ? const M360LoadingState()
              : roles.isEmpty
                  ? const M360EmptyState(
                      icon: Icons.security_outlined,
                      title: 'کوئی کردار نہیں',
                      description: 'نیا کردار بنا کر اجازتیں ترتیب دیں۔',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: M360PrimaryButton(
            label: 'نیا کردار',
            icon: Icons.add,
            fullWidth: true,
            onPressed: _showNewRoleDialog,
          ),
        ),
      ],
    );
  }

  void _showPermissionsSheet(AppRole role) {
    // Make a mutable copy of current permissions.
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
                  M360PrimaryButton(
                    label: 'اجازتیں محفوظ کریں',
                    icon: Icons.save,
                    fullWidth: true,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await ref
                            .read(userManagementProvider.notifier)
                            .updateRole(
                                role.copyWith(permissions: permissions));
                        if (!mounted) return;
                        showM360SnackBar(context, 'اجازتیں محفوظ ہو گئیں');
                      } catch (_) {
                        if (!mounted) return;
                        showM360SnackBar(context, 'محفوظ کرنے میں خطا ہوئی',
                            isError: true);
                      }
                    },
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
    // Group permissions into categories.
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

  Future<void> _showNewRoleDialog() async {
    final nameUrdu = await showM360Dialog<String>(
      context,
      title: 'نیا کردار بنائیں',
      icon: Icons.add_moderator,
      content: const _RoleForm(),
    );
    if (nameUrdu != null && mounted) {
      showM360SnackBar(context, 'نیا کردار بن گیا — اجازتیں ترتیب دیں');
    }
  }

  Future<void> _confirmDeleteRole(AppRole role) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'کردار حذف کریں؟',
      message:
          '"${role.nameUrdu}" کو مستقل طور پر حذف کر دیا جائے گا۔ یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (!confirmed) return;
    final err =
        await ref.read(userManagementProvider.notifier).deleteRole(role);
    if (!mounted) return;
    if (err == null) {
      showM360SnackBar(context, 'کردار حذف ہو گیا');
    } else {
      showM360SnackBar(context, 'خرابی: $err', isError: true);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// New-role form. Pops the Urdu name on success.
// ─────────────────────────────────────────────────────────────

class _RoleForm extends ConsumerStatefulWidget {
  const _RoleForm();

  @override
  ConsumerState<_RoleForm> createState() => _RoleFormState();
}

class _RoleFormState extends ConsumerState<_RoleForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nameUrduCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameUrduCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final newRole = AppRole(
        name: _nameCtrl.text.trim().toLowerCase().replaceAll(' ', '_'),
        nameUrdu: _nameUrduCtrl.text.trim(),
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      await ref.read(userManagementProvider.notifier).createRole(newRole);
      if (!mounted) return;
      Navigator.of(context).pop(newRole.nameUrdu);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'کردار بنانے میں خطا ہوئی', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          M360TextField(
            label: 'کردار کا نام (انگریزی)',
            hint: 'e.g. librarian',
            controller: _nameCtrl,
            prefixIcon: Icons.label,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'نام درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'کردار کا نام (اردو)',
            hint: 'جیسے: لائبریرین',
            controller: _nameUrduCtrl,
            prefixIcon: Icons.label_outline,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'اردو نام درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'تفصیل (اختیاری)',
            hint: 'مختصر تفصیل',
            controller: _descCtrl,
            prefixIcon: Icons.info_outline,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: M360TertiaryButton(
                  label: 'منسوخ کریں',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M360PrimaryButton(
                  label: 'بنائیں',
                  icon: Icons.add,
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Cards
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
    return M360Card(
      borderColor: active ? null : AppColors.error.withValues(alpha: 0.3),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: active
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.divider,
            child: Text(
              account.initials,
              style: AppTypography.labelLarge.copyWith(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                    _PermBadge(
                      label: account.roleNameUrdu,
                      color: AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                M360Email(
                  account.email,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (!active)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: M360StatusChip(status: M360Status.inactive),
                  ),
              ],
            ),
          ),
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
                  title: Text('ترمیم'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    active ? Icons.block : Icons.check_circle_outline,
                    size: 18,
                    color: active ? AppColors.warning : AppColors.success,
                  ),
                  title: Text(active ? 'غیر فعال کریں' : 'فعال کریں'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 18),
                  title: Text('حذف کریں',
                      style: AppTypography.labelNastaliq.copyWith(
                        color: AppColors.error,
                      )),
                ),
              ),
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
    return M360Card(
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
                child: const Icon(Icons.shield_outlined,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(role.nameUrdu,
                              style: AppTypography.titleMedium,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (role.isSystem) ...[
                          const SizedBox(width: 6),
                          _PermBadge(
                            label: 'بنیادی',
                            color: AppColors.info,
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
              M360IconButton(
                icon: Icons.tune,
                tooltip: 'اجازتیں',
                onPressed: onEdit,
              ),
              if (onDelete != null)
                M360IconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'حذف کریں',
                  color: AppColors.error,
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: role.permissions
                .map((p) => _PermBadge(
                      label: p.urduLabel,
                      color: AppColors.primary,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// RTL-aware colored pill badge for roles and permission labels.
class _PermBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _PermBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: AppTypography.labelSmall
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
