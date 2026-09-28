import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// مدرسہ 360 — ریسپانسیو مددگار
/// Responsive helpers built on [M360Breakpoint].
///
/// * [Responsive.isMobile]/[isTablet]/[isDesktop] — breakpoint queries.
/// * [ResponsiveLayout] — picks a layout builder per breakpoint.
/// * [M360ConstrainedWidth] — centers content with a max width and gutters.
class Responsive {
  Responsive._();

  /// Phone layout: width < 600.
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < M360Breakpoint.mobile;

  /// Large phone / small tablet: 600 ≤ width < 1100.
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= M360Breakpoint.mobile && width < M360Breakpoint.tablet;
  }

  /// Desktop: width ≥ 1100.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= M360Breakpoint.tablet;

  /// Current breakpoint name, useful for logging and tests.
  static String breakpointName(BuildContext context) {
    if (isMobile(context)) return 'mobile';
    if (isTablet(context)) return 'tablet';
    return 'desktop';
  }
}

/// Picks a child builder by breakpoint.
///
/// [tablet] falls back to [desktop] when omitted; [desktop] falls back to
/// [tablet] then [mobile]. [mobile] is always required.
class ResponsiveLayout extends StatelessWidget {
  /// Creates a responsive layout switch.
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  /// Phone layout builder.
  final WidgetBuilder mobile;

  /// Tablet layout builder; defaults to [desktop] ?? [mobile].
  final WidgetBuilder? tablet;

  /// Desktop layout builder; defaults to [tablet] ?? [mobile].
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) return mobile(context);
    if (Responsive.isTablet(context)) {
      return (tablet ?? desktop ?? mobile)(context);
    }
    return (desktop ?? tablet ?? mobile)(context);
  }
}

/// Centers [child] with a breakpoint-aware max width and screen gutters.
///
/// Prevents full-bleed stretching on wide displays while keeping phone
/// layouts edge-to-edge (minus [gutter]).
class M360ConstrainedWidth extends StatelessWidget {
  /// Creates a constrained-width wrapper.
  const M360ConstrainedWidth({
    super.key,
    required this.child,
    this.maxWidth,
    this.gutter = M360Spacing.md,
    this.padding,
  });

  /// Content.
  final Widget child;

  /// Max content width; defaults to [M360Layout.maxContentWidthDesktop].
  final double? maxWidth;

  /// Horizontal gutter on narrow screens.
  final double gutter;

  /// Full padding override; defaults to horizontal [gutter].
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? M360Layout.maxContentWidthDesktop,
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: gutter),
          child: child,
        ),
      ),
    );
  }
}
