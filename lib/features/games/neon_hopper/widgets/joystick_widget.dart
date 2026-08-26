import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Joystick DINÂMICO horizontal (zona esquerda): o knob nasce onde o dedo
/// toca; arrastar ±48 px define o eixo (-1..1). Multi-toque real: rastreia
/// o PRÓPRIO pointerId (mover + pular simultâneos).
class JoystickWidget extends StatefulWidget {
  const JoystickWidget({super.key, required this.onAxis});

  /// Eixo contínuo -1..1 (0 = parado).
  final ValueChanged<double> onAxis;

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  static const double _maxDrag = 48;

  int? _pointerId;
  double _anchorX = 0;
  double _knobDx = 0;

  void _down(PointerDownEvent e) {
    if (_pointerId != null) return; // já há um dedo comandando
    _pointerId = e.pointer;
    _anchorX = e.localPosition.dx;
    setState(() => _knobDx = 0);
    widget.onAxis(0);
  }

  void _move(PointerMoveEvent e) {
    if (_pointerId != e.pointer) return;
    final double dx = (e.localPosition.dx - _anchorX).clamp(-_maxDrag, _maxDrag);
    setState(() => _knobDx = dx);
    widget.onAxis(dx / _maxDrag);
  }

  void _up(PointerEvent e) {
    if (_pointerId != e.pointer) return;
    _pointerId = null;
    setState(() => _knobDx = 0);
    widget.onAxis(0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        children: <Widget>[
          // Base do joystick (visível quando ativo).
          if (_pointerId != null)
            Positioned(
              left: _anchorX - _maxDrag - 18,
              top: 0,
              bottom: 0,
              width: (_maxDrag + 18) * 2,
              child: Center(
                child: Container(
                  width: (_maxDrag + 18) * 2,
                  height: (_maxDrag + 18) * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.5),
                    ),
                    color: AppColors.background.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
          // Knob.
          if (_pointerId != null)
            Positioned(
              left: _anchorX + _knobDx - 22,
              top: 0,
              bottom: 0,
              width: 44,
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cyan.withValues(alpha: 0.85),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: AppColors.cyan.withValues(alpha: 0.4), blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ),
          // Dica estática quando inativo.
          if (_pointerId == null)
            Center(
              child: Text(
                '◀ MOVER ▶',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
