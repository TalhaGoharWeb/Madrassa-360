/// مدرسے کا لوگو — انتظام اسکرین
/// Madrassa logo management screen.
///
/// Lets the madrassa owner (mohtamim / tenant_owner / tenant_admin) upload,
/// change, or remove the madrassa logo, and toggle whether it appears on
/// generated reports, report cards, receipts, and other documents.
///
/// Urdu-first, RTL. All short labels use Nastaleeq (≥15sp).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/role_service.dart';
import '../../../core/services/tenant_context.dart';
import '../../../services/tenant_logo_service.dart';

class MadrassaLogoScreen extends ConsumerStatefulWidget {
  const MadrassaLogoScreen({super.key});

  @override
  ConsumerState<MadrassaLogoScreen> createState() => _MadrassaLogoScreenState();
}

class _MadrassaLogoScreenState extends ConsumerState<MadrassaLogoScreen> {
  bool _busy = false;

  bool get _canManage {
    final roles = ref.watch(roleServiceProvider);
    return roles.isTenantOwner() ||
        roles.isTenantAdmin() ||
        roles.activeRoleKeys().contains('mohtamim');
  }

  Future<void> _pickAndUpload(String tenantId) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(tenantLogoServiceProvider).uploadLogo(tenantId, picked);
      ref.invalidate(tenantLogoUrlProvider(tenantId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لوگو کامیابی سے اپ لوڈ ہو گیا',
              style: AppTypography.labelNastaliq,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لوگو اپ لوڈ ناکام: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String tenantId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('لوگو ہٹائیں؟', style: AppTypography.labelNastaliq),
        content: Text(
          'مدرسے کا لوگو ہٹا دیا جائے گا۔ رپورٹس پر دوبارہ معیاری نشان نظر آئے گا۔',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('منسوخ کریں', style: AppTypography.labelNastaliq),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('ہٹائیں', style: AppTypography.labelNastaliq),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(tenantLogoServiceProvider).removeLogo(tenantId);
      ref.invalidate(tenantLogoUrlProvider(tenantId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لوگو ہٹا دیا گیا', style: AppTypography.labelNastaliq),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لوگو ہٹانا ناکام: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleUseOnReports(String tenantId, bool use) async {
    try {
      await ref
          .read(tenantLogoServiceProvider)
          .setUseLogoOnReports(tenantId, use);
      ref.invalidate(useLogoOnReportsProvider(tenantId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ترتیب محفوظ ناکام: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(currentTenantIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('مدرسے کا لوگو', style: AppTypography.appBarTitle),
        centerTitle: true,
      ),
      body: tenantId == null
          ? Center(
              child: Text(
                'پہلے اپنا مدرسہ منتخب کریں',
                style: AppTypography.labelNastaliq,
              ),
            )
          : !_canManage
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے',
                          style: AppTypography.labelNastaliq,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'لوگو کا انتظام صرف مہتمم یا ناظم کر سکتا ہے۔',
                          style: AppTypography.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : _logoManager(tenantId),
    );
  }

  Widget _logoManager(String tenantId) {
    final logoUrlAsync = ref.watch(tenantLogoUrlProvider(tenantId));
    final useOnReportsAsync = ref.watch(useLogoOnReportsProvider(tenantId));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Current logo preview ─────────────────────────────
        Center(
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: logoUrlAsync.when(
                data: (url) => url == null
                    ? _placeholder()
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => _placeholder(),
                        errorWidget: (_, __, ___) => _placeholder(),
                      ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => _placeholder(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'موجودہ لوگو',
            style: AppTypography.labelNastaliq,
          ),
        ),
        const SizedBox(height: 24),

        // ── Upload / change button ───────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                _busy ? null : () => _pickAndUpload(tenantId),
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.upload),
            label: Text(
              logoUrlAsync.valueOrNull == null
                  ? 'لوگو اپ لوڈ کریں'
                  : 'لوگو تبدیل کریں',
              style: AppTypography.labelNastaliq
                  .copyWith(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Remove button ────────────────────────────────────
        if (logoUrlAsync.valueOrNull != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _remove(tenantId),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: Text(
                'لوگو ہٹائیں',
                style: AppTypography.labelNastaliq
                    .copyWith(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        const SizedBox(height: 24),

        // ── Use on reports toggle ────────────────────────────
        Card(
          child: SwitchListTile(
            title: Text(
              'رپورٹس پر لوگو استعمال کریں',
              style: AppTypography.labelNastaliq,
            ),
            subtitle: Text(
              'فعال ہونے پر آپ کا لوگو رپورٹ کارڈز، فیس رسیدوں اور تمام تیار کردہ دستاویزات پر نظر آئے گا۔',
              style: AppTypography.bodySmall,
            ),
            value: useOnReportsAsync.valueOrNull ?? true,
            activeColor: AppColors.primary,
            onChanged: (v) => _toggleUseOnReports(tenantId, v),
          ),
        ),
        const SizedBox(height: 16),

        // ── Hint ─────────────────────────────────────────────
        Text(
          'بہترین نتیجے کے لیے مربع (square) تصویر استعمال کریں۔ لوگو خودکار طور پر رپورٹس کے لیے محفوظ ہو جاتا ہے، انٹرنیٹ کے بغیر بھی۔',
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Icon(
        Icons.mosque,
        size: 64,
        color: AppColors.primary.withValues(alpha: 0.5),
      ),
    );
  }
}
