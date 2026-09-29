import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/design/m360.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/models.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/auth_provider.dart';

/// کتب خانہ — m360 redesign (Phase 10)
///
/// Same provider flows (books, issues, returns, fines). Destructive
/// actions go through destructive [showM360ConfirmDialog]. Rendered as
/// an [AppShell] destination: no Scaffold, no AppBar — [PageContainer]/
/// [PageHeader] only.
class LibraryScreen extends ConsumerStatefulWidget {
  final String? madrasaId;
  const LibraryScreen({super.key, this.madrasaId});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        ref.read(libraryProvider.notifier).load(madrasaId: widget.madrasaId));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Back affordance for deep-pushed routes. Shell destinations get the
  /// shell's own back chevron, so this renders nothing for them.
  List<Widget> _withBack(BuildContext context, List<Widget> actions) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return [
      if (canPop)
        M360IconButton(
          icon: Icons.arrow_back,
          tooltip: 'واپس',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ...actions,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final isAdmin =
        (ref.watch(authProvider).user?.role.name ?? '').contains('admin');

    return PageContainer(
      scrollable: false,
      header: PageHeader(
        title: 'کتب خانہ',
        breadcrumb: 'منتظم',
        description: 'کتابیں، اجراء اور واپسی کا ریکارڈ',
        actions: _withBack(context, [
          if (isAdmin)
            M360PrimaryButton(
              label: 'نئی کتاب',
              icon: Icons.add,
              onPressed: () => _showAddBookDialog(context),
            ),
        ]),
      ),
      child: state.isLoading
          ? const M360LoadingState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  controller: _tabs,
                  labelColor: AppColors.primaryDark,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: 'تمام کتابیں'),
                    Tab(text: 'جاری'),
                    Tab(text: 'واجبُ الواپسی'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _BooksList(
                        books: state.books,
                        isAdmin: isAdmin,
                        madrasaId: widget.madrasaId,
                      ),
                      _IssuesList(
                        issues:
                            state.issues.where((i) => !i.isReturned).toList(),
                        isAdmin: isAdmin,
                      ),
                      _IssuesList(
                        issues: state.issues.where((i) => i.isOverdue).toList(),
                        isAdmin: isAdmin,
                        isOverdue: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showAddBookDialog(BuildContext context) async {
    final title = await showM360Dialog<String>(
      context,
      title: 'نئی کتاب',
      icon: Icons.menu_book_outlined,
      content: _BookForm(madrasaId: widget.madrasaId),
    );
    if (title == null) return;
    if (!context.mounted) return;
    showM360SnackBar(context, '«$title» شامل کر دی گئی');
  }
}

// ─────────────────────────────────────────────────────────────

class _BooksList extends ConsumerWidget {
  final List<LibraryBook> books;
  final bool isAdmin;
  final String? madrasaId;

  const _BooksList({
    required this.books,
    required this.isAdmin,
    required this.madrasaId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (books.isEmpty) {
      return const M360EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'کوئی کتاب نہیں',
        description: 'پہلی کتاب شامل کر کے لائبریری شروع کریں۔',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: books.length,
      itemBuilder: (ctx, i) => _bookRow(context, ref, books[i]),
    );
  }

  Widget _bookRow(BuildContext context, WidgetRef ref, LibraryBook b) {
    final available = b.availableCopies > 0;
    return M360Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.menu_book_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.title, style: AppTypography.bodyLarge),
                if ((b.author ?? '').isNotEmpty)
                  Text(b.author!,
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.textSecondary)),
                if ((b.subject ?? '').isNotEmpty)
                  Text(b.subject!,
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.textSecondary)),
                if ((b.isbn ?? '').isNotEmpty)
                  M360LatinText(
                    'ISBN: ${b.isbn}',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 6),
                _LibBadge(
                  label:
                      available ? 'دستیاب: ${b.availableCopies}' : 'غیر دستیاب',
                  color: available ? AppColors.success : AppColors.error,
                ),
              ],
            ),
          ),
          if (isAdmin)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (available)
                  M360IconButton(
                    icon: Icons.outbox_outlined,
                    tooltip: 'کتاب جاری کریں',
                    onPressed: () => _showIssueDialog(context, ref, b),
                  ),
                M360IconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'کتاب حذف کریں',
                  color: AppColors.error,
                  onPressed: () => _confirmDeleteBook(context, ref, b),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteBook(
    BuildContext context,
    WidgetRef ref,
    LibraryBook b,
  ) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'کتاب حذف کریں؟',
      message: '«${b.title}» مستقل طور پر حذف ہو جائے گی۔'
          ' یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (confirmed) {
      await ref.read(libraryProvider.notifier).deleteBook(b.id ?? '');
    }
  }

  Future<void> _showIssueDialog(
    BuildContext context,
    WidgetRef ref,
    LibraryBook book,
  ) async {
    final issued = await showM360Dialog<bool>(
      context,
      title: 'کتاب جاری کریں',
      icon: Icons.outbox_outlined,
      content: _IssueForm(book: book, madrasaId: madrasaId),
    );
    if (issued == true && context.mounted) {
      showM360SnackBar(context, 'کتاب جاری کر دی گئی');
    }
  }
}

