import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';
import 'm360_buttons.dart';
import 'm360_inputs.dart';

/// مدرسہ 360 — ڈائیلاگز
/// Dialogs. All dialog chrome goes through [M360Dialog]; destructive actions
/// use [showM360ConfirmDialog], never an ad-hoc [AlertDialog].
///
/// * [M360Dialog] — title + content + actions shell (radius 16, RTL).
/// * [showM360Dialog] — shows an [M360Dialog], returns the popped value.
/// * [M360ConfirmDialog] — confirmation with optional danger styling and
///   optional typed confirmation for destructive platform actions.
/// * [showM360ConfirmDialog] — shows it, returns true when confirmed.

/// Standard dialog shell: Nastaleeq title, scrollable content, action row.
class M360Dialog extends StatelessWidget {
  /// Creates a dialog shell.
  const M360Dialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.icon,
    this.maxWidth = 480,
  });

  /// Urdu title (Nastaleeq).
  final String title;

  /// Dialog body — text, forms, lists.
  final Widget content;

  /// Action buttons, laid out inline-end (left in RTL), e.g.
  /// `[M360TertiaryButton(cancel), M360PrimaryButton(confirm)]`.
  final List<Widget> actions;

  /// Optional header icon in a tinted circle.
  final IconData? icon;

  /// Max dialog width; defaults to 480.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(M360Radius.lg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(M360Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: M360Spacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      textDirection: TextDirection.rtl,
                      style: AppTypography.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: M360Spacing.sm),
              Flexible(
                child: SingleChildScrollView(child: content),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: M360Spacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: M360Spacing.xs),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows an [M360Dialog]; completes with the value passed to
/// `Navigator.pop`, or null when dismissed.
Future<T?> showM360Dialog<T>(
  BuildContext context, {
  required String title,
  required Widget content,
  List<Widget> actions = const [],
  IconData? icon,
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (context) => M360Dialog(
      title: title,
      content: content,
      actions: actions,
      icon: icon,
    ),
  );
}

/// Confirmation dialog.
///
/// Set [danger] for destructive actions (red confirm button, warning icon).
/// Set [requireTypedConfirmation] with [expectedText] for platform-level
/// destructive actions (e.g. tenant suspension): the confirm button stays
/// disabled until the user types the expected text exactly.
class M360ConfirmDialog extends StatefulWidget {
  /// Creates a confirmation dialog.
  const M360ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'تصدیق کریں',
    this.cancelLabel = 'منسوخ کریں',
    this.danger = false,
    this.requireTypedConfirmation = false,
    this.expectedText,
    this.typedHint = 'تصدیق کے لیے نام لکھیں',
  }) : assert(
          !requireTypedConfirmation ||
              (expectedText != null && expectedText.isNotEmpty),
          'Typed confirmation needs a non-empty expectedText.',
        );

  /// Urdu title (Nastaleeq).
  final String title;

  /// Urdu explanation (Naskh).
  final String message;

  /// Confirm button label.
  final String confirmLabel;

  /// Cancel button label.
  final String cancelLabel;

  /// Red confirm button + warning icon.
  final bool danger;

  /// Require typing [expectedText] before confirming.
  final bool requireTypedConfirmation;

  /// Text the user must type; required when [requireTypedConfirmation].
  final String? expectedText;

  /// Label for the typed-confirmation field.
  final String typedHint;

  @override
  State<M360ConfirmDialog> createState() => _M360ConfirmDialogState();
}

class _M360ConfirmDialogState extends State<M360ConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm =
        !widget.requireTypedConfirmation || _matches;
    return M360Dialog(
      title: widget.title,
      icon: widget.danger
          ? Icons.warning_amber_rounded
          : Icons.help_outline,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.message,
            textDirection: TextDirection.rtl,
            style: AppTypography.bodyMedium,
          ),
          if (widget.requireTypedConfirmation) ...[
            const SizedBox(height: M360Spacing.md),
            M360TextField(
              label: widget.typedHint,
              controller: _controller,
              onChanged: (value) => setState(
                () => _matches = value.trim() == widget.expectedText,
              ),
            ),
          ],
        ],
      ),
      actions: [
        M360TertiaryButton(
          label: widget.cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        if (widget.danger)
          M360DangerButton(
            label: widget.confirmLabel,
            icon: Icons.delete_outline,
            onPressed:
                canConfirm ? () => Navigator.of(context).pop(true) : null,
          )
        else
          M360PrimaryButton(
            label: widget.confirmLabel,
            onPressed:
                canConfirm ? () => Navigator.of(context).pop(true) : null,
          ),
      ],
    );
  }
}

/// Shows an [M360ConfirmDialog]; completes with true when the user
/// confirms, false on cancel/dismiss.
Future<bool> showM360ConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تصدیق کریں',
  String cancelLabel = 'منسوخ کریں',
  bool danger = false,
  bool requireTypedConfirmation = false,
  String? expectedText,
  String typedHint = 'تصدیق کے لیے نام لکھیں',
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: !requireTypedConfirmation,
    builder: (context) => M360ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      requireTypedConfirmation: requireTypedConfirmation,
      expectedText: expectedText,
      typedHint: typedHint,
    ),
  ).then((value) => value ?? false);
}
