/// ڈیش بورڈ فریم ورک — میرا آج کا کام
/// Dashboard framework — "میرا آج کا کام" checklist card.
///
/// Renders a checkbox list. Done-state is OWNED BY THE CALLER (passed in
/// via [tasks]); toggling a box only reports back through [onToggle] —
/// the widget keeps no state of its own, so initial checked states can be
/// derived from real data (e.g. attendance already complete).

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

/// One row of the today-tasks checklist.
class TodayTask {
  /// Urdu task label, e.g. 'آج کی حاضری مکمل کریں'.
  final String label;

  /// Optional supporting line, e.g. '3 میں سے 2 جماعتیں باقی'.
  final String? subtitle;

  /// Whether the box starts checked (caller-owned state).
  final bool done;

  const TodayTask({
    required this.label,
    this.subtitle,
    this.done = false,
  });

  TodayTask copyWith({bool? done}) => TodayTask(
        label: label,
        subtitle: subtitle,
        done: done ?? this.done,
      );
}

/// Checklist card titled 'میرا آج کا کام' with per-row checkboxes.
class TodayTasks extends StatelessWidget {
  final List<TodayTask> tasks;
  final void Function(int index, bool done) onToggle;

  /// Optional action per row (index-aligned with [tasks]); a row shows a
  /// small "کریں" affordance when its action is non-null.
  final List<VoidCallback?>? rowActions;

  const TodayTasks({
    super.key,
    required this.tasks,
    required this.onToggle,
    this.rowActions,
  }) : assert(
          rowActions == null || rowActions.length == tasks.length,
          'rowActions must align with tasks',
        );

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'میرا آج کا کام',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...List.generate(tasks.length, (i) {
            final task = tasks[i];
            final action = rowActions != null && i < rowActions!.length
                ? rowActions![i]
                : null;
            return InkWell(
              onTap: () => onToggle(i, !task.done),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: task.done,
                      activeColor: AppColors.primary,
                      onChanged: (v) => onToggle(i, v ?? false),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.label,
                            style: AppTypography.bodyMedium.copyWith(
                              decoration:
                                  task.done ? TextDecoration.lineThrough : null,
                              color: task.done
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          if (task.subtitle != null &&
                              task.subtitle!.isNotEmpty)
                            Text(
                              task.subtitle!,
                              style: AppTypography.labelSmall,
                            ),
                        ],
                      ),
                    ),
                    if (action != null && !task.done)
                      TextButton(
                        onPressed: action,
                        child: const Text('کریں'),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
