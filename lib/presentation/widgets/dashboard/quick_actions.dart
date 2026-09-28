/// ڈیش بورڈ فریم ورک — فوری عمل
/// Dashboard framework — quick-action grid.
///
/// Large touch targets (min 72dp), every icon paired with its Urdu label.

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';

/// One quick-action tile: icon + Urdu label + tap handler.
class QuickActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const QuickActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.primary,
  });
}

/// Grid of large quick-action tiles (3 columns).
class QuickActionGrid extends StatelessWidget {
  final List<QuickActionItem> items;

  const QuickActionGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Tall enough for two Nastaliq label lines (16sp, height 2.0).
        mainAxisExtent: 124,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.icon, color: item.color, size: 26),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    item.label,
                    style: AppTypography.labelNastaliq,
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
    );
  }
}
