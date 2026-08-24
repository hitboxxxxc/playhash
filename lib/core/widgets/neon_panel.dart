import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/chamfered_border.dart';

/// Painel de conteúdo chanfrado com contorno neon suave.
class NeonPanel extends StatelessWidget {
  const NeonPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.accent = AppColors.cyan,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.surface,
        shape: ChamferedBorder(
          cut: 14,
          side: BorderSide(color: accent.withValues(alpha: 0.45)),
        ),
        shadows: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
