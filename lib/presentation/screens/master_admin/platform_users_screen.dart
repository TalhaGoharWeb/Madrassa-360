/// پلیٹ فارم صارفین
/// Master Admin — manage platform operators (platform_admins).
///
/// - Lists all platform_admins with their role.
/// - Adding: inserts a row (platform_support only via UI; platform_owner
///   elevation is intentionally not offered here).
/// - Removing a platform_support: single confirm dialog.
/// - Removing a platform_owner: TYPED confirmation (mission §49/§50) AND
///   the last remaining platform_owner cannot be removed (fail-safe).
///
/// Phase 10: shell-hosted destination — the nested Scaffold/AppBar/FAB
/// became PageContainer + PageHeader; dialogs and snackbars use the m360
/// components. Query, guard, and typed-confirmation semantics are
/// unchanged.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

class PlatformUsersScreen extends StatefulWidget {
  const PlatformUsersScreen({super.key});

  @override
  State<PlatformUsersScreen> createState() => _PlatformUsersScreenState();
}

class _PlatformUsersScreenState extends State<PlatformUsersScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _admins = [];
  String? _myUid;

  @override
  void initState() {
    super.initState();
    _myUid = _client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Try to join display names via profiles; fall back to bare rows if
      // the PostgREST embed is unavailable (platform_admins has no FK to
      // profiles — user_id references auth.users only).
      List<Map<String, dynamic>> rows;
      try {
        final embedded = await _client
            .from('platform_admins')
            .select('user_id, role, profiles ( name )')
            .order('role');
        rows = List<Map<String, dynamic>>.from(embedded);
      } catch (_) {
        final plain = await _client
            .from('platform_admins')
            .select('user_id, role')
            .order('role');
        rows = List<Map<String, dynamic>>.from(plain);
      }
      _admins = rows;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _ownerCount =>
      _admins.where((a) => a['role'] == 'platform_owner').length;

  // ── Add platform_support ────────────────────────────────────────────
  //
  // Client-side email → auth-uuid resolution is impossible without the
  // service key (removed as a P0 security fix), so the supported flow is:
  // the operator pastes the new support user's Auth UUID (Supabase
  // Dashboard → Authentication → Users). The user must have signed in at
  // least once so their profiles row exists.
  Future<void> _addSupport() async {
    final idCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final ok = await showM360Dialog<bool>(
      context,
      title: 'Add platform_support',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          M360TextField(
            controller: emailCtrl,
            label: 'ای میل / Email (for your reference)',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 10),
          M360TextField(
            controller: idCtrl,
            label: 'Auth user UUID *',
            hint: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
          ),
          const SizedBox(height: 8),
          Text(
            'Supabase Dashboard → Authentication → Users سے UUID کاپی '
            'کریں۔ صارف کو کم از کم ایک بار سائن اِن ہونا چاہیے۔',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: 'منسوخ',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        M360PrimaryButton(
          label: 'platform_support بنائیں',
          onPressed: () {
            final id = idCtrl.text.trim();
            final uuidOk =
                RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                    .hasMatch(id);
            if (!uuidOk) {
              showM360SnackBar(context, 'درست UUID لکھیں', isError: true);
              return;
            }
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );
    final uid = idCtrl.text.trim();
    idCtrl.dispose();
    emailCtrl.dispose();
    if (ok != true) return;

    try {
      await _client.from('platform_admins').insert({
        'user_id': uid,
        'role': 'platform_support',
      });
      if (mounted) {
        showM360SnackBar(context, 'platform_support شامل ہو گیا');
      }
      _load();
    } catch (e) {
      if (mounted) {
        showM360SnackBar(context, 'Insert failed: $e', isError: true);
      }
    }
  }

  // ── Remove ──────────────────────────────────────────────────────────
  Future<void> _remove(Map<String, dynamic> admin) async {
    final uid = admin['user_id'] as String;
    final role = (admin['role'] as String?) ?? '';
    final profile = admin['profiles'] as Map<String, dynamic>?;
    final label = (profile?['name'] as String?)?.isNotEmpty == true
        ? profile!['name'] as String
        : uid.substring(0, 8);

    if (uid == _myUid) {
      if (mounted) {
        showM360SnackBar(context, 'آپ اپنا اکاؤنٹ خود نہیں ہٹا سکتے',
            isError: true);
      }
      return;
    }

    if (role == 'platform_owner') {
      if (_ownerCount <= 1) {
        if (mounted) {
          showM360SnackBar(
              context,
              'آخری platform_owner کو ہٹایا نہیں جا سکتا — پہلے کسی '
              'اور کو owner بنائیں',
              isError: true);
        }
        return;
      }
      // TYPED confirmation for platform_owner removal (§49/§50).
      final typed = await showM360ConfirmDialog(
        context,
        title: 'platform_owner ہٹائیں — تصدیق',
        message: 'آپ "$label" کو platform_owner سے ہٹا رہے ہیں۔ تصدیق '
            'کے لیے بالکل یہی لکھیں:\nREMOVE OWNER',
        confirmLabel: 'ہٹائیں',
        cancelLabel: 'منسوخ',
        danger: true,
        requireTypedConfirmation: true,
        expectedText: 'REMOVE OWNER',
        typedHint: 'REMOVE OWNER لکھیں',
      );
      if (!typed) return;
    } else {
      final confirm = await showM360ConfirmDialog(
        context,
        title: 'platform_support ہٹائیں؟',
        message: 'Remove platform_support access for "$label"?',
        confirmLabel: 'ہٹائیں',
        cancelLabel: 'منسوخ',
        danger: true,
      );
      if (!confirm) return;
    }

    try {
      await _client.from('platform_admins').delete().eq('user_id', uid);
      if (mounted) {
        showM360SnackBar(context, 'ہٹا دیا گیا');
      }
      _load();
    } catch (e) {
      if (mounted) {
        showM360SnackBar(context, 'Remove failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Shell-hosted destination: no Scaffold of its own.
    if (_loading) {
      return const M360LoadingState();
    }
    if (_error != null) {
      return M360ErrorState(message: _error!, onRetry: _load);
    }
    return PageContainer(
      scrollable: false,
      header: PageHeader(
        title: 'پلیٹ فارم صارفین',
        description: 'پلیٹ فارم آپریٹرز — کردار دیکھیں، سپورٹ شامل/ہٹائیں',
        actions: [
          M360PrimaryButton(
            label: 'Add support',
            icon: Icons.person_add,
            onPressed: _addSupport,
          ),
        ],
      ),
      child: _admins.isEmpty
          ? const M360EmptyState(
              icon: Icons.admin_panel_settings_outlined,
              title: 'کوئی پلیٹ فارم ایڈمن نہیں',
              description: 'platform_admins is empty. Add the first '
                  'platform_support (bootstrapping the first owner '
                  'requires a DB superuser — see migration 004 notes).',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _admins.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final a = _admins[i];
                  final role = (a['role'] as String?) ?? '';
                  final isOwner = role == 'platform_owner';
                  final isSelf = a['user_id'] == _myUid;
                  final profile = a['profiles'] as Map<String, dynamic>?;
                  final name = (profile?['name'] as String?)?.isNotEmpty == true
                      ? profile!['name'] as String
                      : '—';
                  return M360Card(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            (isOwner ? AppColors.warning : AppColors.primary)
                                .withValues(alpha: 0.15),
                        child: Icon(
                          isOwner
                              ? Icons.shield
                              : Icons.admin_panel_settings_outlined,
                          color:
                              isOwner ? AppColors.warning : AppColors.primary,
                        ),
                      ),
                      title: Text(name,
                          style: AppTypography.titleMedium
                              .copyWith(fontWeight: FontWeight.w600)),
                      subtitle: M360LatinText(
                        '${a['user_id']}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          M360Badge.custom(
                            label: role,
                            color: isOwner ? AppColors.warning : AppColors.info,
                          ),
                          if (isSelf)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                '(you)',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          if (!isSelf)
                            M360IconButton(
                              icon: Icons.person_remove_outlined,
                              tooltip: 'Remove',
                              color: AppColors.error,
                              onPressed: () => _remove(a),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
