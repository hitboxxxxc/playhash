import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/power_format.dart';
import '../../../data/models/league_model.dart';
import 'league_shield.dart';

/// Fileira das 5 ligas (escudos próprios por tier): nome + "Poder necessário".
/// A liga ATUAL do usuário é destacada em ciano (borda + brilho).
class LeagueRow extends StatelessWidget {
  const LeagueRow({
    super.key,
    required this.leagues,
    this.currentLeagueId,
  });

  final List<LeagueModel> leagues;
  final String? currentLeagueId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < leagues.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _LeagueCell(league: leagues[i], isCurrent: leagues[i].id == currentLeagueId)),
        ],
      ],
    );
  }
}

class _LeagueCell extends StatelessWidget {
  const _LeagueCell({required this.league, required this.isCurrent});

  final LeagueModel league;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(league.colorValue);
    final String colorHex =
        color.toARGB32().toRadixString(16).substring(2, 8);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isCurrent ? AppColors.cyan : color.withValues(alpha: 0.35),
            width: isCurrent ? 2 : 1,
          ),
        ),
        shadows: isCurrent
            ? <BoxShadow>[BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: 16)]
            : const <BoxShadow>[],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            LeagueShield.icon(colorHex: '#$colorHex', tier: league.tier, size: 40),
            const SizedBox(height: 6),
            Text(
              league.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? AppColors.cyan : AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Poder necessário:',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 9),
            ),
            Text(
              PowerFormat.format(league.minPower),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isCurrent ? AppColors.cyan : AppColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
