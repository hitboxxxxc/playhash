import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state_panel.dart';
import '../../core/widgets/neon_icons.dart';
import '../../core/widgets/skeleton_box.dart';
import '../../data/models/game_model.dart';
import 'neon_hopper/neon_hopper_screen.dart';
import 'nova_swarm/nova_swarm_screen.dart';
import 'widgets/game_card.dart';

/// Aba JOGAR — catálogo REAL lido de `games/*` (cache-first, backend é a
/// fonte). Grade 2 colunas adaptável; estados loading/vazio/erro/offline.
/// Filtro de dificuldade com estado preservado entre abas (keepAlive).
class GamesScreen extends ConsumerStatefulWidget {
  const GamesScreen({super.key});

  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen>
    with AutomaticKeepAliveClientMixin {
  /// Registry local de jogos COM implementação no app. Games vindos do
  /// Firestore fora deste conjunto são exibidos como "EM BREVE" com JOGAR
  /// desabilitado — nunca abrem um playfield sem implementação.
  static const Set<String> _implementedGames = <String>{'nova-swarm', 'neon-hopper'};

  static const List<String> _difficulties = <String>[
    'Fácil',
    'Médio',
    'Difícil',
  ];
  static const List<String> _difficultyKeys = <String>[
    'easy',
    'medium',
    'hard',
  ];

  int _selectedDifficulty = -1; // nenhum filtro selecionado inicialmente

  @override
  bool get wantKeepAlive => true; // preserva estado entre abas

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AsyncValue<List<GameModel>> catalog =
        ref.watch(gamesCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('JOGAR')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'ESCOLHA UM DESAFIO',
                    style: AppTheme.neonLabel(fontSize: 16),
                  ),
                ),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: _difficulties.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final bool selected = index == _selectedDifficulty;
                      return FilterChip(
                        label: Text(
                          _difficulties[index].toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.background
                                : AppColors.textSecondary,
                          ),
                        ),
                        selected: selected,
                        selectedColor: AppColors.cyan,
                        backgroundColor: AppColors.surface,
                        checkmarkColor: AppColors.background,
                        side: BorderSide(
                          color: selected
                              ? AppColors.cyan
                              : AppColors.purple.withValues(alpha: 0.5),
                        ),
                        showCheckmark: false,
                        onSelected: (_) => setState(() =>
                            _selectedDifficulty =
                                selected ? -1 : index),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: catalog.when(
                    loading: () => const _CatalogSkeleton(),
                    error: (Object e, StackTrace _) => _CatalogEmpty(
                      message: 'Não foi possível carregar o catálogo. '
                          'Verifique sua conexão.',
                      onRetry: () => ref.invalidate(gamesCatalogProvider),
                    ),
                    data: (List<GameModel> games) {
                      final List<GameModel> filtered = _selectedDifficulty < 0
                          ? games
                          : games
                              .where((GameModel g) =>
                                  g.difficulty ==
                                  _difficultyKeys[_selectedDifficulty])
                              .toList(growable: false);
                      if (filtered.isEmpty) {
                        return _CatalogEmpty(
                          message: games.isEmpty
                              ? 'Nenhum jogo disponível agora. '
                                  'O catálogo é publicado pelo servidor.'
                              : 'Nenhum jogo nesta dificuldade ainda.',
                          onRetry: () =>
                              ref.invalidate(gamesCatalogProvider),
                        );
                      }
                      return LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints c) {
                          final int columns = c.maxWidth > 560 ? 3 : 2;
                          return GridView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (BuildContext context, int index) =>
                                GameCard(
                              game: filtered[index],
                              implemented: _implementedGames
                                  .contains(filtered[index].id),
                              onPlay: () =>
                                  _openGame(context, filtered[index]),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openGame(BuildContext context, GameModel game) {
    // Defesa em profundidade: só navega se houver implementação local.
    if (!_implementedGames.contains(game.id)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => switch (game.id) {
          'neon-hopper' => NeonHopperScreen(game: game),
          _ => NovaSwarmScreen(game: game),
        },
      ),
    );
  }
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final int columns = c.maxWidth > 560 ? 3 : 2;
          return GridView.count(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.72,
            children: const <Widget>[
              SkeletonBox(),
              SkeletonBox(),
              SkeletonBox(),
              SkeletonBox(),
            ],
          );
        },
      );
}

class _CatalogEmpty extends StatelessWidget {
  const _CatalogEmpty({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            EmptyStatePanel(
              icon: NeonIcons.gamepad,
              title: 'Catálogo indisponível',
              message: message,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('TENTAR NOVAMENTE'),
            ),
          ],
        ),
      );
}
