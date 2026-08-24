import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_panel.dart';

/// Atalho "Missões de hoje" na HOME → /app/missions. Exibe badge dourado
/// com a quantidade de recompensas PRONTAS para resgate (missões +
/// conquistas), derivada dos dados oficiais do runner.
class MissionsShortcutCard extends ConsumerWidget {
  const MissionsShortcutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int claimables = ref.watch(claimablesCountProvider);

    return Semantics(
      button: true,
      label: 'Abrir missões',
      child: GestureDetector(
        onTap: () => context.push(RoutePaths.missions),
        child: NeonPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              SvgPicture.string(AppAssets.gamepadIconSvg, width: 40, height: 40),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'MISSÕES DE HOJE',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Complete tarefas e receba recompensas',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (claimables > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: ShapeDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.gold),
                    ),
                  ),
                  child: Text(
                    '$claimables',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
