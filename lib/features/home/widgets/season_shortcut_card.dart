import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/season_model.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/neon_panel.dart';

/// Atalho "TEMPORADA 01" na HOME → /season. Exibe o nível OFICIAL atual
/// (seasonProgress/{uid} — derivado pelo backend; sem dado ⇒ nível 1).
class SeasonShortcutCard extends ConsumerWidget {
  const SeasonShortcutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SeasonProgressModel? progress = ref.watch(seasonProgressStreamProvider).value;
    final int level = progress?.level ?? 1;

    return Semantics(
      button: true,
      label: 'Abrir temporada',
      child: GestureDetector(
        onTap: () => context.push(RoutePaths.season),
        child: NeonPanel(
          padding: const EdgeInsets.all(16),
          accent: AppColors.purple,
          child: Row(
            children: <Widget>[
              SvgPicture.string(
                NeonIcons.shield,
                width: 40,
                height: 40,
                colorFilter: const ColorFilter.mode(AppColors.purple, BlendMode.srcIn),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'TEMPORADA 01',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Suba de nível e resgate a trilha gratuita',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: ShapeDecoration(
                  color: AppColors.purple.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.purple),
                  ),
                ),
                child: Text(
                  'NV $level',
                  style: const TextStyle(
                    color: AppColors.purple,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
