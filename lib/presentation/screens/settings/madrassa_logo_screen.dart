/// مدرسے کا لوگو — انتظام اسکرین
/// Madrassa logo management (per-tenant branding).
///
/// Lets a privileged user (platform admin or a tenant member holding
/// `settings.update`) upload / change / remove the madrassa's logo and
/// flip the "use logo on reports" toggle. The logo is stored in the
/// `tenant-logos` Supabase bucket (`<tenant_id>/logo.png`), its public URL
/// on `tenants.logo_url`, and the toggle on `tenants.use_logo_on_reports`
/// (migration 024).
///
/// Where the logo appears: the dashboard sidebar strip, the tenant header
/// on generated documents — certificates, result cards, fee receipts,
/// admission forms, ID cards, exam papers — via the offline report cache
/// ([cacheReportBranding]), and anywhere [TenantLogo] is used. When the
/// toggle is off (or no logo is set) documents draw the neutral emblem.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/observability/app_logger.dart';
import '../../../core/services/tenant_context.dart';
import '../../../core/widgets/tenant_logo.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/tenant_branding_provider.dart';
import '../../../services/tenant_logo_service.dart';
import 'role_ux_widgets.dart';

class MadrassaLogoScreen extends ConsumerStatefulWidget {
  const MadrassaLogoScreen({super.key});

  @override
  ConsumerState<MadrassaLogoScreen> createState() => _MadrassaLogoScreenState();
}

class _MadrassaLogoScreenState extends ConsumerState<MadrassaLogoScreen> {
  bool _busy = false;

  TenantLogoService get _service => TenantLogoService();

  Future<void> _pickAndUpload(String tenantId) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await _service.uploadLogo(tenantId, picked);
      ref.invalidate(tenantBrandingProvider);
      if (mounted) showUxSnack(context, 'لوگو کامیابی سے اپ لوڈ ہو گیا');
    } on TenantLogoDenied catch (e) {
      if (mounted) showUxSnack(context, e.message, isError: true);
    } catch (e) {
      AppLogger().error('Logo upload failed', error: e);
      if (mounted) {
        showUxSnack(context, 'لوگو اپ لوڈ ناکام — دوبارہ کوشش کریں',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String tenantId) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'لوگو ہٹائیں؟',
      message: 'مدرسے کا لوگو ہٹا دیا جائے گا۔ رپورٹس اور دستاویزات پر '
          'غیر جانبدار علامت نظر آئے گی۔',
      confirmLabel: 'ہٹائیں',
      danger: true,
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _service.removeLogo(tenantId);
      ref.invalidate(tenantBrandingProvider);
      if (mounted) showUxSnack(context, 'لوگو ہٹا دیا گیا');
    } catch (e) {
      AppLogger().error('Logo remove failed', error: e);
      if (mounted) {
        showUxSnack(context, 'لوگو ہٹانا ناکام — دوبارہ کوشش کریں',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleReports(String tenantId, bool value) async {
    setState(() => _busy = true);
    try {
      await _service.setUseLogoOnReports(tenantId, value);
      ref.invalidate(tenantBrandingProvider);
      if (mounted) {
        showUxSnack(
          context,
          value
              ? 'لوگو اب رپورٹس اور دستاویزات پر نظر آئے گا'
              : 'رپورٹس پر لوگو بند کر دیا گیا',
        );
      }
    } catch (e) {
      AppLogger().error('Logo toggle failed', error: e);
      if (mounted) {
        showUxSnack(context, 'تبدیلی ناکام — دوبارہ کوشش کریں', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManageLogo =
        ref.watch(hasPermissionProvider(AppPermissions.manageSettings));
    if (!canManageLogo) {
      return const Scaffold(
        appBar: M360AppBar(title: 'مدرسے کا لوگو'),
        body: UxEmptyState(
          icon: Icons.lock_outline,
          title: 'آپ کو یہ صفحہ دیکھنے کی اجازت نہیں ہے',
          hint: 'لوگو تبدیل کرنے کے لیے آپ کے پاس ترتیبات کی اجازت '
              'ہونی ضروری ہے۔',
        ),
      );
    }

    final tenantId = ref.watch(currentTenantIdProvider);
    if (tenantId == null || tenantId.isEmpty) {
      return const Scaffold(
        appBar: M360AppBar(title: 'مدرسے کا لوگو'),
        body: UxEmptyState(
          icon: Icons.business_outlined,
          title: 'کوئی مدرسہ منتخب نہیں',
          hint: 'پہلے اپنا مدرسہ منتخب کریں۔',
        ),
      );
    }

    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final hasLogo = branding?.hasLogo ?? false;

    return Scaffold(
      appBar: const M360AppBar(title: 'مدرسے کا لوگو'),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              // ── current logo ──
              Center(
                child: Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.divider.withValues(alpha: 0.7),
                    ),
                  ),
                  child: const Center(
                    child: TenantLogo(size: 120, radius: 20),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TenantNameText(
                  style: AppTypography.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  hasLogo
                      ? 'یہ لوگو ڈیش بورڈ اور دستاویزات پر نظر آئے گا'
                      : 'ابھی کوئی لوگو نہیں لگایا گیا',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // ── actions ──
              M360PrimaryButton(
                label: hasLogo ? 'لوگو تبدیل کریں' : 'لوگو لگائیں',
                icon: Icons.upload_outlined,
                onPressed: _busy ? null : () => _pickAndUpload(tenantId),
              ),
              if (hasLogo) ...[
                const SizedBox(height: 12),
                M360DangerButton(
                  label: 'لوگو ہٹائیں',
                  icon: Icons.delete_outline,
                  onPressed: _busy ? null : () => _remove(tenantId),
                ),
              ],
              const SizedBox(height: 20),

              // ── reports toggle ──
              const M360SectionHeader(title: 'دستاویزات'),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  value: branding?.useLogoOnReports ?? true,
                  onChanged: _busy ? null : (v) => _toggleReports(tenantId, v),
                  title: Text(
                    'رپورٹس اور دستاویزات پر لوگو دکھائیں',
                    style: AppTypography.labelNastaliq,
                  ),
                  subtitle: Text(
                    'سرٹیفکیٹ، رزلٹ کارڈ، فیس رسید، داخلہ فارم، '
                    'شناختی کارڈ اور امتحانی پرچے',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── where it appears ──
              const M360SectionHeader(title: 'رہنمائی'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '• لوگو ڈیش بورڈ کی سائیڈ بار میں مدرسے کے نام کے ساتھ '
                    'نظر آئے گا۔\n'
                    '• آن ہونے پر یہ ہر سرٹیفکیٹ، رزلٹ کارڈ، فیس رسید اور '
                    'امتحانی پرچے کے سرنامے (ہیڈر) میں چھپے گا۔\n'
                    '• لوگو آف لائن بھی دستاویزات پر نظر آئے گا۔',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      height: 2.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x52000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
