/// PDF اسمبلی کٹ
/// PDF assembly kit — branded header/footer, bilingual widgets, tables.
///
/// All Urdu strings are rasterised through [UrduPdf] (see urdu_pdf.dart
/// for why `pw.Text` can NOT be used for Urdu with the Nastaleeq font).
/// Latin text uses the pdf engine's native text (searchable).
///
/// Because `pw.MultiPage`'s header/footer/build callbacks are
/// synchronous, every Urdu image is pre-rendered BEFORE the document is
/// assembled — report builders are async and return finished widgets.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_branding.dart';
import 'urdu_pdf.dart';

PdfColor _pdf(Color c) => PdfColor(
      ((c.value >> 16) & 0xFF) / 255.0,
      ((c.value >> 8) & 0xFF) / 255.0,
      (c.value & 0xFF) / 255.0,
      ((c.value >> 24) & 0xFF) / 255.0,
    );

ui.Color _ui(Color c) => ui.Color(c.value);

/// Async build context handed to every report builder.
class PdfBuildScope {
  final ReportBranding branding;
  final UrduPdf urdu;

  final PdfColor primary;
  final PdfColor secondary;
  final PdfColor accent;
  static final PdfColor ink = PdfColor(0x21 / 255, 0x21 / 255, 0x21 / 255);
  static final PdfColor muted = PdfColor(0x75 / 255, 0x75 / 255, 0x75 / 255);
  static final PdfColor line = PdfColor(0xBD / 255, 0xBD / 255, 0xBD / 255);
  static final PdfColor zebra = PdfColor(0xF5 / 255, 0xF5 / 255, 0xF5 / 255);

  // Pre-rendered header pieces (header callback must stay sync).
  final pw.Widget _nameUr;
  final pw.Widget? _addrUr;
  final pw.Widget? _contactUr;
  final pw.Widget? _logo;
  final pw.Widget _titleUr;
  final pw.Widget? _subtitleUr;
  final String _titleEn;
  final String? _subtitleEn;
  final bool _bare;

  PdfBuildScope._({
    required this.branding,
    required this.urdu,
    required PdfColor primary,
    required PdfColor secondary,
    required PdfColor accent,
    required pw.Widget nameUr,
    required pw.Widget? addrUr,
    required pw.Widget? contactUr,
    required pw.Widget? logo,
    required pw.Widget titleUr,
    required pw.Widget? subtitleUr,
    required String titleEn,
    required String? subtitleEn,
    required bool bare,
  })  : primary = primary,
        secondary = secondary,
        accent = accent,
        _nameUr = nameUr,
        _addrUr = addrUr,
        _contactUr = contactUr,
        _logo = logo,
        _titleUr = titleUr,
        _subtitleUr = subtitleUr,
        _titleEn = titleEn,
        _subtitleEn = subtitleEn,
        _bare = bare;

  static Future<PdfBuildScope> create({
    required ReportBranding branding,
    required UrduPdf urdu,
    required String titleUr,
    required String titleEn,
    String? subtitleUr,
    String? subtitleEn,
    bool bare = false,
  }) async {
    final uiInk = _ui(const Color(0xFF212121));
    final uiMuted = _ui(const Color(0xFF616161));
    final uiPrimary = _ui(branding.primary);
    return PdfBuildScope._(
      branding: branding,
      urdu: urdu,
      primary: _pdf(branding.primary),
      secondary: _pdf(branding.secondary),
      accent: _pdf(branding.accent),
      nameUr: await urdu.text(
        branding.nameUrdu ?? branding.name,
        fontSize: 17,
        bold: true,
        color: uiInk,
        align: ui.TextAlign.left,
      ),
      addrUr: branding.addressLine == null
          ? null
          : await urdu.text(
              branding.addressLine!,
              fontSize: 9,
              color: uiMuted,
              align: ui.TextAlign.left,
            ),
      contactUr: branding.contactLine == null
          ? null
          : await urdu.text(
              branding.contactLine!,
              fontSize: 9,
              color: uiMuted,
              align: ui.TextAlign.left,
            ),
      logo: branding.hasLogo
          ? pw.Image(
              pw.MemoryImage(branding.logoBytes!),
              width: 48,
              height: 48,
              fit: pw.BoxFit.contain,
            )
          : null,
      titleUr: await urdu.text(
        titleUr,
        fontSize: 15,
        bold: true,
        color: uiPrimary,
        align: ui.TextAlign.right,
      ),
      subtitleUr: subtitleUr == null
          ? null
          : await urdu.text(
              subtitleUr,
              fontSize: 10,
              color: uiMuted,
              align: ui.TextAlign.right,
            ),
      titleEn: titleEn,
      subtitleEn: subtitleEn,
      bare: bare,
    );
  }

