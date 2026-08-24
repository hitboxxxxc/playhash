import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_icons.dart';

/// Badge circular com raio — identidade visual própria do card de poder.
class PowerBoltBadge extends StatelessWidget {
  const PowerBoltBadge({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.6)),
        color: AppColors.background,
      ),
      child: Center(
        child: SvgPicture.string(
          NeonIcons.bolt,
          width: size * 0.45,
          colorFilter: const ColorFilter.mode(AppColors.cyan, BlendMode.srcIn),
        ),
      ),
    );
  }
}
