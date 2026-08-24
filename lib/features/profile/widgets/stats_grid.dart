import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/chamfered_border.dart';

/// Grade de estatísticas do perfil (6 cards).
///
/// IMPORTANTE: economia e partidas ainda NÃO foram implementadas. Os valores
/// exibidos são placeholders honestos ("0" ou "—") — NUNCA números inventados.
/// Quando o backend passar a fornecer stats reais, este widget receberá os
/// valores por parâmetro.
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key});

  /// (rótulo, valor) — valores são placeholders até o backend existir.
  static const List<(String, String)> _stats = <(String, String)>[
    ('PODER TOTAL', '0'),
    ('PARTIDAS', '0'),
    ('VITÓRIAS', '0'),
    ('CONQUISTAS', '0'),
    ('MÁQUINAS', '0'),
    ('LIGA', '—'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.25,
      children: <Widget>[
        for (final (String, String) stat in _stats)
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
