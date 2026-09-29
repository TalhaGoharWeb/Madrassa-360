import 'package:flutter/material.dart';

import 'package:madrasa_360/core/constants/app_typography.dart';

/// مدرسہ 360 — لاطینی متن
/// Technical text (emails, invoice numbers, ISBNs, URLs) inside RTL pages.
///
/// [M360LatinText] forces LTR base direction and the Naskh-family rendering
/// so mixed content stays legible; [M360Email] is a semantic alias for
/// emails/contact text.

class M360LatinText extends StatelessWidget {
  /// Creates LTR technical text.
  const M360LatinText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  /// The technical text (email, identifier, URL, number).
  final String text;

  /// Style override; defaults to [AppTypography.bodyMedium].
  final TextStyle? style;

  /// Horizontal alignment.
  final TextAlign? textAlign;

  /// Max lines before ellipsizing.
  final int? maxLines;

  /// Overflow behavior.
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textDirection: TextDirection.ltr,
      style: style ?? AppTypography.bodyMedium,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Semantic alias for emails/contact text in RTL layouts.
class M360Email extends M360LatinText {
  /// Creates LTR email text.
  const M360Email(
    super.text, {
    super.key,
    super.style,
    super.textAlign,
    super.maxLines,
    super.overflow,
  });
}
