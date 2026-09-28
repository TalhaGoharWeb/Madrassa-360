/// ماڈیول کیٹلاگ
/// Master Admin — platform-wide module catalog view (modules_catalog).
/// Catalog rows are seeded by migration 003; per-tenant enablement is
/// managed on the madrasa detail screen.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import 'widgets/ma_widgets.dart';

class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _modules = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _client
          .from('modules_catalog')
          .select('module, name, name_urdu, description')
          .order('module');
      _modules = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingWidget(message: 'ماڈیولز لوڈ ہو رہے ہیں…');
    }
    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'modules_catalog دستیاب نہیں',
        message: _error,
        actionLabel: 'دوبارہ کوشش کریں',
        onAction: _load,
      );
    }
    if (_modules.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.extension_outlined,
        title: 'کیٹلاگ خالی ہے',
        message: 'Run migration 003_tenant_modules.sql to seed the catalog.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.25,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _modules.length,
        itemBuilder: (context, i) {
          final m = _modules[i];
          final nameUrdu = (m['name_urdu'] as String?) ?? '';
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.extension,
                          color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (m['name'] as String?) ?? (m['module'] as String),
                          style: AppTypography.titleSmall
                              .copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (nameUrdu.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(nameUrdu,
                          style: AppTypography.bodyMedium,
                          textDirection: TextDirection.rtl),
                    ),
                  const Spacer(),
                  Text(
                    (m['description'] as String?) ?? '',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m['module'] as String,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
