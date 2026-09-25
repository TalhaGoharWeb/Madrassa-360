import 'package:flutter/material.dart';
import 'app_colors.dart';

/// مدرسہ 360 - خطاطی
/// Typography styles using Jameel Noori Nastaleeq font
class AppTypography {
  AppTypography._();

  /// Get base Urdu text style with Jameel Noori Nastaleeq font
  static TextStyle get _baseUrduStyle => const TextStyle(
        fontFamily: 'JameelNooriNastaleeq',
        fontFamilyFallback: ['NotoNastaliqUrdu'],
      );

  // Heading Styles
  static TextStyle get headingLarge => _baseUrduStyle.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 2.0, // Extra line height for Nastaliq
      );

  static TextStyle get headingMedium => _baseUrduStyle.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.8,
      );

  static TextStyle get headingSmall => _baseUrduStyle.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.8,
      );

  // Title Styles
  static TextStyle get titleLarge => _baseUrduStyle.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.8,
      );

  static TextStyle get titleMedium => _baseUrduStyle.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.7,
      );

  static TextStyle get titleSmall => _baseUrduStyle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.6,
      );

  // Body Styles
  static TextStyle get bodyLarge => _baseUrduStyle.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.8,
      );

  static TextStyle get bodyMedium => _baseUrduStyle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.7,
      );

  static TextStyle get bodySmall => _baseUrduStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
        height: 1.6,
      );

  // Label Styles
  static TextStyle get labelLarge => _baseUrduStyle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.6,
      );

  static TextStyle get labelMedium => _baseUrduStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  static TextStyle get labelSmall => _baseUrduStyle.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  // Button Text
  static TextStyle get buttonText => _baseUrduStyle.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.6,
      );

  // App Bar Title
  static TextStyle get appBarTitle => _baseUrduStyle.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 1.8,
      );

  // Navigation Bar Label
  static TextStyle get navLabel => _baseUrduStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.5,
      );

  /// Helper to create custom style
  static TextStyle custom({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color color = AppColors.textPrimary,
    double height = 1.7,
  }) {
    return _baseUrduStyle.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }
}
