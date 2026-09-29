import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'design_tokens.dart';
import 'responsive.dart';

/// مدرسہ 360 — پیج کنٹینر اور پیج ہیڈر
/// The ONLY page chrome content screens may use inside [AppShell].
///
/// Pages must NOT build their own Scaffold/AppBar — the shell owns
/// navigation, the global header, and the page background. A page is:
///
/// ```dart
/// PageContainer(
///   header: PageHeader(
///     breadcrumb: 'طلبہ',
///     title: 'طلبہ کی فہرست',
///     description: '...',
///     actions: [M360PrimaryButton(label: '+ نیا طالب علم', ...)],
///   ),
///   child: ...,
/// )
/// ```

/// Page title block: breadcrumb, title, description, actions.
class PageHeader extends StatelessWidget {
  /// Creates a page header.
  const PageHeader({
    super.key,
    required this.title,
    this.description,
    this.breadcrumb,
    this.actions = const [],
  });

  /// Urdu page title (Nastaleeq), e.g. «طلبہ کی فہرست».
  final String title;

  /// Optional one-line Naskh description under the title.
  final String? description;

  /// Optional breadcrumb label, e.g. «طلبہ».
  final String? breadcrumb;

  /// Action buttons at the inline-end (e.g. the primary CTA).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: M360Spacing.md,
        bottom: M360Spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (breadcrumb != null)
                  Text(
                    breadcrumb!,
                    textDirection: TextDirection.rtl,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.titleLarge,
                ),
                if (description != null) ...[
                  const SizedBox(height: M360Spacing.xxs),
                  Text(
                    description!,
                    textDirection: TextDirection.rtl,
                    style: AppTypography.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: M360Spacing.sm),
            Wrap(
              spacing: M360Spacing.xs,
              runSpacing: M360Spacing.xs,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Page body wrapper: centers content at the breakpoint max width and
/// owns the single page scroll. Never add another Scaffold inside.
class PageContainer extends StatelessWidget {
  /// Creates a page container.
  const PageContainer({
    super.key,
    required this.header,
    required this.child,
    this.scrollable = true,
    this.maxWidth,
  });

  /// The page's [PageHeader].
  final PageHeader header;

  /// Page content.
  final Widget child;

  /// Whether the content scrolls as one page; set false when the child
  /// manages its own scroll (e.g. a full-height table).
  final bool scrollable;

  /// Max content width override; defaults to the desktop layout max.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return M360ConstrainedWidth(
      maxWidth: maxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: scrollable
                ? SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      bottom: M360Spacing.lg,
                    ),
                    child: child,
                  )
                : child,
          ),
        ],
      ),
    );
  }
}
