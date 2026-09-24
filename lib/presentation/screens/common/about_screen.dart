/// بارے میں اسکرین
/// About Screen — project info, developer credentials, contact

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/madrassa_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

// ─────────────────────────────────────────────────────────────
// Developer constants — edit here if details change
// ─────────────────────────────────────────────────────────────
const _devName    = 'Muhammad Talha Farid';
const _devEmail   = 'goharenaqshband@gmail.com';
const _devPhone   = '03287819000';
const _production = 'HijaziApps Production';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _isUrdu = true; // language toggle

  // ── Project description ──────────────────────────────────

  static const _descUrdu =
      'مدرسہ 360 ایک مکمل ڈیجیٹل انتظامی نظام ہے جسے HijaziApps پروڈکشن کے تحت '
      'محمد طلحہ فرید نے تیار کیا ہے۔ اس منصوبے کا مقصد مدارس کو ان کے ریکارڈ، '
      'طلباء، عملے اور روزمرہ کے انتظامی امور کو آسان، منظم اور جدید انداز میں '
      'سنبھالنے میں مدد فراہم کرنا ہے۔\n\n'
      'اگر آپ اپنے مدرسے کے ریکارڈ کو ڈیجیٹل بنانا اور جدید نظام کو اپنانا چاہتے '
      'ہیں تو ڈویلپر سے فوری رابطہ کریں۔';

  static const _descEnglish =
      'Madrasa 360 is a complete digital management system developed under '
      'HijaziApps Production by Muhammad Talha Farid. The goal of this platform '
      'is to help madrassas manage their records, students, staff, and operations '
      'in an easy, organised, and modern way.\n\n'
      'If you want to modernise and digitise your madrassa records, contact the '
      'developer today.';

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
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App Bar (gradient) ──────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white30, width: 2),
                      ),
                      child: const Icon(Icons.mosque, color: Colors.white, size: 42),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppConfig.appName,
                      style: AppTypography.headingSmall.copyWith(color: Colors.white),
                    ),
                    Text(
                      'v${MadrassaConfig.appVersion}',
                      style: AppTypography.bodySmall.copyWith(color: Colors.white70),
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
                    onToggle: (v) => setState(() => _isUrdu = v),
                  ),
                  const SizedBox(height: 20),

                  // ── Project Description ──────────────

                  _SectionCard(
                    header: _isUrdu ? 'منصوبے کے بارے میں' : 'About the Project',
                    headerIcon: Icons.info_outline,
                    child: Text(
                      _isUrdu ? _descUrdu : _descEnglish,
                      style: AppTypography.bodyMedium.copyWith(height: 1.7),
                      textAlign: TextAlign.justify,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Developer Credentials ────────────

                  _SectionCard(
                    header: _isUrdu ? 'ڈویلپر کی معلومات' : 'Developer Credentials',
                    headerIcon: Icons.person_outline,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DevInfoRow(
                          icon: Icons.badge_outlined,
                          label: _isUrdu ? 'نام' : 'Name',
                          value: _devName,
                          onTap: null,
                        ),
                        const Divider(height: 20),
                        _DevInfoRow(
                          icon: Icons.business_outlined,
                          label: _isUrdu ? 'پروڈکشن' : 'Production',
                          value: _production,
                          onTap: null,
                        ),
                        const Divider(height: 20),
                        _DevInfoRow(
                          icon: Icons.email_outlined,
                          label: _isUrdu ? 'ای میل' : 'Email',
                          value: _devEmail,
                          onTap: () => _copy(context, _devEmail,
                              _isUrdu ? 'ای میل' : 'Email'),
                          tapIcon: Icons.copy,
                        ),
                        const Divider(height: 20),
                        _DevInfoRow(
                          icon: Icons.phone_outlined,
                          label: _isUrdu ? 'رابطہ نمبر' : 'Phone',
                          value: _devPhone,
                          onTap: () =>
                              _copy(context, _devPhone, _isUrdu ? 'نمبر' : 'Number'),
                          tapIcon: Icons.copy,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Contact Buttons ──────────────────

                  _SectionCard(
                    header: _isUrdu ? 'ڈویلپر سے رابطہ کریں' : 'Contact Developer',
                    headerIcon: Icons.contact_support_outlined,
                    child: Column(
                      children: [
                        _ContactButton(
                          icon: Icons.email,
                          label: _isUrdu ? 'ای میل بھیجیں' : 'Send Email',
                          subtitle: _devEmail,
                          color: const Color(0xFF1976D2),
                          onTap: () => _launchEmail(context),
                        ),
                        const SizedBox(height: 12),
                        _ContactButton(
                          icon: Icons.phone,
                          label: _isUrdu ? 'فون کریں' : 'Call Developer',
                          subtitle: _devPhone,
                          color: const Color(0xFF388E3C),
                          onTap: () => _launchPhone(context),
                        ),
                        const SizedBox(height: 12),
                        _ContactButton(
                          icon: Icons.chat_bubble_outline,
                          label: _isUrdu ? 'واٹس ایپ پر رابطہ' : 'WhatsApp',
                          subtitle: '+92 $_devPhone',
                          color: const Color(0xFF00897B),
                          onTap: () => _launchWhatsApp(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── App Info ─────────────────────────

                  _SectionCard(
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
                          value: MadrassaConfig.appVersion,
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'مدرسہ' : 'Institution',
                          value: _isUrdu
                              ? MadrassaConfig.nameUrdu
                              : MadrassaConfig.nameEnglish,
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'شہر' : 'City',
                          value: _isUrdu
                              ? MadrassaConfig.cityUrdu
                              : MadrassaConfig.cityEnglish,
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'ای میل' : 'Email',
                          value: MadrassaConfig.email,
                        ),
                        _InfoRow(
                          label: _isUrdu ? 'جاری تاریخ' : 'Released',
                          value: 'January 2026',
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
                          'Developed by $_production',
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _devName,
                          style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textSecondary),
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

  void _launchEmail(BuildContext ctx) {
    final subject = Uri.encodeComponent('Madrasa 360 — Inquiry');
    final body = Uri.encodeComponent(
        'السلام علیکم ${_devName} صاحب،\n\nمیں اپنے مدرسے کے لیے معلومات چاہتا ہوں۔');
    final url = 'mailto:$_devEmail?subject=$subject&body=$body';
    _tryLaunch(ctx, url);
  }

  void _launchPhone(BuildContext ctx) {
    _tryLaunch(ctx, 'tel:+92$_devPhone');
  }

  void _launchWhatsApp(BuildContext ctx) {
    final text = Uri.encodeComponent(
        'السلام علیکم! مجھے Madrasa 360 کے بارے میں معلومات چاہیے۔');
    _tryLaunch(ctx, 'https://wa.me/92${_devPhone.substring(1)}?text=$text');
  }

  void _tryLaunch(BuildContext ctx, String url) {
    // Copy the URL to clipboard as friendly fallback
    Clipboard.setData(ClipboardData(text:
        url.startsWith('mailto') ? _devEmail :
        url.startsWith('tel')    ? _devPhone : url));
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(_isUrdu
            ? 'رابطہ کی معلومات کاپی ہو گئی'
            : 'Contact info copied to clipboard'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shared small widgets
// ═══════════════════════════════════════════════════════════════

class _LanguageToggle extends StatelessWidget {
  final bool isUrdu;
  final ValueChanged<bool> onToggle;

  const _LanguageToggle({required this.isUrdu, required this.onToggle});

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
          _Tab(label: 'اردو',   active: isUrdu,  onTap: () => onToggle(true)),
          _Tab(label: 'English', active: !isUrdu, onTap: () => onToggle(false)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
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

  const _SectionCard({
    required this.header,
    required this.headerIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              color: AppColors.primary.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(headerIcon, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Text(header,
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.primary)),
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

class _DevInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? tapIcon;

  const _DevInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.tapIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value,
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (onTap != null)
          IconButton(
            icon: Icon(tapIcon ?? Icons.copy,
                size: 18, color: AppColors.textSecondary),
            onPressed: onTap,
            tooltip: 'Copy',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
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
      color: color.withOpacity(0.08),
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
                  color: color.withOpacity(0.15),
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
                        style: AppTypography.titleMedium
                            .copyWith(color: color)),
                    Text(subtitle,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.arrow_back_ios,
                  size: 14, color: color.withOpacity(0.6)),
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
