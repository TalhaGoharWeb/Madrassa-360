/// رپورٹس ہب
/// Reports hub — catalog, filters, preview, save, share, print.
///
/// All generation runs through [ReportsService] against the LOCAL
/// database (offline-first). PDF preview/print/share use the
/// `printing` package; files are saved with `path_provider`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/reports/data/report_data.dart';
import '../../../core/reports/data/report_models.dart';
import '../../../core/reports/report_catalog.dart';
import '../../../core/reports/report_params.dart';
import '../../../core/reports/reports_service.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_provider.dart';

/// رپورٹس
/// Entry screen: two tabs (طلبہ / انتظامیہ) listing the report catalog.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('رپورٹس',
            style: TextStyle(fontFamily: 'JameelNooriNastaleeq')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelStyle:
              TextStyle(fontFamily: 'JameelNooriNastaleeq', fontSize: 16),
          tabs: const [Tab(text: 'طلبہ'), Tab(text: 'انتظامیہ')],
        ),
      ),
      body: tenantId == null
          ? const Center(
              child: Text('براہ کرم پہلے لاگ اِن کریں۔',
                  style: TextStyle(fontFamily: 'JameelNooriNastaleeq')))
          : TabBarView(
              controller: _tabs,
              children: [
                _reportList(context, ReportCategory.student, tenantId),
                _reportList(context, ReportCategory.admin, tenantId),
              ],
            ),
    );
  }

  Widget _reportList(
      BuildContext context, ReportCategory category, String tenantId) {
    final reports = ReportCatalog.byCategory(category);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = reports[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Icon(
                r.tabular ? Icons.table_chart : Icons.description,
                color: AppColors.primary,
              ),
            ),
            title: Text(r.titleUr,
                style: const TextStyle(
                    fontFamily: 'JameelNooriNastaleeq', fontSize: 17)),
            subtitle: Text('${r.titleEn}\n${r.descriptionUr}',
                style: const TextStyle(fontSize: 12)),
            isThreeLine: true,
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _openFilters(context, tenantId, r),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(problem)));
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خرابی: $e')),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('محفوظ ہو گیا: ${file.path}')),
          );
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
              Text(_def.titleUr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'JameelNooriNastaleeq',
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              Text(_def.titleEn,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              if (_def.needsStudent) ...[
                _label('طالب علم'),
                if (_student == null)
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'نام یا رول نمبر لکھیں…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: _searchStudents,
                  )
                else
                  _selectedChip(
                    '${_student!.name} (${_student!.rollNo ?? '—'})',
                    () => setState(() => _student = null),
                  ),
                ..._searchHits.map((s) => ListTile(
                      dense: true,
                      title: Text(s.name),
                      subtitle: Text(
                          'رول: ${s.rollNo ?? '—'} | ${s.className ?? ''}'),
                      onTap: () => setState(() {
                        _student = s;
                        _searchHits = [];
                      }),
                    )),
              ],
              if (_def.needsClass) ...[
                _label('جماعت (اختیاری)'),
                _dropdown<String>(
                  value: _classId,
                  hint: 'تمام جماعتیں',
                  items: {
                    for (final c in _classes) c.id: c.name,
                  },
                  onChanged: (v) => setState(() => _classId = v),
                ),
              ],
              if (_def.needsDarja && _classId == null) ...[
                _label('درجہ (اختیاری)'),
                _dropdown<String>(
                  value: _darjaId,
                  hint: 'تمام درجات',
                  items: {
                    for (final d in _darjas) d.id: d.name,
                  },
                  onChanged: (v) => setState(() => _darjaId = v),
                ),
              ],
              if (_def.needsExam) ...[
                _label(_def.id == 'exam_results'
                    ? 'امتحان'
                    : 'امتحان (اختیاری — خالی ہو تو تازہ ترین)'),
                _dropdown<String>(
                  value: _examId,
                  hint: 'منتخب کریں',
                  items: {
                    for (final e in _exams) e.id: e.name,
                  },
                  onChanged: (v) => setState(() => _examId = v),
                ),
              ],
              if (_def.needsDateRange) ...[
                _label('مدت (اختیاری)'),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _range == null
                        ? 'تاریخ منتخب کریں'
                        : '${_fmtD(_range!.start)} تا ${_fmtD(_range!.end)}',
                  ),
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
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.preview),
                        label: const Text('پیش نظارہ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _preview,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print),
                        label: const Text('پرنٹ'),
                        onPressed: _print,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.save_alt),
                        label: const Text('محفوظ کریں'),
                        onPressed: _savePdf,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share),
                        label: const Text('شیئر'),
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
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.grid_on),
                          label: const Text('CSV'),
                          onPressed: _shareCsv,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.table_chart),
                          label: const Text('Excel'),
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
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'JameelNooriNastaleeq', fontSize: 15)),
      );

  Widget _selectedChip(String text, VoidCallback onClear) => Chip(
        label: Text(text),
        deleteIcon: const Icon(Icons.close, size: 18),
        onDeleted: onClear,
      );

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        decoration:
            const InputDecoration(border: OutlineInputBorder(), isDense: true),
        hint: Text(hint),
        items: [
          DropdownMenuItem<T>(
            value: null,
            child:
                Text('— $hint —', style: const TextStyle(color: Colors.grey)),
          ),
          for (final e in items.entries)
            DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(fontFamily: 'JameelNooriNastaleeq')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
      ),
    );
  }
}
