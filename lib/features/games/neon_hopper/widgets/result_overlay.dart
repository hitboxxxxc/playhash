import 'package:flutter/material.dart';

import '../../../../core/services/game_session_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../../core/widgets/neon_panel.dart';

/// Estado do fluxo pós-partida (score local é PROVISÓRIO — o backend
/// recalcula o OFICIAL a partir do breakdown e concede o poder; doc 05 §51).
enum HopperResultStage { idle, sending, validating, granted, rejected, sendFailed }

/// Overlay de resultado NEON HOPPER: título por motivo de fim
/// ("BANDEIRA ALCANÇADA" / "TEMPO ESGOTADO" / "FIM DE JOGO"), breakdown
/// (pisões/moedas/bandeira) + status do servidor — mesmo padrão NOVA SWARM.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.stage,
    required this.score,
    required this.stomps,
    required this.coins,
    required this.flagReached,
    required this.livesLeft,
    this.endReason,
    this.serverResult,
    this.onCollect,
    required this.onBack,
  });

  final HopperResultStage stage;

  /// Score apresentado (breakdown aplicado; oficial = backend).
  final int score;
  final int stomps;
  final int coins;
  final bool flagReached;
  final int livesLeft;

  /// 'flag' | 'timeUp' | 'dead'.
  final String? endReason;

  final GameSessionServerResult? serverResult;

  /// Dispara o finishSession com breakdown (retry seguro/idempotente).
  final VoidCallback? onCollect;

  final VoidCallback onBack;

  String get _title {
    if (stage == HopperResultStage.granted && flagReached) return 'VITÓRIA!';
    switch (endReason) {
      case 'flag':
        return 'BANDEIRA ALCANÇADA!';
      case 'timeUp':
        return 'TEMPO ESGOTADO';
      case 'dead':
        return 'FIM DE JOGO';
      default:
        return 'FIM DE JOGO';
    }
  }

  String get _statusText {
    switch (stage) {
      case HopperResultStage.idle:
        return 'Toque em COLETAR para validar sua pontuação.';
      case HopperResultStage.sending:
        return 'Enviando resultado…';
      case HopperResultStage.validating:
        return 'Em validação pelo servidor…';
      case HopperResultStage.granted:
        final int hs = serverResult?.powerAmountHs ?? 0;
        final DateTime? expires = serverResult?.expiresAt;
        final String hhmm = expires != null
            ? '${expires.hour.toString().padLeft(2, '0')}:${expires.minute.toString().padLeft(2, '0')}'
            : '--:--';
        return '+$hs H/s por 24h · expira $hhmm';
      case HopperResultStage.rejected:
        return 'Sessão rejeitada pelo servidor.';
      case HopperResultStage.sendFailed:
        return 'Não foi possível enviar o resultado.';
    }
  }

  Color get _statusColor {
    switch (stage) {
      case HopperResultStage.granted:
        return AppColors.green;
      case HopperResultStage.rejected:
      case HopperResultStage.sendFailed:
        return AppColors.error;
      case HopperResultStage.idle:
      case HopperResultStage.sending:
      case HopperResultStage.validating:
        return AppColors.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool busy =
        stage == HopperResultStage.sending || stage == HopperResultStage.validating;
    final bool canCollect =
        stage == HopperResultStage.idle || stage == HopperResultStage.sendFailed;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: NeonPanel(
          accent: _statusColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _title,
                textAlign: TextAlign.center,
                style: AppTheme.neonLabel(fontSize: 22)
                    .copyWith(color: _statusColor, letterSpacing: 4),
              ),
              const SizedBox(height: 18),
              _Stat(label: 'SCORE', value: '$score', color: AppColors.cyan),
              _Stat(label: 'PISÕES', value: '$stomps', color: AppColors.textPrimary),
              _Stat(label: 'MOEDAS', value: '$coins', color: AppColors.gold),
              _Stat(
                label: 'BANDEIRA',
                value: flagReached ? 'SIM (+bônus)' : 'NÃO',
                color: flagReached ? AppColors.green : AppColors.textSecondary,
              ),
              _Stat(label: 'VIDAS RESTANTES', value: '$livesLeft', color: AppColors.purple),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (busy) ...<Widget>[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (stage == HopperResultStage.granted)
                    const Icon(Icons.verified_outlined, size: 16, color: AppColors.green)
                  else if (stage == HopperResultStage.rejected ||
                      stage == HopperResultStage.sendFailed)
                    const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _statusColor, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (canCollect && onCollect != null) ...<Widget>[
                NeonButton(
                  label: stage == HopperResultStage.sendFailed
                      ? 'COLETAR NOVAMENTE'
                      : 'COLETAR RECOMPENSA',
                  onPressed: onCollect,
                ),
                const SizedBox(height: 10),
              ],
              NeonButton(
                label: 'VOLTAR',
                onPressed: onBack,
                color: AppColors.purple,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: color,
              ),
            ),
          ],
        ),
      );
}
