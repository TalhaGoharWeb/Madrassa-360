import 'package:flutter/material.dart';

/// المرکز الاسلامی قصور - رنگوں کی فہرست
/// Al Markaz al Islami Kasur Color Palette
class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primary = Color(0xFF009688);        // Islamic Teal
  static const Color primaryDark = Color(0xFF00796B);    // Darker Teal
  static const Color primaryLight = Color(0xFF4DB6AC);   // Lighter Teal

  // Attendance Status Colors
  static const Color present = Color(0xFF4CAF50);        // حاضر - Green
  static const Color absent = Color(0xFFF44336);         // غیر حاضر - Red
  static const Color leave = Color(0xFFFFC107);          // چھٹی - Amber/Yellow

  // Neutral Colors
  static const Color background = Color(0xFFF5F5F5);     // Light Gray Background
  static const Color surface = Color(0xFFFFFFFF);        // White Surface
  static const Color textPrimary = Color(0xFF212121);    // Dark Text
  static const Color textSecondary = Color(0xFF757575);  // Gray Text
  static const Color divider = Color(0xFFBDBDBD);        // Divider Gray

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Fee Status Colors
  static const Color paid = Color(0xFF4CAF50);           // ادا شدہ
  static const Color pending = Color(0xFFFF9800);        // زیر التواء
  static const Color pastDue = Color(0xFFF44336);        // واجب الادا
}
