/// رپورٹ سیاق
/// Shared build context handed to every report builder.

import 'data/report_data.dart';
import 'report_branding.dart';
import 'report_params.dart';
import 'urdu_pdf.dart';

/// Everything a report builder needs: offline data, branding, the Urdu
/// rasteriser, and the run parameters.
class ReportContext {
  final ReportData data;
  final ReportBranding branding;
  final UrduPdf urdu;
  final ReportParams params;
  final ReportDefinition definition;

  ReportContext({
    required this.data,
    required this.branding,
    required this.urdu,
    required this.params,
    required this.definition,
  });
}
