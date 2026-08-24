import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bloco de skeleton (loading) padrão — retângulo chanfrado de baixa
/// opacidade, sem animações pesadas. Usado enquanto o servidor responde.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 6,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
