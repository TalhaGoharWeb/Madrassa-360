/// المرکز الاسلامی قصور - اردو متن
/// Al Markaz al Islami Kasur Urdu Strings - All UI labels in Urdu
import '../config/app_config.dart';

class AppStrings {
  AppStrings._();

  // App Name — single source of truth is AppConfig.appName
  static const String appName = AppConfig.appName;
  static const String appNameEnglish = AppConfig.appNameEnglish;
  static const String appTagline = 'مدارس کا مکمل نظام';

  // Navigation Labels
  static const String home = 'ہوم';
  static const String attendance = 'حاضری';
  static const String results = 'نتائج';
  static const String profile = 'پروفائل';
  static const String settings = 'ترتیبات';
  static const String students = 'طلباء';
  static const String staff = 'عملہ';
  static const String fees = 'فیس';
  static const String dashboard = 'ڈیش بورڈ';

  // Attendance Screen
  static const String attendanceRegister = 'حاضری رجسٹر';
  static const String markAttendance = 'حاضری لگائیں';
  static const String present = 'حاضر';
  static const String absent = 'غیر حاضر';
  static const String leave = 'چھٹی';
  static const String saveAttendance = 'حاضری محفوظ کریں';
  static const String selectClass = 'جماعت منتخب کریں';
  static const String totalStudents = 'کل طلباء';
  static const String presentCount = 'حاضر';
  static const String absentCount = 'غیر حاضر';
  static const String leaveCount = 'چھٹی پر';

  // Student Info
  static const String studentName = 'طالب علم کا نام';
  static const String fatherName = 'والد کا نام';
  static const String rollNumber = 'رول نمبر';
  static const String className = 'جماعت';
  static const String darja = 'درجہ';

  // Auth Screen
  static const String login = 'لاگ ان';
  static const String phoneNumber = 'فون نمبر';
  static const String password = 'پاس ورڈ';
  static const String forgotPassword = 'پاس ورڈ بھول گئے؟';
  static const String loginButton = 'داخل ہوں';

  // Roles
  static const String admin = 'منتظم';
  static const String teacher = 'استاد';
  static const String parent = 'والدین';
  static const String student = 'طالب علم';

  // Common Actions
  static const String save = 'محفوظ کریں';
  static const String cancel = 'منسوخ';
  static const String delete = 'حذف کریں';
  static const String edit = 'ترمیم';
  static const String add = 'شامل کریں';
  static const String search = 'تلاش کریں';
  static const String filter = 'فلٹر';
  static const String refresh = 'تازہ کریں';
  static const String loading = 'لوڈ ہو رہا ہے...';
  static const String noData = 'کوئی ڈیٹا نہیں';
  static const String error = 'خرابی';
  static const String success = 'کامیابی';

  // Messages
  static const String attendanceSaved = 'حاضری کامیابی سے محفوظ ہو گئی';
  static const String confirmSave = 'کیا آپ محفوظ کرنا چاہتے ہیں؟';

  // Days of Week (Urdu)
  static const String monday = 'پیر';
  static const String tuesday = 'منگل';
  static const String wednesday = 'بدھ';
  static const String thursday = 'جمعرات';
  static const String friday = 'جمعہ';
  static const String saturday = 'ہفتہ';
  static const String sunday = 'اتوار';

  // Darjaat (Levels)
  static const String darjaAwwal = 'درجہ اولیٰ';
  static const String darjaDuwum = 'درجہ دوم';
  static const String darjaSuwum = 'درجہ سوم';
  static const String darjaChaharum = 'درجہ چہارم';
  static const String darjaPanjum = 'درجہ پنجم';

  // Dashboard Cards
  static const String totalStudentsCard = 'کل طلباء';
  static const String todayAttendance = 'آج کی حاضری';
  static const String pendingFees = 'واجب الادا فیس';
  static const String upcomingExams = 'آئندہ امتحانات';
}
