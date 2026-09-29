import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/design/m360.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/models.dart';
import '../../../providers/darja_provider.dart';

/// درجات — m360 redesign (Phase 10)
///
/// Same provider flows (load/create/delete darjas and sections, real
/// darja UUIDs). Destructive actions go through destructive
/// [showM360ConfirmDialog]. Rendered as an [AppShell] destination: no
/// Scaffold, no AppBar — [PageContainer]/[PageHeader] only.
class DarjaScreen extends ConsumerStatefulWidget {
  final String? madrasaId;
  const DarjaScreen({super.key, this.madrasaId});

  @override
  ConsumerState<DarjaScreen> createState() => _DarjaScreenState();
}

class _DarjaScreenState extends ConsumerState<DarjaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        ref.read(darjaProvider.notifier).loadAll(madrasaId: widget.madrasaId));
  }

  static const _levelColors = <String, Color>{
    'nazra': AppColors.info,
    'hifz': AppColors.success,
    'dars_e_nizami': AppColors.primary,
    'takhassus': AppColors.accent,
  };

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
    final state = ref.watch(darjaProvider);
    final darjas = state.darjas;

    // Group by level.
    final grouped = <String, List<Darja>>{};
    for (final d in darjas) {
      grouped.putIfAbsent(d.level, () => []).add(d);
    }
    const levels = ['nazra', 'hifz', 'dars_e_nizami', 'takhassus'];

    return PageContainer(
      header: PageHeader(
        title: 'درجات',
        breadcrumb: 'منتظم',
        description: 'جماعتیں اور ان کے سیکشنز',
        actions: _withBack(context, [
          M360PrimaryButton(
            label: 'نیا درجہ',
            icon: Icons.add,
            onPressed: () => _showAddDarjaDialog(context),
          ),
        ]),
      ),
      child: state.isLoading
          ? const M360LoadingState()
          : darjas.isEmpty
              ? M360EmptyState(
                  icon: Icons.class_outlined,
                  title: 'کوئی درجہ نہیں',
                  description: 'پہلا درجہ بنا کر جماعتوں کی تنظیم شروع کریں۔',
                  actionLabel: 'نیا درجہ بنائیں',
                  onAction: () => _showAddDarjaDialog(context),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final level in levels)
                      if (grouped.containsKey(level)) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Row(
                            children: [
                              _LevelBadge(
                                label: _levelLabel(level),
                                color: _levelColors[level] ?? AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${grouped[level]!.length} درجے',
                                style: AppTypography.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        for (final darja in grouped[level]!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DarjaCard(
                              darja: darja,
                              color: _levelColors[level] ?? AppColors.primary,
                              madrasaId: widget.madrasaId,
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
    );
  }

  String _levelLabel(String level) {
    switch (level) {
      case 'nazra':
        return 'ناظرہ';
      case 'hifz':
        return 'حفظ';
      case 'dars_e_nizami':
        return 'درس نظامی';
      case 'takhassus':
        return 'تخصص';
      default:
        return level;
    }
  }

  Future<void> _showAddDarjaDialog(BuildContext context) async {
    final added = await showM360Dialog<bool>(
      context,
      title: 'نیا درجہ',
      icon: Icons.class_outlined,
      content: _DarjaForm(madrasaId: widget.madrasaId),
    );
    if (added != true) return;
    if (!context.mounted) return;
    showM360SnackBar(context, 'درجہ شامل کر دیا گیا');
  }
}

// ─────────────────────────────────────────────────────────────

class _DarjaCard extends ConsumerWidget {
  final Darja darja;
  final Color color;
  final String? madrasaId;

  const _DarjaCard({
    required this.darja,
    required this.color,
    required this.madrasaId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections =
        ref.read(darjaProvider.notifier).sectionsForDarja(darja.id ?? '');

    return M360Card(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            '${darja.orderIndex}',
            style: AppTypography.bodyLarge.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          darja.nameUrdu,
          style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${darja.nameEnglish} • گنجائش: ${darja.capacity}',
          style:
              AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
        ),
        trailing: M360IconButton(
          icon: Icons.delete_outline,
          tooltip: 'درجہ حذف کریں',
          color: AppColors.error,
          onPressed: () => _confirmDeleteDarja(context, ref),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sections.isEmpty)
                  Text(
                    'کوئی سیکشن نہیں',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                for (final sec in sections)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.group_outlined, color: color, size: 20),
                    title: Text(sec.nameUrdu, style: AppTypography.bodyMedium),
                    trailing: M360IconButton(
                      icon: Icons.remove_circle_outline,
                      tooltip: 'سیکشن حذف کریں',
                      color: AppColors.error,
                      onPressed: () => _confirmDeleteSection(context, ref, sec),
                    ),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: M360SecondaryButton(
                    label: 'سیکشن شامل کریں',
                    icon: Icons.add,
                    onPressed: () => _showAddSectionDialog(context, ref),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteDarja(BuildContext context, WidgetRef ref) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'درجہ حذف کریں؟',
      message: '«${darja.nameUrdu}» مستقل طور پر حذف ہو جائے گا۔'
          ' یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (confirmed) {
      await ref.read(darjaProvider.notifier).deleteDarja(darja.id ?? '');
    }
  }

  Future<void> _confirmDeleteSection(
    BuildContext context,
    WidgetRef ref,
    DarjaSection sec,
  ) async {
    final confirmed = await showM360ConfirmDialog(
      context,
      title: 'سیکشن حذف کریں؟',
      message: '«${sec.nameUrdu}» مستقل طور پر حذف ہو جائے گا۔'
          ' یہ عمل واپس نہیں ہو سکتا۔',
      confirmLabel: 'حذف کریں',
      danger: true,
    );
    if (confirmed) {
      await ref.read(darjaProvider.notifier).deleteSection(sec.id ?? '');
    }
  }

  Future<void> _showAddSectionDialog(
      BuildContext context, WidgetRef ref) async {
    final added = await showM360Dialog<bool>(
      context,
      title: 'نیا سیکشن',
      icon: Icons.group_add_outlined,
      content: _SectionForm(darja: darja, madrasaId: madrasaId),
    );
    if (added == true && context.mounted) {
      showM360SnackBar(context, 'سیکشن شامل کر دیا گیا');
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Create-darja form. Pops true on success.
// ─────────────────────────────────────────────────────────────

class _DarjaForm extends ConsumerStatefulWidget {
  final String? madrasaId;

  const _DarjaForm({required this.madrasaId});

  @override
  ConsumerState<_DarjaForm> createState() => _DarjaFormState();
}

class _DarjaFormState extends ConsumerState<_DarjaForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameUCtrl = TextEditingController();
  final _nameECtrl = TextEditingController();
  final _capCtrl = TextEditingController(text: '30');
  String _level = 'nazra';
  bool _saving = false;

  @override
  void dispose() {
    _nameUCtrl.dispose();
    _nameECtrl.dispose();
    _capCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(darjaProvider.notifier).createDarja(Darja(
            nameUrdu: _nameUCtrl.text.trim(),
            nameEnglish: _nameECtrl.text.trim(),
            level: _level,
            tenantId: ref.read(currentTenantIdProvider) ?? '',
            madrasaId: widget.madrasaId,
            capacity: int.tryParse(_capCtrl.text.trim()) ?? 30,
          ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'درجہ بنانے میں خطا ہوئی', isError: true);
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
            label: 'نام (اردو)',
            controller: _nameUCtrl,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'نام درج کریں' : null,
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'نام (انگریزی)',
            controller: _nameECtrl,
          ),
          const SizedBox(height: 12),
          M360Dropdown<String>(
            label: 'سطح',
            value: _level,
            items: const [
              M360DropdownItem(value: 'nazra', label: 'ناظرہ'),
              M360DropdownItem(value: 'hifz', label: 'حفظ'),
              M360DropdownItem(value: 'dars_e_nizami', label: 'درس نظامی'),
              M360DropdownItem(value: 'takhassus', label: 'تخصص'),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _level = v);
            },
          ),
          const SizedBox(height: 12),
          M360TextField(
            label: 'گنجائش',
            controller: _capCtrl,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              if (n == null || n <= 0) return 'درست گنجائش درج کریں';
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
// Create-section form. Pops true on success.
// ─────────────────────────────────────────────────────────────

class _SectionForm extends ConsumerStatefulWidget {
  final Darja darja;
  final String? madrasaId;

  const _SectionForm({required this.darja, required this.madrasaId});

  @override
  ConsumerState<_SectionForm> createState() => _SectionFormState();
}

class _SectionFormState extends ConsumerState<_SectionForm> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(darjaProvider.notifier).createSection(DarjaSection(
            darjaId: widget.darja.id ?? '',
            tenantId: ref.read(currentTenantIdProvider) ?? '',
            madrasaId: widget.madrasaId,
            nameUrdu: _ctrl.text.trim(),
          ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showM360SnackBar(context, 'سیکشن بنانے میں خطا ہوئی', isError: true);
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
            label: 'سیکشن کا نام',
            hint: 'مثلاً الف',
            controller: _ctrl,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'نام درج کریں' : null,
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

/// RTL-aware colored pill badge for darja level headers.
class _LevelBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _LevelBadge({required this.label, required this.color});

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
        style: AppTypography.labelMedium
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
