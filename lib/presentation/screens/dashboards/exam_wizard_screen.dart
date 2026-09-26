/// امتحان وزرڈ — §15 (Phase 7b)
/// Step-by-step exam creation wizard (mumtahin, nazim_taleem).
///
/// The whole workflow is NEVER shown at once: one step is visible at a
/// time, with a progress indicator ("مرحلہ N از 8"):
///
///   0 امتحان بنائیں → 1 مضامین → 2 طلبہ → 3 نمبر درج کریں →
///   4 جانچ کریں → 5 نتیجہ تیار کریں → 6 منظوری → 7 شائع کریں
///
/// Real persistence at every step: step 0 creates the exam row through
/// the result repository (local-first sync); step 3 saves marks through
/// the existing result notifier; steps 4–6 are computed from the real
/// saved rows.
///
/// Honesty note: the `exams` table has no publish flag, so step 7 does
/// NOT fake one — "شائع" means the entered results are live on the
/// نتائج screen, and the wizard says exactly that.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_permissions.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/result.dart';
import '../../../data/models/student.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/dashboard_data_provider.dart';
import '../../../providers/result_provider.dart';
import '../../../providers/student_provider.dart';
import '../teacher/results_screen.dart';

const _stepTitles = [
  'امتحان بنائیں',
  'مضامین',
  'طلبہ',
  'نمبر درج کریں',
  'جانچ کریں',
  'نتیجہ تیار کریں',
  'منظوری',
  'شائع کریں',
];

/// One wizard subject row (step 1): name + total marks.
class _SubjectRow {
  final TextEditingController name = TextEditingController();
  final TextEditingController marks = TextEditingController();
  void dispose() {
    name.dispose();
    marks.dispose();
  }
}

class ExamWizardScreen extends ConsumerStatefulWidget {
  const ExamWizardScreen({super.key});

  @override
  ConsumerState<ExamWizardScreen> createState() => _ExamWizardScreenState();
}

class _ExamWizardScreenState extends ConsumerState<ExamWizardScreen> {
  int _step = 0;
  bool _busy = false;

  // Step 0 — exam header.
  final _nameCtrl = TextEditingController();
  final _totalMarksCtrl = TextEditingController(text: '100');
  DateTime _date = DateTime.now();
  String? _classId;
  String? _examId;

  // Step 1 — subjects.
  final List<_SubjectRow> _subjects = [_SubjectRow()];

  // Step 2 — students.
  final List<Student> _students = [];
  final Set<String> _selectedIds = {};

  // Step 3 — marks entry: studentId → subject → obtained.
  final Map<String, Map<String, double>> _marks = {};

