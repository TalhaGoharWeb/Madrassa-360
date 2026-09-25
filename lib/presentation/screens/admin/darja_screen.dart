import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/tenant_context.dart';
import '../../../data/models/models.dart';
import '../../../providers/darja_provider.dart';

class DarjaScreen extends StatefulWidget {
  final String? madrasaId;
  const DarjaScreen({super.key, this.madrasaId});
  @override
  State<DarjaScreen> createState() => _DarjaScreenState();
}

class _DarjaScreenState extends State<DarjaScreen> {
  WidgetRef? _ref;

  static const _levelColors = {
    'nazra': Color(0xFF1565C0),
    'hifz': Color(0xFF2E7D32),
    'dars_e_nizami': Color(0xFF6A1B9A),
    'takhassus': Color(0xFFE65100),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        _ref?.read(darjaProvider.notifier).loadAll(
            madrasaId: widget.madrasaId));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      _ref = ref;
      final state = ref.watch(darjaProvider);
      final darjas = state.darjas;

      // Group by level
      final grouped = <String, List<Darja>>{};
      for (final d in darjas) {
        grouped.putIfAbsent(d.level, () => []).add(d);
      }
      final levels = ['nazra', 'hifz', 'dars_e_nizami', 'takhassus'];

      return Scaffold(
        appBar: AppBar(
          title: Text('درجات', style: AppTypography.appBarTitle),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('نیا درجہ'),
          onPressed: () => _showAddDarjaDialog(context, ref),
        ),
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : darjas.isEmpty
                ? Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Icon(Icons.class_outlined,
                            size: 64, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text('کوئی درجہ نہیں',
                            style: AppTypography.bodyLarge.copyWith(
                                color: AppColors.textSecondary)),
                      ]))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final level in levels)
                        if (grouped.containsKey(level)) ...[
                          _LevelHeader(
                              _levelLabel(level),
                              _levelColors[level] ??
                                  AppColors.primary),
                          const SizedBox(height: 8),
                          for (final darja
                              in grouped[level]!) ...[
                            _DarjaCard(darja, ref,
                                _levelColors[level] ??
                                    AppColors.primary, context, widget.madrasaId),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
      );
    });
  }

  String _levelLabel(String level) {
    switch (level) {
      case 'nazra': return 'ناظرہ';
      case 'hifz': return 'حفظ';
      case 'dars_e_nizami': return 'درس نظامی';
      case 'takhassus': return 'تخصص';
      default: return level;
    }
  }

  Future<void> _showAddDarjaDialog(BuildContext ctx, WidgetRef ref) async {
    final nameUCtrl = TextEditingController();
    final nameECtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '30');
    String level = 'nazra';

    await showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
        return AlertDialog(
          title: Text('نیا درجہ', style: AppTypography.titleMedium),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(nameUCtrl, 'نام (اردو)'),
              _field(nameECtrl, 'نام (انگریزی)'),
              DropdownButtonFormField<String>(
                value: level,
                decoration: const InputDecoration(
                    labelText: 'سطح', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'nazra', child: Text('ناظرہ')),
                  DropdownMenuItem(value: 'hifz', child: Text('حفظ')),
                  DropdownMenuItem(value: 'dars_e_nizami', child: Text('درس نظامی')),
                  DropdownMenuItem(value: 'takhassus', child: Text('تخصص')),
                ],
                onChanged: (v) => setS(() => level = v!),
              ),
              const SizedBox(height: 12),
              _field(capCtrl, 'گنجائش'),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('منسوخ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(dCtx);
                await ref.read(darjaProvider.notifier).createDarja(Darja(
                  nameUrdu: nameUCtrl.text,
                  nameEnglish: nameECtrl.text,
                  level: level,
                  tenantId: ref.read(currentTenantIdProvider) ?? '',
                  madrasaId: widget.madrasaId,
                  capacity: int.tryParse(capCtrl.text) ?? 30,
                ));
              },
              child: const Text('شامل'),
            ),
          ],
        );
      }),
    );
  }

  Widget _field(TextEditingController ctrl, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: ctrl,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────
class _LevelHeader extends StatelessWidget {
  const _LevelHeader(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: AppTypography.titleSmall.copyWith(color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
class _DarjaCard extends StatelessWidget {
  const _DarjaCard(this.darja, this.ref, this.color, this.ctx, this.madrasaId);
  final Darja darja;
  final WidgetRef ref;
  final Color color;
  final BuildContext ctx;
  final String? madrasaId;

  @override
  Widget build(BuildContext context) {
    final sections = ref.read(darjaProvider.notifier).sectionsForDarja(darja.id ?? '');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Text(
            '${darja.orderIndex}',
            style: AppTypography.bodyLarge.copyWith(
                color: color, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(darja.nameUrdu,
            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${darja.nameEnglish} • گنجائش: ${darja.capacity}',
          style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.error, size: 20),
            onPressed: () => ref.read(darjaProvider.notifier).deleteDarja(darja.id ?? ''),
          ),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (sections.isEmpty)
                Text('کوئی سیکشن نہیں',
                    style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textSecondary)),
              for (final sec in sections)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.group_outlined, color: color, size: 20),
                  title: Text(sec.nameUrdu, style: AppTypography.bodyMedium),
                  trailing: IconButton(
                    icon: Icon(Icons.remove_circle_outline,
                        color: AppColors.error, size: 18),
                    onPressed: () =>
                        ref.read(darjaProvider.notifier).deleteSection(sec.id ?? ''),
                  ),
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('سیکشن شامل'),
                style: OutlinedButton.styleFrom(foregroundColor: color),
                onPressed: () => _addSection(context, ref, darja),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _addSection(
      BuildContext context, WidgetRef ref, Darja darja) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('نیا سیکشن'),
        content: TextField(
          controller: ctrl,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
              labelText: 'سیکشن کا نام (مثلاً الف)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('منسوخ')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              await ref.read(darjaProvider.notifier).createSection(DarjaSection(
                    darjaId: darja.id ?? '',
                    tenantId: ref.read(currentTenantIdProvider) ?? '',
                    madrasaId: madrasaId,
                    nameUrdu: ctrl.text,
                  ));
            },
            child: const Text('شامل'),
          ),
        ],
      ),
    );
  }
}
