/// ڈیش بورڈ فریم ورک — ہلکا اسلامی پیٹرن
/// Dashboard framework — subtle Islamic geometric background.
///
/// Paints a faint eight-pointed-star lattice behind dashboard content.
/// Deliberately very low contrast: texture, not decoration.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Wraps [child] with a faint geometric star pattern behind it.
class PatternBackground extends StatelessWidget {
  final Widget child;

  /// Pattern ink colour. Defaults to a whisper of the primary teal.
  final Color color;

  const PatternBackground({
    super.key,
    required this.child,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarLatticePainter(color: color),
      child: child,
    );
  }
}

/// Eight-pointed stars (two overlaid squares) on a quiet grid.
class _StarLatticePainter extends CustomPainter {
  final Color color;

  /// Grid spacing in logical pixels.
  static const double _step = 96;

  /// Star radius in logical pixels.
  static const double _radius = 22;

  const _StarLatticePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double y = _step / 2; y < size.height + _step; y += _step) {
      for (double x = _step / 2; x < size.width + _step; x += _step) {
        _drawStar(canvas, paint, Offset(x, y), _radius);
      }
    }
  }

  /// Eight-pointed star = square + same square rotated 45°.
  void _drawStar(Canvas canvas, Paint paint, Offset c, double r) {
    final square = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        square.moveTo(p.dx, p.dy);
      } else {
        square.lineTo(p.dx, p.dy);
      }
    }
    square.close();

    final diamond = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + math.pi / 4;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      if (i == 0) {
        diamond.moveTo(p.dx, p.dy);
      } else {
        diamond.lineTo(p.dx, p.dy);
      }
    }
    diamond.close();

    canvas.drawPath(square, paint);
    canvas.drawPath(diamond, paint);
  }

  @override
  bool shouldRepaint(covariant _StarLatticePainter oldDelegate) =>
      oldDelegate.color != color;
}
