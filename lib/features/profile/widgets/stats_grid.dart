import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/chamfered_border.dart';

/// Grade de estatísticas do perfil (6 cards).
///
/// Valores vêm SEMPRE do backend (`users/{uid}.stats` escrito pelo runner —
/// plays/wins/bestScore; poder total de `power/{uid}`). Parâmetro ausente =>
/// placeholder honesto ("0" ou "—") — NUNCA número inventado.
class StatsGrid extends StatelessWidget {
  const StatsGrid({
    super.key,
    this.powerTotal,
    this.plays,
    this.wins,
    this.achievements,
    this.machines,
  });

  /// Poder total oficial (unidades H/s inteiras) de `power/{uid}`.
  final int? powerTotal;

  /// Partidas consolidadas pelo runner (`users/{uid}.stats.plays`).
  final int? plays;

  /// Vitórias consolidadas pelo runner (`users/{uid}.stats.wins`).
  final int? wins;

  /// Conquistas com progresso (`userAchievements/{uid}/items`).
  final int? achievements;

  /// Máquinas ativas do jogador.
  final int? machines;

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> stats = <(String, String)>[
      ('PODER TOTAL', powerTotal?.toString() ?? '0'),
      ('PARTIDAS', plays?.toString() ?? '0'),
      ('VITÓRIAS', wins?.toString() ?? '0'),
      ('CONQUISTAS', achievements?.toString() ?? '0'),
      ('MÁQUINAS', machines?.toString() ?? '0'),
      ('LIGA', '—'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.25,
      children: <Widget>[
        for (final (String, String) stat in stats)
          _StatCard(label: stat.$1, value: stat.$2),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 8,
          side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              value,
              style: AppTheme.neonLabel(
                fontSize: 20,
                color: AppColors.cyan,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
