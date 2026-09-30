/// m360 navigation helpers — ONE NAVIGATION SYSTEM.
///
/// Dashboard cards push detail screens via [pushM360Page], which wraps the
/// page in a [Scaffold] painted with the app background. Screens built with
/// [PageContainer] intentionally carry no [Scaffold] of their own (the shell
/// provides it), so pushing them bare leaves the route background black.
library;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Pushes [page] onto the navigator wrapped in a [Scaffold] with the
/// standard app background.
///
/// Use this for every dashboard-card → detail-screen push. Pages that
/// already own a [Scaffold] are unaffected (a nested Scaffold is harmless).
Future<T?> pushM360Page<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: page),
      ),
    ),
  );
}
