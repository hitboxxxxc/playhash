import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/models/league_model.dart';

/// Recompensa diária da liga: valor oficial do catálogo + status. O envio é
/// AUTOMÁTICO pelo servidor (league_sweep, 1×/dia — idempotente por data);
/// aqui exibimos o horário/dia do último grant (userLeagues.lastDailyGrant).
class LeagueDailyCard extends StatelessWidget {
  const LeagueDailyCard({
    super.key,
    required this.league,
    this.lastDailyGrant,
  });

  final LeagueModel league;
  final String? lastDailyGrant;

  @override
  Widget build(BuildContext context) {
    final bool grantedToday = lastDailyGrant == _todayKey();
    return NeonPanel(
      accent: AppColors.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Center(
            child: Text(
              'RECOMPENSA DA LIGA',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(Icons.card_giftcard, color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recompensa diária da liga ${league.name}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Icon(Icons.monetization_on, color: AppColors.gold, size: 18),
              const SizedBox(width: 6),
              Text(
                '${league.dailyRewardCoins} COIN / dia',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(
                grantedToday ? Icons.check_circle : Icons.schedule,
                color: grantedToday ? AppColors.green : AppColors.textSecondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  grantedToday
                      ? 'Enviada hoje automaticamente pelo servidor.'
                      : 'Enviada automaticamente pelo servidor todos os dias.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (lastDailyGrant != null && lastDailyGrant!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Último envio: $lastDailyGrant (UTC)',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _todayKey() {
    final DateTime now = DateTime.now().toUtc();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
