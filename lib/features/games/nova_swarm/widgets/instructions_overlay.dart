import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../../core/widgets/neon_panel.dart';
import '../../../../data/models/game_model.dart';

/// Overlay de instruções (painel chanfrado): título, como jogar, regras da
/// config recebida e botão INICIAR — que cria a SESSÃO no Firestore ANTES
/// do play. Estados: ocioso / criando sessão / erro seguro PT-BR.
class InstructionsOverlay extends StatelessWidget {
  const InstructionsOverlay({
    super.key,
    required this.game,
    required this.onStart,
    required this.isLoading,
    this.error,
  });

  final GameModel game;
  final VoidCallback onStart;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final GameConfig cfg = game.configuration;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: NeonPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                game.name.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTheme.neonLabel(fontSize: 22).copyWith(
                  color: AppColors.cyan,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Toque e SEGURE para mover e atirar. '
                'Destrua a enxame antes que o tempo acabe.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              _RuleRow(
                icon: Icons.timer_outlined,
                text: 'Duração: ${cfg.durationSeconds > 0 ? cfg.durationSeconds : 60}s',
              ),
              _RuleRow(
                icon: Icons.favorite_outline,
                text: 'Vidas: ${cfg.lives > 0 ? cfg.lives : 3}',
              ),
              _RuleRow(
                icon: Icons.shield_outlined,
                text:
                    'Inimigos comuns aguentam ${cfg.enemyHp > 0 ? cfg.enemyHp : 2} acertos',
              ),
              _RuleRow(
                icon: Icons.bolt_outlined,
                text: 'Ondas crescentes: '
                    '${cfg.baseEnemies > 0 ? cfg.baseEnemies : 8} inimigos na 1ª, '
                    '+${cfg.enemiesPerWaveStep > 0 ? cfg.enemiesPerWaveStep : 4} por onda',
              ),
              const SizedBox(height: 20),
              if (error != null) ...<Widget>[
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],
              NeonButton(
                label: 'INICIAR',
                onPressed: onStart,
                isLoading: isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}
