/// دستاویز معاونین
/// Shared helpers for the document builders.

import 'package:flutter/material.dart' show Color;
import 'package:pdf/widgets.dart' as pw;

import '../pdf_kit.dart';

/// Today's date as YYYY-MM-DD.
String todayIso() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

/// Labeled form row: value field (left, underlined) + Urdu label (right).
///
/// A null [value] leaves the field blank for handwriting.
Future<pw.Widget> fieldRow(
  PdfBuildScope s,
  String labelUr,
  String? value,
) async {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 3, left: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                    color: PdfBuildScope.line, width: 0.8),
              ),
            ),
            child: pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: value == null
                  ? pw.SizedBox(height: 14)
                  : await s.auto(value, size: 11),
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.SizedBox(
          width: 120,
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: await s.u(
              '$labelUr :',
              size: 11,
              bold: true,
              color: const Color(0xFF424242),
            ),
          ),
        ),
      ],
    ),
  );
}
