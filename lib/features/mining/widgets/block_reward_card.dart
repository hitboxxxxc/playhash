import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coin_format.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/repositories/mining_repository.dart';

/// Card "RECOMPENSA DO BLOCO" da MINERAÇÃO (doc 05 §47/§48).
///
/// Exibe a recompensa-base do bloco VINDA DO BACKEND (espelho público
/// `blocks/current`, escrito exclusivamente pelo runner a partir de
/// config/economy) e a participação estimada do jogador
/// (totalPower próprio / networkPower do último bloco finalizado).
///
/// NENHUM valor econômico é decidido no cliente: sem dados oficiais => "—".
/// A participação é SEMPRE rotulada como ESTIMADA (display apenas).
class BlockRewardCard extends StatelessWidget {
  const BlockRewardCard({
    super.key,
    this.block,
    this.estimate,
  });

  final BlockSnapshot? block;
  final RewardEstimate? estimate;

  String get _rewardLabel {
    final BigInt? reward = block?.totalBlockRewardMinimalUnits;
    if (reward == null || reward <= BigInt.zero) return '—';
    return CoinFormat.formatWithTicker(reward);
  }

  String get _estimatedShareLabel {
    final RewardEstimate? est = estimate;
    if (est == null) return '—';
    return CoinFormat.formatWithTicker(est.estimatedRewardMinimalUnits);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData = _rewardLabel != '—';

    return NeonPanel(
      accent: AppColors.gold,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Text(
              'RECOMPENSA DO BLOCO',
              style: AppTheme.neonLabel(fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Recompensa do bloco',
            value: _rewardLabel,
            child: Text(
              _rewardLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: hasData ? 28 : 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: hasData ? AppColors.gold : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SvgPicture.string(
                NeonIcons.bolt,
                width: 16,
                colorFilter: const ColorFilter.mode(
                  AppColors.green,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'SUA PARTICIPAÇÃO ESTIMADA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.textSecondary),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ESTIMADA',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Sua participação estimada',
                value: _estimatedShareLabel,
                child: Text(
                  _estimatedShareLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: estimate == null
                        ? AppColors.textSecondary
                        : AppColors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
