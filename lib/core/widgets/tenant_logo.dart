/// Tenant logo widget — Phase 4 (SaaS transformation).
///
/// Renders the active tenant's logo from `tenants.logo_url` via
/// [TenantBranding]. Uses `cached_network_image` with a neutral,
/// institution-free placeholder (mosque glyph on the tenant's primary
/// colour) while loading, when no logo is configured, and on error —
/// so the UI never shows a broken image or another tenant's identity.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../providers/tenant_branding_provider.dart';

/// Circular/square tenant logo driven by [tenantBrandingProvider].
class TenantLogo extends ConsumerWidget {
  final double size;
  final double radius;
  final bool circular;

  const TenantLogo({
    super.key,
    this.size = 44,
    this.radius = 12,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    final logoUrl = branding?.logoUrl;
    final primary = branding?.primaryColor ?? AppColors.primary;

    Widget fallback() => _NeutralMark(size: size, color: primary);

    if (logoUrl == null || logoUrl.trim().isEmpty) return fallback();

    final image = CachedNetworkImage(
      imageUrl: logoUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, __) => fallback(),
      errorWidget: (_, __, ___) => fallback(),
    );

    if (circular) {
      return ClipOval(child: image);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
  }
}

/// Neutral institution-free mark: mosque glyph tinted with the tenant's
/// primary colour. Used as the loading/empty/error state for logos.
class _NeutralMark extends StatelessWidget {
  final double size;
  final Color color;

  const _NeutralMark({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Icon(
        Icons.mosque,
        color: color,
        size: size * 0.5,
      ),
    );
  }
}

/// Tenant name text driven by [tenantBrandingProvider].
/// Shows nothing (empty box) until branding resolves — never a wrong name.
class TenantNameText extends ConsumerWidget {
  final TextStyle? style;
  final bool urdu;
  final TextAlign? textAlign;

  const TenantNameText({
    super.key,
    this.style,
    this.urdu = true,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(tenantBrandingProvider).valueOrNull;
    if (branding == null) return const SizedBox.shrink();
    return Text(
      branding.displayName(urdu: urdu),
      style: (style ?? AppTypography.titleMedium)
          .copyWith(fontFamily: branding.fontFamily),
      textAlign: textAlign,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
