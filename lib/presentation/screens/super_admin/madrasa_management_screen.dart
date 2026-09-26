import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/models.dart';
import '../../../providers/madrasa_provider.dart';

/// @deprecated Phase-3 replacement: legacy madrasa management is superseded
/// by MadrasaListScreen / MadrasaDetailScreen / CreateMadrasaWizard at
/// lib/presentation/screens/master_admin/ (route '/master', gated by
/// MasterAdminGuard). Kept only because other code may still reference it —
/// do not build new features here.
@Deprecated(
    'Use the Master Admin screens under lib/presentation/screens/master_admin/ instead')
class MadrasaManagementScreen extends StatefulWidget {
  const MadrasaManagementScreen({super.key});
  @override
  State<MadrasaManagementScreen> createState() =>
      _MadrasaManagementScreenState();
}

class _MadrasaManagementScreenState extends State<MadrasaManagementScreen> {
  WidgetRef? _ref;
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ref?.read(madrasaProvider.notifier).loadAll());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      _ref = ref;
      final state = ref.watch(madrasaProvider);
      final filtered = state.madrasas
          .where((m) =>
              _search.isEmpty ||
              m.nameUrdu.contains(_search) ||
              m.nameEnglish.toLowerCase().contains(_search.toLowerCase()) ||
              m.cityUrdu.contains(_search))
          .toList();

      return Scaffold(
        appBar: AppBar(
          title: Text('مدارس کا انتظام', style: AppTypography.appBarTitle),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        backgroundColor: AppColors.background,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('نیا مدرسہ'),
          onPressed: () => _showMadrasaDialog(context, ref),
        ),
        body: Column(children: [
          // Search bar
          Container(
            color: const Color(0xFF1A237E),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              textDirection: TextDirection.rtl,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'تلاش کریں...',
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: Colors.white54,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),

          if (state.isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator())),

          if (!state.isLoading)
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.account_balance_outlined,
                          size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text('کوئی مدرسہ نہیں',
                          style: AppTypography.bodyLarge
                              .copyWith(color: AppColors.textSecondary)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _madrasaCard(filtered[i], ref),
                    ),
            ),
        ]),
      );
    });
  }

  Widget _madrasaCard(Madrasa m, WidgetRef ref) {
    Color planColor = AppColors.info;
    if (m.subscriptionPlan == 'premium') planColor = Colors.amber[700]!;
    if (m.subscriptionPlan == 'standard') planColor = AppColors.primary;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF1A237E),
              child: Text(
                m.nameUrdu.isNotEmpty ? m.nameUrdu[0] : 'م',
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nameUrdu,
                        style: AppTypography.bodyLarge
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (m.nameEnglish.isNotEmpty)
                      Text(m.nameEnglish,
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textSecondary)),
                  ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: planColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(m.planLabel,
                  style: AppTypography.labelSmall.copyWith(color: planColor)),
            ),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.location_on_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(m.cityUrdu,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(width: 16),
            Icon(Icons.tag, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(m.branchCode ?? '',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            // Active toggle
            Switch(
              value: m.isActive,
              activeThumbColor: AppColors.success,
              onChanged: (_) =>
                  ref.read(madrasaProvider.notifier).toggleStatus(m),
            ),
            Text(m.isActive ? 'فعال' : 'غیرفعال',
                style: AppTypography.labelMedium.copyWith(
                    color: m.isActive ? AppColors.success : AppColors.error)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              color: AppColors.primary,
              onPressed: () => _showMadrasaDialog(context, ref, madrasa: m),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: AppColors.error,
              onPressed: () => _confirmDelete(context, ref, m),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _showMadrasaDialog(BuildContext context, WidgetRef ref,
      {Madrasa? madrasa}) async {
    final isEdit = madrasa != null;
    final nameUCtrl = TextEditingController(text: madrasa?.nameUrdu ?? '');
    final nameECtrl = TextEditingController(text: madrasa?.nameEnglish ?? '');
    final cityUCtrl = TextEditingController(text: madrasa?.cityUrdu ?? '');
    final cityECtrl = TextEditingController(text: madrasa?.cityEnglish ?? '');
    final phoneCtrl = TextEditingController(text: madrasa?.phone ?? '');
    final emailCtrl = TextEditingController(text: madrasa?.email ?? '');
    final branchCtrl = TextEditingController(text: madrasa?.branchCode ?? '');
    String plan = madrasa?.subscriptionPlan ?? 'basic';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isEdit ? 'مدرسہ ترمیم' : 'نیا مدرسہ',
              style: AppTypography.titleMedium),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(nameUCtrl, 'نام (اردو)'),
              _field(nameECtrl, 'نام (انگریزی)'),
              _field(cityUCtrl, 'شہر (اردو)'),
              _field(cityECtrl, 'شہر (انگریزی)'),
              _field(phoneCtrl, 'فون نمبر'),
              _field(emailCtrl, 'ای میل'),
              _field(branchCtrl, 'برانچ کوڈ'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: plan,
                decoration: const InputDecoration(
                    labelText: 'سبسکرپشن پلان', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'basic', child: Text('بیسک')),
                  DropdownMenuItem(value: 'standard', child: Text('اسٹینڈرڈ')),
                  DropdownMenuItem(value: 'premium', child: Text('پریمیم')),
                ],
                onChanged: (v) => setS(() => plan = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('منسوخ')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                if (isEdit) {
                  await ref.read(madrasaProvider.notifier).update(
                        madrasa.copyWith(
                          nameUrdu: nameUCtrl.text,
                          nameEnglish: nameECtrl.text,
                          cityUrdu: cityUCtrl.text,
                          cityEnglish: cityECtrl.text,
                          phone: phoneCtrl.text,
                          email: emailCtrl.text,
                          branchCode: branchCtrl.text,
                          subscriptionPlan: plan,
                        ),
                      );
                } else {
                  await ref.read(madrasaProvider.notifier).create(
                        Madrasa(
                          nameUrdu: nameUCtrl.text,
                          nameEnglish: nameECtrl.text,
                          cityUrdu: cityUCtrl.text,
                          cityEnglish: cityECtrl.text,
                          phone: phoneCtrl.text,
                          email: emailCtrl.text,
                          branchCode: branchCtrl.text,
                          subscriptionPlan: plan,
                        ),
                      );
                }
              },
              child: Text(isEdit ? 'محفوظ' : 'شامل'),
            ),
          ],
        ),
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

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Madrasa m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کریں؟'),
        content: Text('کیا آپ "${m.nameUrdu}" کو حذف کرنا چاہتے ہیں؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('نہیں')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ہاں، حذف')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(madrasaProvider.notifier).delete(m.id ?? '');
    }
  }
}
