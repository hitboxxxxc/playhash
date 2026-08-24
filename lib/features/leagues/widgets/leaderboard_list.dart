import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../data/models/league_model.dart';

/// Ranking da liga (top 100 por poder — dados oficiais do backend com
/// maskedName). Troféus para o top 3; linha "VOCÊ" destacada com a posição
/// real; fora do top ⇒ bloco fixo com sua posição. Estados loading/erro/
/// offline/vazio cobertos.
class LeaderboardList extends StatelessWidget {
  const LeaderboardList({
    super.key,
    required this.entries,
    required this.uid,
    this.myPower,
    this.isLoading = false,
    this.hasError = false,
  });

  final List<LeaderboardEntry> entries;
  final String uid;

  /// Poder total OFICIAL do usuário (power/{uid}) — usado no bloco fixo
  /// quando a entrada dele está fora do top 100 (posição não fabricada).
  final int? myPower;
  final bool isLoading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(
            child: Text(
              'RANKING DA LIGA',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: SkeletonBox(height: 120)),
            )
          else if (hasError)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Ranking indisponível agora (offline?).',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            )
          else if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Ranking vazio — seja o primeiro da liga!',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            )
          else ...<Widget>[
            _headerRow(),
            const SizedBox(height: 6),
            for (int i = 0; i < entries.length; i++)
              _EntryRow(position: i + 1, entry: entries[i], isMe: entries[i].uid == uid),
            if (!entries.any((LeaderboardEntry e) => e.uid == uid))
              _myPositionBlock(),
          ],
        ],
      ),
    );
  }

  Widget _headerRow() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Text('POSIÇÃO',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Text('JOGADOR',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
            Text('PODER',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  /// Fora do top 100: bloco fixo com o poder oficial do usuário. A posição
  /// NÃO é fabricada (o backend só publica o top 100) — exibe ">100".
  Widget _myPositionBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _EntryRow(
        position: -1,
        entry: LeaderboardEntry(uid: uid, maskedName: 'VOCÊ', totalPower: myPower ?? 0),
        isMe: true,
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.position,
    required this.entry,
    required this.isMe,
  });

  final int position;
  final LeaderboardEntry entry;
  final bool isMe;

  static const List<Color> _trophyColors = <Color>[
    AppColors.gold,
    Color(0xFFC0C8D4),
    Color(0xFFB0713B),
  ];

  @override
  Widget build(BuildContext context) {
    final Widget leading = position > 0 && position <= 3
        ? Icon(Icons.emoji_events, color: _trophyColors[position - 1], size: 20)
        : SizedBox(
            width: 20,
            child: Text(
              position > 0 ? '$position' : '>100',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isMe ? AppColors.cyan : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? AppColors.cyan.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMe ? AppColors.cyan : AppColors.textSecondary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 56, child: leading),
          Expanded(
            child: Text(
              isMe ? 'VOCÊ' : entry.maskedName,
              style: TextStyle(
                color: isMe ? AppColors.cyan : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            PowerFormat.format(entry.totalPower),
            style: TextStyle(
              color: isMe ? AppColors.cyan : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
