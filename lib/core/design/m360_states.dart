import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';
import 'm360_buttons.dart';

/// مدرسہ 360 — اسکرین اسٹیٹس
/// Screen states: empty, loading (skeleton shimmer) and error.
///
/// All copy is Urdu-first: titles in Nastaleeq, descriptions in Naskh.

/// Empty state: large tinted icon, Nastaleeq title, Naskh description and
/// an optional action button.
class M360EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const M360EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  /// Illustrative icon, shown large in a tinted circle.
  final IconData icon;

  /// Urdu title, e.g. «کوئی طالب علم نہیں ملا».
  final String title;

  /// Longer Naskh explanation, e.g. what to do next.
  final String description;

  /// Optional action label, e.g. «طالب علم شامل کریں».
  final String? actionLabel;

  /// Action handler; the button renders only with [actionLabel].
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(M360Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: M360Spacing.md),
            Text(
              title,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: AppTypography.titleSmall,
            ),
            const SizedBox(height: M360Spacing.xs),
            Text(
              description,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall,
            ),
            if (hasAction) ...[
              const SizedBox(height: M360Spacing.lg),
              M360SecondaryButton(
                label: actionLabel!,
                onPressed: onAction,
                icon: Icons.add,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading state: a shimmering skeleton list.
///
/// Renders [itemCount] skeleton rows; each row mimics an avatar + two text
/// lines. Pure presentation — no timers or business logic beyond the
/// shimmer animation itself.
class M360LoadingState extends StatelessWidget {
  /// Creates a skeleton loading list.
  const M360LoadingState({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(M360Spacing.md),
  });

  /// Number of skeleton rows.
  final int itemCount;

  /// Outer padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: M360Spacing.sm),
      itemBuilder: (_, __) => const _ShimmerRow(),
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _ShimmerBox(width: 48, height: 48, circular: true),
        SizedBox(width: M360Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShimmerBox(width: double.infinity, height: 16),
              SizedBox(height: M360Spacing.xs),
              _ShimmerBox(width: 160, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.circular = false,
  });

  final double width;
  final double height;
  final bool circular;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.divider.withValues(alpha: 0.45);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweep the highlight across the box as the controller repeats.
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius:
                widget.circular ? null : BorderRadius.circular(M360Radius.sm),
            shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * t, 0),
              end: Alignment(0.0 + 2.0 * t, 0),
              colors: [base, AppColors.surface, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Error state: warning icon, Urdu message and a retry button.
class M360ErrorState extends StatelessWidget {
  /// Creates an error state.
  const M360ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'دوبارہ کوشش کریں',
  });

  /// Urdu error message shown to the user (never a raw exception).
  final String message;

  /// Retry handler.
  final VoidCallback onRetry;

  /// Retry button label.
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(M360Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: M360Spacing.md),
            Text(
              'کچھ غلط ہو گیا',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: AppTypography.titleSmall,
            ),
            const SizedBox(height: M360Spacing.xs),
            Text(
              message,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: M360Spacing.lg),
            M360PrimaryButton(
              label: retryLabel,
              onPressed: onRetry,
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }
}
