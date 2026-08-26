import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/chamfered_border.dart';

/// Botão PULO chanfrado (zona direita): pressionar registra buffer no
/// engine; SOLTAR CEDO corta a subida pela metade (pulo variável).
/// Multi-toque real: rastreia o PRÓPRIO pointerId.
class JumpButton extends StatefulWidget {
  const JumpButton({
    super.key,
    required this.onPress,
    required this.onRelease,
  });

  final VoidCallback onPress;
  final VoidCallback onRelease;

  @override
  State<JumpButton> createState() => _JumpButtonState();
}

class _JumpButtonState extends State<JumpButton> {
  int? _pointerId;
  bool _pressed = false;

  void _down(PointerDownEvent e) {
    if (_pointerId != null) return;
    _pointerId = e.pointer;
    setState(() => _pressed = true);
    widget.onPress();
  }

  void _up(PointerEvent e) {
    if (_pointerId != e.pointer) return;
    _pointerId = null;
    setState(() => _pressed = false);
    widget.onRelease();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Center(
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 60),
          child: Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: _pressed
                  ? AppColors.cyan.withValues(alpha: 0.35)
                  : AppColors.cyan.withValues(alpha: 0.12),
              shape: const ChamferedBorder(
                cut: 16,
                side: BorderSide(color: AppColors.cyan),
              ),
            ),
            child: const Text(
              'PULO',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: AppColors.cyan,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
