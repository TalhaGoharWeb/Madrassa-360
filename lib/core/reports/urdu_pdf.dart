/// اردو PDF رینڈرنگ — نستعلیق کی درست تشکیل
/// Urdu text rendering for PDFs — CORRECT Nastaleeq shaping.
///
/// ── WHY THIS FILE EXISTS ─────────────────────────────────────────
/// The `pdf` package (3.12.0, verified from source) shapes Arabic script
/// by mapping each character to a Unicode *presentation form*
/// (U+FB50–FDFF / U+FE70–FEFF) in `lib/src/pdf/font/arabic.dart`, and it
/// performs NO OpenType GSUB/GPOS shaping at all (upstream issue
/// DavBfr/dart_pdf#1907: "the library currently maps Unicode → glyphs
/// directly without applying GSUB/GPOS shaping").
///
/// The bundled Jameel Noori Nastaleeq TTFs were inspected with
/// fontTools (2026-09-25):
///   • Arabic base block (U+0600–06FF): 127 glyphs present
///   • Presentation Forms-A (U+FB50–FDFF): 4 of 688 present
///   • Presentation Forms-B (U+FE70–FEFF): 0 of 144 present
///   • GSUB: yes, GPOS: yes (full OpenType shaping tables)
///
/// Conclusion: feeding Urdu strings to `pw.Text` with the Nastaleeq
/// font would address presentation-form codepoints the font DOES NOT
/// HAVE → tofu / broken glyphs. And even if it did, the result would
/// be Naskh-style joining, not Nastaleeq's cascading layout, which
/// fundamentally requires HarfBuzz-level GSUB/GPOS.
///
/// The only correct approach with this toolchain: shape Urdu with the
/// FLUTTER ENGINE (Skia/HarfBuzz — the same pipeline that renders the
/// app's own UI correctly) via [TextPainter], rasterise to PNG, and
/// embed the image in the PDF. Latin text keeps using the pdf package's
/// native text (searchable/selectable); every Urdu string is routed
/// through [UrduPdf].
///
/// Confidence: HIGH that glyphs are correct (same shaper as on-screen
/// UI). Known trade-off: Urdu text in PDFs is raster, not selectable —
/// documented in docs/REPORTING.md.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf/widgets.dart' as pw;

/// One rasterised Urdu text run, sized in PDF points.
class UrduPdfImage {
  final Uint8List png;
  final double widthPt;
  final double heightPt;

  const UrduPdfImage({
    required this.png,
    required this.widthPt,
    required this.heightPt,
  });
}

/// Renders Urdu strings to PNGs via the Flutter text engine.
///
/// Instances are cheap; keep one per document build so repeated strings
/// (table headers, labels) are rasterised once.
class UrduPdf {
  UrduPdf({
    this.pixelRatio = 3.0,
    this.fontFamily = 'JameelNooriNastaleeq',
    this.lineHeight = 1.9,
  });

  /// Raster scale. 3x keeps Nastaleeq's fine strokes crisp in print.
  final double pixelRatio;

  /// Must match the `family` declared in pubspec.yaml fonts.
  final String fontFamily;

  /// Nastaleeq is tall; generous line height avoids clipped nuqtas.
  final double lineHeight;

  final Map<String, UrduPdfImage> _cache = {};

  /// Matches Arabic-script codepoints (Arabic, Urdu extensions,
  /// presentation forms) — used to auto-route mixed content.
  static final RegExp _urdu = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  static bool isUrdu(String s) => _urdu.hasMatch(s);

  String _key(String text, double size, int color, double? maxW, bool bold,
          int align) =>
      '$text|$size|$color|${maxW?.toStringAsFixed(1)}|$bold|$align';

  /// Rasterises [text] (RTL, shaped by the engine).
  ///
  /// [maxWidthPt] wraps the paragraph; null = single line.
  Future<UrduPdfImage> render(
    String text, {
    double fontSize = 12,
    ui.Color color = const ui.Color(0xFF212121),
    double? maxWidthPt,
    ui.TextAlign align = ui.TextAlign.right,
    bool bold = false,
  }) async {
    if (text.trim().isEmpty) return _empty();
    final key = _key(
        text, fontSize, color.value, maxWidthPt, bold, align.index);
    final hit = _cache[key];
    if (hit != null) return hit;

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          height: lineHeight,
        ),
      ),
      textDirection: ui.TextDirection.rtl,
      textAlign: align,
    );
    painter.layout(maxWidth: maxWidthPt ?? double.infinity);

    final w = painter.width;
    final h = painter.height;
    if (w <= 0 || h <= 0) return _empty();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);
    painter.paint(canvas, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (w * pixelRatio).ceil(),
      (h * pixelRatio).ceil(),
    );
    final bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    final result = UrduPdfImage(
      png: bytes!.buffer.asUint8List(),
      widthPt: w,
      heightPt: h,
    );
    _cache[key] = result;
    return result;
  }

  /// A [pw.Widget] that draws the rasterised text at its natural size.
  Future<pw.Widget> text(
    String text, {
    double fontSize = 12,
    ui.Color color = const ui.Color(0xFF212121),
    double? maxWidthPt,
    ui.TextAlign align = ui.TextAlign.right,
    bool bold = false,
  }) async {
    final img = await render(
      text,
      fontSize: fontSize,
      color: color,
      maxWidthPt: maxWidthPt,
      align: align,
      bold: bold,
    );
    return pw.Image(
      pw.MemoryImage(img.png),
      width: img.widthPt,
      height: img.heightPt,
    );
  }

  UrduPdfImage _empty() {
    final key = '__empty__';
    final hit = _cache[key];
    if (hit != null) return hit;
    // Built lazily on first use; cached so the transparent 1×1 PNG is
    // constructed only once. (Not `const`: the byte list is static final.)
    final img = UrduPdfImage(
      png: _kTransparent1px,
      widthPt: 1,
      heightPt: 1,
    );
    _cache[key] = img;
    return img;
  }

  /// 1×1 transparent PNG.
  static final _kTransparent1px = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}
