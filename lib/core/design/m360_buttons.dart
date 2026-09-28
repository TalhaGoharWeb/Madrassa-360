import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';

/// مدرسہ 360 — بٹنز
/// Urdu-first buttons. Labels render in Nastaleeq ([AppTypography.labelNastaliq]);
/// every button guarantees a 48px minimum touch target and full RTL support.
///
/// Variants:
/// * [M360PrimaryButton] — filled teal, the default call-to-action.
/// * [M360SecondaryButton] — outlined teal, secondary actions.
/// * [M360DangerButton] — filled red, destructive actions.
/// * [M360IconButton] — 48×48 icon-only button.
class M360PrimaryButton extends StatelessWidget {
  /// Creates a primary (filled teal) button.
  ///
  /// When [isLoading] is true a spinner replaces the label and the button
  /// is disabled. Set [fullWidth] to stretch across the parent.
  const M360PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.fullWidth = false,
    this.icon,
    this.semanticLabel,
  });

  /// Urdu label, rendered in Nastaleeq.
  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Shows a loading spinner and disables the button.
  final bool isLoading;

  /// Stretches the button to the parent width.
  final bool fullWidth;

  /// Optional leading icon (appears at the inline-start, i.e. right in RTL).
  final IconData? icon;

  /// Accessibility label; defaults to [label].
  final String? semanticLabel;

  bool get _disabled => onPressed == null || isLoading;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: _disabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.divider,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(88, M360TouchTarget.minHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: M360Spacing.lg,
          vertical: M360Spacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
        ),
        textStyle: AppTypography.labelNastaliq.copyWith(color: Colors.white),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        spinnerColor: Colors.white,
      ),
    );
    return Semantics(
      button: true,
      enabled: !_disabled,
      label: semanticLabel ?? label,
      child:
          fullWidth ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Outlined secondary button — teal border and label on a surface background.
class M360SecondaryButton extends StatelessWidget {
  /// Creates a secondary (outlined) button.
  const M360SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.fullWidth = false,
    this.icon,
    this.semanticLabel,
  });

  /// Urdu label, rendered in Nastaleeq.
  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Shows a loading spinner and disables the button.
  final bool isLoading;

  /// Stretches the button to the parent width.
  final bool fullWidth;

  /// Optional leading icon.
  final IconData? icon;

  /// Accessibility label; defaults to [label].
  final String? semanticLabel;

  bool get _disabled => onPressed == null || isLoading;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: _disabled ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textSecondary,
        minimumSize: const Size(88, M360TouchTarget.minHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: M360Spacing.lg,
          vertical: M360Spacing.xs,
        ),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
        ),
        textStyle:
            AppTypography.labelNastaliq.copyWith(color: AppColors.primary),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        spinnerColor: AppColors.primary,
      ),
    );
    return Semantics(
      button: true,
      enabled: !_disabled,
      label: semanticLabel ?? label,
      child:
          fullWidth ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Destructive-action button — filled red, white Nastaleeq label.
class M360DangerButton extends StatelessWidget {
  /// Creates a danger (filled red) button, e.g. «حذف کریں».
  const M360DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.fullWidth = false,
    this.icon,
    this.semanticLabel,
  });

  /// Urdu label, rendered in Nastaleeq.
  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Shows a loading spinner and disables the button.
  final bool isLoading;

  /// Stretches the button to the parent width.
  final bool fullWidth;

  /// Optional leading icon.
  final IconData? icon;

  /// Accessibility label; defaults to [label].
  final String? semanticLabel;

  bool get _disabled => onPressed == null || isLoading;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: _disabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.divider,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(88, M360TouchTarget.minHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: M360Spacing.lg,
          vertical: M360Spacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(M360Radius.md),
        ),
        textStyle: AppTypography.labelNastaliq.copyWith(color: Colors.white),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        spinnerColor: Colors.white,
      ),
    );
    return Semantics(
      button: true,
      enabled: !_disabled,
      label: semanticLabel ?? label,
      child:
          fullWidth ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// 48×48 icon-only button with an ink ripple and tooltip.
class M360IconButton extends StatelessWidget {
  /// Creates an icon button.
  ///
  /// [tooltip] is required for accessibility — every icon-only button must
  /// announce an Urdu label to screen readers.
  const M360IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color = AppColors.primary,
    this.backgroundColor,
  });

  /// The icon to display.
  final IconData icon;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Urdu accessibility label and hover tooltip.
  final String tooltip;

  /// Icon color.
  final Color color;

  /// Optional circular background; defaults to transparent.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: backgroundColor ?? Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: M360TouchTarget.minWidth,
              height: M360TouchTarget.minHeight,
              child: Icon(
                icon,
                color: onPressed == null ? AppColors.divider : color,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared label / spinner / icon composition for the text buttons.
class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.isLoading,
    required this.spinnerColor,
    this.icon,
  });

  final String label;
  final bool isLoading;
  final Color spinnerColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: spinnerColor,
            ),
          ),
          const SizedBox(width: M360Spacing.xs),
          Text(
            label,
            textDirection: TextDirection.rtl,
            style: AppTypography.labelNastaliq
                .copyWith(color: spinnerColor.withValues(alpha: 0.85)),
          ),
        ],
      );
    }
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: M360Spacing.xs),
          Flexible(
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Text(
      label,
      textDirection: TextDirection.rtl,
      overflow: TextOverflow.ellipsis,
    );
  }
}
