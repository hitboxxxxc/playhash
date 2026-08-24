import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/skeleton_box.dart';

/// Linha de 4 cards rápidos: poder das máquinas, poder dos jogos,
/// próxima recompensa e ranking global. Sem dado oficial => "—".
class QuickStatsRow extends StatelessWidget {
  const QuickStatsRow({
    super.key,
    this.machinesPower,
    this.gamesPower,
    this.nextRewardLabel,
    this.ranking,
    this.loading = false,
  });

  final int? machinesPower;
  final int? gamesPower;

  /// Rótulo da próxima recompensa — SOMENTE com schedule do backend.
  final String? nextRewardLabel;

  /// Posição no ranking — somente com dado oficial do servidor.
  final int? ranking;

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 380;
        final List<Widget> cards = <Widget>[
          _QuickCard(
            icon: NeonIcons.chip,
            iconColor: AppColors.cyan,
            label: 'PODER DAS MÁQUINAS',
            value: machinesPower == null || machinesPower! <= 0
                ? (machinesPower == null ? '—' : '0 H/s')
                : PowerFormat.format(machinesPower!),
            loading: loading,
          ),
          _QuickCard(
            icon: NeonIcons.gamepad,
            iconColor: AppColors.green,
            label: 'PODER DOS JOGOS',
            value: gamesPower == null || gamesPower! <= 0
                ? (gamesPower == null ? '—' : '0 H/s')
                : PowerFormat.format(gamesPower!),
            loading: loading,
          ),
          _QuickCard(
            icon: NeonIcons.clock,
            iconColor: AppColors.purple,
            label: 'PRÓXIMA RECOMPENSA',
            value: nextRewardLabel ?? '—',
            loading: loading,
          ),
          _QuickCard(
            icon: NeonIcons.trophy,
            iconColor: AppColors.gold,
            label: 'RANKING GLOBAL',
            value: ranking == null ? '—' : '#$ranking',
            loading: loading,
          ),
        ];

        if (narrow) {
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[Expanded(child: cards[2]), const SizedBox(width: 10), Expanded(child: cards[3])],
              ),
            ],
          );
        }

        return Row(
          children: <Widget>[
            for (int i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.loading,
  });

  final String icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: iconColor.withValues(alpha: 0.35)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SvgPicture.string(
            icon,
            width: 22,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          ),
          const SizedBox(height: 8),
          if (loading)
            const SkeletonBox(width: 44, height: 12)
          else
            Semantics(
              label: label,
              value: value,
              child: Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.neonLabel(
                  fontSize: 12,
                  color: value == '—' ? AppColors.textSecondary : iconColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
