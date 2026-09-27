/// کرایہ دار کا انتظام
/// Tenant management — suspend/unsuspend, SaaS expiry timer, broadcast
/// message. All destructive actions confirm first; every control is
/// Urdu-first RTL.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/date_utils.dart' as app_date;
import '../../../services/super_admin_service.dart';

class TenantDetailScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const TenantDetailScreen({super.key, required this.tenantId});

  @override
  ConsumerState<TenantDetailScreen> createState() =>
      _TenantDetailScreenState();
}

class _TenantDetailScreenState extends ConsumerState<TenantDetailScreen> {
  Future<Tenant?>? _tenantFuture;
  bool _busy = false;

  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _tenantFuture =
          ref.read(superAdminServiceProvider).getTenant(widget.tenantId);
    });
  }

  SuperAdminService get _svc => ref.read(superAdminServiceProvider);

  Future<void> _runGuarded(Future<void> Function() action, String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(okMsg, style: AppTypography.bodyMedium)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خرابی: $e', style: AppTypography.bodyMedium),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('مدرسے کا انتظام', style: AppTypography.appBarTitle),
        centerTitle: true,
      ),
      body: FutureBuilder<Tenant?>(
        future: _tenantFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final tenant = snap.data;
          if (tenant == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('مدرسہ نہیں ملا', style: AppTypography.titleMedium),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _reload,
                    child: Text('دوبارہ کوشش کریں',
                        style: AppTypography.buttonText),
                  ),
                ],
              ),
            );
          }
          // Seed the message field once per tenant load.
          if (_messageController.text.isEmpty &&
              (tenant.adminMessage ?? '').isNotEmpty) {
            _messageController.text = tenant.adminMessage!;
          }
          return _body(tenant);
        },
      ),
    );
  }

  Widget _body(Tenant t) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoCard(t),
            const SizedBox(height: 16),
            _suspendCard(t),
            const SizedBox(height: 16),
            _expiryCard(t),
            const SizedBox(height: 16),
            _messageCard(t),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Info ──────────────────────────────────────────────────────────

  Widget _infoCard(Tenant t) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance,
                      color: AppColors.primary, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.displayName,
                          style: AppTypography.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (t.name.isNotEmpty && t.urduName.isNotEmpty)
                        Text(t.name,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _infoRow('حیثیت', t.isSuspended ? 'معطل' : t.isExpired ? 'میعاد ختم' : 'فعال'),
            _infoRow('اراکین', '${t.memberCount}'),
            if (t.createdAt != null)
              _infoRow('شمولیت', app_date.DateUtils.formatDateUrdu(t.createdAt!)),
            if (t.expiresAt != null)
              _infoRow('میعاد', app_date.DateUtils.formatDateUrdu(t.expiresAt!)),
            if ((t.suspensionReason ?? '').isNotEmpty)
              _infoRow('معطلی کی وجہ', t.suspensionReason!),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 16, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: AppTypography.bodyMedium, softWrap: true),
          ),
        ],
      ),
    );
  }

  // ── Suspend / unsuspend ───────────────────────────────────────────

  Widget _suspendCard(Tenant t) {
    final suspended = t.isSuspended;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  suspended ? Icons.block : Icons.check_circle_outline,
                  color: suspended ? AppColors.error : AppColors.success,
                ),
                const SizedBox(width: 8),
                Text('رسائی کا انتظام',
                    style: AppTypography.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              suspended
                  ? 'یہ مدرسہ فی الحال معطل ہے۔ صارفین ایپ استعمال نہیں کر سکتے۔'
                  : 'مدرسے کی رسائی معطل کرنے سے تمام صارفین کا داخلہ فوراً بند ہو جائے گا۔',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy
                    ? null
                    : () => suspended
                        ? _confirmUnsuspend(t)
                        : _showSuspendDialog(t),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      suspended ? AppColors.success : AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(suspended ? Icons.check_circle : Icons.block),
                label: Text(
                  suspended ? 'رسائی بحال کریں' : 'رسائی معطل کریں',
                  style: AppTypography.buttonText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSuspendDialog(Tenant t) async {
    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('رسائی معطل کریں', style: AppTypography.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('معطلی کی وجہ درج کریں (صارف کو دکھائی جائے گی):',
                style: AppTypography.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'مثلاً: واجب الادا فیس کی عدم ادائیگی',
                hintStyle: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('منسوخ کریں', style: AppTypography.buttonText.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                      content: Text('براہ کرم وجہ درج کریں',
                          style: AppTypography.bodyMedium)),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: Text('معطل کریں', style: AppTypography.buttonText),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (ok == true && mounted) {
      await _runGuarded(
        () => _svc.suspendTenant(t.id, reasonController.text),
        'مدرسے کی رسائی معطل کر دی گئی',
      );
    }
  }

  Future<void> _confirmUnsuspend(Tenant t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('رسائی بحال کریں', style: AppTypography.titleMedium),
        content: Text(
          'کیا آپ واقعی "${t.displayName}" کی رسائی بحال کرنا چاہتے ہیں؟',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('منسوخ کریں', style: AppTypography.buttonText.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('بحال کریں', style: AppTypography.buttonText),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _runGuarded(
        () => _svc.unsuspendTenant(t.id),
        'مدرسے کی رسائی بحال کر دی گئی',
      );
    }
  }

  // ── Expiry timer ──────────────────────────────────────────────────

  Widget _expiryCard(Tenant t) {
    final days = t.daysRemaining;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: AppColors.warning),
                const SizedBox(width: 8),
                Text('میعاد کا ٹائمر', style: AppTypography.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (t.expiresAt == null)
              Text('کوئی میعاد مقرر نہیں — لامحدود رسائی۔',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary))
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (days != null && days < 0
                          ? AppColors.error
                          : AppColors.warning)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  days == null
                      ? 'میعاد: ${app_date.DateUtils.formatDateUrdu(t.expiresAt!)}'
                      : days < 0
                          ? 'میعاد ختم ہو چکی ہے (${-days} دن پہلے)'
                          : days == 0
                              ? 'آج آخری دن ہے!'
                              : '$days دن باقی ہیں',
                  style: AppTypography.labelNastaliq.copyWith(
                    fontSize: 17,
                    color: days != null && days < 0
                        ? AppColors.error
                        : AppColors.warning,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 12),
            Text('فوری مدت منتخب کریں:',
                style: AppTypography.labelNastaliq
                    .copyWith(fontSize: 16, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _quickExpiry('7 دن', const Duration(days: 7), t),
                _quickExpiry('30 دن', const Duration(days: 30), t),
                _quickExpiry('90 دن', const Duration(days: 90), t),
                _quickExpiry('1 سال', const Duration(days: 365), t),
                _quickExpiry('2 سال', const Duration(days: 730), t),
                _quickExpiry('5 سال', const Duration(days: 1825), t),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickExpiryDate(t),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('تاریخ منتخب کریں',
                        style: AppTypography.buttonText
                            .copyWith(color: AppColors.primary)),
                  ),
                ),
                if (t.expiresAt != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _runGuarded(
                                () => _svc.clearTenantExpiry(t.id),
                                'میعاد ختم کر دی گئی (لامحدود رسائی)',
                              ),
                      icon: const Icon(Icons.clear,
                          color: AppColors.textSecondary),
                      label: Text('میعاد صاف کریں',
                          style: AppTypography.buttonText
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickExpiry(String label, Duration duration, Tenant t) {
    return ActionChip(
      label: Text(label,
          style: AppTypography.labelNastaliq
              .copyWith(fontSize: 15, color: AppColors.primary)),
      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
      onPressed: _busy
          ? null
          : () => _runGuarded(
                () => _svc.setTenantExpiry(
                    t.id, DateTime.now().add(duration)),
                'میعاد مقرر کر دی گئی: $label',
              ),
    );
  }

  Future<void> _pickExpiryDate(Tenant t) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: t.expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      helpText: 'میعاد کی تاریخ منتخب کریں',
      cancelText: 'منسوخ کریں',
      confirmText: 'منتخب کریں',
    );
    if (picked != null && mounted) {
      await _runGuarded(
        () => _svc.setTenantExpiry(t.id, picked),
        'میعاد مقرر کر دی گئی',
      );
    }
  }

  // ── Broadcast message ─────────────────────────────────────────────

  Widget _messageCard(Tenant t) {
    final hasMessage =
        t.adminMessage != null && t.adminMessage!.trim().isNotEmpty;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_outlined,
                    color: AppColors.primary),
                const SizedBox(width: 8),
                Text('اطلاعی پیغام', style: AppTypography.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'یہ پیغام مدرسے کے تمام ڈیش بورڈز کے اوپر ظاہر ہو گا (مثلاً ادائیگی کی یاد دہانی)۔',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'مثلاً: براہ کرم اپنی ماہانہ فیس جلد ادا کریں…',
                hintStyle: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            final msg = _messageController.text.trim();
                            if (msg.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('براہ کرم پیغام لکھیں',
                                        style:
                                            AppTypography.bodyMedium)),
                              );
                              return;
                            }
                            _runGuarded(
                              () => _svc.setTenantMessage(t.id, msg),
                              'پیغام شائع کر دیا گیا',
                            );
                          },
                    icon: const Icon(Icons.send_outlined),
                    label: Text('پیغام شائع کریں',
                        style: AppTypography.buttonText),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (hasMessage) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              _messageController.clear();
                              _runGuarded(
                                () => _svc.clearTenantMessage(t.id),
                                'پیغام ہٹا دیا گیا',
                              );
                            },
                      icon: const Icon(Icons.clear,
                          color: AppColors.textSecondary),
                      label: Text('پیغام ہٹائیں',
                          style: AppTypography.buttonText
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
