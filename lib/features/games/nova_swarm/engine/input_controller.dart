import 'dart:ui';

import 'game_state.dart';
import 'physics.dart';

/// Controle por toque em NÍVEL DE PONTEIRO (Listener bruto — NÃO participa da
/// arena de gestos, logo nenhum scroll/overlay consegue roubar o toque):
/// down/move definem o ALVO (X e Y — v3: movimento livre em ambas as
/// dimensões) e marcam toque ativo; a nave faz lerp 0.22/frame em AMBOS os
/// eixos (em [physics.dart]); up/cancel param os tiros.
/// Tiros (autofire 160ms) ocorrem SOMENTE enquanto o dedo estiver na tela.
class NovaSwarmInputController {
  NovaSwarmInputController(this._update);

  /// Aplica (target, isTouching) ao estado corrente.
  final void Function(Offset target, bool isTouching) _update;

  final double _margin = NovaSwarmPhysics.playerMargin;

  /// Margem interna de clamp nas bordas (dp).
  double get margin => _margin;

  Offset _lastTarget = Offset.zero;

  /// Pointer id do dedo COMANDANTE (o primeiro a tocar). Dedos extras são
  /// ignorados: o up/cancel de um segundo dedo NUNCA interrompe o toque
  /// principal (evita autofire morrendo com multi-touch acidental).
  int? _activePointer;

  /// true enquanto o ponteiro comandante estiver na tela.
  bool get isTouching => _activePointer != null;

  void onPointerDown(int pointer, Offset localPosition, Size fieldSize) {
    // Novo toque assume o comando somente se não há dedo ativo (defesa contra
    // down duplicado do mesmo pointer em alguns digitizers).
    _activePointer ??= pointer;
    if (pointer != _activePointer) return;
    _apply(localPosition, fieldSize);
  }

  void onPointerMove(int pointer, Offset localPosition, Size fieldSize) {
    if (pointer != _activePointer) return;
    _apply(localPosition, fieldSize);
  }

  void onPointerUp(int pointer) {
    if (pointer != _activePointer) return;
    _release();
  }

  void onPointerCancel(int pointer) => onPointerUp(pointer);

  /// Força soltar (pausa, fim de partida, lifecycle). Nunca deixa autofire
  /// zumbi caso o evento de up/cancel se perca.
  void release() => _release();

  void _release() {
    final bool wasActive = _activePointer != null;
    _activePointer = null;
    if (wasActive) _update(_lastTarget, false);
  }

  void _apply(Offset position, Size fieldSize) {
    final double half = NovaSwarmState.playerWidth / 2;
    // Eixo X: laterais do playfield.
    final double minX = half + _margin;
    final double maxX = fieldSize.width - half - _margin;
    // Eixo Y (v3): topo = abaixo do HUD; base = fundo do playfield. Sem
    // "túnel" vertical — a nave pode ir do topo até próximo à base.
    final double minY = NovaSwarmPhysics.playerTopMargin + half * 0.5;
    final double maxY = fieldSize.height - half - _margin;
    _lastTarget = Offset(
      position.dx
          .clamp(minX, maxX < minX ? fieldSize.width / 2 : maxX)
          .toDouble(),
      position.dy
          .clamp(minY, maxY < minY ? fieldSize.height * 0.8 : maxY)
          .toDouble(),
    );
    _update(_lastTarget, true);
  }
}
