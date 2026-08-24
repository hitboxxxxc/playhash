import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../../core/widgets/neon_panel.dart';
import '../../../../core/services/game_session_service.dart';

/// Estado do fluxo pós-partida (score local é PROVISÓRIO — o backend valida
/// e CONCEDE o poder; doc 05 §51).
///
/// [idle] = partida encerrou e o jogador ainda NÃO tocou em
/// "COLETAR RECOMPENSA" (que garante o finishSession com retry idempotente).
enum ResultStage { idle, sending, validating, granted, rejected, sendFailed }

/// Overlay de resultado: título por motivo de fim ("TEMPO ESGOTADO" /
/// "FIM DE JOGO"), Score/Kills/Waves/power-ups coletados + status do servidor
/// ("Enviando resultado…" → "Em validação pelo servidor…" →
/// "+X H/s por 24h · expira HH:mm" ou rejeição com mensagem segura).
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.stage,
    required this.score,
    required this.kills,
    required this.waves,
    this.endReason,
    this.powerUpsCollected = 0,
    this.serverResult,
    this.onRetry,
    this.onCollect,
    required this.onBack,
  });

  final ResultStage stage;
  final int score;
  final int kills;
  final int waves;

  /// 'timeUp' ⇒ "TEMPO ESGOTADO"; 'dead' ⇒ "FIM DE JOGO".
  final String? endReason;

  /// Total de power-ups coletados na partida.
  final int powerUpsCollected;

  final GameSessionServerResult? serverResult;
  final VoidCallback? onRetry;

  /// Dispara o finishSession (retry seguro/idempotente).
  final VoidCallback? onCollect;

  final VoidCallback onBack;

  String get _title {
    if (stage == ResultStage.granted) return 'VITÓRIA!';
    switch (endReason) {
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
      case ResultStage.idle:
        return 'Toque em COLETAR para validar sua pontuação.';
      case ResultStage.sending:
        return 'Enviando resultado…';
      case ResultStage.validating:
        return 'Em validação pelo servidor…';
      case ResultStage.granted:
        final int hs = serverResult?.powerAmountHs ?? 0;
        final DateTime? expires = serverResult?.expiresAt;
        final String hhmm = expires != null
            ? '${expires.hour.toString().padLeft(2, '0')}:${expires.minute.toString().padLeft(2, '0')}'
            : '--:--';
        return '+$hs H/s por 24h · expira $hhmm';
      case ResultStage.rejected:
        return 'Sessão rejeitada pelo servidor.';
      case ResultStage.sendFailed:
        return 'Não foi possível enviar o resultado.';
    }
  }

  Color get _statusColor {
    switch (stage) {
      case ResultStage.granted:
        return AppColors.green;
      case ResultStage.rejected:
      case ResultStage.sendFailed:
        return AppColors.error;
      case ResultStage.idle:
      case ResultStage.sending:
      case ResultStage.validating:
        return AppColors.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool busy =
        stage == ResultStage.sending || stage == ResultStage.validating;
    final bool canCollect =
        stage == ResultStage.idle || stage == ResultStage.sendFailed;
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
              _Stat(label: 'ABATES', value: '$kills', color: AppColors.textPrimary),
              _Stat(label: 'ONDAS', value: '$waves', color: AppColors.purple),
              _Stat(
                label: 'POWER-UPS',
                value: '$powerUpsCollected',
                color: AppColors.gold,
              ),
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
                  if (stage == ResultStage.granted)
                    const Icon(Icons.verified_outlined, size: 16, color: AppColors.green)
                  else if (stage == ResultStage.rejected ||
                      stage == ResultStage.sendFailed)
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
              // COLETAR RECOMPENSA: garante o finishSession (retry seguro
              // idempotente). Depois vira status "Em validação…" → serverResult.
              if (canCollect && onCollect != null) ...<Widget>[
                NeonButton(
                  label: stage == ResultStage.sendFailed
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
