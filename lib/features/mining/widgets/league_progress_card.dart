import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../core/widgets/skeleton_box.dart';

/// Card "PRÓXIMA LIGA" — escudos SVG próprios + barra de progresso.
/// Sem dados oficiais de liga => 0% e "—" (nada inventado).
class LeagueProgressCard extends StatelessWidget {
  const LeagueProgressCard({
    super.key,
    this.currentLeagueName,
    this.nextLeagueName,
    this.currentPower,
    this.nextThreshold,
    this.loading = false,
  });

  final String? currentLeagueName;
  final String? nextLeagueName;
  final int? currentPower;
  final int? nextThreshold;
  final bool loading;

  double get _progress {
    final int? power = currentPower;
    final int? threshold = nextThreshold;
    if (power == null || threshold == null || threshold <= 0) return 0;
    return (power / threshold).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: AppColors.cyan,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Text(
            'PRÓXIMA LIGA',
            style: AppTheme.neonLabel(fontSize: 14),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _Shield(color: AppColors.cyan, label: currentLeagueName),
              const SizedBox(width: 14),
              Expanded(
                child: loading
                    ? const SkeletonBox(height: 12)
                    : Semantics(
                        label: 'Progresso para a próxima liga',
                        value: '${(_progress * 100).toStringAsFixed(0)}%',
                        child: Stack(
                          children: <Widget>[
                            Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                border: Border.all(
                                  color:
                                      AppColors.cyan.withValues(alpha: 0.4),
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: _progress,
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: AppColors.cyan,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              _Shield(color: AppColors.gold, label: nextLeagueName),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            loading
                ? '—'
                : (currentPower == null || nextThreshold == null)
                    ? '— / —'
                    : '${PowerFormat.format(currentPower!)} / '
                        '${PowerFormat.format(nextThreshold!)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Escudo SVG próprio (ícone [NeonIcons.shield]) com romano decorativo.
class _Shield extends StatelessWidget {
  const _Shield({required this.color, this.label});

  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label == null ? 'Liga atual desconhecida' : 'Liga $label',
      child: Column(
        children: <Widget>[
          SvgPicture.string(
            NeonIcons.shield,
            width: 34,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          const SizedBox(height: 4),
          Text(
            label == null ? '—' : label!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
