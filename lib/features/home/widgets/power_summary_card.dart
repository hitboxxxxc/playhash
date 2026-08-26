import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../core/widgets/next_block_countdown.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../data/repositories/mining_repository.dart';
import 'power_bolt_badge.dart';

/// Card "MEU PODER" da HOME: total oficial, poder PERMANENTE real
/// (power/{uid}) ou "—", multiplicador placeholder (recurso ainda não
/// fornecido pelo backend) e a linha "Próxima recompensa em" com o MESMO
/// countdown ticando da MINERAÇÃO (`blocks/current.nextBlockAt` — schedule
/// 100% do backend; sem schedule => "--:--", nunca horário inventado).
class PowerSummaryCard extends StatelessWidget {
  const PowerSummaryCard({
    super.key,
    this.totalPower,
    this.permanentPower,
    this.block,
    this.loading = false,
  });

  final int? totalPower;

  /// Poder permanente oficial (soma das máquinas owned — backend).
  final int? permanentPower;

  /// Snapshot oficial de bloco — alimenta o countdown compartilhado.
  final BlockSnapshot? block;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: AppColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const PowerBoltBadge(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'MEU PODER',
                      style:
                          AppTheme.neonLabel(fontSize: 13, color: AppColors.cyan),
                    ),
                    const SizedBox(height: 6),
                    if (loading)
                      const SkeletonBox(width: 160, height: 30)
                    else
                      Semantics(
                        label: 'Poder total',
                        value: totalPower == null
                            ? 'indisponível'
                            : PowerFormat.format(totalPower!),
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: totalPower == null
                                    ? '—'
                                    : PowerFormat.format(totalPower!),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: AppColors.cyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (permanentPower != null) ...<Widget>[
                      Semantics(
                        label: 'Poder permanente',
                        value: PowerFormat.format(permanentPower!),
                        child: Text(
                          'Permanente: ${PowerFormat.format(permanentPower!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    const Text(
                      'Multiplicador: —',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: AppColors.textSecondary.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 10),
          NextBlockCountdown(
            block: block,
            label: 'Próxima recompensa em',
            fontSize: 12,
            centered: false,
          ),
        ],
      ),
    );
  }
}