// ─────────────────────────────────────────────────────────────

class _IssuesList extends ConsumerWidget {
  final List<BookIssue> issues;
  final bool isAdmin;
  final bool isOverdue;

  const _IssuesList({
    required this.issues,
    required this.isAdmin,
    this.isOverdue = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (issues.isEmpty) {
      return M360EmptyState(
        icon: isOverdue ? Icons.warning_amber_outlined : Icons.outbox_outlined,
        title: 'کوئی ریکارڈ نہیں',
        description: isOverdue
            ? 'کوئی کتاب واجبُ الواپسی نہیں ہے۔'
            : 'ابھی کوئی کتاب جاری نہیں کی گئی۔',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: issues.length,
      itemBuilder: (ctx, i) => _issueRow(context, issues[i]),
    );
  }

  Widget _issueRow(BuildContext context, BookIssue issue) {
    return M360Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (isOverdue ? AppColors.error : AppColors.info)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_outline,
              color: isOverdue ? AppColors.error : AppColors.info,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.bookTitle, style: AppTypography.bodyLarge),
                Text(
                  '${issue.borrowerName} • ${_borrowerLabel(issue.borrowerType)}',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (isOverdue) ...[
                  const SizedBox(height: 4),
                  _LibBadge(
                    label: 'واجبُ الواپسی',
                    color: AppColors.error,
                  ),
                ],
              ],
            ),
          ),
          if (isAdmin)
            M360SecondaryButton(
              label: 'واپس کریں',
              onPressed: () => _showReturnDialog(context, issue),
            ),
        ],
      ),
    );
  }

  Future<void> _showReturnDialog(BuildContext context, BookIssue issue) async {
    final done = await showM360Dialog<bool>(
      context,
      title: 'کتاب واپس',
      icon: Icons.inbox_outlined,
      content: _ReturnForm(issue: issue),
    );
    if (done == true && context.mounted) {
      showM360SnackBar(context, 'کتاب واپس ہو گئی');
    }
  }
}

String _borrowerLabel(String type) {
  switch (type) {
    case 'student':
      return 'طالب علم';
    case 'teacher':
      return 'استاذ';
    default:
      return type;
  }
}

// ─────────────────────────────────────────────────────────────
// Add-book form. Pops the book title on success.
// ─────────────────────────────────────────────────────────────

class _BookForm extends ConsumerStatefulWidget {
  final String? madrasaId;

  const _BookForm({required this.madrasaId});

