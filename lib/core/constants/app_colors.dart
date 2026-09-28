import 'package:flutter/material.dart';

/// مدرسہ 360 - رنگوں کی فہرست
/// Madrasa 360 Color Palette
///
/// 60/30/10 Color Harmony (per PRD v1.0.0):
/// - 60% Soft Institutional Mint (#F1FAF7 / #FFFFFF): backgrounds, paper-like comfort
/// - 30% Deep Institutional Teal (#0F6B63 / #094742): scholarly administrative identity
/// - 10% Warm Action Orange (#F28C28): high-contrast CTA accents for primary actions
class AppColors {
  AppColors._();

  // Primary Colors — Deep Institutional Teal (30%)
  static const Color primary = Color(0xFF0F6B63); // Deep Institutional Teal
  static const Color primaryDark = Color(0xFF094742); // Darker Teal (headers, gradients)
  static const Color primaryLight = Color(0xFF4DB6AC); // Lighter Teal (tints)

  // CTA Accent — Warm Action Orange (10%)
  // Used for primary action buttons: + نیا طالب علم, حاضری محفوظ کریں, etc.
  static const Color accent = Color(0xFFF28C28); // Warm Action Orange
  static const Color accentDark = Color(0xFFD97706); // Darker Orange (pressed state)

  // Gold — brand accent (logo, special highlights)
  static const Color gold = Color(0xFFC9A227); // Institutional Gold

  // Attendance Status Colors
  static const Color present = Color(0xFF4CAF50); // حاضر - Green
  static const Color absent = Color(0xFFF44336); // غیر حاضر - Red
  static const Color leave = Color(0xFFFFC107); // چھٹی - Amber/Yellow
  static const Color late = Color(0xFF2196F3); // تاخیر سے حاضر - Blue

  // Neutral Colors — Soft Institutional Mint (60%)
  static const Color background = Color(0xFFF1FAF7); // Soft Mint Background
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
