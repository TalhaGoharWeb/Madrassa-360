import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';
import 'm360_inputs.dart';

/// مدرسہ 360 — تاریخ منتخب کریں
/// Urdu-styled date picker around [showDatePicker]. The calendar header
/// uses the design-system color scheme; Urdu month/day names come from the
/// app's Urdu localization (see `main.dart`).

/// Shows the canonical date picker; completes with the chosen date or
/// null when dismissed.
///
/// [initialDate] defaults to today. Bounds default to one year past /
/// one year future — override for enrollment or document dates.
Future<DateTime?> showM360DatePicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String? helpText,
  String? cancelText,
  String? confirmText,
  bool selectableFutureOnly = false,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDatePicker(
    context: context,
    initialDate: initialDate ?? today,
    firstDate: firstDate ?? today.subtract(const Duration(days: 365)),
    lastDate: lastDate ??
        (selectableFutureOnly ? today : today.add(const Duration(days: 365))),
    helpText: helpText ?? 'تاریخ منتخب کریں',
    cancelText: cancelText ?? 'منسوخ کریں',
    confirmText: confirmText ?? 'منتخب کریں',
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

/// Read-only date display field: shows the selected date as Naskh text and
/// opens [showM360DatePicker] on tap. Use inside forms where dates are
/// picked, not typed.
///
/// [formatter] converts the date to display text; it must produce Urdu
/// output (e.g. the project's Urdu date utility), never raw ISO text.
class M360DatePicker extends StatelessWidget {
  /// Creates a date-picker field.
  const M360DatePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.formatter,
    this.hint,
    this.firstDate,
    this.lastDate,
    this.validator,
    this.enabled = true,
  });

  /// Urdu field label (Nastaleeq).
  final String label;

  /// Selected date; null renders [hint].
  final DateTime? value;

  /// Handler with the newly picked date.
  final ValueChanged<DateTime?> onChanged;

  /// Converts [value] to display text (Urdu via the project date utility).
  final String Function(DateTime) formatter;

  /// Urdu hint (Nastaleeq).
  final String? hint;

  /// Picker lower bound.
  final DateTime? firstDate;

  /// Picker upper bound.
  final DateTime? lastDate;

  /// Validation; return an Urdu message or null when valid.
  final FormFieldValidator<DateTime>? validator;

  /// Disabled state.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(M360Radius.md),
      onTap: enabled
          ? () async {
              final picked = await showM360DatePicker(
                context,
                initialDate: value,
                firstDate: firstDate,
                lastDate: lastDate,
              );
              if (picked != null) onChanged(picked);
            }
          : null,
      child: InputDecorator(
        decoration: m360FieldDecoration(
          label: label,
          hint: hint,
          prefixIcon: const Icon(
            Icons.calendar_today_outlined,
            size: 22,
          ),
        ),
        child: Text(
          value == null ? '' : formatter(value!),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: AppTypography.bodyLarge,
        ),
      ),
    );
  }
}
