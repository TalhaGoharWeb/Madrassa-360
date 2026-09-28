import 'package:flutter/material.dart';

/// مدرسہ 360 - رنگوں کی فہرست
/// Madrasa 360 Color Palette — 60/30/10 harmony (PRD v1.0.0).
class AppColors {
  AppColors._();

  // Primary — Deep Institutional Teal (30%)
  static const Color primary = Color(0xFF0F6B63);
  static const Color primaryDark = Color(0xFF094742);
  static const Color primaryLight = Color(0xFF4DB6AC);

  // CTA Accent — Warm Action Orange (10%)
  static const Color accent = Color(0xFFF28C28);
  static const Color accentDark = Color(0xFFD97706);

  // Gold — brand accent (logo, highlights)
  static const Color gold = Color(0xFFC9A227);

  // Attendance Status Colors
  static const Color present = Color(0xFF4CAF50); // حاضر - Green
  static const Color absent = Color(0xFFF44336); // غیر حاضر - Red
  static const Color leave = Color(0xFFFFC107); // چھٹی - Amber/Yellow
  static const Color late = Color(0xFF2196F3); // تاخیر سے حاضر - Blue

  // Neutral Colors — Soft Institutional Mint (60%)
  static const Color background = Color(0xFFF1FAF7);
  static const Color surface = Color(0xFFFFFFFF); // White Surface
  static const Color textPrimary = Color(0xFF212121); // Dark Text
  static const Color textSecondary = Color(0xFF757575); // Gray Text
  static const Color divider = Color(0xFFBDBDBD); // Divider Gray

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Fee Status Colors
  static const Color paid = Color(0xFF4CAF50); // ادا شدہ
  static const Color pending = Color(0xFFFF9800); // زیر التواء
  static const Color pastDue = Color(0xFFF44336); // واجب الادا
}
