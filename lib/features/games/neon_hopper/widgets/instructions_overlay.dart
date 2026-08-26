import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../../core/widgets/neon_panel.dart';
import '../../../../data/models/game_model.dart';

/// Overlay de instruções do NEON HOPPER: como jogar (joystick, pulo, pisão),
/// regras da config recebida do backend e botão INICIAR — que cria a SESSÃO
/// no Firestore ANTES do play. Estados: ocioso / criando sessão / erro.
class InstructionsOverlay extends StatelessWidget {
  const InstructionsOverlay({
    super.key,
    required this.game,
    required this.onStart,
    required this.isLoading,
    this.error,
    this.onBack,
  });

  final GameModel game;
  final VoidCallback onStart;
  final bool isLoading;
  final String? error;

  /// Botão VOLTAR exibido junto ao erro de sessão (o usuário nunca fica
  /// preso no overlay).
  final VoidCallback? onBack;

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
                'Mova no joystick e pule com o botão PULO. '
                'PISE nos inimigos para pontuar; encostar de lado tira vida. '
                'Pegue moedas e chegue à bandeira antes do tempo acabar.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              _RuleRow(
                icon: Icons.timer_outlined,
                text: 'Duração: ${cfg.durationSeconds > 0 ? cfg.durationSeconds : 45}s',
              ),
              _RuleRow(
                icon: Icons.favorite_outline,
                text: 'Vidas: ${cfg.lives > 0 ? cfg.lives : 3}',
              ),
              _RuleRow(
                icon: Icons.directions_run_outlined,
                text:
                    'Pisão em inimigo: +${cfg.pointsPerStomp > 0 ? cfg.pointsPerStomp : 100} pontos',
              ),
              _RuleRow(
                icon: Icons.paid_outlined,
                text: 'Moeda: +${cfg.pointsPerCoin > 0 ? cfg.pointsPerCoin : 50} pontos',
              ),
              _RuleRow(
                icon: Icons.flag_outlined,
                text: 'Bandeira final: +${cfg.flagBonus > 0 ? cfg.flagBonus : 500} pontos',
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
              if (error != null && onBack != null) ...<Widget>[
                const SizedBox(height: 10),
                NeonButton(
                  label: 'VOLTAR',
                  onPressed: onBack!,
                  color: AppColors.purple,
                ),
              ],
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
