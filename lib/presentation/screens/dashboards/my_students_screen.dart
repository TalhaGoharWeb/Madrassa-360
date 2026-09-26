/// میرے طلبہ — استاد کی جماعتوں کے طلبہ
/// The teacher's own students (Phase 7a).
///
/// Aggregates active students across ONLY the teacher's assigned classes
/// ([teacherClassStudentsProvider], tenant-scoped), de-duplicated by id.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/student.dart';
import '../../../providers/teacher_portal_provider.dart';

class MyStudentsScreen extends ConsumerWidget {
  const MyStudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classIds = ref.watch(teacherAssignedClassIdsProvider);

    // Aggregate students across assigned classes, de-duplicated by id.
    final seen = <String>{};
    final students = <Student>[];
    var loading = false;
    var failed = false;
    for (final id in classIds) {
      final async = ref.watch(teacherClassStudentsProvider(id));
      if (async.isLoading) loading = true;
      if (async.hasError) failed = true;
      for (final s in async.valueOrNull ?? const <Student>[]) {
        if (seen.add(s.id)) students.add(s);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('میرے طلبہ')),
      body: Builder(builder: (context) {
        if (classIds.isEmpty) {
          return _empty('ابھی کوئی جماعت تفویض نہیں');
        }
        if (loading && students.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (failed && students.isEmpty) {
          return _empty('طلبہ لوڈ کرنے میں خطا');
        }
        if (students.isEmpty) {
          return _empty('ابھی کوئی طالب علم نہیں');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'کل ${students.length} طلبہ',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: students.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = students[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          child: Text(
                            s.name.isEmpty
                                ? '؟'
                                : String.fromCharCode(s.name.runes.first),
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: AppTypography.labelNastaliq.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              Text(
                                s.className.isEmpty
                                    ? 'جماعت: —'
                                    : 'جماعت: ${s.className}',
                                style: AppTypography.labelNastaliq
                                    .copyWith(fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                        if (s.rollNo.isNotEmpty)
                          Text(
                            'نمبر ${s.rollNo}',
                            style: AppTypography.labelNastaliq
                                .copyWith(fontSize: 15),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _empty(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            style: AppTypography.labelNastaliq.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.normal,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
}
