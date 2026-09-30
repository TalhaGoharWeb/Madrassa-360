import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:madrasa_360/core/design/m360.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../data/models/models.dart';
import '../../../providers/madrasa_provider.dart';

/// @deprecated Phase-3 replacement: legacy madrasa management is superseded
/// by MadrasaListScreen / MadrasaDetailScreen / CreateMadrasaWizard at
/// lib/presentation/screens/master_admin/ (route '/master', gated by
/// MasterAdminGuard). Kept only because other code may still reference it —
/// do not build new features here.
///
/// Phase 10: visuals moved onto the m360 component language; the provider
/// wiring (search, toggle, create/update/delete) is unchanged.
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

      // Shell destination: hosted by SuperAdminMainScreen's Scaffold and
      // pushed from the dashboard with a deep-page root — no Scaffold of
      // its own. The create action lives in the PageHeader; the FAB is gone.
      return PageContainer(
        header: PageHeader(
          title: 'مدارس کا انتظام',
          actions: [
            M360PrimaryButton(
              label: 'نیا مدرسہ',
              icon: Icons.add,
              onPressed: () => _showMadrasaDialog(context, ref),
            ),
          ],
        ),
        scrollable: false,
        child: Column(children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: M360SearchField(
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          if (state.isLoading) const Expanded(child: M360LoadingState()),

          if (!state.isLoading)
            Expanded(
              child: filtered.isEmpty
                  ? const M360EmptyState(
                      icon: Icons.account_balance_outlined,
                      title: 'کوئی مدرسہ نہیں',
                      description: '',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8),
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
    if (m.subscriptionPlan == 'premium') planColor = AppColors.warning;
    if (m.subscriptionPlan == 'standard') planColor = AppColors.primary;

    return M360Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary,
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.nameUrdu,
                  style: AppTypography.bodyLarge
                      .copyWith(fontWeight: FontWeight.w600)),
              if (m.nameEnglish.isNotEmpty)
                M360LatinText(
                  m.nameEnglish,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textSecondary),
                ),
            ]),
          ),
          M360Badge.custom(label: m.planLabel, color: planColor),
        ]),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(m.cityUrdu,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tag, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: M360LatinText(
                    m.branchCode ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
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
              style: AppTypography.labelNastaliq.copyWith(
                  color: m.isActive ? AppColors.success : AppColors.error)),
          const Spacer(),
          M360IconButton(
            icon: Icons.edit_outlined,
            tooltip: 'ترمیم کریں',
            onPressed: () => _showMadrasaDialog(context, ref, madrasa: m),
          ),
          M360IconButton(
            icon: Icons.delete_outline,
            tooltip: 'حذف کریں',
            color: AppColors.error,
            onPressed: () => _confirmDelete(context, ref, m),
          ),
        ]),
      ]),
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

    await showM360Dialog(
      context,
      title: isEdit ? 'مدرسہ ترمیم' : 'نیا مدرسہ',
      content: StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(nameUCtrl, 'نام (اردو)'),
            _field(nameECtrl, 'نام (انگریزی)'),
            _field(cityUCtrl, 'شہر (اردو)'),
            _field(cityECtrl, 'شہر (انگریزی)'),
            _field(phoneCtrl, 'فون نمبر'),
            _field(emailCtrl, 'ای میل'),
            _field(branchCtrl, 'برانچ کوڈ'),
            const SizedBox(height: 8),
            M360Dropdown<String>(
              label: 'سبسکرپشن پلان',
              value: plan,
              items: const [
                M360DropdownItem(value: 'basic', label: 'بیسک'),
                M360DropdownItem(value: 'standard', label: 'اسٹینڈرڈ'),
                M360DropdownItem(value: 'premium', label: 'پریمیم'),
              ],
              onChanged: (v) => setS(() => plan = v!),
            ),
          ],
        ),
      ),
      actions: [
        M360TertiaryButton(
          label: 'منسوخ',
          onPressed: () => Navigator.pop(context),
        ),
        M360PrimaryButton(
          label: isEdit ? 'محفوظ' : 'شامل',
          onPressed: () async {
            Navigator.pop(context);
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
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: M360TextField(controller: ctrl, label: label),
      );

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Madrasa m) async {
    final ok = await showM360ConfirmDialog(
      context,
      title: 'حذف کریں؟',
      message: 'کیا آپ "${m.nameUrdu}" کو حذف کرنا چاہتے ہیں؟',
      confirmLabel: 'ہاں، حذف',
      cancelLabel: 'نہیں',
      danger: true,
    );
    if (ok) {
      ref.read(madrasaProvider.notifier).delete(m.id ?? '');
    }
  }
}