  // ── Header / footer (sync — used by MultiPage) ──────────────────

  pw.Widget _emblem() => pw.Stack(
        children: [
          pw.Container(
            width: 48,
            height: 48,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: primary,
            ),
          ),
          pw.Positioned(
            left: 12,
            top: 6,
            child: pw.Container(
              width: 34,
              height: 34,
              decoration: const pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.Positioned(
            left: 6,
            top: 12,
            child: pw.Container(
              width: 22,
              height: 22,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: primary,
              ),
            ),
          ),
        ],
      );

  pw.Widget buildHeader(pw.Context context) {
    if (_bare) return pw.SizedBox();
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _logo ?? _emblem(),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _nameUr,
                  pw.Text(
                    branding.name,
                    style: pw.TextStyle(fontSize: 9, color: muted),
                  ),
                  if (_addrUr != null) _addrUr!,
                  if (_contactUr != null) _contactUr!,
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _titleUr,
                pw.Text(
                  _titleEn,
                  style: pw.TextStyle(fontSize: 9, color: muted),
                ),
                if (_subtitleUr != null) _subtitleUr!,
                if (_subtitleEn != null)
                  pw.Text(
                    _subtitleEn!,
                    style: pw.TextStyle(fontSize: 8, color: muted),
                  ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: primary, thickness: 2),
        pw.SizedBox(height: 6),
      ],
    );
  }

  pw.Widget buildFooter(pw.Context context) {
    if (_bare) return pw.SizedBox();
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return pw.Column(
      children: [
        pw.SizedBox(height: 6),
        pw.Divider(color: line, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Spacer(),
            pw.Text(
              'Generated: $stamp (offline)',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ],
    );
  }

  // ── Text helpers ───────────────────────────────────────────────

  /// Latin text via the pdf engine (searchable).
  pw.Widget e(
    String text, {
    double size = 10,
    PdfColor? color,
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: size,
          color: color ?? ink,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );

  /// Urdu text — always rasterised (see urdu_pdf.dart).
  Future<pw.Widget> u(
    String text, {
    double size = 11,
    Color? color,
    double? maxWidth,
    bool bold = false,
    ui.TextAlign align = ui.TextAlign.right,
  }) =>
      urdu.text(
        text,
        fontSize: size,
        color: _ui(color ?? const Color(0xFF212121)),
        maxWidthPt: maxWidth,
        bold: bold,
        align: align,
      );

  /// Routes each string to [u] or [e] by script detection.
  Future<pw.Widget> auto(
    String text, {
    double size = 10,
    Color? color,
    double? maxWidth,
    bool bold = false,
  }) {
    if (UrduPdf.isUrdu(text)) {
      return u(text, size: size + 1, color: color, maxWidth: maxWidth, bold: bold);
    }
    return Future.value(e(text,
        size: size,
        color: color == null ? null : _pdf(color),
        bold: bold));
  }

  /// Section heading: Urdu title + primary rule.
  Future<pw.Widget> sectionTitle(String titleUr, [String? titleEn]) async {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: await u(titleUr, size: 13, bold: true,
                    color: branding.primary),
              ),
            ),
          ],
        ),
        if (titleEn != null)
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: e(titleEn, size: 8, color: muted),
          ),
        pw.SizedBox(height: 2),
        pw.Container(height: 1.5, color: primary),
        pw.SizedBox(height: 8),
      ],
    );
  }

  /// Clean empty-state notice — used instead of zeros-as-data.
  Future<pw.Widget> emptyNotice(String messageUr, String messageEn) async {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: line),
        borderRadius: pw.BorderRadius.circular(6),
        color: zebra,
      ),
      child: pw.Column(
        children: [
          pw.Align(
            alignment: pw.Alignment.center,
            child: await u(messageUr,
                size: 13, color: const Color(0xFF616161)),
          ),
          pw.SizedBox(height: 4),
          e(messageEn,
              size: 9, color: muted, align: pw.TextAlign.center),
        ],
      ),
    );
  }

  // ── Tables ─────────────────────────────────────────────────────

  /// Bilingual data table. Every cell is auto-routed (Urdu → raster,
  /// Latin → native text). Set [rtl] to mirror column order for
  /// fully-Urdu tables; defaults to auto-detect from headers.
  Future<pw.Widget> dataTable({
    required List<String> headers,
    required List<List<String>> rows,
    bool? rtl,
    double headerSize = 10,
    double cellSize = 9,
    double? maxCellWidth,
    List<double>? columnWidths,
  }) async {
    final isRtl = rtl ?? headers.every(UrduPdf.isUrdu);
    final h = isRtl ? headers.reversed.toList() : headers;
    final b = rows
        .map((r) => isRtl ? r.reversed.toList() : r)
        .toList();

    Future<pw.Widget> cell(String text, {required bool header}) async {
      final w = await auto(
        text,
        size: header ? headerSize : cellSize,
        color: header ? const Color(0xFFFFFFFF) : null,
        maxWidth: maxCellWidth,
        bold: header,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        child: w,
      );
    }

    final headerCells = <pw.Widget>[];
    for (final hh in h) {
      headerCells.add(await cell(hh, header: true));
    }
    final bodyRows = <pw.TableRow>[];
    var zebraOn = false;
    for (final row in b) {
      final cells = <pw.Widget>[];
      for (final c in row) {
        cells.add(await cell(c, header: false));
      }
      bodyRows.add(pw.TableRow(
        decoration:
            zebraOn ? pw.BoxDecoration(color: zebra) : null,
        children: cells,
      ));
      zebraOn = !zebraOn;
    }

    return pw.Table(
      border: pw.TableBorder.all(color: line, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths == null
          ? null
          : {
              for (var i = 0; i < columnWidths.length; i++)
                i: pw.FixedColumnWidth(columnWidths[i]),
            },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: primary),
          children: headerCells,
        ),
        ...bodyRows,
      ],
    );
  }

  /// Summary stat boxes (label Urdu, value Latin).
  Future<pw.Widget> statRow(List<StatBox> stats) async {
    final boxes = <pw.Widget>[];
    for (final s in stats) {
      boxes.add(
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 4),
            padding: const pw.EdgeInsets.symmetric(
                vertical: 8, horizontal: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: primary, width: 1),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              children: [
                await u(s.labelUr, size: 10,
                    color: const Color(0xFF616161)),
                pw.SizedBox(height: 2),
                e(s.valueEn,
                    size: 14,
                    bold: true,
                    color: primary,
                    align: pw.TextAlign.center),
                if (s.subEn != null)
                  e(s.subEn!, size: 8, color: muted,
                      align: pw.TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    return pw.Row(children: boxes);
  }

  /// Signature line row for certificates/forms.
  Future<pw.Widget> signatureRow(List<String> labelsUr) async {
    final cols = <pw.Widget>[];
    for (final label in labelsUr) {
      cols.add(
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.SizedBox(height: 36),
              pw.Container(height: 1, color: ink),
              pw.SizedBox(height: 4),
              await u(label, size: 10,
                  color: const Color(0xFF616161)),
            ],
          ),
        ),
      );
      cols.add(pw.SizedBox(width: 24));
    }
    if (cols.isNotEmpty) cols.removeLast();
    return pw.Row(children: cols);
  }
}

