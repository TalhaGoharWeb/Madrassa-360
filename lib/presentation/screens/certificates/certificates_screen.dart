/// اسناد
/// Certificates module (Phase 8).
///
/// GENERATION IS REAL: certificate PDFs are produced by the existing
/// reporting engine ([ReportsService] + `student_documents.dart` — the
/// same pipeline as the Reports hub). No parallel implementation.
/// Success is reported only after [ReportsService.generatePdf] actually
/// returns bytes.
///
/// ISSUANCE TRACKING IS BACKEND-PENDING: there is no issuance/serial/
/// verification table (docs/audit-backend-capabilities.md), so the
/// history tab goes through the isolated [CertificateRepository], whose
/// current implementation surfaces the honest unavailable state.
///
/// Renders inside the single [AppShell] via [ShellPageBody].

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/reports/data/report_data.dart';
import '../../../core/reports/data/report_models.dart';
import '../../../core/reports/report_catalog.dart';
import '../../../core/reports/report_params.dart';
import '../../../core/reports/reports_service.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/local/database_provider.dart';
import '../../../data/repositories/certificate_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/certificate_provider.dart';
import '../../shell/shell_page_body.dart';

const _uuid = Uuid();

/// اسناد — the certificates module entry screen (nav destination).
class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    Future.microtask(
        () => ref.read(certificateProvider.notifier).loadHistory());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canIssue =
        ref.watch(hasPermissionProvider(AppPermissions.issueCertificates));

    return ShellPageBody(
      tabBar: TabBar(
        controller: _tabs,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textSecondary,
        tabs: const [
          Tab(text: 'سند جاری کریں'),
          Tab(text: 'جاری شدہ اسناد'),
        ],
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PageHeader(
              title: 'اسناد',
              description: 'کردار اور منتقلی سرٹیفکیٹ تیار کریں',
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _IssueTab(canIssue: canIssue),
                const _HistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tab 1: issue a certificate (REAL pipeline)
// ─────────────────────────────────────────────

class _IssueTab extends ConsumerStatefulWidget {
  final bool canIssue;

  const _IssueTab({required this.canIssue});

  @override
  ConsumerState<_IssueTab> createState() => _IssueTabState();
}

class _IssueTabState extends ConsumerState<_IssueTab> {
  CertificateType _type = CertificateType.character;
  ReportStudent? _student;
  String _search = '';
  List<ReportStudent> _hits = [];
  bool _searching = false;
  bool _busy = false;
  String? _notice;
  bool _noticeIsError = true;

  ReportData get _data => ReportData(ref.read(appDatabaseProvider));
  ReportsService get _service => ReportsService(ref.read(appDatabaseProvider));

  Future<void> _searchStudents(String q) async {
    _search = q;
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null || q.trim().length < 2) {
      if (mounted) {
        setState(() {
          _hits = [];
          _searching = false;
        });
      }
      return;
    }
    setState(() => _searching = true);
    try {
      final hits = await _data.students(tenantId, search: q.trim());
      if (!mounted || q != _search) return;
      setState(() => _hits = hits.take(20).toList());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Generates the PDF through the REAL report pipeline. Success is
  /// reported only after bytes are actually produced.
  Future<Uint8List?> _generate() async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null) {
      setState(() {
        _notice = 'براہ کرم پہلے لاگ اِن کریں۔';
        _noticeIsError = true;
      });
      return null;
    }
    if (_student == null) {
      setState(() {
        _notice = 'براہ کرم طالب علم منتخب کریں۔';
        _noticeIsError = true;
      });
      return null;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final bytes = await _service.generatePdf(
        _type.reportId,
        ReportParams(tenantId: tenantId, studentId: _student!.id),
      );
      return bytes;
    } catch (_) {
      if (mounted) {
        setState(() {
          _notice = 'سند بنانے میں خرابی ہوئی۔ دوبارہ کوشش کریں۔';
          _noticeIsError = true;
        });
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fileName(String ext) =>
      '${_type.reportId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

  /// Attempts to log the issuance. With no backend this returns false —
  /// the PDF itself was already produced, so this is surfaced as an
  /// honest warning, never as a generation failure.
  Future<void> _logIssuance() async {
    final tenantId = ref.read(currentTenantIdProvider);
    final student = _student;
    if (tenantId == null || student == null) return;
    final user = ref.read(currentUserProvider);
    // Issuer attribution: the user's chosen display name (never an email
    // address); the login email only as a last resort for traceability.
    final displayName = ref.read(displayNameProvider(''));
    final issuedBy = displayName.isNotEmpty ? displayName : user?.email;
    final ok = await ref
        .read(certificateProvider.notifier)
        .recordIssuance(CertificateIssuance(
          id: _uuid.v4(),
          tenantId: tenantId,
          studentId: student.id,
          studentName: student.name,
          type: _type,
          issuedAt: DateTime.now(),
          issuedBy: issuedBy,
        ));
    if (!mounted) return;
    if (ok) {
      setState(() {
        _notice = 'سند تیار ہو گئی اور اجراء ریکارڈ میں درج ہو گیا۔';
        _noticeIsError = false;
      });
    } else {
      setState(() {
        _notice =
            'سند کی PDF تیار ہو گئی، لیکن اجراء کا ریکارڈ محفوظ نہیں ہو سکا — '
            'ریکارڈ کا بیک اینڈ ابھی دستیاب نہیں ہے۔';
        _noticeIsError = true;
      });
      ref.read(certificateProvider.notifier).clearError();
    }
  }

  Future<void> _preview() async {
    final bytes = await _generate();
    if (bytes == null || !mounted) return;
    await _logIssuance();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CertificatePreviewScreen(
          title: _type.labelUr,
          bytes: bytes,
        ),
      ),
    );
  }

  Future<void> _print() async {
    final bytes = await _generate();
    if (bytes == null) return;
    try {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      await _logIssuance();
    } catch (_) {
      if (mounted) {
        setState(() {
          _notice = 'پرنٹ میں خرابی ہوئی۔ دوبارہ کوشش کریں۔';
          _noticeIsError = true;
        });
      }
    }
  }

  Future<void> _share() async {
    final bytes = await _generate();
    if (bytes == null) return;
    try {
      await Printing.sharePdf(bytes: bytes, filename: _fileName('pdf'));
      await _logIssuance();
    } catch (_) {
      if (mounted) {
        setState(() {
          _notice = 'شیئر میں خرابی ہوئی۔ دوبارہ کوشش کریں۔';
          _noticeIsError = true;
        });
      }
    }
  }

  Future<void> _save() async {
    final bytes = await _generate();
    if (bytes == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_fileName('pdf')}');
      await file.writeAsBytes(bytes);
      // _logIssuance already set the notice: a plain success when the
      // record was stored, or the honest warning when the backend is
      // pending. Nothing more to add — the PDF itself is real.
      await _logIssuance();
    } catch (_) {
      if (mounted) {
        setState(() {
          _notice = 'محفوظ کرنے میں خرابی ہوئی۔ دوبارہ کوشش کریں۔';
          _noticeIsError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const M360SectionHeader(
          title: 'سند کی قسم',
          subtitle: 'حقیقی رپورٹ پائپ لائن سے تیار ہوگی',
        ),
        for (final t in CertificateType.values) ...[
          _TypeCard(
            type: t,
            selected: _type == t,
            onTap: () => setState(() => _type = t),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const M360SectionHeader(title: 'طالب علم'),
        M360SearchField(
          hint: 'نام یا رول نمبر سے تلاش کریں...',
          onChanged: _searchStudents,
        ),
        if (_searching) ...[
          const SizedBox(height: 8),
          const M360LoadingState(itemCount: 2),
        ] else if (_hits.isNotEmpty) ...[
          const SizedBox(height: 8),
          M360Card(
            child: Column(
              children: [
                for (final s in _hits)
                  ListTile(
                    title: Text(s.name, textDirection: TextDirection.rtl),
                    subtitle:
                        s.rollNo == null ? null : M360LatinText(s.rollNo!),
                    trailing: _student?.id == s.id
                        ? const Icon(Icons.check_circle,
                            color: AppColors.success)
                        : null,
                    onTap: () => setState(() {
                      _student = s;
                      _hits = [];
                      _search = '';
                    }),
                  ),
              ],
            ),
          ),
        ],
        if (_student != null) ...[
          const SizedBox(height: 8),
          M360Card(
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _student!.name,
                        textDirection: TextDirection.rtl,
                        style: AppTypography.titleSmall
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (_student!.rollNo != null)
                        M360LatinText(_student!.rollNo!),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _student = null),
                  child: Text('تبدیل کریں', style: AppTypography.labelNastaliq),
                ),
              ],
            ),
          ),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_noticeIsError ? AppColors.error : AppColors.success)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _notice!,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: _noticeIsError ? AppColors.error : AppColors.success,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Orange ONLY for the single primary CTA (preview/generate).
        M360PrimaryButton(
          label: 'پیش نظارہ',
          icon: Icons.preview_outlined,
          fullWidth: true,
          isLoading: _busy,
          onPressed: (_busy || !widget.canIssue) ? null : _preview,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: M360SecondaryButton(
                label: 'پرنٹ کریں',
                icon: Icons.print_outlined,
                onPressed: (_busy || !widget.canIssue) ? null : _print,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: M360SecondaryButton(
                label: 'شیئر کریں',
                icon: Icons.share_outlined,
                onPressed: (_busy || !widget.canIssue) ? null : _share,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: M360SecondaryButton(
                label: 'محفوظ کریں',
                icon: Icons.save_outlined,
                onPressed: (_busy || !widget.canIssue) ? null : _save,
              ),
            ),
          ],
        ),
        if (!widget.canIssue) ...[
          const SizedBox(height: 12),
          const Text(
            'آپ کو سند جاری کرنے کی اجازت نہیں ہے۔',
            textDirection: TextDirection.rtl,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  final CertificateType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final def = ReportCatalog.byId(type.reportId);
    return M360TappableCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (selected ? AppColors.accent : AppColors.primary)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.workspace_premium_outlined,
              color: selected ? AppColors.accent : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.labelUr,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.titleSmall
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  def.descriptionUr,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (selected) const Icon(Icons.check_circle, color: AppColors.accent),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tab 2: issuance history (backend-pending)
// ─────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(certificateProvider);
    if (state.isLoading || state.status == CertificateLoadStatus.initial) {
      return const M360LoadingState();
    }
    if (state.backendUnavailable) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const M360EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'اجراء کا ریکارڈ دستیاب نہیں',
            description:
                'جاری شدہ اسناد کی فہرست (سند نمبر، طالب علم، تاریخ) ابھی بیک اینڈ سے منسلک نہیں ہے۔ '
                'بیک اینڈ دستیاب ہوتے ہی ہر جاری شدہ سند یہاں درج نظر آئے گی۔ '
                'سندیں بنانا (پچھلا ٹیب) مکمل طور پر کام کرتا ہے۔',
          ),
          const SizedBox(height: 8),
          Center(
            child: M360SecondaryButton(
              label: 'دوبارہ کوشش کریں',
              icon: Icons.refresh,
              onPressed: () =>
                  ref.read(certificateProvider.notifier).loadHistory(),
            ),
          ),
        ],
      );
    }
    if (state.status == CertificateLoadStatus.error) {
      return M360ErrorState(
        message: state.error ?? 'خرابی ہوئی۔',
        onRetry: () => ref.read(certificateProvider.notifier).loadHistory(),
      );
    }
    if (state.history.isEmpty) {
      return const M360EmptyState(
        icon: Icons.workspace_premium_outlined,
        title: 'ابھی کوئی سند جاری نہیں ہوئی',
        description:
            'پچھلے ٹیب سے پہلی سند تیار کریں — وہ یہاں درج ہو جائے گی۔',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final h = state.history[i];
        return M360Card(
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.studentName,
                      textDirection: TextDirection.rtl,
                      style: AppTypography.titleSmall
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${h.type.labelUr}${h.serialNumber == null ? '' : ' — نمبر: ${h.serialNumber}'}',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              M360StatusChip(status: M360Status.complete),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// PDF preview (real bytes from the pipeline)
// ─────────────────────────────────────────────

/// سند کا پیش نظارہ — shows the real generated PDF bytes.
class CertificatePreviewScreen extends StatelessWidget {
  final String title;
  final Uint8List bytes;

  const CertificatePreviewScreen({
    super.key,
    required this.title,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    return ShellPageBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: PageHeader(title: title),
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
