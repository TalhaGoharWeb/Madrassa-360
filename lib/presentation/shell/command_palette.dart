import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/constants/app_colors.dart';
import 'package:madrasa_360/core/constants/app_typography.dart';
import 'package:madrasa_360/core/design/m360.dart';
import 'package:madrasa_360/providers/dashboard_data_provider.dart';
import 'package:madrasa_360/providers/fee_provider.dart';
import 'package:madrasa_360/providers/staff_provider.dart';
import 'package:madrasa_360/providers/student_provider.dart';

import 'nav_destinations.dart';

/// مدرسہ 360 — کمانڈ پیلیٹ (Ctrl+K)
///
/// Global command search for the shell: pages, quick commands, and data
/// (students / staff / darjas / fees) in one palette.
///
/// * Data comes from the same already-loaded client-side providers as
///   [GlobalSearchPage] — the documented limitation applies: only cached
///   data is searchable.
/// * Keyboard: ↑/↓ move, Enter activates, Esc closes.
/// * Page/command selection drives the shell via [onSelectDestination];
///   data results jump to the relevant in-shell list destination.
class CommandPalette extends ConsumerStatefulWidget {
  /// Shows the palette as a dialog. Returns nothing.
  static Future<void> show(
    BuildContext context, {
    required List<NavDestination> visibleDestinations,
    required ValueChanged<String> onSelectDestination,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CommandPalette(
        visibleDestinations: visibleDestinations,
        onSelectDestination: onSelectDestination,
      ),
    );
  }

  const CommandPalette({
    super.key,
    required this.visibleDestinations,
    required this.onSelectDestination,
  });

  /// Permission-filtered destinations the current user may open.
  final List<NavDestination> visibleDestinations;

