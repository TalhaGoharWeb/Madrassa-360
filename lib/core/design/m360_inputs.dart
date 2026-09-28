import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';

/// مدرسہ 360 — ان پٹ فیلڈز
/// Form inputs. Product policy, enforced here by construction:
///
/// * labels → Nastaleeq ([AppTypography.labelNastaliq])
/// * hints → Nastaleeq (never Naskh)
/// * typed text → Naskh ([AppTypography.bodyLarge])
/// * fields are RTL-native: [TextDirection.rtl] with right-aligned text,
///   so Urdu shaping and cursor behaviour are correct even inside an
///   otherwise LTR subtree.
class M360TextField extends StatelessWidget {
  /// Creates a labeled text field.
  const M360TextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.onSaved,
    this.onFieldSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.inputFormatters,
    this.onTap,
  });

  /// Urdu field label (Nastaleeq), e.g. «طالب علم کا نام».
  final String label;

  /// Urdu hint (Nastaleeq), e.g. «پورا نام لکھیں».
  final String? hint;

  /// Text controller.
  final TextEditingController? controller;

  /// Validation; return an Urdu message or null when valid.
  final FormFieldValidator<String>? validator;

  /// Change listener.
  final ValueChanged<String>? onChanged;

  /// Form-save handler.
  final FormFieldSetter<String>? onSaved;

  /// Submit-action handler.
  final ValueChanged<String>? onFieldSubmitted;

  /// Icon at the inline-start (right side in RTL).
  final IconData? prefixIcon;

  /// Icon at the inline-end (left side in RTL).
  final IconData? suffixIcon;

  /// Obscure text (passwords).
  final bool obscureText;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Maximum lines; >1 makes a textarea.
  final int? maxLines;

  /// Minimum lines.
  final int? minLines;

  /// Disabled state.
  final bool enabled;

  /// Read-only (e.g. picker-backed fields).
  final bool readOnly;

  /// Autofocus on mount.
  final bool autofocus;

  /// Input formatters.
  final List<TextInputFormatter>? inputFormatters;

  /// Tap handler (used with [readOnly] picker fields).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      onSaved: onSaved,
      onFieldSubmitted: onFieldSubmitted,
      onTap: onTap,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      minLines: minLines,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      inputFormatters: inputFormatters,
      // RTL-native: Urdu shaping, cursor and selection follow RTL rules
      // regardless of the ambient directionality.
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      style: AppTypography.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.labelNastaliq,
        hintText: hint,
        // Policy: hints MUST be Nastaleeq.
        hintStyle: AppTypography.labelNastaliq.copyWith(
          color: AppColors.textSecondary,
        ),
        hintTextDirection: TextDirection.rtl,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIcon:
            prefixIcon == null ? null : Icon(prefixIcon, size: 22),
        suffixIcon:
            suffixIcon == null ? null : Icon(suffixIcon, size: 22),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: M360Spacing.md,
          vertical: M360Spacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
          borderSide:
              const BorderSide(color: AppColors.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
          borderSide:
              BorderSide(color: AppColors.divider.withValues(alpha: 0.6)),
        ),
        errorStyle: AppTypography.bodySmall.copyWith(
          color: AppColors.error,
        ),
        errorMaxLines: 3,
      ),
    );
  }
}

/// A read-only field that opens a picker (date, dropdown, …) on tap.
///
/// Renders an [M360TextField] in read-only mode with a trailing affordance
/// icon; [onTap] opens the picker and the caller writes the chosen value
/// into [controller].
class M360PickerField extends StatelessWidget {
  /// Creates a picker-backed field.
  const M360PickerField({
    super.key,
    required this.label,
    required this.controller,
    required this.onTap,
    this.hint,
    this.validator,
    this.pickerIcon = Icons.calendar_today,
    this.enabled = true,
  });

  /// Urdu label (Nastaleeq).
  final String label;

  /// Controller holding the display value.
  final TextEditingController controller;

  /// Opens the picker.
  final VoidCallback onTap;

  /// Urdu hint (Nastaleeq).
  final String? hint;

  /// Validation.
  final FormFieldValidator<String>? validator;

  /// Trailing affordance icon.
  final IconData pickerIcon;

  /// Disabled state.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return M360TextField(
      label: label,
      hint: hint,
      controller: controller,
      validator: validator,
      readOnly: true,
      enabled: enabled,
      suffixIcon: pickerIcon,
      onTap: enabled ? onTap : null,
    );
  }
}
