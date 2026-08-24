import 'dart:math';
import 'dart:ui';

/// Scheduler e trajetória dos MERGULHOS (v2) — funções PURAS.
///
/// - A cada [interval] (rampa por wave até o mínimo) 1 inimigo aleatório
///   vira "diver".
/// - Trajetória senoidal do slot até a região do jogador em 2.2s
///   ([diveDuration]); atira 1 vez ao cruzar ~40% da altura (prob 0.7).
/// - Passou do fundo ⇒ retorna ao slot com fade de 0.5s ([returnDuration]).
abstract final class DiveController {
  /// Duração da descida até passar do fundo (s).
  static const double diveDuration = 2.2;

  /// Duração do retorno ao slot com fade (s).
  static const double returnDuration = 0.5;

  /// Altura (fração do campo) em que o diver dispara sua orbe.
  static const double fireHeightFraction = 0.40;

  /// Probabilidade do diver disparar ao cruzar a altura de tiro.
  static const double fireChance = 0.7;

  /// Amplitude da oscilação senoidal horizontal durante a descida (dp).
  static const double weaveAmplitude = 36;

  /// Intervalo até o próximo mergulho na [wave]:
  /// max(min, base − ramp × (wave − 1)).
  static double intervalForWave({
    required int wave,
    required double baseSeconds,
    required double minSeconds,
    required double rampPerWave,
  }) =>
      max(minSeconds, baseSeconds - rampPerWave * (wave - 1));

  /// Progresso normalizado da descida [0..1].
  static double progress({
    required double elapsed,
    required double diveStartAt,
  }) {
    if (diveStartAt < 0) return 0;
    return ((elapsed - diveStartAt) / diveDuration).clamp(0.0, 1.0);
  }

  /// Posição do diver durante a DESCIDA (progress p ∈ [0..1]):
  /// y desce do slot até o fundo; x persegue o alvo com costura senoidal
  /// (Bézier-like: seno fecha em 0 nas pontas, suave no slot e no fundo).
  static Offset descentPosition({
    required double p,
    required double fromX,
    required double fromY,
    required double targetX,
    required double fieldHeight,
  }) {
    final double eased = p * p; // acelera levemente ao descer
    final double y = fromY + (fieldHeight + 60 - fromY) * eased;
    final double x = fromX +
        (targetX - fromX) * p +
        sin(p * 2 * pi) * weaveAmplitude;
    return Offset(x, y);
  }

  /// true quando o diver cruzou a altura de tiro (~40%) nesta frame.
  static bool crossedFireHeight({
    required double previousY,
    required double currentY,
    required double fieldHeight,
  }) {
    final double fireY = fieldHeight * fireHeightFraction;
    return previousY < fireY && currentY >= fireY;
  }

  /// Progresso do RETORNO [0..1] (fade + lerp de volta ao slot).
  static double returnProgress({
    required double elapsed,
    required double returnStartedAt,
  }) {
    if (returnStartedAt < 0) return 0;
    return ((elapsed - returnStartedAt) / returnDuration).clamp(0.0, 1.0);
  }

  /// Alpha do diver no retorno: some ao sair de cena, reaparece no slot.
  static double returnAlpha(double returnP) => returnP;

  /// Escolhe o índice de um inimigo aleatório que NÃO está mergulhando.
  /// Retorna −1 se não houver candidato.
  static int pickDiverCandidate(List<bool> isDiving, Random rng) {
    final List<int> candidates = <int>[
      for (int i = 0; i < isDiving.length; i++)
        if (!isDiving[i]) i,
    ];
    if (candidates.isEmpty) return -1;
    return candidates[rng.nextInt(candidates.length)];
  }
}
