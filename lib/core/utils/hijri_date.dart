/// ہجری تاریخ
/// Hijri (Islamic) date conversion for display chips.
///
/// Uses the tabular (arithmetic) Islamic calendar — the same algorithm used
/// by most software calendars. It can differ by ±1 day from physical
/// moon-sighting, so it is suitable for display purposes (e.g. the
/// dashboard date chip), not for religious rulings.

class HijriDate {
  /// Hijri year, e.g. 1448.
  final int year;

  /// Hijri month, 1 (محرم) .. 12 (ذوالحجہ).
  final int month;

  /// Day of month, 1..30.
  final int day;

  const HijriDate({
    required this.year,
    required this.month,
    required this.day,
  });

  /// Urdu month names, index 0 = محرم.
  static const List<String> monthNamesUrdu = [
    'محرم',
    'صفر',
    'ربیع الاول',
    'ربیع الثانی',
    'جمادی الاول',
    'جمادی الثانی',
    'رجب',
    'شعبان',
    'رمضان',
    'شوال',
    'ذوالقعدہ',
    'ذوالحجہ',
  ];

  /// '3 ربیع الثانی 1448ھ'
  String formatUrdu() => '$day ${monthNamesUrdu[month - 1]} $yearھ';

  /// Converts a Gregorian calendar date to the tabular Islamic calendar.
  static HijriDate fromGregorian(DateTime date) {
    final jd = _gregorianToJd(date.year, date.month, date.day);
    var l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;
    final m = (24 * l) ~/ 709;
    final d = l - (709 * m) ~/ 24;
    final y = 30 * n + j - 30;
    return HijriDate(year: y, month: m, day: d);
  }

  /// Julian day number for a Gregorian calendar date.
  static int _gregorianToJd(int year, int month, int day) {
    final a = (14 - month) ~/ 12;
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;
    return day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045;
  }
}
