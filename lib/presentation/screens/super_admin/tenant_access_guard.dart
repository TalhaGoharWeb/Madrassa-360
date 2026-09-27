/// کرایہ دار رسائی محافظ
/// Tenant access guard — wraps tenant home content.
///
/// On every build it checks the active tenant's SaaS state:
///   - suspended → full-screen Urdu suspension notice (with reason)
///   - expired   → full-screen Urdu expiry notice
///   - admin_message set → dismissible banner above the child
///
/// The check fails OPEN (shows the child) on any error: a network/RLS
/// failure must never false-lock a tenant out. Server-side RLS remains
/// the real enforcement.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../services/super_admin_service.dart';

class TenantAccessGuard extends ConsumerStatefulWidget {
  final Widget child;

  const TenantAccessGuard({super.key, required this.child});

  @override
  ConsumerState<TenantAccessGuard> createState() =>
      _TenantAccessGuardState();
}

class _TenantAccessGuardState extends ConsumerState<TenantAccessGuard> {
  /// Dismissed message cache: tenantId -> message text (so re-checks
  /// don't resurrect a dismissed banner within the session).
  final Map<String, String> _dismissed = {};

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(currentTenantIdProvider);
    if (tenantId == null || tenantId.isEmpty) {
      // No tenant context (e.g. platform operator) — nothing to gate.
      return widget.child;
    }

    final access = ref.watch(tenantAccessProvider(tenantId));
    return access.when(
      data: (status) => _render(status, tenantId),
      loading: () => widget.child,
      // Fail open on error — never false-lock on a network/RLS failure.
      error: (_, __) => widget.child,
    );
  }

  Widget _render(TenantAccessStatus status, String tenantId) {
    if (status.suspended) return _suspendedScreen(status);
    if (status.expired) return _expiredScreen(status);
    if (status.hasMessage) {
      final msg = status.adminMessage!.trim();
      if (_dismissed[tenantId] != msg) {
        return Column(
          children: [
            _messageBanner(msg, () {
              setState(() => _dismissed[tenantId] = msg);
            }),
            Expanded(child: widget.child),
          ],
        );
      }
    }
    return widget.child;
  }

  Widget _messageBanner(String message, VoidCallback onDismiss) {
    return Material(
      color: AppColors.warning.withValues(alpha: 0.15),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.campaign_outlined,
                  color: AppColors.warning, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message,
                    style: AppTypography.bodyMedium, softWrap: true),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'بند کریں',
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suspendedScreen(TenantAccessStatus status) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.block,
                      size: 52, color: AppColors.error),
                ),
                const SizedBox(height: 24),
                Text(
                  'آپ کے ادارے کی رسائی معطل کر دی گئی ہے',
                  textAlign: TextAlign.center,
                  style: AppTypography.headingSmall
                      .copyWith(color: AppColors.error),
                ),
                if ((status.suspensionReason ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('وجہ:',
                            style: AppTypography.labelNastaliq.copyWith(
                                fontSize: 16,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(status.suspensionReason!.trim(),
                            style: AppTypography.bodyMedium),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'رسائی کی بحالی کے لیے براہ کرم انتظامیہ سے رابطہ کریں۔',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  'support@madrassa360.pk',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(tenantAccessProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text('دوبارہ چیک کریں',
                      style: AppTypography.buttonText
                          .copyWith(color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _expiredScreen(TenantAccessStatus status) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.timer_off_outlined,
                      size: 52, color: AppColors.warning),
                ),
                const SizedBox(height: 24),
                Text(
                  'آپ کی رکنیت کی مدت ختم ہو گئی ہے',
                  textAlign: TextAlign.center,
                  style: AppTypography.headingSmall
                      .copyWith(color: AppColors.warning),
                ),
                const SizedBox(height: 12),
                if (status.hasMessage)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(status.adminMessage!.trim(),
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium),
                  )
                else
                  Text(
                    'جاری رکھنے کے لیے براہ کرم اپنی رکنیت کی تجدید کروائیں۔',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 8),
                Text(
                  'support@madrassa360.pk',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(tenantAccessProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text('دوبارہ چیک کریں',
                      style: AppTypography.buttonText
                          .copyWith(color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
