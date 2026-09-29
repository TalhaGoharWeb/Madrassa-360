/// رپورٹس ہب
/// Reports hub — catalog, filters, preview, save, share, print.
///
/// All generation runs through the REAL [ReportsService] against the LOCAL
/// database (offline-first) — no parallel implementation. PDF preview/print/
/// share use the `printing` package; files are saved with `path_provider`.
/// Generation feedback is honest: loading state while generating, inline
/// error notices on failure, and success is only ever reported after the
/// service actually returns bytes / writes the file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/reports/data/report_data.dart';
import '../../../core/reports/data/report_models.dart';
import '../../../core/reports/report_catalog.dart';
import '../../../core/reports/report_params.dart';
import '../../../core/reports/reports_service.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_provider.dart';
import '../../shell/shell_page_body.dart';

/// رپورٹس
/// Entry screen: two tabs (طلبہ / انتظامیہ) listing the report catalog.
/// Renders inside [AppShell] via [ShellPageBody].
class ReportsHubScreen extends ConsumerStatefulWidget {
  const ReportsHubScreen({super.key});

  @override
  ConsumerState<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends ConsumerState<ReportsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(currentTenantIdProvider);
    return ShellPageBody(
      tabBar: TabBar(
        controller: _tabs,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTypography.labelLarge,
        tabs: const [Tab(text: 'طلبہ'), Tab(text: 'انتظامیہ')],
      ),
      child: tenantId == null
          ? const M360EmptyState(
              icon: Icons.login,
              title: 'براہ کرم پہلے لاگ اِن کریں۔',
              description: 'رپورٹس بنانے اور دیکھنے کے لیے لاگ اِن ضروری ہے۔',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: PageHeader(
                    title: 'رپورٹس',
                    description:
                        'طلبہ اور انتظامی رپورٹس بنائیں، دیکھیں، پرنٹ اور شیئر کریں',
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _reportList(context, ReportCategory.student, tenantId),
                      _reportList(context, ReportCategory.admin, tenantId),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _reportList(
      BuildContext context, ReportCategory category, String tenantId) {
    final reports = ReportCatalog.byCategory(category);
    if (reports.isEmpty) {
      return const M360EmptyState(
        icon: Icons.description_outlined,
        title: 'کوئی رپورٹ نہیں',
        description: 'اس زمرے میں فی الحال کوئی رپورٹ دستیاب نہیں۔',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: reports.length,
      itemBuilder: (_, i) {
        final r = reports[i];
        return M360TappableCard(
          margin: const EdgeInsets.only(bottom: 10),
          onTap: () => _openFilters(context, tenantId, r),
          semanticLabel: r.titleUr,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  r.tabular
                      ? Icons.table_chart_outlined
                      : Icons.description_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.titleUr,
                        style: AppTypography.titleSmall.copyWith(fontSize: 17)),
                    M360LatinText(
                      r.titleEn,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.descriptionUr,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: AppColors.textSecondary),
            ],
          ),
        );
      },
    );
  }

  void _openFilters(
      BuildContext context, String tenantId, ReportDefinition def) {
    final db = ref.read(appDatabaseProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReportFilterSheet(
        db: db,
        tenantId: tenantId,
        definition: def,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Filter sheet
// ─────────────────────────────────────────────

class _ReportFilterSheet extends ConsumerStatefulWidget {
  final AppDatabase db;
  final String tenantId;
  final ReportDefinition definition;

  const _ReportFilterSheet({
    required this.db,
    required this.tenantId,
    required this.definition,
  });

  @override
  ConsumerState<_ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends ConsumerState<_ReportFilterSheet> {
  ReportStudent? _student;
  String? _classId;
  String? _darjaId;
  String? _examId;
  DateTimeRange? _range;
  String _search = '';
  List<ReportStudent> _searchHits = [];
  List<ReportClass> _classes = [];
  List<ReportDarja> _darjas = [];
  List<ReportExam> _exams = [];
  bool _busy = false;

  /// Inline feedback (validation / errors / save confirmation) rendered in
  /// the sheet itself — the sheet has no Scaffold ancestor to host a
  /// SnackBar, so honest feedback renders here instead.
  String? _notice;
  bool _noticeIsError = true;

  ReportDefinition get _def => widget.definition;
  ReportData get _data => ReportData(widget.db);
  ReportsService get _service => ReportsService(widget.db);

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    if (_def.needsClass) {
      _classes = await _data.classes(widget.tenantId);
    }
    if (_def.needsDarja) {
      _darjas = await _data.darjas(widget.tenantId);
    }
    if (_def.needsExam) {
      _exams = await _data.exams(widget.tenantId);
    }
    if (mounted) setState(() {});
  }

  Future<void> _searchStudents(String q) async {
    _search = q;
    if (q.trim().length < 2) {
      setState(() => _searchHits = []);
      return;
    }
    final hits = await _data.students(widget.tenantId, search: q.trim());
    if (!mounted || q != _search) return;
    setState(() => _searchHits = hits.take(20).toList());
  }

  ReportParams _params() => ReportParams(
        tenantId: widget.tenantId,
        studentId: _student?.id,
        classId: _classId,
        darjaId: _darjaId,
        examId: _examId,
        from: _range?.start,
        to: _range?.end,
      );

  /// Returns an error string when required filters are missing.
  String? _validate() {
    if (_def.needsStudent && _student == null) {
      return 'براہ کرم طالب علم منتخب کریں۔';
    }
    if (_def.id == 'exam_results' && _examId == null) {
      return 'براہ کرم امتحان منتخب کریں۔';
    }
    return null;
  }

  String _fileName(String ext) =>
      '${_def.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';

  Future<void> _run(Future<void> Function() fn) async {
    final problem = _validate();
    if (problem != null) {
      if (mounted) {
        setState(() {
          _notice = problem;
          _noticeIsError = true;
        });
      }
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = 'خرابی: $e';
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _preview() => _run(() async {
        final bytes = await _service.generatePdf(_def.id, _params());
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _PdfPreviewScreen(
              title: _def.titleUr,
              bytes: bytes,
            ),
          ),
        );
      });

  void _print() => _run(() async {
        final bytes = await _service.generatePdf(_def.id, _params());
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      });

  void _sharePdf() => _run(() async {
        final bytes = await _service.generatePdf(_def.id, _params());
        await Printing.sharePdf(bytes: bytes, filename: _fileName('pdf'));
      });

  void _savePdf() => _run(() async {
        final bytes = await _service.generatePdf(_def.id, _params());
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/${_fileName('pdf')}');
        await file.writeAsBytes(bytes);
        if (mounted) {
          setState(() {
            _notice = 'محفوظ ہو گیا';
            _noticeIsError = false;
          });
        }
      });

  void _shareCsv() => _run(() async {
        final csv = await _service.generateCsv(_def.id, _params());
        // generateCsv already prefixes the UTF-8 BOM.
        await Printing.sharePdf(
          bytes: utf8.encode(csv),
          filename: _fileName('csv'),
        );
      });

  void _shareXlsx() => _run(() async {
        final bytes = await _service.generateXlsx(_def.id, _params());
        await Printing.sharePdf(bytes: bytes, filename: _fileName('xlsx'));
      });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _def.titleUr,
                textAlign: TextAlign.center,
                style: AppTypography.titleMedium.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              M360LatinText(
                _def.titleEn,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (_def.needsStudent) ...[
                _label('طالب علم'),
                if (_student == null)
                  M360SearchField(
                    hint: 'نام یا رول نمبر لکھیں…',
                    onChanged: _searchStudents,
                  )
                else
                  _selectedChip(
                    '${_student!.name} (${_student!.rollNo ?? '—'})',
                    () => setState(() => _student = null),
                  ),
                ..._searchHits.map((s) => InkWell(
                      onTap: () => setState(() {
                        _student = s;
                        _searchHits = [];
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 20, color: AppColors.textSecondary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name, style: AppTypography.bodyMedium),
                                  Text(
                                    'رول: ${s.rollNo ?? '—'} | ${s.className ?? ''}',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
              ],
              if (_def.needsClass)
                _dropdown(
                  label: 'جماعت (اختیاری)',
                  value: _classId,
                  hint: 'تمام جماعتیں',
                  items: {for (final c in _classes) c.id: c.name},
                  onChanged: (v) => setState(() => _classId = v),
                ),
              if (_def.needsDarja && _classId == null)
                _dropdown(
                  label: 'درجہ (اختیاری)',
                  value: _darjaId,
                  hint: 'تمام درجات',
                  items: {for (final d in _darjas) d.id: d.name},
                  onChanged: (v) => setState(() => _darjaId = v),
                ),
              if (_def.needsExam)
                _dropdown(
                  label: _def.id == 'exam_results'
                      ? 'امتحان'
                      : 'امتحان (اختیاری — خالی ہو تو تازہ ترین)',
                  value: _examId,
                  hint: 'منتخب کریں',
                  items: {for (final e in _exams) e.id: e.name},
                  onChanged: (v) => setState(() => _examId = v),
                ),
              if (_def.needsDateRange) ...[
                _label('مدت (اختیاری)'),
                M360SecondaryButton(
                  label: _range == null
                      ? 'تاریخ منتخب کریں'
                      : '${_fmtD(_range!.start)} تا ${_fmtD(_range!.end)}',
                  icon: Icons.date_range_outlined,
                  fullWidth: true,
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _range = picked);
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),
              // Inline validation / error / success notice — the sheet has
              // no Scaffold ancestor, so honest feedback renders here.
              if (_notice != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (_noticeIsError ? AppColors.error : AppColors.success)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _notice!,
                    style: AppTypography.bodySmall.copyWith(
                      color:
                          _noticeIsError ? AppColors.error : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_busy)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'رپورٹ تیار ہو رہی ہے…',
                      style: AppTypography.labelNastaliq.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: M360PrimaryButton(
                        label: 'پیش نظارہ',
                        icon: Icons.preview_outlined,
                        onPressed: _preview,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: M360SecondaryButton(
                        label: 'پرنٹ',
                        icon: Icons.print_outlined,
                        onPressed: _print,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: M360SecondaryButton(
                        label: 'محفوظ کریں',
                        icon: Icons.save_alt_outlined,
                        onPressed: _savePdf,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: M360SecondaryButton(
                        label: 'شیئر',
                        icon: Icons.share_outlined,
                        onPressed: _sharePdf,
                      ),
                    ),
                  ],
                ),
                if (_def.tabular) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: M360TertiaryButton(
                          label: 'CSV',
                          onPressed: _shareCsv,
                        ),
                      ),
                      Expanded(
                        child: M360TertiaryButton(
                          label: 'Excel',
                          onPressed: _shareXlsx,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(text, style: AppTypography.labelNastaliq),
      );

  Widget _selectedChip(String text, VoidCallback onClear) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Chip(
          label: Text(text, style: AppTypography.bodyMedium),
          deleteIcon: const Icon(Icons.close, size: 18),
          onDeleted: onClear,
        ),
      );

  Widget _dropdown({
    required String label,
    required String? value,
    required String hint,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: M360Dropdown<String?>(
          label: label,
          value: value,
          hint: hint,
          items: [
            M360DropdownItem<String?>(value: null, label: '— $hint —'),
            for (final e in items.entries)
              M360DropdownItem<String?>(value: e.key, label: e.value),
          ],
          onChanged: onChanged,
        ),
      );

  String _fmtD(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────
// PDF preview screen
// ─────────────────────────────────────────────

class _PdfPreviewScreen extends StatelessWidget {
  final String title;
  final Uint8List bytes;

  const _PdfPreviewScreen({
    required this.title,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    // Deep-pushed preview: AppShell owns the only Scaffold/AppBar, so the
    // preview renders inside ShellPageBody with a PageHeader carrying the
    // report title.
    return ShellPageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: title,
            breadcrumb: 'رپورٹس',
          ),
          Expanded(
            child: PdfPreview(
              build: (_) async => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
            ),
          ),
        ],
      ),
    );
  }
}
