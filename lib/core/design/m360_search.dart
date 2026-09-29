import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';

/// مدرسہ 360 — سرچ فیلڈ
/// The single canonical search field: search icon at the inline-start,
/// clear button when text is present, optional filter affordance at the
/// inline-end. Replaces the ad-hoc `SearchField` in `app_widgets.dart`.

class M360SearchField extends StatefulWidget {
  /// Creates a search field.
  const M360SearchField({
    super.key,
    this.controller,
    this.hint = 'تلاش کریں...',
    this.onChanged,
    this.onSubmitted,
    this.onFilterTap,
    this.autofocus = false,
    this.enabled = true,
  });

  /// External controller; the field creates and owns one when omitted.
  final TextEditingController? controller;

  /// Urdu hint (Nastaleeq).
  final String hint;

  /// Fired per keystroke.
  final ValueChanged<String>? onChanged;

  /// Fired on keyboard submit.
  final ValueChanged<String>? onSubmitted;

  /// When provided, a filter (tune) button renders at the inline-end.
  final VoidCallback? onFilterTap;

  /// Autofocus on mount.
  final bool autofocus;

  /// Disabled state.
  final bool enabled;

  @override
  State<M360SearchField> createState() => _M360SearchFieldState();
}

class _M360SearchFieldState extends State<M360SearchField> {
  late TextEditingController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(M360SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onTextChanged);
      if (_ownsController) _controller.dispose();
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = TextEditingController();
        _ownsController = true;
      }
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(M360Radius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: TextField(
        controller: _controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
        style: AppTypography.bodyMedium,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTypography.labelNastaliq.copyWith(
            color: AppColors.textSecondary,
          ),
          hintTextDirection: TextDirection.rtl,
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.textSecondary,
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'صاف کریں',
                  icon: const Icon(
                    Icons.clear,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                  },
                ),
              if (widget.onFilterTap != null)
                IconButton(
                  tooltip: 'فلٹر',
                  icon: const Icon(
                    Icons.tune,
                    color: AppColors.primary,
                  ),
                  onPressed: widget.onFilterTap,
                ),
            ],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: M360Spacing.md,
            vertical: M360Spacing.md,
          ),
        ),
      ),
    );
  }
}
