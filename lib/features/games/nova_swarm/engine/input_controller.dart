import 'dart:ui';

import 'game_state.dart';
import 'physics.dart';

/// Controle por toque: onPanDown/Move define o ALVO horizontal; a nave faz
/// lerp 0.22/frame (em [physics.dart]); onPanEnd para os tiros.
/// Tiros ocorrem SOMENTE enquanto o dedo está na tela.
class NovaSwarmInputController {
  NovaSwarmInputController(this._update);

  /// Aplica (targetX, shooting) ao estado corrente.
  final void Function(double targetX, bool shooting) _update;

  final double _margin = NovaSwarmPhysics.playerMargin;

  /// Margem interna de clamp nas bordas (dp).
  double get margin => _margin;

  void onPanDown(Offset localPosition, Size fieldSize) =>
      _apply(localPosition, fieldSize, shooting: true);

  void onPanUpdate(Offset localPosition, Size fieldSize) =>
      _apply(localPosition, fieldSize, shooting: true);

  void onPanEnd() => _update(_lastTarget, false);

  double _lastTarget = 0;

  void _apply(Offset position, Size fieldSize, {required bool shooting}) {
    final double half = NovaSwarmState.playerWidth / 2;
    final double minX = half + _margin;
    final double maxX = fieldSize.width - half - _margin;
    _lastTarget = position.dx.clamp(minX, maxX < minX ? fieldSize.width / 2 : maxX)
        .toDouble();
    _update(_lastTarget, shooting);
  }
}
