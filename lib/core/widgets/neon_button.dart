import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/chamfered_border.dart';

/// Botão primário do PlayHash: chanfrado, com glow neon e altura >= 48dp
/// (alvo de toque confortável / acessibilidade).
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color = AppColors.cyan,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !isLoading;

    return SizedBox(
      width: double.infinity,
      height: 52, // >= 48dp
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const ChamferedBorder(cut: 10),
          shadows: enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 16,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.25),
            foregroundColor: AppColors.background,
            disabledForegroundColor:
                AppColors.background.withValues(alpha: 0.5),
            elevation: 0,
            shape: const ChamferedBorder(cut: 10),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.background,
                  ),
                )
              : Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ),
    );
  }
}
