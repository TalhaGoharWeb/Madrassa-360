/// تاریخ کی افادیت
/// Date and Time Utilities

import 'package:intl/intl.dart';

class DateUtils {
  /// Format date to Urdu format (dd/MM/yyyy)
  static String formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Format time to 12-hour format
  static String formatTime(DateTime time) {
    return DateFormat('hh:mm a').format(time);
  }

  /// Format date and time
  static String formatDateTime(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy hh:mm a').format(dateTime);
  }

  /// Format date to Urdu day name
  static String formatDayName(DateTime date) {
    final dayNumber = date.weekday;
    const urduDays = [
      'سوموار', // Monday
      'منگل', // Tuesday
      'بدھ', // Wednesday
      'جمعرات', // Thursday
      'جمعہ', // Friday
      'ہفتہ', // Saturday
      'اتوار', // Sunday
    ];
    return urduDays[dayNumber - 1];
  }

  /// Format month name in Urdu
  static String formatMonthName(DateTime date) {
    const urduMonths = [
      'جنوری',
      'فروری',
      'مارچ',
      'اپریل',
      'مئی',
      'جون',
      'جولائی',
      'اگست',
      'ستمبر',
      'اکتوبر',
      'نومبر',
      'دسمبر',
    ];
    return urduMonths[date.month - 1];
  }

  /// Format date with Urdu month
  static String formatDateUrdu(DateTime date) {
    return '${date.day} ${formatMonthName(date)} ${date.year}';
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Check if date is yesterday
  static bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  /// Check if date is tomorrow
  static bool isTomorrow(DateTime date) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day;
  }

  /// Get relative date string (آج، کل، etc.)
  static String getRelativeDateString(DateTime date) {
    if (isToday(date)) return 'آج';
    if (isYesterday(date)) return 'کل';
    if (isTomorrow(date)) return 'آنے والا کل';
    return formatDateUrdu(date);
  }

  /// Get time ago string
  static String getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'ابھی';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} منٹ پہلے';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} گھنٹے پہلے';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} دن پہلے';
    } else {
      return formatDate(dateTime);
    }
  }

  /// Get start of day
  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get end of day
  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  /// Get start of month
  static DateTime startOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  /// Get end of month
  static DateTime endOfMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0, 23, 59, 59);
  }

  /// Get days in month
  static int daysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  /// Check if date is in range
  static bool isInRange(DateTime date, DateTime start, DateTime end) {
    return date.isAfter(start) && date.isBefore(end);
  }

  /// Add working days (skip weekends)
  static DateTime addWorkingDays(DateTime date, int days) {
    var result = date;
    var addedDays = 0;

    while (addedDays < days) {
      result = result.add(const Duration(days: 1));
      // Skip Saturday (6) and Sunday (7)
      if (result.weekday != DateTime.saturday && result.weekday != DateTime.sunday) {
        addedDays++;
      }
    }

    return result;
  }

  /// Parse date from string (dd/MM/yyyy)
  static DateTime? parseDate(String dateString) {
    try {
      return DateFormat('dd/MM/yyyy').parse(dateString);
    } catch (e) {
      return null;
    }
  }

  /// Get age from date of birth
  static int getAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }
}

/// Numbers display — always English (Latin) digits
class UrduNumbers {
  static const _urduDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  /// Return number as English Latin digits (no-op wrapper kept for API compat)
  static String toUrdu(dynamic number) => number.toString();

  /// Convert Urdu/Arabic digits to English
  static String toEnglish(String urduNumber) {
    return urduNumber.split('').map((char) {
      final index = _urduDigits.indexOf(char);
      return index >= 0 ? index.toString() : char;
    }).join();
  }
}
