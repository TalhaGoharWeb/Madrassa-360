/// ایپ کی ترتیب
/// Application Configuration and Environment Variables
///
/// ─────────────────────────────────────────────
/// DEVELOPER NOTE
/// To deploy for a different madrassa, edit ONE file:
///   lib/core/config/madrassa_config.dart
/// Supabase credentials go in:
///   assets/.env  (copy from assets/.env.example)
/// ─────────────────────────────────────────────

import 'madrassa_config.dart';

/// Always use Supabase — mock data has been removed for production
const bool kUseSupabase = true;

class AppConfig {
  // ── Madrassa Identity (read from MadrassaConfig — single source of truth) ──
  static const String appName        = MadrassaConfig.nameUrdu;
  static const String appNameEnglish = MadrassaConfig.nameEnglish;
  static const String appEmail       = MadrassaConfig.email;
  static const String appPhone       = MadrassaConfig.phone;
  static const String appWebsite     = MadrassaConfig.website;
  static const String appVersion     = MadrassaConfig.appVersion;
  static const String appBuildNumber = MadrassaConfig.appBuildNumber;

  // ── Supabase (credentials loaded at runtime from assets/.env) ──────────
  // See assets/.env.example for required keys.

  // ── General App Settings ───────────────────────────────────────
  // Feature Flags
  static const bool enableOfflineMode = true;
  static const bool enableNotifications = true;
  static const bool enableBiometricAuth = false;
  static const bool enableDarkMode = false;

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Cache Configuration
  static const int cacheExpiryDays = 7;
  static const int maxCacheSize = 50; // MB

  // Date Formats
  static const String dateFormat = 'dd/MM/yyyy';
  static const String timeFormat = 'hh:mm a';
  static const String dateTimeFormat = 'dd/MM/yyyy hh:mm a';

  // Validation Rules
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 20;
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 20;
  static const int minNameLength = 2;
  static const int maxNameLength = 50;

  // File Upload Limits
  static const int maxImageSizeKB = 2048; // 2MB
  static const int maxDocumentSizeKB = 5120; // 5MB
  static const List<String> allowedImageExtensions = ['jpg', 'jpeg', 'png'];
  static const List<String> allowedDocumentExtensions = ['pdf', 'doc', 'docx'];

  // Session Configuration
  static const int sessionTimeoutMinutes = 30;
  static const bool rememberMeEnabled = true;

  // UI Configuration
  static const double borderRadius = 12.0;
  static const double cardElevation = 2.0;
  static const double buttonHeight = 48.0;
  static const double inputFieldHeight = 56.0;

  // Animation Durations (milliseconds)
  static const int shortAnimationDuration = 200;
  static const int normalAnimationDuration = 300;
  static const int longAnimationDuration = 500;

  // Snackbar Duration (seconds)
  static const int snackbarDuration = 3;
  static const int errorSnackbarDuration = 5;

  // Environment
  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  static bool get isDevelopment => environment == 'development';
  static bool get isProduction  => environment == 'production';
  static bool get isStaging     => environment == 'staging';

  // Assets Paths
  static const String assetsPath = 'assets/';
  static const String imagesPath = '${assetsPath}images/';
  static const String iconsPath = '${assetsPath}icons/';
  static const String fontsPath = '${assetsPath}fonts/';

  // Default Images
  static const String defaultUserImage = '${imagesPath}default_user.png';
  static const String defaultStudentImage = '${imagesPath}default_student.png';
  static const String logoImage = '${imagesPath}logo.png';
}

/// API Endpoints (for future Firebase/Backend integration)
class ApiEndpoints {
  // Auth endpoints
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String register = '/auth/register';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String changePassword = '/auth/change-password';

  // Student endpoints
  static const String students = '/students';
  static const String studentById = '/students/:id';
  static const String studentAttendance = '/students/:id/attendance';
  static const String studentResults = '/students/:id/results';
  static const String studentFees = '/students/:id/fees';

  // Teacher endpoints
  static const String teachers = '/teachers';
  static const String teacherById = '/teachers/:id';
  static const String teacherSchedule = '/teachers/:id/schedule';

  // Attendance endpoints
  static const String attendance = '/attendance';
  static const String attendanceByDate = '/attendance/:date';
  static const String attendanceByClass = '/attendance/class/:classId';

  // Fee endpoints
  static const String fees = '/fees';
  static const String feeById = '/fees/:id';
  static const String feePayments = '/fees/payments';

  // Results endpoints
  static const String results = '/results';
  static const String resultsByStudent = '/results/student/:studentId';
  static const String resultsByClass = '/results/class/:classId';

  // Notifications endpoints
  static const String notifications = '/notifications';
  static const String markNotificationRead = '/notifications/:id/read';
}
