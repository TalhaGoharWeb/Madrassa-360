/// پلیٹ فارم صارفین
/// Master Admin — manage platform operators (platform_admins).
///
/// - Lists all platform_admins with their role.
/// - Adding: inserts a row (platform_support only via UI; platform_owner
///   elevation is intentionally not offered here).
/// - Removing a platform_support: single confirm dialog.
/// - Removing a platform_owner: TYPED confirmation (mission §49/§50) AND
///   the last remaining platform_owner cannot be removed (fail-safe).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add platform_support'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'ای میل / Email (for your reference)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: 'Auth user UUID *',
                  hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                ),
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
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('منسوخ')),
          ElevatedButton(
            onPressed: () {
              final id = idCtrl.text.trim();
              final uuidOk = RegExp(
                      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                  .hasMatch(id);
              if (!uuidOk) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('درست UUID لکھیں')));
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('platform_support بنائیں'),
          ),
        ],
      ),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('platform_support شامل ہو گیا')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Insert failed: $e')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('آپ اپنا اکاؤنٹ خود نہیں ہٹا سکتے')));
      }
      return;
    }

    if (role == 'platform_owner') {
      if (_ownerCount <= 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'آخری platform_owner کو ہٹایا نہیں جا سکتا — پہلے کسی '
                  'اور کو owner بنائیں')));
        }
        return;
      }
      // TYPED confirmation for platform_owner removal (§49/§50).
      final typed = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              title: const Text('platform_owner ہٹائیں — تصدیق'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'آپ "$label" کو platform_owner سے ہٹا رہے ہیں۔ تصدیق '
                    'کے لیے بالکل یہی لکھیں:\nREMOVE OWNER',
                    style: AppTypography.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    onChanged: (_) => setS(() {}),
                    decoration: const InputDecoration(
                        labelText: 'REMOVE OWNER لکھیں'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('منسوخ')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error),
                  onPressed: ctrl.text.trim() == 'REMOVE OWNER'
                      ? () => Navigator.of(ctx).pop(ctrl.text.trim())
                      : null,
                  child: const Text('ہٹائیں'),
                ),
              ],
            ),
          );
        },
      );
      if (typed == null) return;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('platform_support ہٹائیں؟'),
          content: Text('Remove platform_support access for "$label"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('منسوخ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('ہٹائیں'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    try {
      await _client.from('platform_admins').delete().eq('user_id', uid);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ہٹا دیا گیا')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingWidget(message: 'صارفین لوڈ ہو رہے ہیں…');
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'خرابی / Error',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _load,
      );
    }
    return Scaffold(
      body: _admins.isEmpty
          ? const EmptyStateWidget(
              icon: Icons.admin_panel_settings_outlined,
              title: 'کوئی پلیٹ فارم ایڈمن نہیں',
              message: 'platform_admins is empty. Add the first '
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
                  final profile =
                      a['profiles'] as Map<String, dynamic>?;
                  final name =
                      (profile?['name'] as String?)?.isNotEmpty == true
                          ? profile!['name'] as String
                          : '—';
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (isOwner
                                ? AppColors.warning
                                : AppColors.primary)
                            .withOpacity(0.15),
                        child: Icon(
                          isOwner
                              ? Icons.shield
                              : Icons.admin_panel_settings_outlined,
                          color: isOwner
                              ? AppColors.warning
                              : AppColors.primary,
                        ),
                      ),
                      title: Text(name,
                          style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${a['user_id']}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isOwner
                                      ? AppColors.warning
                                      : AppColors.info)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              role,
                              style: AppTypography.labelSmall.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isOwner
                                    ? AppColors.warning
                                    : AppColors.info,
                              ),
                            ),
                          ),
                          if (isSelf)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text('(you)',
                                  style:
                                      TextStyle(color: AppColors.textSecondary)),
                            ),
                          if (!isSelf)
                            IconButton(
                              icon: const Icon(Icons.person_remove_outlined,
                                  color: AppColors.error),
                              tooltip: 'Remove',
                              onPressed: () => _remove(a),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSupport,
        icon: const Icon(Icons.person_add),
        label: const Text('Add support'),
      ),
    );
  }
}
