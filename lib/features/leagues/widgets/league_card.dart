import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/models/league_model.dart';
import 'league_shield.dart';

/// Card da liga ATUAL: escudo grande, nome + numeração do tier, seu poder
/// (oficial de power/{uid}) e próxima liga com barra de progresso.
/// Sem liga ⇒ estado vazio ("Jogue para entrar em uma liga").
class LeagueCard extends StatelessWidget {
  const LeagueCard({
    super.key,
    required this.league,
    required this.totalPower,
    this.nextLeague,
  });

  final LeagueModel league;

  /// Poder total OFICIAL (units base H/s) — espelho de power/{uid}.
  final int totalPower;
  final LeagueModel? nextLeague;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(league.colorValue);
    final String colorHex =
        color.toARGB32().toRadixString(16).substring(2, 8);
    final double progress = nextLeague == null || nextLeague!.minPower <= 0
        ? 1.0
        : (totalPower / nextLeague!.minPower).clamp(0.0, 1.0);

    return NeonPanel(
      accent: color,
      child: Row(
        children: <Widget>[
          LeagueShield.icon(
            colorHex: '#$colorHex',
            tier: league.tier,
            size: 84,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Estilo "OURO I": nome da liga + numeração da divisão
                // (numeração por promotedAt fica para divisões futuras).
                Text(
                  '${league.name} I',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Icon(Icons.bolt, color: AppColors.cyan, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Seu poder:',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  PowerFormat.format(totalPower),
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (nextLeague != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.arrow_upward,
                          color: AppColors.textSecondary, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Próxima liga: ${nextLeague!.name}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${PowerFormat.format(nextLeague!.minPower)} necessários',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor:
                          AppColors.textSecondary.withValues(alpha: 0.2),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 10),
                  const Text(
                    'Liga máxima alcançada!',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

}

/// Estado vazio do card (usuário ainda sem liga — poder abaixo do menor
/// limiar). Nada é inventado: apenas orientação para jogar.
class LeagueCardEmpty extends StatelessWidget {
  const LeagueCardEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      child: Column(
        children: <Widget>[
          LeagueShield.icon(colorHex: '#9AA3C0', tier: 1, size: 64),
          const SizedBox(height: 10),
          const Text(
            'SEM LIGA AINDA',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aumente seu poder para entrar em uma liga.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
