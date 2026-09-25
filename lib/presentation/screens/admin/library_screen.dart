import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/models.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/auth_provider.dart';

class LibraryScreen extends StatefulWidget {
  final String? madrasaId;
  const LibraryScreen({super.key, this.madrasaId});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  WidgetRef? _ref;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        _ref?.read(libraryProvider.notifier).load(
            madrasaId: widget.madrasaId));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      _ref = ref;
      final state = ref.watch(libraryProvider);
      final isAdmin = (ref.watch(authProvider).user?.role.name ?? '')
          .contains('admin');

      return Scaffold(
        appBar: AppBar(
          title: Text('کتب خانہ', style: AppTypography.appBarTitle),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'تمام کتابیں'),
              Tab(text: 'جاری'),
              Tab(text: 'واجبُ الواپسی'),
            ],
          ),
        ),
        backgroundColor: AppColors.background,
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add),
                label: const Text('نئی کتاب'),
                onPressed: () => _showAddBookDialog(context, ref),
              )
            : null,
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(controller: _tabs, children: [
                _BooksList(state.books, ref, isAdmin, context, widget.madrasaId),
                _IssuesList(
                    state.issues.where((i) => !i.isReturned).toList(),
                    ref, isAdmin, context),
                _IssuesList(
                    state.issues.where((i) => i.isOverdue).toList(),
                    ref, isAdmin, context,
                    isOverdue: true),
              ]),
      );
    });
  }

  Future<void> _showAddBookDialog(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final isbnCtrl = TextEditingController();
    final copiesCtrl = TextEditingController(text: '1');

    await showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('نئی کتاب', style: AppTypography.titleMedium),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(titleCtrl, 'عنوان'),
            _field(authorCtrl, 'مصنف'),
            _field(subjectCtrl, 'مضمون'),
            _field(isbnCtrl, 'ISBN (اختیاری)'),
            _field(copiesCtrl, 'کاپیاں'),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('منسوخ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dCtx);
              await ref.read(libraryProvider.notifier).addBook(LibraryBook(
                    title: titleCtrl.text,
                    author: authorCtrl.text,
                    subject: subjectCtrl.text,
                    isbn: isbnCtrl.text,
                    totalCopies: int.tryParse(copiesCtrl.text) ?? 1,
                    availableCopies: int.tryParse(copiesCtrl.text) ?? 1,
                    tenantId: ref.read(currentTenantIdProvider) ?? '',
                    madrasaId: widget.madrasaId,
                  ));
            },
            child: const Text('شامل'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────
class _BooksList extends StatelessWidget {
  const _BooksList(
      this.books, this.ref, this.isAdmin, this.parentCtx, this.madrasaId);
  final List<LibraryBook> books;
  final WidgetRef ref;
  final bool isAdmin;
  final BuildContext parentCtx;
  final String? madrasaId;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
          child: Text('کوئی کتاب نہیں',
              style: AppTypography.bodyLarge
                  .copyWith(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final b = books[i];
        final available = b.availableCopies > 0;
        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 48,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.menu_book_outlined,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(b.title, style: AppTypography.bodyLarge),
                    Text(b.author ?? '',
                        style: AppTypography.labelMedium
                            .copyWith(color: AppColors.textSecondary)),
                    Text(b.subject ?? '',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: available
                              ? AppColors.success.withOpacity(0.1)
                              : AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          available
                              ? 'دستیاب: ${b.availableCopies}'
                              : 'غیر دستیاب',
                          style: AppTypography.labelSmall.copyWith(
                              color: available
                                  ? AppColors.success
                                  : AppColors.error),
                        ),
                      ),
                    ]),
                  ])),
              if (isAdmin)
                Column(children: [
                  if (available)
                    IconButton(
                      icon: const Icon(Icons.outbox_outlined),
                      color: AppColors.primary,
                      tooltip: 'جاری',
                      onPressed: () => _issueBookDialog(context, b),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: AppColors.error,
                    onPressed: () =>
                        ref.read(libraryProvider.notifier).deleteBook(b.id ?? ''),
                  ),
                ]),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _issueBookDialog(BuildContext context, LibraryBook book) async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    String borrowerType = 'student';

    await showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
        return AlertDialog(
          title: Text('کتاب جاری کریں', style: AppTypography.titleMedium),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(book.title,
                style: AppTypography.bodyLarge
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: nameCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                    labelText: 'نام', border: OutlineInputBorder()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                    labelText: 'ID / رول نمبر',
                    border: OutlineInputBorder()),
              ),
            ),
            DropdownButtonFormField<String>(
              value: borrowerType,
              decoration: const InputDecoration(
                  labelText: 'نوعیت', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'student', child: Text('طالب')),
                DropdownMenuItem(value: 'teacher', child: Text('استاذ')),
              ],
              onChanged: (v) => setS(() => borrowerType = v!),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('منسوخ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(dCtx);
                await ref.read(libraryProvider.notifier).issueBook(BookIssue(
                      bookId: book.id ?? '',
                      bookTitle: book.title,
                      borrowerId: idCtrl.text,
                      borrowerName: nameCtrl.text,
                      borrowerType: borrowerType,
                      tenantId: ref.read(currentTenantIdProvider) ?? '',
                      madrasaId: madrasaId,
                      issuedAt: DateTime.now(),
                      dueAt: DateTime.now().add(const Duration(days: 14)),
                    ));
              },
              child: const Text('جاری'),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
class _IssuesList extends StatelessWidget {
  const _IssuesList(this.issues, this.ref, this.isAdmin, this.ctx,
      {this.isOverdue = false});
  final List<BookIssue> issues;
  final WidgetRef ref;
  final bool isAdmin;
  final BuildContext ctx;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return Center(
          child: Text('کوئی ریکارڈ نہیں',
              style: AppTypography.bodyLarge
                  .copyWith(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: issues.length,
      itemBuilder: (ctx, i) {
        final issue = issues[i];
        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  isOverdue ? AppColors.error.withOpacity(0.1) : AppColors.info.withOpacity(0.1),
              child: Icon(Icons.person_outline,
                  color: isOverdue ? AppColors.error : AppColors.info),
            ),
            title: Text(issue.bookTitle, style: AppTypography.bodyLarge),
            subtitle: Text(
              '${issue.borrowerName} • ${issue.borrowerType}',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            trailing: isAdmin
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4)),
                    onPressed: () =>
                        _returnDialog(context, issue),
                    child: const Text('واپسی'),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _returnDialog(BuildContext context, BookIssue issue) async {
    final fineCtrl = TextEditingController(text: '0');
    await showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('کتاب واپس'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('کتاب: ${issue.bookTitle}',
              style: AppTypography.bodyLarge),
          const SizedBox(height: 8),
          if (issue.isOverdue)
            Text('واجبُ الواپسی — جرمانہ لگائیں',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.error)),
          const SizedBox(height: 12),
          TextField(
            controller: fineCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'جرمانہ (₹)',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('منسوخ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dCtx);
              await ref.read(libraryProvider.notifier).returnBook(
                    issue.id ?? '',
                    fine: double.tryParse(fineCtrl.text) ?? 0,
                  );
            },
            child: const Text('واپسی مکمل'),
          ),
        ],
      ),
    );
  }
}
