import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Abas de categoria da LOJA. Somente MÁQUINAS está ativa; as demais exibem
/// chip "EM BREVE" e conteúdo vazio informativo (nunca catálogo inventado).
class CategoryTabs extends StatelessWidget {
  const CategoryTabs({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// Categorias com flag "em breve" (índice alinhado a [selectedIndex]).
  final List<({String label, bool comingSoon})> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final bool selected = index == selectedIndex;
          final bool comingSoon = categories[index].comingSoon;
          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  categories[index].label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.background
                        : AppColors.textSecondary,
                  ),
                ),
                if (comingSoon) ...<Widget>[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.purple.withValues(alpha: 0.7),
                      ),
                    ),
                    child: const Text(
                      'EM BREVE',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purple,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            selected: selected,
            selectedColor: AppColors.cyan,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: selected
                  ? AppColors.cyan
                  : AppColors.purple.withValues(alpha: 0.5),
            ),
            showCheckmark: false,
            onSelected: (_) => onSelected(index),
          );
        },
      ),
    );
  }
}
