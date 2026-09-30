/// لائسنسز
/// Master Admin — licenses table view + REAL license operations.
///
/// - Read: real rows from public.licenses (platform admins: RLS FOR ALL).
/// - Revoke: real UPDATE status='cancelled' + log_audit('license.revoked'),
///   behind a typed destructive confirmation.
/// - Extend: real UPDATE expires_at + log_audit('license.extended').
/// - Status vocabulary comes from [licenseStatusFilters] (the exact CHECK
///   values in 011_licensing.sql) — the old bogus 'revoked' filter is gone.
/// - Never reports success unless the DB write actually persisted.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/repositories/license_repository.dart';
import 'widgets/ma_widgets.dart';

class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  late final LicenseRepository _repo;

  bool _loading = true;
  String? _error;
  String _status = 'all';
  String _query = '';
  List<LicenseRecord> _rows = [];

  @override
  void initState() {
    super.initState();
    _repo = LicenseRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows =
          await _repo.fetchLicenses(status: _status == 'all' ? null : _status);
    } on LicenseOperationException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  List<LicenseRecord> get _visible {
    if (_query.trim().isEmpty) return _rows;
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      return (r.tenantName ?? '').toLowerCase().contains(q) ||
          (r.tenantCode ?? '').toLowerCase().contains(q) ||
          (r.planName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openDetail(LicenseRecord record) async {
    // The detail dialog pops with a result token on success; the parent
    // owns the success snackbar (the dialog's context is dead by then).
    final result = await showM360Dialog<String>(
      context,
      title: 'لائسنس کی تفصیل',
      icon: Icons.verified_outlined,
      content: _LicenseDetailDialog(record: record, repo: _repo),
    );
    if (result == 'revoked') {
      _load();
      if (mounted) showM360SnackBar(context, 'لائسنس منسوخ کر دیا گیا۔');
    } else if (result == 'extended') {
      _load();
      if (mounted) showM360SnackBar(context, 'لائسنس کی میعاد بڑھا دی گئی۔');
    } else if (result == 'changed') {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: M360SearchField(
            hint: 'مدرسہ یا پلان تلاش کریں…',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        // Horizontal scroll + Row (instead of a fixed-height ListView) so
        // the strip grows naturally with large text scales.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (int i = 0; i < licenseStatusFilters.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Builder(builder: (context) {
                  final s = licenseStatusFilters[i];
                  final selected = s == _status;
                  return ChoiceChip(
                    label: Text(s == 'all' ? 'تمام' : licenseStatusUrdu(s),
                        style: AppTypography.labelNastaliq),
                    selected: selected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    onSelected: (_) {
                      setState(() => _status = s);
                      _load();
                    },
                  );
                }),
              ],
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingWidget(message: 'لائسنس لوڈ ہو رہے ہیں…');
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'licenses دستیاب نہیں',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _load,
      );
    }
    final rows = _visible;
    if (rows.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.verified_outlined,
        title: 'کوئی لائسنس نہیں',
        message: 'موجودہ فلٹر سے کوئی لائسنس نہیں ملا۔ '
            'لائسنس provision-tenant سے خودکار جاری ہوتے ہیں۔',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _row(rows[i]),
      ),
    );
  }

  Widget _row(LicenseRecord r) {
    return InkWell(
      borderRadius: BorderRadius.circular(M360Radius.md),
      onTap: () => _openDetail(r),
      child: M360Card(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        child: ListTile(
          leading:
              const Icon(Icons.verified, color: AppColors.primary, size: 32),
          title: Text(
            r.tenantName ?? r.tenantId ?? '—',
            style:
                AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'پلان: ${r.planName ?? '—'}  •  '
            'اختتام: ${r.expiresAt != null ? _day(r.expiresAt!) : '—'}',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          trailing: MaStatusChip(status: r.status),
        ),
      ),
    );
  }

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// License detail + real revoke/extend actions.
///
/// Pops `true` when a write succeeded so the list reloads. Success is
/// reported only after the repository confirms the DB write persisted.
class _LicenseDetailDialog extends StatefulWidget {
  final LicenseRecord record;
  final LicenseRepository repo;

  const _LicenseDetailDialog({required this.record, required this.repo});

  @override
  State<_LicenseDetailDialog> createState() => _LicenseDetailDialogState();
}

class _LicenseDetailDialogState extends State<_LicenseDetailDialog> {
  bool _busy = false;
  String? _error;

  LicenseRecord get _r => widget.record;

  String get _tenantLabel =>
      _r.tenantName ?? _r.tenantCode ?? _r.tenantId ?? '—';

  Future<void> _revoke() async {
    // Typed destructive confirmation — the button stays disabled until
    // the operator types the tenant name exactly.
    final typedName = (_r.tenantName?.trim().isNotEmpty ?? false)
        ? _r.tenantName!.trim()
        : _r.id;
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'لائسنس منسوخ کریں',
      message: 'کیا آپ واقعی "$_tenantLabel" کا لائسنس منسوخ کرنا چاہتے ہیں؟ '
          'اس کے بعد یہ مدرسہ سسٹم استعمال نہیں کر سکے گا۔ یہ عمل آڈٹ لاگ میں درج ہو گا۔',
      confirmLabel: 'منسوخ کریں',
      danger: true,
      requireTypedConfirmation: true,
      expectedText: typedName,
      typedHint: 'تصدیق کے لیے مدرسے کا نام لکھیں',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.revokeLicense(_r);
      if (!mounted) return;
      // Pop with the result token — the parent shows the success
      // snackbar on its own (live) context.
      Navigator.of(context).pop('revoked');
    } on LicenseOperationException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _extend() async {
    final picked = await showM360DatePicker(
      context,
      initialDate: _r.expiresAt != null
          ? _r.expiresAt!.add(const Duration(days: 30))
          : DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'نئی میعاد ختم کی تاریخ',
    );
    if (picked == null || !mounted) return;
    final newExpiry = DateTime(picked.year, picked.month, picked.day);
    // Typed confirmation — same guard as revoke: the operator must type
    // the exact tenant name before a license write can proceed.
    final typedName = (_r.tenantName?.trim().isNotEmpty ?? false)
        ? _r.tenantName!.trim()
        : _r.id;
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'میعاد بڑھائیں',
      message: '"$_tenantLabel" کے لائسنس کی میعاد '
          '${newExpiry.year}-${newExpiry.month.toString().padLeft(2, '0')}-'
          '${newExpiry.day.toString().padLeft(2, '0')} تک بڑھا دی جائے؟ '
          'یہ عمل آڈٹ لاگ میں درج ہو گا۔',
      confirmLabel: 'میعاد بڑھائیں',
      requireTypedConfirmation: true,
      expectedText: typedName,
      typedHint: 'تصدیق کے لیے مدرسے کا نام لکھیں',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.extendLicense(_r, newExpiry);
      if (!mounted) return;
      Navigator.of(context).pop('extended');
    } on LicenseOperationException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Plain content column — showM360Dialog already provides the
    // M360Dialog chrome; the action buttons live here so they can
    // react to the busy/error state.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kv('مدرسہ', _tenantLabel),
        _kv('مدرسہ کوڈ', _r.tenantCode),
        _kv('پلان', _r.planName),
        _kv('حالت', licenseStatusUrdu(_r.status)),
        _kv('جاری ہوا', _r.issuedAt != null ? _day(_r.issuedAt!) : null),
        _kv('میعاد ختم', _r.expiresAt != null ? _day(_r.expiresAt!) : null),
        _kv('زیادہ سے زیادہ صارفین', _r.maxUsers),
        _kv('زیادہ سے زیادہ طلبہ', _r.maxStudents),
        _kv('فعال ماڈیولز',
            _r.enabledModules.isEmpty ? null : _r.enabledModules.join(', ')),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            M360TertiaryButton(
              label: 'بند کریں',
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            if (!_r.isCancelled)
              M360DangerButton(
                label: 'لائسنس منسوخ کریں',
                icon: Icons.cancel_outlined,
                onPressed: _busy ? null : _revoke,
              ),
            // Orange primary CTA: the constructive action.
            M360PrimaryButton(
              label: 'میعاد بڑھائیں',
              icon: Icons.event_available_outlined,
              isLoading: _busy,
              onPressed: _busy ? null : _extend,
            ),
          ],
        ),
      ],
    );
  }

  Widget _kv(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Flexible(
            child: Text((value ?? '—').toString(),
                style: AppTypography.bodySmall
                    .copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
