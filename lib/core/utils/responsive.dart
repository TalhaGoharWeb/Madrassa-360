/// جوابی ڈیزائن کی افادیت
/// Responsive Design Utilities

import 'package:flutter/material.dart';

/// Screen Size Extensions
extension ResponsiveContext on BuildContext {
  /// Get screen width
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Get screen height
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Check if screen is mobile (< 600px)
  bool get isMobile => screenWidth < 600;

  /// Check if screen is tablet (600px - 900px)
  bool get isTablet => screenWidth >= 600 && screenWidth < 900;

  /// Check if screen is desktop (> 900px)
  bool get isDesktop => screenWidth >= 900;

  /// Get responsive value based on screen size
  T responsive<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop && desktop != null) return desktop;
    if (isTablet && tablet != null) return tablet;
    return mobile;
  }
}

/// Responsive Size Calculator
class ResponsiveSize {
  final BuildContext context;

  ResponsiveSize(this.context);

  /// Get responsive width (percentage of screen width)
  double width(double percentage) {
    return context.screenWidth * (percentage / 100);
  }

  /// Get responsive height (percentage of screen height)
  double height(double percentage) {
    return context.screenHeight * (percentage / 100);
  }

  /// Get responsive font size
  double fontSize(double baseSize) {
    final width = context.screenWidth;
    if (width < 360) return baseSize * 0.9;
    if (width < 400) return baseSize * 0.95;
    if (width > 600) return baseSize * 1.1;
    return baseSize;
  }

  /// Get responsive padding
  EdgeInsets padding({
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    final factor = context.isMobile ? 1.0 : 1.2;
    return EdgeInsets.only(
      left: (left ?? horizontal ?? all ?? 0) * factor,
      top: (top ?? vertical ?? all ?? 0) * factor,
      right: (right ?? horizontal ?? all ?? 0) * factor,
      bottom: (bottom ?? vertical ?? all ?? 0) * factor,
    );
  }

  /// Get responsive margin
  EdgeInsets margin({
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    return padding(
      all: all,
      horizontal: horizontal,
      vertical: vertical,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }
}

/// Spacing Constants
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  /// Get responsive spacing
  static double responsive(BuildContext context, double baseSpacing) {
    if (context.isDesktop) return baseSpacing * 1.5;
    if (context.isTablet) return baseSpacing * 1.25;
    return baseSpacing;
  }
}

/// Grid System
class ResponsiveGrid {
  /// Calculate columns based on screen size
  static int columns(BuildContext context) {
    if (context.isDesktop) return 4;
    if (context.isTablet) return 3;
    return 2;
  }

  /// Calculate cross-axis count for GridView
  static int crossAxisCount(BuildContext context, {int? mobile, int? tablet, int? desktop}) {
    return context.responsive(
      mobile: mobile ?? 2,
      tablet: tablet ?? 3,
      desktop: desktop ?? 4,
    );
  }

  /// Calculate child aspect ratio
  static double childAspectRatio(BuildContext context) {
    if (context.isDesktop) return 1.2;
    if (context.isTablet) return 1.1;
    return 1.0;
  }
}

/// Breakpoint Constants
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1600;
}

/// Responsive Builder Widget
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ResponsiveSize size) builder;

  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, ResponsiveSize(context));
  }
}

/// Responsive Layout Widget
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return context.responsive(
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
}

/// Orientation Builder Extension
extension OrientationExtension on BuildContext {
  /// Check if orientation is portrait
  bool get isPortrait => MediaQuery.of(this).orientation == Orientation.portrait;

  /// Check if orientation is landscape
  bool get isLandscape => MediaQuery.of(this).orientation == Orientation.landscape;

  /// Get value based on orientation
  T orientation<T>({
    required T portrait,
    required T landscape,
  }) {
    return isPortrait ? portrait : landscape;
  }
}

/// Safe Area Extension
extension SafeAreaExtension on BuildContext {
  /// Get safe area padding
  EdgeInsets get safeAreaPadding => MediaQuery.of(this).padding;

  /// Get safe area insets
  EdgeInsets get viewInsets => MediaQuery.of(this).viewInsets;

  /// Check if keyboard is visible
  bool get isKeyboardVisible => viewInsets.bottom > 0;
}
