import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/power_format.dart';
import '../../../core/widgets/machine_icons.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../core/widgets/neon_panel.dart';

/// Card "DISTRIBUIÇÃO DO PODER" — donut CustomPaint próprio
/// (ciano = máquinas, roxo = jogos). Zero poder => empty state.
///
/// Os valores vêm de dados oficiais do servidor: poder das máquinas é a
/// soma das máquinas; poder dos jogos é o restante do total oficial.
class PowerDistributionChart extends StatelessWidget {
  const PowerDistributionChart({
    super.key,
    this.machinesPower,
    this.gamesPower,
    this.loading = false,
  });

  final int? machinesPower;
  final int? gamesPower;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: AppColors.purple,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Text(
            'DISTRIBUIÇÃO DO PODER',
            style: AppTheme.neonLabel(fontSize: 14),
          ),
          const SizedBox(height: 16),
          if (loading)
            const SizedBox(
              height: 140,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.cyan,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (machinesPower == null && gamesPower == null ||
              (machinesPower ?? 0) + (gamesPower ?? 0) <= 0)
            _buildEmpty()
          else
            _buildChart(),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: <Widget>[
          SvgPicture.string(
            MachineIcons.donutEmpty,
            width: 84,
            colorFilter: const ColorFilter.mode(
              AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'SEM PODER PARA DISTRIBUIR',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Adquira máquinas e jogue para gerar poder de mineração.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final int machines = machinesPower ?? 0;
    final int games = gamesPower ?? 0;
    final int total = machines + games;
    final double machinesShare = total > 0 ? machines / total : 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _LegendEntry(
                color: AppColors.cyan,
                icon: NeonIcons.chip,
                label: 'PODER DAS MÁQUINAS',
                value: PowerFormat.format(machines),
                percent: machinesShare,
              ),
              const SizedBox(height: 14),
              _LegendEntry(
                color: AppColors.purple,
                icon: NeonIcons.gamepad,
                label: 'PODER DOS JOGOS',
                value: PowerFormat.format(games),
                percent: total > 0 ? 1 - machinesShare : 0,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Semantics(
            label: 'Gráfico de distribuição do poder',
            value: 'Total ${PowerFormat.format(total)}',
            child: SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(
                painter: _DonutPainter(machinesShare: machinesShare),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        PowerFormat.format(total),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.percent,
  });

  final Color color;
  final String icon;
  final String label;
  final String value;
  final double percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Center(
            child: SvgPicture.string(
              icon,
              width: 18,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                _percentLabel(percent),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Percentual pt-BR (vírgula decimal).
String _percentLabel(double percent) =>
    '${(percent * 100).toStringAsFixed(1)}%'.replaceAll('.', ',');

/// Donut próprio: ciano = máquinas, roxo = jogos.
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.machinesShare});

  final double machinesShare;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    const double stroke = 18;

    final Paint background = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surface;

    canvas.drawCircle(center, radius - stroke / 2, background);

    final Rect arcRect = Rect.fromCircle(
      center: center,
      radius: radius - stroke / 2,
    );

    final Paint machinesPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.cyan;

    final Paint gamesPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.purple;

    const double start = -math.pi / 2;
    final double machinesSweep = 2 * math.pi * machinesShare;
    canvas.drawArc(arcRect, start, machinesSweep, false, machinesPaint);
    canvas.drawArc(
      arcRect,
      start + machinesSweep,
      2 * math.pi - machinesSweep,
      false,
      gamesPaint,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.machinesShare != machinesShare;
}
