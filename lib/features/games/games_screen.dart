import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state_panel.dart';
import '../../core/widgets/neon_icons.dart';

/// Aba JOGAR — estrutura de catálogo com filtros de dificuldade.
/// Conteúdo real do catálogo chega em fase posterior (backend é a fonte).
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  static const List<String> _difficulties = <String>[
    'Fácil',
    'Médio',
    'Difícil',
  ];

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen>
    with AutomaticKeepAliveClientMixin {
  int _selectedDifficulty = -1; // nenhum filtro selecionado inicialmente

  @override
  bool get wantKeepAlive => true; // preserva estado entre abas

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('JOGAR')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
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
                    itemCount: GamesScreen._difficulties.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final bool selected = index == _selectedDifficulty;
                      return FilterChip(
                        label: Text(
                          GamesScreen._difficulties[index].toUpperCase(),
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
                        onSelected: (_) =>
                            setState(() => _selectedDifficulty = index),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: EmptyStatePanel(
                        icon: NeonIcons.gamepad,
                        title: 'Catálogo em construção',
                        message:
                            'Os jogos estarão disponíveis em breve. '
                            'Filtros e partidas serão habilitados junto com o '
                            'servidor de sessões.',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
