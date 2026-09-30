import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// مدرسہ 360 - ایپ تھیم
/// App Theme Configuration with RTL Support
class AppTheme {
  AppTheme._();

  /// Light Theme (Primary Theme)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Default font — Jameel Noori Nastaleeq. Every text element that does
      // not declare its own family (labels, hints, dialogs, dropdowns,
      // tooltips, buttons, …) inherits this, so ALL Urdu text in the app
      // renders in Nastaleeq. The explicit textTheme below keeps its own
      // families: ThemeData merges, never overwrites, provided styles.
      fontFamily: AppTypography.nastaliqFamily,

      // Color Scheme
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primaryLight,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),

      // Scaffold
      scaffoldBackgroundColor: AppColors.background,

      // AppBar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.appBarTitle,
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: AppTypography.navLabel,
        unselectedLabelStyle: AppTypography.navLabel,
      ),

      // M3 Navigation Bar Theme — same Nastaleeq labels as the legacy bar.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTypography.navLabel.copyWith(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          );
        }),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 2,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Elevated Button Theme — Warm Action Orange for primary CTAs (10%).
      // accentDark keeps white label text at readable contrast (~3:1).
      // Labels use buttonNastaliq so every Urdu button renders in
      // Jameel Noori Nastaleeq (the M360 button language).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentDark,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTypography.buttonNastaliq,
        ),
      ),

      // Text Button Theme — Nastaleeq labels in the primary colour,
      // matching the M360 tertiary button language.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle:
              AppTypography.labelNastaliq.copyWith(color: AppColors.primary),
        ),
      ),

      // Outlined Button Theme — same Nastaleeq label language.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle:
              AppTypography.labelNastaliq.copyWith(color: AppColors.primary),
        ),
      ),

      // Chip Theme — short Urdu chip labels in Jameel Noori Nastaleeq.
      chipTheme: ChipThemeData(
        labelStyle: AppTypography.labelNastaliq,
      ),

      // Floating Action Button Theme — Warm Action Orange.
      // accentDark keeps the white icon at readable contrast.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentDark,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: AppTypography.bodyMedium,
        hintStyle:
            AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
      ),

      // ListTile Theme
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        titleTextStyle: AppTypography.titleMedium,
        subtitleTextStyle: AppTypography.bodySmall,
        tileColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // Text Theme with Urdu Font
      textTheme: TextTheme(
        headlineLarge: AppTypography.headingLarge,
        headlineMedium: AppTypography.headingMedium,
        headlineSmall: AppTypography.headingSmall,
        titleLarge: AppTypography.titleLarge,
        titleMedium: AppTypography.titleMedium,
        titleSmall: AppTypography.titleSmall,
        bodyLarge: AppTypography.bodyLarge,
        bodyMedium: AppTypography.bodyMedium,
        bodySmall: AppTypography.bodySmall,
        labelLarge: AppTypography.labelLarge,
        labelMedium: AppTypography.labelMedium,
        labelSmall: AppTypography.labelSmall,
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 24,
      ),

      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle:
            AppTypography.bodyMedium.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Dark Theme (Optional - for future)
  static ThemeData get darkTheme {
    // TODO: Implement dark theme in Phase 2
    return lightTheme;
  }
}
