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

/// پاکستانی گروپنگ کے ساتھ رقم — مشترکہ معاون
/// Shared PKR money format for every financial surface.
///
/// Pakistani digit grouping: 380000 → '3,80,000 روپے'. Rounds to whole
/// rupees — the app never records paisa. Use this (never a local
/// re-implementation) wherever money is shown: dashboards, fee rows,
/// invoices, payments, ledger, expenses, receipts and reports. The currency
/// marker is part of the output — do NOT append another 'روپے' yourself.
String formatPK(num value) {
  final n = value.round();
  final sign = n < 0 ? '-' : '';
  final digits = n.abs().toString();
  final String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.add(rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    groups.add(rest);
    grouped = '${groups.reversed.join(',')},$last3';
  }
  return '$sign$grouped روپے';
}
