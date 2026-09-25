/// بارے میں اسکرین
/// About Screen — product info, tenant (institution) info, contact.
///
/// Phase 4: institution identity (name, city, phone, email, address, logo)
/// is loaded per-tenant from [tenantBrandingProvider] — nothing is
/// hard-coded. Developer contact PII was removed from this shipped screen;
/// the contact section now reaches the tenant's own administration.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/widgets/tenant_logo.dart';
import '../../../providers/tenant_branding_provider.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  bool _isUrdu = true; // language toggle

  // ── Product description (tenant-agnostic, no personal data) ──────

  static const _descUrdu =
      'مدرسہ 360 ایک مکمل ڈیجیٹل انتظامی نظام ہے جو مدارس کے ریکارڈ، طلباء، '
      'عملے اور روزمرہ کے انتظامی امور کو آسان، منظم اور جدید انداز میں '
      'سنبھالنے میں مدد فراہم کرتا ہے۔';

  static const _descEnglish =
      'Madrasa 360 is a complete digital management system that helps '
      'madrassas manage their records, students, staff, and day-to-day '
      'operations in an easy, organised, and modern way.';

  // ── Helpers ───────────────────────────────────────────────

  void _copy(BuildContext ctx, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('$label کاپی ہو گیا'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final headerColor = branding?.primaryColor ?? AppColors.primary;
    final headerDark = branding?.secondaryColor ?? AppColors.primaryDark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App Bar (tenant-tinted gradient) ──────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: headerColor,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [headerColor, headerDark],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    // Phase 4 — the tenant's own logo (neutral mark if unset)
                    const TenantLogo(size: 80, circular: true),
                    const SizedBox(height: 12),
                    TenantNameText(
                      style: AppTypography.headingSmall
                          .copyWith(color: Colors.white),
                    ),
                    Text(
                      'v${AppConfig.appVersion}',
                      style: AppTypography.bodySmall
                          .copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            title: const Text('ایپ کے بارے میں'),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Language Toggle ──────────────────

                  _LanguageToggle(
                    isUrdu: _isUrdu,
                    accent: headerColor,
                    onToggle: (v) => setState(() => _isUrdu = v),
                  ),
                  const SizedBox(height: 20),

                  // ── Product Description ──────────────

                  _SectionCard(
                    accent: headerColor,
                    header:
                        _isUrdu ? 'منصوبے کے بارے میں' : 'About the Product',
                    headerIcon: Icons.info_outline,
                    child: Text(
                      _isUrdu ? _descUrdu : _descEnglish,
                      style: AppTypography.bodyMedium.copyWith(height: 1.7),
                      textAlign: TextAlign.justify,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Institution (tenant) info ────────

                  _SectionCard(
                    accent: headerColor,
                    header: _isUrdu ? 'مدرسے کی معلومات' : 'Institution',
                    headerIcon: Icons.mosque_outlined,
                    child: Column(
                      children: [
                        _InfoRow(
                          label: _isUrdu ? 'مدرسہ' : 'Institution',
                          value: branding?.displayName(urdu: _isUrdu) ?? '—',
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'پتہ' : 'Address',
                          value: (branding?.locationLine.isNotEmpty == true)
                              ? branding!.locationLine
                              : '—',
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'فون' : 'Phone',
                          value: (branding?.phone?.isNotEmpty == true)
                              ? branding!.phone!
                              : '—',
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'ای میل' : 'Email',
                          value: (branding?.email?.isNotEmpty == true)
                              ? branding!.email!
                              : '—',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Contact the administration ───────

                  if (branding?.hasContact == true)
                    _SectionCard(
                      accent: headerColor,
                      header: _isUrdu ? 'انتظامیہ سے رابطہ' : 'Contact',
                      headerIcon: Icons.contact_support_outlined,
                      child: Column(
                        children: [
                          if (branding?.phone?.isNotEmpty == true)
                            _ContactButton(
                              icon: Icons.phone,
                              label: _isUrdu ? 'فون کریں' : 'Call',
                              subtitle: branding!.phone!,
                              color: const Color(0xFF388E3C),
                              onTap: () => _copy(context, branding.phone!,
                                  _isUrdu ? 'نمبر' : 'Number'),
                            ),
                          if (branding?.phone?.isNotEmpty == true &&
                              branding?.email?.isNotEmpty == true)
                            const SizedBox(height: 12),
                          if (branding?.email?.isNotEmpty == true)
                            _ContactButton(
                              icon: Icons.email,
                              label: _isUrdu ? 'ای میل' : 'Email',
                              subtitle: branding!.email!,
                              color: const Color(0xFF1976D2),
                              onTap: () => _copy(context, branding.email!,
                                  _isUrdu ? 'ای میل' : 'Email'),
                            ),
                        ],
                      ),
                    ),
                  if (branding?.hasContact == true) const SizedBox(height: 16),

                  // ── App Info ─────────────────────────

                  _SectionCard(
                    accent: headerColor,
                    header: _isUrdu ? 'ایپ کی معلومات' : 'App Information',
                    headerIcon: Icons.phone_android_outlined,
                    child: Column(
                      children: [
                        _InfoRow(
                          label: _isUrdu ? 'ایپ کا نام' : 'App Name',
                          value: AppConfig.appName,
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'ورژن' : 'Version',
                          value: AppConfig.appVersion,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Footer ───────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Text(
                          AppConfig.appNameEnglish,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shared small widgets
// ═══════════════════════════════════════════════════════════════

class _LanguageToggle extends StatelessWidget {
  final bool isUrdu;
  final Color accent;
  final ValueChanged<bool> onToggle;

  const _LanguageToggle(
      {required this.isUrdu, required this.accent, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _Tab(
              label: 'اردو',
              active: isUrdu,
              accent: accent,
              onTap: () => onToggle(true)),
          _Tab(
              label: 'English',
              active: !isUrdu,
              accent: accent,
              onTap: () => onToggle(false)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _Tab(
      {required this.label,
      required this.active,
      required this.accent,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.labelLarge.copyWith(
              color: active ? Colors.white : AppColors.textSecondary,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String header;
  final IconData headerIcon;
  final Widget child;
  final Color accent;

  const _SectionCard({
    required this.header,
    required this.headerIcon,
    required this.child,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(headerIcon, color: accent, size: 20),
                const SizedBox(width: 10),
                Text(header,
                    style: AppTypography.titleMedium.copyWith(color: accent)),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ContactButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            AppTypography.titleMedium.copyWith(color: color)),
                    Text(subtitle,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.arrow_back_ios,
                  size: 14, color: color.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(label,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
            ),
            Expanded(
              flex: 3,
              child: Text(value,
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.start),
            ),
          ],
        ),
        if (!isLast) const Divider(height: 20),
      ],
    );
  }
}
