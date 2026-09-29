import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'm360_inputs.dart';

/// مدرسہ 360 — ڈراپ ڈاؤن
/// Single-select dropdown matching the [M360TextField] visual language:
/// Nastaleeq label, Naskh selected value, RTL-native, radius 12.

/// One dropdown option: the stored [value] and its Urdu [label].
class M360DropdownItem<T> {
  /// Creates a dropdown option.
  const M360DropdownItem({required this.value, required this.label});

  /// The value written to the model (e.g. a row id — never a display
  /// string).
  final T value;

  /// Urdu label shown in the menu.
  final String label;
}

/// Labeled single-select dropdown.
class M360Dropdown<T> extends StatelessWidget {
  /// Creates a dropdown.
  const M360Dropdown({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.hint,
    this.validator,
    this.enabled = true,
    this.prefixIcon,
  });

  /// Urdu field label (Nastaleeq), e.g. «درجہ منتخب کریں».
  final String label;

  /// Options.
  final List<M360DropdownItem<T>> items;

  /// Currently selected value; null shows [hint].
  final T? value;

  /// Selection handler; null disables the field.
  final ValueChanged<T?>? onChanged;

  /// Urdu hint (Nastaleeq).
  final String? hint;

  /// Validation; return an Urdu message or null when valid.
  final FormFieldValidator<T>? validator;

  /// Disabled state.
  final bool enabled;

  /// Icon at the inline-start (right side in RTL).
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item.value,
            child: Text(
              item.label,
              textDirection: TextDirection.rtl,
              style: AppTypography.bodyLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      validator: validator,
      style: AppTypography.bodyLarge,
      dropdownColor: AppColors.surface,
      icon: const Icon(
        Icons.arrow_drop_down,
        color: AppColors.textSecondary,
      ),
      decoration: m360FieldDecoration(
        label: label,
        hint: hint,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 22),
      ),
    );
  }
}
