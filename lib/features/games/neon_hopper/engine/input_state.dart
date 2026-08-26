import 'physics.dart';

/// NEON HOPPER — estado de ENTRADA multi-toque (joystick dinâmico horizontal
/// + botão de pulo), rastreado por pointerId (cada controle segue o PRÓPRIO
/// dedo; mover e pular simultâneos funcionam de verdade).
///
/// Os widgets (JoystickWidget/JumpButton) chamam os handlers aqui; a tela
/// aplica o resultado ao [NeonHopperState] via copyWith.
class HopperInputController {
  HopperInputController(this._apply);

  /// Aplica (eixo, pulo pressionado agora, pulo segurado) ao estado do jogo.
  final void Function(double axis, bool jumpPressed, bool jumpHeld) _apply;

  // Joystick: um dedo por vez (primeiro pointerId vence).
  int? _stickPointerId;
  double _anchorX = 0;
  static const double _maxDrag = 48; // raio do knob em px lógicos

  // Pulo: dedo próprio.
  int? _jumpPointerId;

  double get axis => _axis;
  double _axis = 0;
  bool _jumpHeld = false;

  /// Toque na zona do joystick inicia o knob DINÂMICO no ponto tocado.
  void onStickDown(int pointerId, double localX) {
    _stickPointerId ??= pointerId;
    if (_stickPointerId != pointerId) return;
    _anchorX = localX;
    _setAxis(0);
  }

  void onStickMove(int pointerId, double localX) {
    if (_stickPointerId != pointerId) return;
    final double dx = (localX - _anchorX).clamp(-_maxDrag, _maxDrag);
    _setAxis(dx / _maxDrag);
  }

  void onStickUp(int pointerId) {
    if (_stickPointerId != pointerId) return;
    _stickPointerId = null;
    _setAxis(0);
  }

  /// Botão PULO: pressiona → registra buffer no estado; solta → corta pulo.
  void onJumpDown(int pointerId) {
    _jumpPointerId ??= pointerId;
    if (_jumpPointerId != pointerId) return;
    _jumpHeld = true;
    _apply(_axis, true, true);
  }

  void onJumpUp(int pointerId) {
    if (_jumpPointerId != pointerId) return;
    _jumpPointerId = null;
    _jumpHeld = false;
    _apply(_axis, false, false);
  }

  /// Soltar TUDO (pausa/lifecycle/fim): nenhum dedo zumbi sobrevive.
  void release() {
    _stickPointerId = null;
    _jumpPointerId = null;
    _axis = 0;
    _jumpHeld = false;
    _apply(0, false, false);
  }

  void _setAxis(double value) {
    _axis = value.clamp(-1.0, 1.0);
    _apply(_axis, false, _jumpHeld);
  }
}
