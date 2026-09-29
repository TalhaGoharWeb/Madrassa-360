import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';

/// مدرسہ 360 — شیل کے اندر صفحے کا خول
/// Interim page wrapper for in-shell destination screens.
///
/// [AppShell] owns the ONLY [Scaffold] / top-level header. Screens rendered
/// as shell destinations must NOT build their own Scaffold/AppBar — they
/// return [ShellPageBody] instead, which preserves exactly what the old
/// Scaffold provided:
///
/// * [backgroundColor] — the old `Scaffold.backgroundColor`
/// * [actions] — the old `AppBar.actions`, rendered in a slim toolbar row
///   at the top of the body (Phase 10 promotes these to [PageHeader])
/// * [tabBar] — the old `AppBar.bottom` TabBar, rendered at the top of the
///   body under the same TabController scope
/// * [floatingActionButton] — the old `Scaffold.floatingActionButton`,
///   positioned bottom-inline-end (matches RTL Scaffold placement)
/// * [bottomNavigationBar] — the old `Scaffold.bottomNavigationBar`,
///   rendered pinned under the body (e.g. the attendance save CTA)
///
/// Phase 10 replaces this with full `PageContainer`/`PageHeader` conversion.
class ShellPageBody extends StatelessWidget {
  /// Creates the shell page body.
  const ShellPageBody({
    super.key,
    this.backgroundColor = AppColors.background,
    this.actions = const [],
    this.tabBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    required this.child,
  });

  /// Page background (was `Scaffold.backgroundColor`).
  final Color backgroundColor;

  /// Former `AppBar.actions` — kept functional in a slim toolbar.
  final List<Widget> actions;

  /// Former `AppBar.bottom` TabBar.
  final PreferredSizeWidget? tabBar;

  /// Former `Scaffold.floatingActionButton`.
  final Widget? floatingActionButton;

  /// Former `Scaffold.bottomNavigationBar` — pinned under the body.
  final Widget? bottomNavigationBar;

  /// Former `Scaffold.body` (or the TabBarView for tab screens).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Deep-pushed screens (e.g. the dashboard's announcement bell) lose
    // their old AppBar's automatic back button — restore it here whenever
    // this route can pop. As a shell destination canPop is false, so the
    // shell's own back chevron remains the single affordance.
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canPop || actions.isNotEmpty)
          _SlimToolbar(actions: actions, showBack: canPop),
        if (tabBar != null) tabBar!,
        Expanded(child: child),
        if (bottomNavigationBar != null) bottomNavigationBar!,
      ],
    );

    final body = floatingActionButton == null
        ? column
        : Stack(
            children: [
              column,
              PositionedDirectional(
                bottom: 16,
                end: 16,
                child: floatingActionButton!,
              ),
            ],
          );

    return ColoredBox(color: backgroundColor, child: body);
  }
}

/// Slim single-row toolbar that keeps former AppBar actions reachable
/// without a duplicate header. Shows a back chevron when the route can
/// pop (deep-pushed screens), so stripped screens stay navigable.
class _SlimToolbar extends StatelessWidget {
  const _SlimToolbar({required this.actions, this.showBack = false});

  final List<Widget> actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              tooltip: 'واپس',
              // arrow_back auto-mirrors in RTL (points right).
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}
