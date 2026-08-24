import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/skeleton_box.dart';

/// Header "MEU PODER" da aba MINERAÇÃO — total formatado ou "—".
class PowerHeader extends StatelessWidget {
  const PowerHeader({
    super.key,
    required this.totalPower,
    this.loading = false,
  });

  /// Total oficial do servidor (H/s). `null` => "—".
  final int? totalPower;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _decorBar(),
            const SizedBox(width: 10),
            Text(
              'MEU PODER',
              style: AppTheme.neonLabel(fontSize: 18),
            ),
            const SizedBox(width: 10),
            _decorBar(),
          ],
        ),
        const SizedBox(height: 10),
        if (loading)
          const SkeletonBox(width: 220, height: 40)
        else
          Semantics(
            label: 'Poder total de mineração',
            value: totalPower == null
                ? 'indisponível'
                : PowerFormat.format(totalPower!),
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: totalPower == null
                        ? '—'
                        : PowerFormat.format(totalPower!),
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: AppColors.cyan,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _decorBar() => Container(
        width: 28,
        height: 3,
        decoration: BoxDecoration(
          color: AppColors.cyan.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// Ícone de raio reutilizável nos headers de poder.
class PowerBoltIcon extends StatelessWidget {
  const PowerBoltIcon({super.key, this.size = 22, this.color = AppColors.cyan});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      NeonIcons.bolt,
      width: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
