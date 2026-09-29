import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';

/// مدرسہ 360 — ڈیپ اسکرین ایپ بار
/// App bar for deep screens pushed via [Navigator.push] (wizards, detail
/// pages, dialogs-as-pages) that live OUTSIDE the shell's chrome.
///
/// The [AppShell] owns the global header — pages inside the shell must use
/// [PageHeader] (see `m360_page.dart`), never this bar. One global header,
/// one page header, no nested app bars.

class M360AppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a deep-screen app bar.
  const M360AppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.showBack = true,
    this.onBack,
    this.bottom,
  });

  /// Urdu title (Nastaleeq).
  final String title;

  /// Trailing actions.
  final List<Widget> actions;

  /// Show the back button; defaults to true.
  final bool showBack;

  /// Custom back behavior; defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// Optional tab bar / bottom widget.
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: showBack ? 0 : 16,
      leading: showBack
          ? IconButton(
              tooltip: 'واپس',
              icon: const Icon(Icons.arrow_back),
              color: AppColors.primary,
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            )
          : null,
      title: Text(
        title,
        textDirection: TextDirection.rtl,
        style: AppTypography.titleMedium,
        overflow: TextOverflow.ellipsis,
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}