  @override
  ConsumerState<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<_BookForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _isbnCtrl = TextEditingController();
  final _copiesCtrl = TextEditingController(text: '1');
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _subjectCtrl.dispose();
    _isbnCtrl.dispose();
    _copiesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final copies = int.tryParse(_copiesCtrl.text.trim()) ?? 1;
    setState(() => _saving = true);
    try {
      await ref.read(libraryProvider.notifier).addBook(LibraryBook(
            title: _titleCtrl.text.trim(),
            author: _authorCtrl.text.trim(),
            subject: _subjectCtrl.text.trim(),
            isbn: _isbnCtrl.text.trim(),
            totalCopies: copies,
            availableCopies: copies,
            tenantId: ref.read(currentTenantIdProvider) ?? '',
            madrasaId: widget.madrasaId,
          ));
      if (!mounted) return;
      Navigator.of(context).pop(_titleCtrl.text.trim());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'کتاب شامل کرنے میں خطا ہوئی', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          M360TextField(
            label: 'عنوان',
            controller: _titleCtrl,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'عنوان درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(label: 'مصنف', controller: _authorCtrl),
          const SizedBox(height: 12),
          M360TextField(label: 'مضمون', controller: _subjectCtrl),
          const SizedBox(height: 12),
          M360TextField(
            label: 'ISBN (اختیاری)',
            controller: _isbnCtrl,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'کاپیاں',
            controller: _copiesCtrl,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              if (n == null || n <= 0) return 'درست تعداد درج کریں';
              return null;
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: M360TertiaryButton(
                  label: 'منسوخ کریں',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M360PrimaryButton(
                  label: 'شامل کریں',
                  icon: Icons.add,
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Issue-book form. Pops true on success.
// ─────────────────────────────────────────────────────────────

class _IssueForm extends ConsumerStatefulWidget {
  final LibraryBook book;
  final String? madrasaId;

  const _IssueForm({required this.book, required this.madrasaId});

  @override
  ConsumerState<_IssueForm> createState() => _IssueFormState();
}

class _IssueFormState extends ConsumerState<_IssueForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  String _borrowerType = 'student';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(libraryProvider.notifier).issueBook(BookIssue(
            bookId: widget.book.id ?? '',
            bookTitle: widget.book.title,
            borrowerId: _idCtrl.text.trim(),
            borrowerName: _nameCtrl.text.trim(),
            borrowerType: _borrowerType,
            tenantId: ref.read(currentTenantIdProvider) ?? '',
            madrasaId: widget.madrasaId,
            issuedAt: DateTime.now(),
            dueAt: DateTime.now().add(const Duration(days: 14)),
          ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'کتاب جاری کرنے میں خطا ہوئی', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.book.title,
            textDirection: TextDirection.rtl,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'نام',
            controller: _nameCtrl,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'نام درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'ID / رول نمبر',
            controller: _idCtrl,
          ),
          const SizedBox(height: 12),
          M360Dropdown<String>(
            label: 'نوعیت',
            value: _borrowerType,
            items: const [
              M360DropdownItem(value: 'student', label: 'طالب علم'),
              M360DropdownItem(value: 'teacher', label: 'استاذ'),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _borrowerType = v);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: M360TertiaryButton(
                  label: 'منسوخ کریں',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: M360PrimaryButton(
                  label: 'جاری کریں',
                  icon: Icons.outbox_outlined,
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Return-book form. Pops true on success.
// ─────────────────────────────────────────────────────────────

class _ReturnForm extends ConsumerStatefulWidget {
  final BookIssue issue;

  const _ReturnForm({required this.issue});

  @override
  ConsumerState<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends ConsumerState<_ReturnForm> {
  final _fineCtrl = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void dispose() {
    _fineCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(libraryProvider.notifier).returnBook(
            widget.issue.id ?? '',
            fine: double.tryParse(_fineCtrl.text.trim()) ?? 0,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'واپسی میں خطا ہوئی', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'کتاب: ${issue.bookTitle}',
          textDirection: TextDirection.rtl,
          style: AppTypography.bodyLarge,
        ),
        const SizedBox(height: 8),
        if (issue.isOverdue)
          Text(
            'واجبُ الواپسی — جرمانہ لگائیں',
            textDirection: TextDirection.rtl,
            style: AppTypography.labelMedium.copyWith(color: AppColors.error),
          ),
        const SizedBox(height: 12),
        M360TextField(
          label: 'جرمانہ (روپے)',
          hint: '0',
          controller: _fineCtrl,
          keyboardType: TextInputType.number,
          prefixIcon: Icons.payments_outlined,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: M360TertiaryButton(
                label: 'منسوخ کریں',
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: M360PrimaryButton(
                label: 'واپسی مکمل',
                icon: Icons.check,
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// RTL-aware colored pill badge for availability/overdue labels.
class _LibBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _LibBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: AppTypography.labelSmall
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
