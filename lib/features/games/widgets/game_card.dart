import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/chamfered_border.dart';
import '../../../data/models/game_model.dart';
import '../nova_swarm/engine/renderer.dart';

/// Card do catálogo JOGAR: thumbnail 100% desenhada em código (mini cena
/// estrelada + nave ciano), nome, chip de dificuldade, melhor score próprio
/// e recompensa ESTIMADA derivada SOMENTE da config recebida do backend.
class GameCard extends ConsumerWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.onPlay,
  });

  final GameModel game;
  final VoidCallback onPlay;

  static const Map<String, (String, Color)> _difficultyLabels = <String, (String, Color)>{
    'easy': ('FÁCIL', AppColors.green),
    'medium': ('MÉDIO', AppColors.gold),
    'hard': ('DIFÍCIL', AppColors.error),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (String label, Color color) =
        _difficultyLabels[game.difficulty] ?? ('—', AppColors.textSecondary);
    final int best = ref.watch(bestScoreProvider(game.id)).value ?? 0;
    final int rewardHs = game.configuration.powerCapPerSessionHs;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 14,
          side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ClipPath(
                clipper: _ChamferClipper(),
                child: CustomPaint(
                  painter: NovaSwarmThumbPainter(),
                  isComplex: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    game.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.neonLabel(fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: ShapeDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: ChamferedBorder(
                      cut: 6,
                      side: BorderSide(color: color.withValues(alpha: 0.7)),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Feedback não dependente só de cor: rótulo textual + ícone.
            Text(
              'Melhor: $best',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rewardHs > 0
                  ? 'até +$rewardHs H/s por 24h (estimado)'
                  : 'recompensa a definir pelo servidor',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44, // >= 44dp; área de toque confortável
              child: ElevatedButton(
                onPressed: onPlay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: AppColors.background,
                  elevation: 0,
                  shape: const ChamferedBorder(cut: 8),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                child: const Text('JOGAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChamferClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const double c = 10;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width - c, 0)
      ..lineTo(size.width, c)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

