/// ڈیش بورڈ فریم ورک — حصہ
/// Dashboard framework — titled collapsible section.
///
/// A [DashboardSection] groups related menu tiles under one titled,
/// collapsible group (e.g. 'مالیات'). Sections are how dashboards stay
/// scannable: each one renders only when the caller decides it applies
/// (module enabled AND permission held).

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

/// One menu tile inside a [DashboardSection]: icon + Urdu label → screen.
class SectionTile {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const SectionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.primary,
  });
}

/// Collapsible titled group of [SectionTile]s.
class DashboardSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<SectionTile> tiles;
  final bool initiallyExpanded;

  const DashboardSection({
    super.key,
    required this.title,
    this.icon,
    required this.tiles,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
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
      child: Theme(
        // Remove the default divider lines for a calmer look.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.only(left: 8, right: 8, bottom: 12),
          leading: icon == null
              ? null
              : Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 22),
                ),
          title: Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 96,
              ),
              itemCount: tiles.length,
              itemBuilder: (context, index) {
                final tile = tiles[index];
                return InkWell(
                  onTap: tile.onTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(tile.icon, color: tile.color, size: 26),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            tile.label,
                            style: AppTypography.labelMedium,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
