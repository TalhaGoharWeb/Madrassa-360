/// صارف کی تفصیل — Phase 8a
/// User detail screen: name, Urdu responsibility label, active status,
/// assigned classes, plain responsibility checklist, and the management
/// actions (change responsibilities, (de)activate, view activity).
///
/// Permission checks are server-resolved ([RoleService]); writes go
/// through [RoleUxController]; every failure is plain Urdu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../../core/services/role_service.dart';
import '../../../data/role_ux_repository.dart';
import '../../../providers/role_ux_provider.dart';
import 'role_ux_widgets.dart';
import 'user_wizard_screen.dart';

class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.user});

  final TenantUser user;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  late TenantUser _user;
  bool _showActivity = false;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(tenantRolesUxProvider);
    final roles = rolesAsync.valueOrNull ?? const [];
    TenantRoleInfo? role;
    for (final r in roles) {
      if (r.key == _user.roleKey) {
        role = r;
        break;
      }
    }
    final roleUrdu = role?.displayUrdu ?? _user.roleKey;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('صارف کی تفصیل'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tenantUsersProvider);
          ref.invalidate(tenantRolesUxProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _headerCard(roleUrdu, roles),
            const SizedBox(height: 12),
            _classesCard(),
            const SizedBox(height: 12),
            _responsibilityCard(role),
            const SizedBox(height: 12),
            _actionsCard(),
            if (_showActivity) ...[
              const SizedBox(height: 12),
              _activityCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerCard(String roleUrdu, List<TenantRoleInfo> roles) {
    return UxCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              _user.initials,
              style: AppTypography.titleLarge
                  .copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_user.name, style: AppTypography.titleMedium),
                if (_user.email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_user.email,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    RoleBadge(label: roleUrdu),
                    ActiveBadge(active: _user.isActive),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _classesCard() {
    return Consumer(
      builder: (context, ref, _) {
        final tenantId = ref.watch(currentTenantIdProvider);
        if (tenantId == null) return const SizedBox.shrink();
        return FutureBuilder<List<AssignedClassInfo>>(
          future: ref
              .read(roleUxRepositoryProvider)
              .assignedClasses(tenantId: tenantId, userId: _user.id),
          builder: (context, snap) {
            final classes = snap.data ?? const [];
            if (classes.isEmpty) return const SizedBox.shrink();
            return UxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const UxSectionTitle('مقرر کردہ جماعتیں',
                      icon: Icons.class_outlined),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in classes)
                        Chip(
                          label: Text(c.name),
                          avatar: const Icon(Icons.class_, size: 16),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _responsibilityCard(TenantRoleInfo? role) {
    final catalogAsync = ref.watch(permissionCatalogProvider);
    final catalog = catalogAsync.valueOrNull ?? const [];
    final overridesAsync = _overridesFuture();
    return FutureBuilder<Map<String, String>>(
      future: overridesAsync,
      builder: (context, snap) {
        final overrides = snap.data ?? const {};
        final effective = {
          for (final code in (role?.permissionCodes ?? const <String>{}))
            if (overrides[code] != 'deny') code,
          for (final entry in overrides.entries)
            if (entry.value == 'grant') entry.key,
        };
        final grouped = <String, List<PermissionInfo>>{};
        for (final p in catalog) {
          if (effective.contains(p.code)) {
            grouped.putIfAbsent(p.categoryUrdu, () => []).add(p);
          }
        }
        return UxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const UxSectionTitle('اختیارات کی فہرست',
                  icon: Icons.key_outlined),
              const SizedBox(height: 8),
              if (grouped.isEmpty)
                Text(
                  effective.isEmpty
                      ? 'اس صارف کے پاس فی الحال کوئی خاص اختیار نہیں۔'
                      : 'اختیارات لوڈ ہو رہے ہیں…',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(entry.key,
                      style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold)),
                ),
                for (final p in entry.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          overrides[p.code] == 'grant'
                              ? Icons.add_circle_outline
                              : Icons.check_circle_outline,
                          size: 18,
                          color: overrides[p.code] == 'grant'
                              ? AppColors.primary
                              : AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p.labelUrdu,
                              style: AppTypography.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, String>> _overridesFuture() async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) return const {};
    try {
      return await ref
          .read(roleUxRepositoryProvider)
          .userOverrides(tenantId: tenantId, userId: _user.id);
    } catch (_) {
      return const {};
    }
  }

  Widget _actionsCard() {
    return UxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UxSectionTitle('انتظام', icon: Icons.settings_outlined),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('ذمہ داریاں تبدیل کریں'),
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserWizardScreen.edit(user: _user),
                ),
              );
              if (updated == true && mounted) {
                showUxSnack(context, 'ذمہ داریاں محفوظ ہو گئیں');
              }
            },
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final canManage =
                  ref.watch(roleServiceProvider).canManageUsers();
              if (!canManage) return const SizedBox.shrink();
              return OutlinedButton.icon(
                icon: Icon(_user.isActive
                    ? Icons.person_off_outlined
                    : Icons.person_add_alt_outlined),
                label: Text(_user.isActive
                    ? 'صارف غیر فعال کریں'
                    : 'صارف فعال کریں'),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      _user.isActive ? AppColors.error : AppColors.success,
                ),
                onPressed: () => _toggleActive(),
              );
            },
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: Icon(_showActivity
                ? Icons.expand_less
                : Icons.history_outlined),
            label: Text(_showActivity ? 'سرگرمی چھپائیں' : 'سرگرمی دیکھیں'),
            onPressed: () =>
                setState(() => _showActivity = !_showActivity),
          ),
        ],
      ),
    );
  }

  Widget _activityCard() {
    return Consumer(
      builder: (context, ref, _) {
        final tenantId = ref.watch(currentTenantIdProvider);
        if (tenantId == null) return const SizedBox.shrink();
        return FutureBuilder<List<AuditRow>>(
          future: ref
              .read(roleUxRepositoryProvider)
              .userActivity(tenantId: tenantId, userId: _user.id),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const UxCard(
                  child:
                      Center(child: CircularProgressIndicator()));
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return const UxCard(
                child: UxEmptyState(
                  icon: Icons.history_outlined,
                  title: 'ابھی کوئی سرگرمی ریکارڈ نہیں',
                  hint:
                      'اس صارف کی سرگرمی یہاں نظر آئے گی جب وہ کام شروع کرے گا۔',
                ),
              );
            }
            return UxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const UxSectionTitle('حالیہ سرگرمی',
                      icon: Icons.history_outlined),
                  const SizedBox(height: 8),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.fiber_manual_record,
                              size: 10, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _auditUrdu(r, _user.id),
                                  style: AppTypography.bodyMedium,
                                ),
                                Text(
                                  _dateUrdu(r.createdAt),
                                  style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleActive() async {
    final ok = await confirmUxAction(
      context,
      title: _user.isActive ? 'صارف غیر فعال کریں' : 'صارف فعال کریں',
      message: _user.isActive
          ? '${_user.name} لاگ اِن نہیں کر سکے گا/گی — کیا آپ جاری رکھنا چاہتے ہیں؟'
          : '${_user.name} کو دوبارہ فعال کیا جائے گا۔',
      confirmLabel: 'جی ہاں، جاری رکھیں',
    );
    if (!ok || !mounted) return;
    final err = await ref
        .read(roleUxControllerProvider.notifier)
        .setUserActive(_user, !_user.isActive);
    if (!mounted) return;
    if (err == null) {
      showUxSnack(context,
          _user.isActive ? 'صارف غیر فعال کر دیا گیا' : 'صارف فعال کر دیا گیا');
      setState(() => _user = TenantUser(
            id: _user.id,
            name: _user.name,
            email: _user.email,
            phone: _user.phone,
            roleKey: _user.roleKey,
            roleUrdu: _user.roleUrdu,
            isActive: !_user.isActive,
            banned: _user.banned,
            lastSignInAt: _user.lastSignInAt,
            createdAt: _user.createdAt,
          ));
    } else {
      showUxSnack(context, err, isError: true);
    }
  }

  /// audit_logs rows -> plain Urdu (action codes stay server-side only).
  /// [viewerId] is the user whose detail screen this is: rows acted upon
  /// by someone else are phrased passively ("کا اکاؤنٹ بنایا گیا").
  String _auditUrdu(AuditRow r, String viewerId) {
    final a = r.action.toLowerCase();
    final byOther = r.actorUserId != null && r.actorUserId != viewerId;
    if (byOther) {
      if (a.contains('create_user')) return 'ان کا اکاؤنٹ بنایا گیا';
      if (a.contains('assign') || a.contains('role')) {
        return 'ان کی ذمہ داری تبدیل کی گئی';
      }
      if (a.contains('set_active') || a.contains('deactivat')) {
        return 'ان کے اکاؤنٹ کی حیثیت تبدیل کی گئی';
      }
      if (a.contains('delete')) return 'ان کا اکاؤنٹ حذف کیا گیا';
      return 'ان کے اکاؤنٹ پر عمل کیا گیا';
    }
    if (a.contains('login')) return 'لاگ اِن کیا';
    if (a.contains('logout')) return 'لاگ آؤٹ کیا';
    if (a.contains('create')) return 'نیا ریکارڈ بنایا';
    if (a.contains('update')) return 'ریکارڈ اپ ڈیٹ کیا';
    if (a.contains('delete')) return 'ریکارڈ حذف کیا';
    if (a.contains('attendance')) return 'حاضری درج کی';
    if (a.contains('result')) return 'نتائج درج کیے';
    if (a.contains('fee')) return 'فیس سے متعلق عمل کیا';
    return r.entity?.isNotEmpty == true ? 'عمل: ${r.entity}' : 'سرگرمی';
  }

  static String _dateUrdu(DateTime d) {
    const months = [
      '',
      'جنوری',
      'فروری',
      'مارچ',
      'اپریل',
      'مئی',
      'جون',
      'جولائی',
      'اگست',
      'ستمبر',
      'اکتوبر',
      'نومبر',
      'دسمبر'
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}
