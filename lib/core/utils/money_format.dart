/// رقم کی شکل — پاکستانی گروپنگ
/// Money formatting shared by the role dashboards (Phase 7b).
///
/// Pakistani digit grouping: Rs 1,25,000 (last group of 3, then groups
/// of 2). Keep dashboard money labels consistent everywhere.

/// Formats [amount] as 'Rs 1,25,000' (Pakistani grouping).
String formatRs(double amount) {
  final negative = amount < 0;
  final s = amount.abs().round().toString();
  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}Rs $grouped';
}