  /// Shell navigation callback (also used to close the palette).
  final ValueChanged<String> onSelectDestination;

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _PaletteEntry {
  const _PaletteEntry({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onActivate,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onActivate;
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _listController = ScrollController();
  String _query = '';
  int _activeIndex = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// Quick navigation commands (shortcuts to destinations).
  List<_PaletteEntry> _commands() => [
        _PaletteEntry(
          icon: Icons.person_add_outlined,
          title: '+ نیا طالب علم',
          subtitle: 'طلبہ کی فہرست کھولیں',
          onActivate: () => _go('student-list'),
        ),
        _PaletteEntry(
          icon: Icons.fact_check_outlined,
          title: 'حاضری لگائیں',
          subtitle: 'آج کی حاضری',
          onActivate: () => _go('attendance'),
        ),
        _PaletteEntry(
          icon: Icons.payments_outlined,
          title: 'فیس وصول کریں',
          subtitle: 'فیس مینجمنٹ',
          onActivate: () => _go('student_fees'),
        ),
        _PaletteEntry(
          icon: Icons.assignment_outlined,
          title: 'امتحانات',
          subtitle: 'امتحانی ڈیش بورڈ',
          onActivate: () => _go('exams'),
        ),
        _PaletteEntry(
          icon: Icons.bar_chart_outlined,
          title: 'رپورٹ بنائیں',
          subtitle: 'رپورٹس ہب',
          onActivate: () => _go('finance_reports'),
        ),
        _PaletteEntry(
          icon: Icons.campaign_outlined,
          title: 'اعلان جاری کریں',
          subtitle: 'اعلانات',
          onActivate: () => _go('announcements'),
        ),
      ];

  void _go(String destinationId) {
    Navigator.of(context).pop();
    widget.onSelectDestination(destinationId);
  }

  List<_PaletteEntry> _pageEntries() {
    final q = _query.trim();
    return [
      for (final d in widget.visibleDestinations)
        if (d.id != 'logout' && (q.isEmpty || d.labelUr.contains(q)))
          _PaletteEntry(
            icon: d.icon,
            title: d.labelUr,
            subtitle: findGroupOf(d.id)?.labelUr,
            onActivate: () => _go(d.id),
          ),
    ];
  }

  List<_PaletteEntry> _commandEntries() {
    final q = _query.trim();
    // Quick commands respect the same permission filtering as the nav:
    // a command only shows when its destination is visible to this user.
    final visibleIds = widget.visibleDestinations.map((d) => d.id).toSet();
    const targets = {
      '+ نیا طالب علم': 'student-list',
      'حاضری لگائیں': 'attendance',
      'فیس وصول کریں': 'student_fees',
      'امتحانات': 'exams',
      'رپورٹ بنائیں': 'finance_reports',
      'اعلان جاری کریں': 'announcements',
    };
    return [
      for (final c in _commands())
        if ((q.isEmpty || c.title.contains(q)) &&
            visibleIds.contains(targets[c.title]))
          c,
    ];
  }

  List<_PaletteEntry> _dataEntries() {
    final q = _query.trim();
    if (q.isEmpty) return const [];
    final entries = <_PaletteEntry>[];

    final students = ref.watch(allStudentsProvider).valueOrNull ?? [];
    for (final s in students
        .where(
          (s) => _matches(q, [s.name, s.rollNo, s.fatherName, s.darjaName]),
        )
        .take(5)) {
      entries.add(_PaletteEntry(
        icon: Icons.school_outlined,
        title: s.name,
        subtitle: 'طالب علم • ${s.darjaName}',
        onActivate: () => _go('student-list'),
      ));
    }

    final staff = ref.watch(allStaffProvider).valueOrNull ?? [];
    for (final s in staff
        .where(
          (s) => _matches(q, [s.name, s.fatherName, s.designation]),
        )
        .take(5)) {
      entries.add(_PaletteEntry(
        icon: Icons.badge_outlined,
        title: s.name,
        subtitle: 'عملہ • ${s.designation}',
        onActivate: () => _go('staff'),
      ));
    }

    final darjas = ref.watch(safeDarjaListProvider).valueOrNull ?? [];
    for (final d in darjas
        .where(
          (d) => _matches(q, [d.nameUrdu, d.nameEnglish]),
        )
        .take(5)) {
      entries.add(_PaletteEntry(
        icon: Icons.layers_outlined,
        title: d.nameUrdu,
        subtitle: 'درجہ',
        onActivate: () => _go('darjas'),
      ));
    }

    final fees = ref.watch(allFeesProvider).valueOrNull ?? [];
    for (final f in fees
        .where(
          (f) => _matches(q, [f.studentName, f.month, f.studentClass]),
        )
        .take(5)) {
      entries.add(_PaletteEntry(
        icon: Icons.receipt_long_outlined,
        title: f.studentName,
        subtitle: 'فیس • ${f.month}',
        onActivate: () => _go('student_fees'),
      ));
    }
    return entries;
  }

  bool _matches(String query, List<String> fields) {
    final q = query.toLowerCase();
    if (q.isEmpty) return false;
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final items = _allEntries();
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _activeIndex = items.isEmpty ? 0 : (_activeIndex + 1) % items.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _activeIndex = items.isEmpty
            ? 0
            : (_activeIndex - 1 + items.length) % items.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (items.isNotEmpty && _activeIndex < items.length) {
        items[_activeIndex].onActivate();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
    // Note: the dialog is also barrier-dismissible (tap outside closes).
  }

  List<_PaletteEntry> _allEntries() => [
        ..._pageEntries(),
        ..._commandEntries(),
        ..._dataEntries(),
      ];

  @override
  Widget build(BuildContext context) {
    final pages = _pageEntries();
    final commands = _commandEntries();
    final data = _dataEntries();
    final all = [...pages, ...commands, ...data];
    // Clamp locally — never mutate state during build.
    final activeIndex = _activeIndex >= all.length ? 0 : _activeIndex;

    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
      alignment: Alignment.topCenter,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(M360Radius.lg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.7,
        ),
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(M360Spacing.sm),
                child: M360SearchField(
                  controller: _controller,
                  hint: 'تلاش کریں — صفحات، احکامات، طلبہ، عملہ…',
                  autofocus: true,
                  onChanged: (v) => setState(() {
                    _query = v.trim();
                    _activeIndex = 0;
                  }),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: all.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(M360Spacing.lg),
                        child: Text(
                          _query.isEmpty
                              ? 'اوپر لکھ کر تلاش شروع کریں'
                              : '«$_query» کے لیے کوئی نتیجہ نہیں',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _listController,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: M360Spacing.xs,
                        ),
                        itemCount: all.length,
                        itemBuilder: (context, i) {
                          final e = all[i];
                          final active = i == activeIndex;
                          // Section headers before each group.
                          final header = (i == 0 && pages.isNotEmpty)
                              ? 'صفحات'
                              : (i == pages.length && commands.isNotEmpty)
                                  ? 'احکامات'
                                  : (i == pages.length + commands.length &&
                                          data.isNotEmpty)
                                      ? 'تلاش کے نتائج'
                                      : null;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (header != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    2,
                                  ),
                                  child: Text(
                                    header,
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  e.icon,
                                  color: active
                                      ? AppColors.primaryDark
                                      : AppColors.textSecondary,
                                ),
                                title: Text(
                                  e.title,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: active
                                        ? AppColors.primaryDark
                                        : AppColors.textPrimary,
                                    fontWeight: active
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: e.subtitle == null
                                    ? null
                                    : Text(
                                        e.subtitle!,
                                        style: AppTypography.bodySmall,
                                      ),
                                tileColor: active
                                    ? AppColors.primary.withValues(alpha: 0.08)
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    M360Radius.sm,
                                  ),
                                ),
                                onTap: e.onActivate,
                              ),
                            ],
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: M360Spacing.md,
                  vertical: M360Spacing.xs,
                ),
                // Wrap, not Row+Spacer: the hint text is long and the fixed
                // Row overflowed at narrow widths — the shortcut flows below
                // the hint instead.
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: M360Spacing.sm,
                  runSpacing: M360Spacing.xxs,
                  children: [
                    Text(
                      '↑↓ انتخاب • Enter کھولیں • Esc بند کریں',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Ctrl+K',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