  /// studentId → subject → saved row id. Re-saving a subject reuses the
  /// existing row id so `upsertResult` updates in place instead of
  /// creating duplicate rows.
  final Map<String, Map<String, String>> _resultIds = {};
  final Set<String> _savedSubjects = {};
  int _subjectIndex = 0;
  bool _approved = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _totalMarksCtrl.dispose();
    for (final s in _subjects) {
      s.dispose();
    }
    super.dispose();
  }

  List<({String name, double total})> get _validSubjects {
    final out = <({String name, double total})>[];
    for (final s in _subjects) {
      final name = s.name.text.trim();
      final total = double.tryParse(s.marks.text.trim());
      if (name.isNotEmpty && total != null && total > 0) {
        out.add((name: name, total: total));
      }
    }
    return out;
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Navigation ────────────────────────────────────────────────

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _next() async {
    if (_busy) return;
    switch (_step) {
      case 0:
        await _createExam();
        break;
      case 1:
        if (_validSubjects.isEmpty) {
          _snack('کم از کم ایک مضمون (نام اور کل نمبر) درج کریں');
          return;
        }
        setState(() => _step++);
        break;
      case 2:
        if (_selectedIds.isEmpty) {
          _snack('کم از کم ایک طالب علم منتخب کریں');
          return;
        }
        await _loadExistingMarks();
        setState(() => _step++);
        break;
      case 7:
        if (mounted) Navigator.of(context).pop();
        break;
      default:
        setState(() => _step++);
    }
  }

  Future<void> _createExam() async {
    final name = _nameCtrl.text.trim();
    final totalMarks = int.tryParse(_totalMarksCtrl.text.trim());
    if (name.isEmpty) {
      _snack('امتحان کا نام لکھیں');
      return;
    }
    if (totalMarks == null || totalMarks <= 0) {
      _snack('کل نمبر درست لکھیں');
      return;
    }
    setState(() => _busy = true);
    try {
      final exam = await ref.read(resultNotifierProvider.notifier).createExam(
            name: name,
            classId: _classId,
            examDate: _dateStr(_date),
            totalMarks: totalMarks,
          );
      setState(() {
        _examId = exam.id;
        _step = 1;
      });
    } catch (e) {
      _snack('امتحان بنانے میں خرابی ہوئی');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prefills [_marks] (and [_resultIds]) with whatever is already saved
  /// for this exam — re-entering the wizard never loses entered marks,
  /// and re-saving updates the same rows instead of duplicating them.
  Future<void> _loadExistingMarks() async {
    final examId = _examId;
    if (examId == null) return;
    try {
      final existing = await ref.read(examResultsProvider(examId).future);
      final map = <String, Map<String, double>>{};
      final ids = <String, Map<String, String>>{};
      for (final sr in existing) {
        for (final sub in sr.subjects) {
          (map[sr.studentId] ??= {})[sub.subject] = sub.marksObtained;
          (ids[sr.studentId] ??= {})[sub.subject] = sub.id;
        }
      }
      _marks
        ..clear()
        ..addAll(map);
      _resultIds
        ..clear()
        ..addAll(ids);
      _savedSubjects
        ..clear()
        ..addAll({
          for (final sr in existing)
            for (final sub in sr.subjects) sub.subject,
        });
    } catch (_) {
      // Prefill is best-effort; entry still works from scratch.
    }
  }

  // ── Step 3: save marks for the current subject ─────────────────

  Future<void> _saveSubjectMarks() async {
    final subjects = _validSubjects;
    if (_subjectIndex >= subjects.length) return;
    final subject = subjects[_subjectIndex];
    final tenantId = ref.read(currentTenantIdProvider);
    final examId = _examId;
    if (tenantId == null || examId == null) {
      _snack('لاگ اِن درکار ہے');
      return;
    }
    final notifier = ref.read(resultNotifierProvider.notifier);
    setState(() => _busy = true);
    var saved = 0;
    try {
      for (final st in _students) {
        if (!_selectedIds.contains(st.id)) continue;
        final obtained = _marks[st.id]?[subject.name];
        if (obtained == null) continue;
        // Reuse the existing row id when present so re-saving updates
        // the same row instead of creating a duplicate.
        final rowId = _resultIds[st.id]?[subject.name] ?? const Uuid().v4();
        await notifier.save(SubjectResult(
          id: rowId,
          tenantId: tenantId,
          examId: examId,
          studentId: st.id,
          subject: subject.name,
          marksObtained: obtained,
          totalMarks: subject.total,
        ));
        (_resultIds[st.id] ??= {})[subject.name] = rowId;
        saved++;
      }
      setState(() => _savedSubjects.add(subject.name));
      _snack(saved == 0
          ? 'کوئی نمبر درج نہیں — پہلے نمبر لکھیں'
          : '$saved طلبہ کے نمبر محفوظ ہو گئے');
    } catch (_) {
      _snack('محفوظ کرنے میں خرابی ہوئی');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Review computation (steps 4–6) ────────────────────────────

  /// studentId → subject → obtained, from the REAL saved rows.
  Map<String, Map<String, double>> _reviewMap(List<StudentResult> results) {
    final map = <String, Map<String, double>>{};
    for (final sr in results) {
      for (final sub in sr.subjects) {
        (map[sr.studentId] ??= {})[sub.subject] = sub.marksObtained;
      }
    }
    return map;
  }

  bool _isComplete(Map<String, Map<String, double>> map) {
    final subjects = _validSubjects;
    for (final id in _selectedIds) {
      final row = map[id];
      for (final s in subjects) {
        if (row?[s.name] == null) return false;
      }
    }
    return _selectedIds.isNotEmpty;
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canPublish = ref.watch(
      hasPermissionProvider(AppPermissions.publishResults),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('امتحان وزرڈ')),
      body: Column(
        children: [
          _ProgressHeader(step: _step),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _stepBody(canPublish),
            ),
          ),
          _BottomBar(
            step: _step,
            busy: _busy,
            onBack: _back,
            onNext: _next,
          ),
        ],
      ),
    );
  }

  Widget _stepBody(bool canPublish) {
    switch (_step) {
      case 0:
        return _buildExamForm();
      case 1:
        return _buildSubjects();
      case 2:
        return _buildStudents();
      case 3:
        return _buildMarksEntry();
      case 4:
        return _buildReview();
      case 5:
        return _buildPrepare();
      case 6:
        return _buildApproval(canPublish);
      case 7:
        return _buildPublish();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 0: exam header form ──────────────────────────────────

  Widget _buildExamForm() {
    final darjasAsync = ref.watch(safeDarjaListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('امتحان کی بنیادی معلومات درج کریں',
            style: AppTypography.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'امتحان کا نام',
            hintText: 'مثلاً: سہ ماہی امتحان',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) setState(() => _date = picked);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'امتحان کی تاریخ',
              border: OutlineInputBorder(),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18),
                const SizedBox(width: 8),
                Text(_dateStr(_date)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        darjasAsync.when(
          data: (darjas) => DropdownButtonFormField<String?>(
            initialValue: _classId,
            decoration: const InputDecoration(
              labelText: 'درجہ / جماعت (اختیاری)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('کوئی نہیں'),
              ),
              for (final d in darjas)
                DropdownMenuItem<String?>(
                  value: d.id,
                  child: Text(d.nameUrdu),
                ),
            ],
            onChanged: (v) => setState(() => _classId = v),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _totalMarksCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'کل نمبر',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  // ── Step 1: subjects ──────────────────────────────────────────

  Widget _buildSubjects() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('امتحان کے مضامین اور ان کے کل نمبر درج کریں',
            style: AppTypography.bodyMedium),
        const SizedBox(height: 12),
        ..._subjects.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.name,
                    decoration: InputDecoration(
                      labelText: 'مضمون ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.marks,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'کل نمبر',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppColors.error,
                  onPressed: _subjects.length <= 1
                      ? null
                      : () {
                          setState(() {
                            row.dispose();
                            _subjects.removeAt(i);
                          });
                        },
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: () => setState(() => _subjects.add(_SubjectRow())),
          icon: const Icon(Icons.add),
          label: const Text('مضمون شامل کریں'),
        ),
      ],
    );
  }

  // ── Step 2: students ──────────────────────────────────────────

  Widget _buildStudents() {
    final studentsAsync = ref.watch(allStudentsProvider);

    return studentsAsync.when(
      data: (all) {
        final active = all.where((s) => s.isActive).toList();
        if (_students.isEmpty && active.isNotEmpty) {
          // First build: seed the selection (all active students).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _students.isNotEmpty) return;
            setState(() {
              _students.addAll(active);
              _selectedIds.addAll(active.map((s) => s.id));
            });
          });
        }
        if (active.isEmpty) {
          return const _EmptyNote(
              'ابھی کوئی طالب علم درج نہیں — پہلے داخلے کریں');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedIds.length} طلبہ منتخب',
                    style: AppTypography.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedIds
                    ..clear()
                    ..addAll(active.map((s) => s.id))),
                  child: const Text('سب منتخب کریں'),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedIds.clear()),
                  child: const Text('سب ختم کریں'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...active.map((s) => CheckboxListTile(
                  value: _selectedIds.contains(s.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedIds.add(s.id);
                    } else {
                      _selectedIds.remove(s.id);
                    }
                  }),
                  title: Text(s.name),
                  subtitle: s.className.isEmpty ? null : Text(s.className),
                  controlAffinity: ListTileControlAffinity.leading,
                )),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _EmptyNote('طلبہ لوڈ نہیں ہو سکے'),
    );
  }

  // ── Step 3: marks entry ───────────────────────────────────────

  Widget _buildMarksEntry() {
    final subjects = _validSubjects;
    if (subjects.isEmpty) {
      return const _EmptyNote('پہلے مضامین درج کریں');
    }
    final subject = subjects[_subjectIndex.clamp(0, subjects.length - 1)];
    final selected =
        _students.where((s) => _selectedIds.contains(s.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('مضمون منتخب کریں، پھر ہر طالب علم کے نمبر لکھیں',
            style: AppTypography.bodyMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: subjects.asMap().entries.map((e) {
            final i = e.key;
            final saved = _savedSubjects.contains(e.value.name);
            return ChoiceChip(
              label: Text('${e.value.name}${saved ? ' ✓' : ''}'),
              selected: i == _subjectIndex,
              onSelected: (_) => setState(() => _subjectIndex = i),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'کل نمبر: ${subject.total.toStringAsFixed(subject.total % 1 == 0 ? 0 : 1)}',
          style: AppTypography.labelSmall,
        ),
        const SizedBox(height: 12),
        ...selected.map((s) {
          final current = _marks[s.id]?[subject.name];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(s.name, style: AppTypography.bodyMedium),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('${s.id}_${subject.name}'),
                    initialValue: current == null
                        ? ''
                        : current.toStringAsFixed(current % 1 == 0 ? 0 : 1),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'نمبر',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v.trim());
                      setState(() {
                        if (parsed == null) {
                          _marks[s.id]?.remove(subject.name);
                        } else {
                          (_marks[s.id] ??= {})[subject.name] =
                              parsed.clamp(0, subject.total);
                        }
                        _savedSubjects.remove(subject.name);
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _saveSubjectMarks,
            icon: const Icon(Icons.save_outlined),
            label: Text('«${subject.name}» کے نمبر محفوظ کریں'),
          ),
        ),
      ],
    );
  }

  // ── Step 4: review ────────────────────────────────────────────

  Widget _buildReview() {
    final examId = _examId;
    if (examId == null) {
      return const _EmptyNote('امتحان نہیں بنا');
    }
    final resultsAsync = ref.watch(examResultsProvider(examId));
    final subjects = _validSubjects;

    return resultsAsync.when(
      data: (results) {
        final map = _reviewMap(results);
        final selected =
            _students.where((s) => _selectedIds.contains(s.id)).toList();
        if (selected.isEmpty) {
          return const _EmptyNote('کوئی طالب علم منتخب نہیں');
        }
        var complete = 0;
        final rows = <Widget>[];
        for (final st in selected) {
          final cells = <Widget>[];
          var allIn = true;
          var total = 0.0;
          for (final sub in subjects) {
            final m = map[st.id]?[sub.name];
            if (m == null) allIn = false;
            total += m ?? 0;
            cells.add(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: m == null
                      ? AppColors.warning.withValues(alpha: 0.15)
                      : AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  m == null ? '—' : m.toStringAsFixed(m % 1 == 0 ? 0 : 1),
                  style: AppTypography.labelSmall,
                ),
              ),
            );
          }
          if (allIn) complete++;
          rows.add(
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(st.name,
                              style: AppTypography.bodyMedium
                                  .copyWith(fontWeight: FontWeight.bold)),
                        ),
                        Icon(
                          allIn
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_outlined,
                          color: allIn ? AppColors.success : AppColors.warning,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var i = 0; i < subjects.length; i++)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(subjects[i].name,
                                style: AppTypography.labelSmall),
                            cells[i],
                          ],
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text('کل: ${total.toStringAsFixed(1)}',
                        style: AppTypography.labelSmall),
                  ],
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusLine(
              ok: complete == selected.length,
              text: complete == selected.length
                  ? 'سب طلبہ کے نمبر مکمل ہیں'
                  : '${selected.length} میں سے $complete طلبہ کے نمبر مکمل ہیں',
            ),
            const SizedBox(height: 12),
            ...rows,
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _EmptyNote('نتائج لوڈ نہیں ہو سکے'),
    );
  }

  // ── Step 5: prepare result ────────────────────────────────────

  Widget _buildPrepare() {
    final examId = _examId;
    if (examId == null) {
      return const _EmptyNote('امتحان نہیں بنا');
    }
    final resultsAsync = ref.watch(examResultsProvider(examId));
    final subjects = _validSubjects;
    final grandTotal = subjects.fold<double>(0, (s, e) => s + e.total);

    return resultsAsync.when(
      data: (results) {
        final map = _reviewMap(results);
        final selected =
            _students.where((s) => _selectedIds.contains(s.id)).toList();
        var complete = 0;
        var pass = 0;
        String? topper;
        var topPct = -1.0;
        for (final st in selected) {
          var got = 0.0;
          var allIn = true;
          for (final sub in subjects) {
            final m = map[st.id]?[sub.name];
            if (m == null) {
              allIn = false;
            } else {
              got += m;
            }
          }
          if (!allIn) continue;
          complete++;
          final pct = grandTotal > 0 ? got * 100 / grandTotal : 0.0;
          if (pct >= 50) pass++;
          if (pct > topPct) {
            topPct = pct;
            topper = st.name;
          }
        }
        final ready = complete == selected.length && selected.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusLine(
              ok: ready,
              text: ready
                  ? 'نتیجہ تیار ہے'
                  : 'نتیجہ ابھی مکمل نہیں — کچھ نمبر باقی ہیں',
            ),
            const SizedBox(height: 12),
            _ResultTile(label: 'مکمل نتائج', value: '$complete'),
            _ResultTile(
                label: 'نامکمل', value: '${selected.length - complete}'),
            _ResultTile(
                label: 'کامیابی کی شرح',
                value: complete == 0
                    ? '—'
                    : '${(pass * 100 / complete).round()}٪'),
            _ResultTile(label: 'اول پوزیشن', value: topper ?? '—'),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _EmptyNote('نتائج لوڈ نہیں ہو سکے'),
    );
  }

  // ── Step 6: approval ──────────────────────────────────────────

  Widget _buildApproval(bool canPublish) {
    final examId = _examId;
    if (examId == null) {
      return const _EmptyNote('امتحان نہیں بنا');
    }
    final resultsAsync = ref.watch(examResultsProvider(examId));

    return resultsAsync.when(
      data: (results) {
        final complete = _isComplete(_reviewMap(results));
        final canApprove = complete && canPublish && !_approved;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('نتائج کی منظوری سے پہلے یہ شرائط پوری ہونی چاہئیں',
                style: AppTypography.bodyMedium),
            const SizedBox(height: 12),
            _CheckRow(ok: complete, label: 'تمام طلبہ کے تمام نمبر درج ہیں'),
            _CheckRow(ok: canPublish, label: 'آپ کو منظوری کا اختیار ہے'),
            const SizedBox(height: 16),
            if (_approved)
              const _StatusLine(ok: true, text: 'نتائج منظور ہو گئے'),
            if (!_approved && !canPublish)
              Text(
                'منظوری کا اختیار ناظم تعلیم کے پاس ہے — براہ کرم ان سے '
                'رابطہ کریں',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.warning,
                ),
              ),
            if (canApprove) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _approved = true),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('منظور کریں'),
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _EmptyNote('نتائج لوڈ نہیں ہو سکے'),
    );
  }

  // ── Step 7: publish ───────────────────────────────────────────

  Widget _buildPublish() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StatusLine(
          ok: true,
          text: 'نمبر درج ہو گئے ہیں — نتائج اب نتائج کی اسکرین پر '
              'دیکھے جا سکتے ہیں',
        ),
        const SizedBox(height: 12),
        if (!_approved)
          Text(
            'نوٹ: منظوری ابھی باقی ہے — نتائج پھر بھی درج شدہ حالت میں '
            'دستیاب ہیں',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.warning,
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ResultsScreen()),
              );
            },
            icon: const Icon(Icons.assessment_outlined),
            label: const Text('نتائج دیکھیں'),
          ),
        ),
      ],
    );
  }
}

/// Progress header: "مرحلہ N از 8" + bar + step title.
class _ProgressHeader extends StatelessWidget {
  final int step;
  const _ProgressHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مرحلہ ${step + 1} از ${_stepTitles.length}',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (step + 1) / _stepTitles.length,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            color: AppColors.primary,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Text(
            _stepTitles[step],
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom navigation: پیچھے / آگے (مکمل کریں on the last step).
class _BottomBar extends StatelessWidget {
  final int step;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _BottomBar({
    required this.step,
    required this.busy,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: step == 0 || busy ? null : onBack,
            child: const Text('پیچھے'),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: busy ? null : onNext,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(step == _stepTitles.length - 1 ? 'مکمل کریں' : 'آگے'),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: AppTypography.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool ok;
  final String text;
  const _StatusLine({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            (ok ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.info_outline,
            color: ok ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final bool ok;
  final String label;
  const _CheckRow({required this.ok, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel_outlined,
            color: ok ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String label;
  final String value;
  const _ResultTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label, style: AppTypography.bodyMedium),
        trailing: Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
