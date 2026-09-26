/// ڈیٹا حدود — انتظام اسکرین (Phase 9)
///
/// Data Scopes management for madrasa admins (`roles.assign`):
/// a tenant-wide directory of every narrowed data scope (who may see /
/// act on which slice of madrasa data), with create / edit / remove.
///
/// Reads go through RLS as the authenticated user; when offline the list
/// falls back to the last-known cache and the UI shows an honest stale
/// banner with the last fetch time. Writes go through
/// [ScopeManagerController]: the client-side [ScopePolicy] narrow-only
/// check refuses over-wide grants before anything is sent (fail closed),
/// then `permission_scopes` is written under 020 RLS and the 019
/// auto-audit trigger writes the human-readable audit rows.
///
/// All strings are Urdu-first, body text is ≥ 15sp, and no technical
/// jargon (codes, table names) reaches the UI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../../core/services/scope_policy.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/utils/audit_urdu.dart';
import '../../../data/role_ux_repository.dart';
import '../../../data/scope_manager_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/role_ux_provider.dart';
import '../../../providers/scope_manager_provider.dart';
import 'role_ux_widgets.dart';

// ─────────────────────────────────────────────────────────────
// Directory screen
// ─────────────────────────────────────────────────────────────

class ScopeManagerScreen extends ConsumerWidget {
  const ScopeManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(roleServiceProvider).canManageRoles();
    if (!canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('ڈیٹا حدود')),
        body: const UxEmptyState(
          icon: Icons.lock_outline,
          title: 'آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے',
          hint:
              'ڈیٹا حدود کے انتظام کے لیے آپ کے پاس متعلقہ اجازت ہونی ضروری ہے۔',
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('ڈیٹا حدود'),
        centerTitle: true,
      ),
      body: const _ScopeDirectory(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScopeEditorScreen()),
          );
          if (saved == true && context.mounted) {
            showUxSnack(context, 'ڈیٹا حدود محفوظ ہو گئیں');
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('دائرہ کار مقرر کریں'),
      ),
    );
  }
}

class _ScopeDirectory extends ConsumerStatefulWidget {
  const _ScopeDirectory();

  @override
  ConsumerState<_ScopeDirectory> createState() => _ScopeDirectoryState();
}

