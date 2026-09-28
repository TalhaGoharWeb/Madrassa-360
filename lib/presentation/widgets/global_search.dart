/// گلوبل سرچ — Global search across طلبہ، اساتذہ، درجات، فیس.
///
/// Opened from the dashboard (app-bar search icon or the "تلاش کریں..."
/// entry field). Queries NO new backend endpoints: it filters the
/// already-loaded provider data client-side —
/// [allStudentsProvider], [allStaffProvider], [safeDarjaListProvider],
/// [allFeesProvider].
///
/// LIMITATION (documented, not hidden): results only cover data those
/// providers have already loaded for the current tenant. If a list is
/// paginated server-side in the future, results are limited to the cached
/// page. A dedicated server-side search endpoint (e.g. Supabase full-text
/// search) would lift this; none exists in the repo today.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../data/models/fee.dart';
import '../../providers/dashboard_data_provider.dart';
import '../../providers/fee_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/student_provider.dart';
import '../screens/admin/darja_screen.dart';
import '../screens/admin/fee_management_screen.dart';
import '../screens/admin/staff_list_screen.dart';
import '../screens/admin/student_list_screen.dart';

/// Max rows rendered per result group; the header shows the true count.
const _maxPerGroup = 8;

/// Full-page search UI (page, not a bottom sheet: full keyboard + RTL
/// layout, room for grouped results).
class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          textInputAction: TextInputAction.search,
          style: AppTypography.bodyLarge.copyWith(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'تلاش کریں...',
            hintStyle: AppTypography.labelNastaliq.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.normal,
            ),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      body:
          _query.isEmpty ? const _SearchHint() : _SearchResults(query: _query),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_outlined,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'نام، رول نمبر، درجہ یا مہینہ لکھ کر تلاش کریں',
              textAlign: TextAlign.center,
              style: AppTypography.labelNastaliq.copyWith(
                fontWeight: FontWeight.normal,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Groups the four provider lists by [_matches] and renders them.
class _SearchResults extends ConsumerWidget {
  final String query;

  const _SearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(allStudentsProvider);
    final staff = ref.watch(allStaffProvider);
    final darjas = ref.watch(safeDarjaListProvider);
    final fees = ref.watch(allFeesProvider);

    final anyLoading = students.isLoading ||
        staff.isLoading ||
        darjas.isLoading ||
        fees.isLoading;
    final hasAnyError =
        students.hasError || staff.hasError || darjas.hasError || fees.hasError;
    final hasAnyData = students.valueOrNull != null ||
        staff.valueOrNull != null ||
        darjas.valueOrNull != null ||
        fees.valueOrNull != null;

    if (anyLoading && !hasAnyData) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (hasAnyError && !hasAnyData) {
      return Center(
        child: Text(
          'تلاش کے لیے ڈیٹا لوڈ نہیں ہو سکا',
          style: AppTypography.bodyMedium,
        ),
      );
    }

    final matchedStudents = (students.valueOrNull ?? [])
        .where(
          (s) => _matches(query, [s.name, s.rollNo, s.fatherName, s.darjaName]),
        )
        .toList();
    final matchedStaff = (staff.valueOrNull ?? [])
        .where((s) => _matches(
              query,
              [s.name, s.fatherName, s.designation, s.department ?? ''],
            ))
        .toList();
    final matchedDarjas = (darjas.valueOrNull ?? [])
        .where((d) => _matches(query, [d.nameUrdu, d.nameEnglish]))
        .toList();
    final matchedFees = (fees.valueOrNull ?? [])
        .where((f) => _matches(query, [f.studentName, f.month, f.studentClass]))
        .toList();

    final total = matchedStudents.length +
        matchedStaff.length +
        matchedDarjas.length +
        matchedFees.length;

    if (total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '«$query» کے لیے کوئی نتیجہ نہیں ملا',
            textAlign: TextAlign.center,
            style: AppTypography.labelNastaliq.copyWith(
              fontWeight: FontWeight.normal,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (matchedStudents.isNotEmpty)
          _ResultGroup(
            icon: Icons.people_outline,
            title: 'طلبہ',
            count: matchedStudents.length,
            children: [
              for (final s in matchedStudents.take(_maxPerGroup))
                _ResultTile(
                  leading: s.name.isNotEmpty ? s.name.characters.first : '?',
                  title: s.name,
                  subtitle: s.darjaName.isNotEmpty
                      ? '${s.darjaName} • رول نمبر ${s.rollNo}'
                      : 'رول نمبر ${s.rollNo}',
                  onTap: () => go(const StudentListScreen()),
                ),
            ],
          ),
        if (matchedStaff.isNotEmpty)
          _ResultGroup(
            icon: Icons.person_outline,
            title: 'اساتذہ',
            count: matchedStaff.length,
            children: [
              for (final s in matchedStaff.take(_maxPerGroup))
                _ResultTile(
                  leading: s.name.isNotEmpty ? s.name.characters.first : '?',
                  title: s.name,
                  subtitle: s.designation,
                  onTap: () => go(const StaffListScreen()),
                ),
            ],
          ),
        if (matchedDarjas.isNotEmpty)
          _ResultGroup(
            icon: Icons.school_outlined,
            title: 'درجات',
            count: matchedDarjas.length,
            children: [
              for (final d in matchedDarjas.take(_maxPerGroup))
                _ResultTile(
                  leading:
                      d.nameUrdu.isNotEmpty ? d.nameUrdu.characters.first : '?',
                  title: d.nameUrdu,
                  subtitle:
                      d.nameEnglish.isNotEmpty && d.nameEnglish != d.nameUrdu
                          ? d.nameEnglish
                          : null,
                  onTap: () => go(const DarjaScreen()),
                ),
            ],
          ),
        if (matchedFees.isNotEmpty)
          _ResultGroup(
            icon: Icons.payments_outlined,
            title: 'فیس',
            count: matchedFees.length,
            children: [
              for (final f in matchedFees.take(_maxPerGroup))
                _ResultTile(
                  leading: '₨',
                  title: f.studentName,
                  subtitle:
                      '${f.month} • ${f.status.urduLabel} • بقایا ${_formatRs(f.amountDue - f.amountPaid)}',
                  onTap: () => go(const FeeManagementScreen()),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'تلاش پہلے سے لوڈ شدہ ڈیٹا میں کی گئی',
            style: AppTypography.labelSmall,
          ),
        ),
      ],
    );
  }
}

/// Case-insensitive substring match across the given fields. Urdu has no
/// case, so lowercasing is a no-op for it and correct for Latin input.
bool _matches(String query, List<String> fields) {
  final q = query.toLowerCase();
  if (q.isEmpty) return false;
  return fields.any((f) => f.toLowerCase().contains(q));
}

class _ResultGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final List<Widget> children;

  const _ResultGroup({
    required this.icon,
    required this.title,
    required this.count,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTypography.labelNastaliq.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: AppTypography.customBody(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (count > _maxPerGroup)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'پہلے $_maxPerGroup دکھائے گئے',
                      style: AppTypography.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _ResultTile({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        child: Text(
          leading,
          style: AppTypography.customBody(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ),
      title: Text(
        title,
        style: AppTypography.labelNastaliq.copyWith(fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: AppTypography.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(
        Icons.arrow_back_ios_new,
        size: 16,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}

/// Rs formatting with Pakistani digit grouping (1,25,000).
String _formatRs(double amount) {
  final s = amount.round().toString();
  if (s.length <= 3) return 'Rs $s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return 'Rs ${parts.join(',')},$last3';
}
