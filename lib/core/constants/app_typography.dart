import 'package:flutter/material.dart';
import 'app_colors.dart';

/// مدرسہ 360 - خطاطی (v3)
/// Typography system — Jameel Noori Nastaleeq for display, Jameel Noori
/// Nastaleeq Kasheeda for hero moments, Noto Naskh Arabic for body.
///
/// * Display (headings, section titles, card titles): Jameel Noori v4.
///   Nastaliq is tall — every display style keeps line height ≥ 2.0 so
///   nuqtas never clip.
/// * Hero (main greeting header): Kasheeda, generous line height.
/// * Body / small text: Noto Naskh Arabic for readability at small sizes;
///   Nastaliq is never used below ~15sp.
///
/// The `JameelNooriNastaleeq` family name is kept (tenant branding rows and
/// PDF rendering reference it); it now points at the v4 font file.
class AppTypography {
  AppTypography._();

  /// Jameel Noori Nastaleeq v4 — display headings.
  static const String nastaliqFamily = 'JameelNooriNastaleeq';

  /// Jameel Noori Nastaleeq Kasheeda — hero moments only.
  static const String kasheedaFamily = 'JameelNooriKasheeda';

  /// Noto Naskh Arabic — body and small text.
  static const String naskhFamily = 'NotoNaskhArabic';

  /// Base display style: Jameel Noori Nastaleeq v4.
  ///
  /// Defensive fallback to the embedded Naskh family: if the Nastaliq file
  /// ever lacks a glyph (Latin letters, digits), text still renders in an
  /// embedded Urdu font — never the platform system font.
  static TextStyle get _displayBase => const TextStyle(
        fontFamily: nastaliqFamily,
        fontFamilyFallback: [naskhFamily],
      );

  /// Base hero style: Kasheeda (falls back to regular Nastaliq).
  static TextStyle get _kasheedaBase => const TextStyle(
        fontFamily: kasheedaFamily,
        fontFamilyFallback: [nastaliqFamily, 'NotoNastaliqUrdu'],
      );

  /// Base body style: Noto Naskh Arabic.
  ///
  /// Defensive fallback to the Nastaliq family: if the Naskh family ever
  /// fails to resolve at runtime, Urdu text must still render in an
  /// embedded Urdu font — never the platform system font.
  static TextStyle get _bodyBase => const TextStyle(
        fontFamily: naskhFamily,
        fontFamilyFallback: [nastaliqFamily],
      );

  // ------------------------------------------------------------------
  // Display styles — Jameel Noori Nastaleeq v4, line height ≥ 2.0.
  // ------------------------------------------------------------------

  static TextStyle get headingLarge => _displayBase.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 2.0,
      );

  static TextStyle get headingMedium => _displayBase.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 2.0,
      );

  static TextStyle get headingSmall => _displayBase.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 2.0,
      );

  static TextStyle get titleLarge => _displayBase.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 2.0,
      );

  static TextStyle get titleMedium => _displayBase.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 2.0,
      );

  static TextStyle get titleSmall => _displayBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 2.0,
      );

  /// True when [text] contains Urdu/Arabic-script characters.
  ///
  /// Use for bilingual labels whose language is only known from the string
  /// itself: pick [labelNastaliq] for Urdu text, a Naskh style for Latin.
  static bool isUrduText(String text) => RegExp(
        r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
      ).hasMatch(text);

  /// Small Nastaliq label — stat-card labels, quick-action / section tile
  /// labels, chips, short status lines, tab labels.
  ///
  /// Nastaleeq stays legible at >= 15sp; every use keeps line height >= 2.0
  /// so nuqtas never clip. This is the style that guarantees short Urdu UI
  /// text always renders in the embedded Jameel Noori Nastaleeq family.
  static TextStyle get labelNastaliq => _displayBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 2.0,
      );

  // ------------------------------------------------------------------
  // Hero styles — Kasheeda for greeting headers only.
  // ------------------------------------------------------------------

  /// Main greeting line (e.g. 'السلام علیکم ورحمۃ اللہ').
  static TextStyle get greetingKasheeda => _kasheedaBase.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.normal,
        color: Colors.white,
        height: 2.2,
      );

  /// Hero user/title line under the greeting.
  static TextStyle get heroKasheeda => _kasheedaBase.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.normal,
        color: Colors.white,
        height: 2.2,
      );

  // ------------------------------------------------------------------
  // Body styles — Noto Naskh Arabic.
  // ------------------------------------------------------------------

  static TextStyle get bodyLarge => _bodyBase.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.8,
      );

  static TextStyle get bodyMedium => _bodyBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.8,
      );

  static TextStyle get bodySmall => _bodyBase.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
        height: 1.7,
      );

  static TextStyle get labelLarge => _bodyBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.7,
      );

  static TextStyle get labelMedium => _bodyBase.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.7,
      );

  static TextStyle get labelSmall => _bodyBase.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.6,
      );

  static TextStyle get buttonText => _bodyBase.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.8,
      );

  static TextStyle get appBarTitle => _displayBase.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        height: 2.0,
      );

  static TextStyle get navLabel => _displayBase.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 2.0,
      );

  /// Helper to create a custom display (Nastaliq) style.
  static TextStyle custom({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.normal,
    Color color = AppColors.textPrimary,
    double height = 2.0,
  }) {
    return _displayBase.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  /// Helper to create a custom body (Naskh) style.
  static TextStyle customBody({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.normal,
    Color color = AppColors.textPrimary,
    double height = 1.8,
  }) {
    return _bodyBase.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }
}
