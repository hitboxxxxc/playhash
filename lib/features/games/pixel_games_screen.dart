import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pixel_card.dart';
import '../../core/widgets/pixel_icon.dart';
import '../../core/widgets/pixel_icons.dart';
import '../../core/widgets/empty_state_panel.dart';
import '../../core/widgets/neon_icons.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/game_model.dart';
import '../../core/providers.dart';
import './nova_swarm/nova_swarm_screen.dart';
import './neon_hopper/neon_hopper_screen.dart';

class PixelGamesScreen extends ConsumerWidget {
  const PixelGamesScreen({super.key});

  static const Set<String> _implementedGames = <String>{'nova-swarm', 'neon-hopper'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<GameModel>> catalog = ref.watch(gamesCatalogProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              PixelCard(
                child: Row(
                  children: [
                    const PixelIcon(matrix: PixelIcons.gamepad, palette: PixelIcons.palette, size: 40),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GAMES', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF7C4DFF))),
                          Text('Jogue e ganhe poder de mineração!', style: TextStyle(fontSize: 12, color: Color(0xFF9AA3C0))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              catalog.when(
                loading: () => const _CatalogSkeleton(),
                error: (_, __) => const EmptyStatePanel(icon: NeonIcons.gamepad, title: 'Erro', message: 'Falha ao carregar.'),
                data: (List<GameModel> games) {
                  if (games.isEmpty) return const EmptyStatePanel(icon: NeonIcons.gamepad, title: 'Vazio', message: 'Nenhum jogo.');
                  return Column(
                    children: games.map((game) => _GameCard(game: game, implemented: _implementedGames.contains(game.id))).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.implemented});
  final GameModel game;
  final bool implemented;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PixelCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(4)),
              child: Stack(
                children: [
                  const Center(child: PixelIcon(matrix: PixelIcons.gamepad, palette: PixelIcons.palette, size: 32)),
                  if (!implemented)
                    Container(
                      color: AppColors.background.withValues(alpha: 0.8),
                      child: const Center(child: Text('EM BREVE', style: TextStyle(fontSize: 10, color: AppColors.textPrimary))),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(game.name, style: AppTheme.neonLabel(fontSize: 14)),
                  Text(implemented ? 'Defenda a base e vença a invasão!' : 'Em breve...', style: AppTheme.neonLabel(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text('COOLDOWN', style: TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                PixelIcon(matrix: PixelIcons.gear, palette: PixelIcons.palette, size: 12),
                                SizedBox(width: 4),
                                Text('—', style: TextStyle(fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 24, color: AppColors.surface),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('RECOMPENSA', style: TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const PixelIcon(matrix: PixelIcons.bolt, palette: PixelIcons.palette, size: 12),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'até +${game.configuration.powerCapPerSessionHs} H/s',
                                    style: const TextStyle(fontSize: 11, color: AppColors.purple),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 24, color: AppColors.surface),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('DIFICULDADE', style: TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                            Text(
                              game.difficulty.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: game.difficulty == 'easy' ? AppColors.green : AppColors.purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: implemented
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => game.id == 'neon-hopper' ? NeonHopperScreen(game: game) : NovaSwarmScreen(game: game),
                        ),
                      )
                  : null,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: implemented ? AppColors.purple : Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(child: PixelIcon(matrix: PixelIcons.play, palette: PixelIcons.palette, size: 24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();
  @override
  Widget build(BuildContext context) => const Column(children: [SkeletonBox(), SizedBox(height: 12), SkeletonBox()]);
}