/// Label/value pair for [PdfBuildScope.statRow].
class StatBox {
  final String labelUr;
  final String valueEn;
  final String? subEn;
  const StatBox(this.labelUr, this.valueEn, [this.subEn]);
}

/// Assembles a complete branded document.
///
/// [body] runs first (async Urdu pre-rendering), then the [pw.MultiPage]
/// is built with the scope's header/footer on every page.
class PdfKit {
  PdfKit._();

  static Future<Uint8List> build({
    required ReportBranding branding,
    required UrduPdf urdu,
    required String titleUr,
    required String titleEn,
    String? subtitleUr,
    String? subtitleEn,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    pw.EdgeInsets margin = const pw.EdgeInsets.all(36),
    bool bare = false,
    required Future<List<pw.Widget>> Function(PdfBuildScope scope) body,
  }) async {
    final scope = await PdfBuildScope.create(
      branding: branding,
      urdu: urdu,
      titleUr: titleUr,
      titleEn: titleEn,
      subtitleUr: subtitleUr,
      subtitleEn: subtitleEn,
      bare: bare,
    );
    final widgets = await body(scope);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: margin,
        header: scope.buildHeader,
        footer: scope.buildFooter,
        build: (_) => widgets,
      ),
    );
    return doc.save();
  }
}
