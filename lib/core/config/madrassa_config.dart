// ════════════════════════════════════════════════════════════════════════════
//  MADRASA 360 — DEPLOYMENT CONFIGURATION
//  ──────────────────────────────────────────────────────────────────────────
//  This is the ONLY file the developer needs to edit when deploying this app
//  for a new madrassa.  All other code reads from this single location.
//
//  HOW TO DEPLOY FOR A NEW MADRASSA
//  ─────────────────────────────────
//  1. Edit every value in the [MadrassaConfig] class below.
//  2. Edit  assets/.env  with the new Supabase project credentials.
//  3. Run  flutter pub get  then rebuild the app.
//
//  DO NOT add editable settings for admins/teachers here — this file is
//  developer-only.  End-users can never see or change any of these values.
// ════════════════════════════════════════════════════════════════════════════

/// حوالہ: تمام مدرسہ کی ترتیبات یہاں سے کنٹرول کریں
/// Single source-of-truth for everything specific to one madrassa deployment.
class MadrassaConfig {
  MadrassaConfig._(); // static-only class

  // ── Identity ──────────────────────────────────────────────────────────────

  /// Madrassa name in Urdu  (shown in app header, invoices, reports)
  static const String nameUrdu = 'خواجہ ایجوکیشنل سسٹم';

  /// Madrassa name in English  (used in about dialog & metadata)
  static const String nameEnglish = 'Khawaja Educational System';

  /// City / district name in Urdu (optional, shown in footer)
  static const String cityUrdu = 'قلعی پیرانوالی';

  /// City / district name in English
  static const String cityEnglish = 'Qili Piranwali';

  // ── Contact ───────────────────────────────────────────────────────────────

  /// Official contact email of this madrassa
  static const String email = 'info@khawajaeducational.com';

  /// Primary phone number (with country code)
  static const String phone = '+92-300-1234567';

  /// Website URL (include https://)
  static const String website = 'https://khawajaeducational.com';

  // ── App Store / Bundle Metadata ───────────────────────────────────────────

  /// App version shown in the About dialog  (keep in sync with pubspec.yaml)
  static const String appVersion = '1.0.0';

  /// Build number  (keep in sync with pubspec.yaml)
  static const String appBuildNumber = '1';

  // ── Supabase ──────────────────────────────────────────────────────────────
  //
  //  Credentials are loaded from  assets/.env  at runtime.
  //  DO NOT hardcode them here.  Edit  assets/.env  instead.
  //
  //  Required keys in assets/.env :
  //    SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
  //    SUPABASE_ANON_KEY=eyJhbGciOi...
  //
  //  See  assets/.env.example  for the full template.
  // ─────────────────────────────────────────────────────────────────────────
}
