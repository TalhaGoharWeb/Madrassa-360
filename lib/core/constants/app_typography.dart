import 'package:flutter/material.dart';
import 'app_colors.dart';

/// مدرسہ 360 - خطاطی (v4)
/// Typography system — Jameel Noori Nastaleeq for ALL Urdu text,
/// Jameel Noori Nastaleeq Kasheeda for hero moments.
///
/// * Every Urdu string in the app — headings, labels, hints, buttons,
///   subtitles, chips, tabs, table headers, body text — renders in
///   Jameel Noori Nastaleeq v4. Nastaliq is tall, so every style keeps
///   line height ≥ 2.0 and no nuqta ever clips.
/// * Hero (main greeting header): Kasheeda, generous line height.
/// * Noto Naskh Arabic is kept ONLY as a defensive fontFamilyFallback
///   (missing glyphs) — it is never the primary family of any style.
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

  /// Base body style: Jameel Noori Nastaleeq v4 — same as display.
  ///
  /// Every Urdu string in the app renders in Nastaliq (headings, labels,
  /// hints, buttons, subtitles, body). Noto Naskh Arabic stays only as a
  /// defensive fallback for glyphs the Nastaliq file may lack — Urdu text
  /// must still render in an embedded Urdu font, never the platform font.
  /// Line height stays ≥ 2.0: Nastaliq is tall and nuqtas must not clip.
  static TextStyle get _bodyBase => const TextStyle(
        fontFamily: nastaliqFamily,
        fontFamilyFallback: [naskhFamily],
        height: 2.0,
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
  /// itself: pick [labelNastaliq] for Urdu text; Latin text in a Nastaleeq
  /// style falls back gracefully through the embedded font chain.
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
  // Body / label / button styles — Jameel Noori Nastaleeq v4 as well.
  // Every style below inherits the Nastaliq-first _bodyBase, so labels,
  // hints, buttons, subtitles and body text all render in Nastaleeq.
  // ------------------------------------------------------------------

  static TextStyle get bodyLarge => _bodyBase.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => _bodyBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodySmall => _bodyBase.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
      );

  static TextStyle get labelLarge => _bodyBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle get labelMedium => _bodyBase.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  static TextStyle get labelSmall => _bodyBase.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  static TextStyle get buttonText => _bodyBase.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );

  /// Primary button label in Jameel Noori Nastaleeq (18sp, semibold, white).
  ///
  /// This is the themed default for filled buttons ([app_theme.dart]
  /// wires it into [elevatedButtonTheme]) so every Urdu button label in
  /// the app renders in Nastaleeq. [buttonText] renders identically —
  /// both are Nastaleeq since the v4 "Nastaleeq everywhere" policy.
  static TextStyle get buttonNastaliq => _displayBase.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 2.0,
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

  /// Helper to create a custom body style (Nastaleeq, like all body text).
  static TextStyle customBody({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.normal,
    Color color = AppColors.textPrimary,
    double height = 2.0,
  }) {
    return _bodyBase.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }
}
