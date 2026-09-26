/// ڈیش بورڈ فریم ورک — سیکشن سرخی
/// Dashboard framework — small section heading.
///
/// The bold sub-heading rendered above dashboard slot content
/// (e.g. 'آج کا مالی خلاصہ' above the stat rows).

import 'package:flutter/material.dart';

import '../../../core/constants/app_typography.dart';

/// Small bold heading used above a dashboard slot's content.
class SlotHeading extends StatelessWidget {
  final String title;

  const SlotHeading(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