class _ScopeDirectoryState extends ConsumerState<_ScopeDirectory> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(scopeAssignmentsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(scopeAssignmentsProvider);
        await ref.read(scopeAssignmentsProvider.future);
      },
      child: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => UxEmptyState(
          icon: Icons.error_outline,
          title: roleUxErrorMessage(e),
          hint: 'تازہ کریں — سوائپ کریں یا واپس آ کر دوبارہ دیکھیں۔',
        ),
        data: (result) => _body(result),
      ),
    );
  }

  Widget _body(ScopeAssignmentListResult result) {
    final q = _search.trim();
    final items = q.isEmpty
        ? result.items
        : result.items
            .where((a) => a.userName.contains(q) || a.userRoleUrdu.contains(q))
            .toList();

    // Group by user, users sorted by name.
    final byUser = <String, List<ScopeAssignment>>{};
    for (final a in items) {
      byUser.putIfAbsent(a.userId, () => []).add(a);
    }
    final userIds = byUser.keys.toList()
      ..sort((x, y) =>
          byUser[x]!.first.userName.compareTo(byUser[y]!.first.userName));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (result.fromCache) _staleBanner(result.fetchedAt),
        TextField(
          decoration: const InputDecoration(
            hintText: 'نام سے تلاش کریں',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        if (userIds.isEmpty)
          const UxEmptyState(
            icon: Icons.data_object_outlined,
            title: 'ابھی کوئی محدود دائرہ کار مقرر نہیں',
            hint:
                'تمام صارفین فی الحال پورے مدرسے کے دائرے میں کام کر رہے ہیں۔ '
                'نیا دائرہ نیچے بٹن سے مقرر کریں۔',
          )
        else
          for (final uid in userIds) _userGroup(byUser[uid]!),
      ],
    );
  }

  Widget _staleBanner(DateTime? fetchedAt) {
    final when = fetchedAt == null
        ? 'آخری تازہ کاری معلوم نہیں'
        : 'آخری تازہ کاری: ${formatAuditDayUrdu(fetchedAt)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: UxCard(
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('آف لائن ڈیٹا دکھایا جا رہا ہے',
                      style: AppTypography.bodyMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(when,
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userGroup(List<ScopeAssignment> assignments) {
    final first = assignments.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: UxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    first.userName.isEmpty
                        ? '؟'
                        : first.userName.characters.first,
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.userName, style: AppTypography.titleMedium),
                      if (first.userRoleUrdu.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        RoleBadge(label: first.userRoleUrdu),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            for (final a in assignments) _assignmentRow(a),
          ],
        ),
      ),
    );
  }

  Widget _assignmentRow(ScopeAssignment a) {
    final names = <String>{
      ...a.classNames.values,
      ...a.studentNames.values,
    }.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.permissionLabelUrdu,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  scopeSummaryUrdu(a.scopeType,
                      classCount: a.classIds.length,
                      studentCount: a.studentIds.length),
                  style: AppTypography.bodyMedium,
                ),
                if (names.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    names.take(3).join('، ') +
                        (names.length > 3 ? ' وغیرہ' : ''),
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Text('لاگو از ${formatAuditDayUrdu(a.createdAt)}',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تبدیل کریں',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScopeEditorScreen(
                    initialUser: TenantUser(
                      id: a.userId,
                      name: a.userName,
                      email: '',
                      roleKey: '',
                      roleUrdu: a.userRoleUrdu,
                      isActive: true,
                      banned: false,
                    ),
                    initialCodes: {a.permissionCode},
                    initialSelection: ScopeSelection(
                      type: a.scopeType,
                      classIds: a.classIds,
                      studentIds: a.studentIds,
                    ),
                  ),
                ),
              );
              if (saved == true && mounted) {
                showUxSnack(context, 'ڈیٹا حدود محفوظ ہو گئیں');
              }
            },
          ),
          IconButton(
            tooltip: 'ہٹائیں',
            icon: Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: () => _removeScope(a),
          ),
        ],
      ),
    );
  }

  Future<void> _removeScope(ScopeAssignment a) async {
    final ok = await confirmUxAction(
      context,
      title: 'دائرہ کار ہٹائیں',
      message: '${a.userName} کے لیے «${a.permissionLabelUrdu}» کا محدود '
          'دائرہ ختم کیا جائے گا — وہ دوبارہ پورے مدرسے کے دائرے میں آ جائیں گے۔',
      confirmLabel: 'جی ہاں، ہٹائیں',
    );
    if (!ok || !mounted) return;
    final err = await ref
        .read(scopeManagerControllerProvider.notifier)
        .removeScopes(targetUserId: a.userId, codes: {a.permissionCode});
    if (!mounted) return;
    if (err == null) {
      showUxSnack(context, 'دائرہ کار ہٹا دیا گیا');
    } else {
      showUxSnack(context, err, isError: true);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Editor screen (create / edit)
// ─────────────────────────────────────────────────────────────

class ScopeEditorScreen extends ConsumerStatefulWidget {
  const ScopeEditorScreen({
    super.key,
    this.initialUser,
    this.initialCodes = const {},
    this.initialSelection,
  });

  /// Fixed target user; when null the editor starts with a user picker.
  final TenantUser? initialUser;
  final Set<String> initialCodes;
  final ScopeSelection? initialSelection;

  @override
  ConsumerState<ScopeEditorScreen> createState() => _ScopeEditorScreenState();
}

class _ScopeEditorScreenState extends ConsumerState<ScopeEditorScreen> {
  TenantUser? _user;
  final Set<String> _codes = {};
  String _type = 'all';
  final Set<String> _classIds = {};
  final Set<String> _studentIds = {};
  final _userSearch = TextEditingController();
  final _studentSearch = TextEditingController();
  List<StudentRef> _studentResults = const [];
  bool _studentSearching = false;
  String _userQuery = '';

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _codes.addAll(widget.initialCodes);
    final sel = widget.initialSelection;
    if (sel != null) {
      _type = sel.type;
      _classIds.addAll(sel.classIds);
      _studentIds.addAll(sel.studentIds);
    }
  }

  @override
  void dispose() {
    _userSearch.dispose();
    _studentSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(currentTenantIdProvider);
    final saving = ref.watch(scopeManagerControllerProvider).isLoading;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('دائرہ کار مقرر کریں'),
        centerTitle: true,
      ),
      body: tenantId == null
          ? const UxEmptyState(
              icon: Icons.error_outline,
              title: 'مدرسہ منتخب نہیں ہے',
              hint: 'پہلے کوئی مدرسہ منتخب کریں۔',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _granterNotice(),
                const SizedBox(height: 12),
                _userCard(),
                const SizedBox(height: 12),
                _areasCard(),
                const SizedBox(height: 12),
                _scopeCard(tenantId),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: const Text('محفوظ کریں'),
                  onPressed: saving ? null : () => _save(),
                ),
              ],
            ),
    );
  }

  /// Honest ceiling notice + fail-closed banner when the granter's own
  /// scopes cannot be loaded (save is disabled then).
  Widget _granterNotice() {
    final tenantId = ref.watch(currentTenantIdProvider);
    final selfId = ref.watch(currentUserProvider)?.id;
    if (tenantId == null || selfId == null) return const SizedBox.shrink();
    return FutureBuilder<Map<String, ScopeSelection>>(
      future: ref
          .read(roleUxRepositoryProvider)
          .userScopes(tenantId: tenantId, userId: selfId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snap.hasError) {
          return UxCard(
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'آپ کا اپنا دائرہ کار لوڈ نہیں ہو سکا — '
                    'حفاظتی طور پر محفوظ کرنا بند ہے۔ دوبارہ کوشش کریں۔',
                    style: AppTypography.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }
        return UxCard(
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'نوٹ: آپ کسی صارف کو اپنے دائرہ کار سے وسیع دائرہ نہیں دے سکتے۔ '
                  'تبدیلی فوراً نافذ ہوگی اور اس کا ریکارڈ محفوظ کیا جائے گا۔',
                  style: AppTypography.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _userCard() {
    if (_user != null) {
      final u = _user!;
      return UxCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(u.initials,
                  style: AppTypography.titleMedium
                      .copyWith(color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name, style: AppTypography.titleMedium),
                  if (u.email.isNotEmpty)
                    Text(u.email,
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  // Never surface a raw role key; the Urdu label map
                  // covers known keys and prettifies unknown ones.
                  RoleBadge(
                      label: u.roleUrdu.isNotEmpty
                          ? u.roleUrdu
                          : roleKeyUrdu(u.roleKey)),
                ],
              ),
            ),
            if (widget.initialUser == null)
              TextButton(
                onPressed: () => setState(() => _user = null),
                child: const Text('تبدیل کریں'),
              ),
          ],
        ),
      );
    }
    // User picker.
    final usersAsync = ref.watch(tenantUsersProvider(_userQuery));
    return UxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UxSectionTitle('صارف منتخب کریں', icon: Icons.person_outline),
          const SizedBox(height: 8),
          TextField(
            controller: _userSearch,
            decoration: InputDecoration(
              hintText: 'نام لکھ کر تلاش کریں',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () =>
                    setState(() => _userQuery = _userSearch.text.trim()),
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => setState(() => _userQuery = v.trim()),
          ),
          const SizedBox(height: 8),
          usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(roleUxErrorMessage(e),
                style:
                    AppTypography.bodyMedium.copyWith(color: AppColors.error)),
            data: (users) {
              final list = users.take(8).toList();
              if (list.isEmpty) {
                return Text('کوئی صارف نہیں ملا۔',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondary));
              }
              return Column(
                children: [
                  for (final u in list)
                    ListTile(
                      title: Text(u.name, style: AppTypography.bodyMedium),
                      subtitle: u.email.isEmpty
                          ? null
                          : Text(u.email,
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.textSecondary)),
                      trailing: RoleBadge(label: u.roleUrdu),
                      onTap: () => setState(() => _user = u),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _areasCard() {
    final catalogAsync = ref.watch(permissionCatalogProvider);
    return UxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UxSectionTitle('کن اختیارات پر لاگو ہو؟',
              icon: Icons.key_outlined),
          const SizedBox(height: 4),
          Text('دائرہ کار صرف حاضری اور نتائج کے اختیارات پر نافذ ہوتا ہے۔',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          catalogAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(roleUxErrorMessage(e),
                style:
                    AppTypography.bodyMedium.copyWith(color: AppColors.error)),
            data: (catalog) {
              final scoped = [
                for (final p in catalog)
                  if (ScopeSelection.scopedCodes.contains(p.code)) p,
              ];
              if (scoped.isEmpty) {
                return Text('اختیارات کی فہرست لوڈ نہیں ہو سکی۔',
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondary));
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in scoped)
                    FilterChip(
                      label: Text(p.labelUrdu),
                      selected: _codes.contains(p.code),
                      onSelected: (s) => setState(() {
                        if (s) {
                          _codes.add(p.code);
                        } else {
                          _codes.remove(p.code);
                        }
                      }),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _scopeCard(String tenantId) {
    return UxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UxSectionTitle('دائرہ کار منتخب کریں',
              icon: Icons.data_object_outlined),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _type,
            onChanged: (v) => setState(() => _type = v ?? 'all'),
            child: Column(
              children: [
                for (final t in ['all', 'classes', 'students', 'department'])
                  _scopeOption(t),
              ],
            ),
          ),
          if (_type == 'classes') ...[
            const SizedBox(height: 12),
            const UxSectionTitle('جماعتیں منتخب کریں',
                icon: Icons.class_outlined),
            const SizedBox(height: 8),
            _classPicker(tenantId),
          ],
          if (_type == 'students') ...[
            const SizedBox(height: 12),
            const UxSectionTitle('طلبہ تلاش کریں', icon: Icons.search),
            const SizedBox(height: 8),
            _studentPicker(tenantId),
          ],
        ],
      ),
    );
  }

  Widget _scopeOption(String value) {
    final selected = _type == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: UxCard(
        onTap: () => setState(() => _type = value),
        child: Row(
          children: [
            Radio<String>(value: value),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scopeTypeUrdu(value),
                      style: AppTypography.bodyMedium.copyWith(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal)),
                  const SizedBox(height: 2),
                  Text(scopeTypeHintUrdu(value),
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _classPicker(String tenantId) {
    return FutureBuilder<List<ClassRef>>(
      future: ref.read(roleUxRepositoryProvider).listClasses(tenantId),
      builder: (context, snap) {
        final classes = snap.data ?? const [];
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (classes.isEmpty) {
          return Text('اس مدرسے میں ابھی کوئی جماعت درج نہیں۔',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in classes)
              FilterChip(
                label: Text(c.name),
                selected: _classIds.contains(c.id),
                onSelected: (s) => setState(() {
                  if (s) {
                    _classIds.add(c.id);
                  } else {
                    _classIds.remove(c.id);
                  }
                }),
              ),
          ],
        );
      },
    );
  }

  Widget _studentPicker(String tenantId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _studentSearch,
          decoration: InputDecoration(
            hintText: 'نام لکھ کر تلاش کریں',
            suffixIcon: _studentSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _searchStudents(tenantId),
                  ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _searchStudents(tenantId),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _studentResults)
              FilterChip(
                label: Text(s.name),
                selected: _studentIds.contains(s.id),
                onSelected: (v) => setState(() {
                  if (v) {
                    _studentIds.add(s.id);
                  } else {
                    _studentIds.remove(s.id);
                  }
                }),
              ),
          ],
        ),
        if (_studentIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${_studentIds.length} طالب علم منتخب',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.primary)),
          ),
      ],
    );
  }

  Future<void> _searchStudents(String tenantId) async {
    final q = _studentSearch.text.trim();
    if (q.isEmpty) return;
    setState(() => _studentSearching = true);
    try {
      final results =
          await ref.read(roleUxRepositoryProvider).searchStudents(tenantId, q);
      if (mounted) setState(() => _studentResults = results);
    } catch (e) {
      if (mounted) showUxSnack(context, roleUxErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _studentSearching = false);
    }
  }

  Future<void> _save() async {
    if (_user == null) {
      showUxSnack(context, 'پہلے کوئی صارف منتخب کریں۔', isError: true);
      return;
    }
    if (_codes.isEmpty) {
      showUxSnack(context, 'کم از کم ایک اختیار منتخب کریں۔', isError: true);
      return;
    }
    if (_type == 'classes' && _classIds.isEmpty) {
      showUxSnack(context, 'کم از کم ایک جماعت منتخب کریں۔', isError: true);
      return;
    }
    if (_type == 'students' && _studentIds.isEmpty) {
      showUxSnack(context, 'کم از کم ایک طالب علم منتخب کریں۔', isError: true);
      return;
    }
    final err =
        await ref.read(scopeManagerControllerProvider.notifier).saveScope(
              targetUserId: _user!.id,
              codes: _codes,
              selection: ScopeSelection(
                type: _type,
                classIds: _classIds,
                studentIds: _studentIds,
              ),
            );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      showUxSnack(context, err, isError: true);
    }
  }
}
