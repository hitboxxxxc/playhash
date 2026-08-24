import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_panel.dart';
import '../../../data/models/season_model.dart';

/// Cabeçalho da TEMPORADA: nome, countdown até endAt (exibição apenas —
/// fonte = doc oficial da season), nível OFICIAL + barra de XP dentro do
/// nível (xp % levelXp; nível/xp vêm de seasonProgress/{uid} do backend).
class SeasonHeader extends StatefulWidget {
  const SeasonHeader({
    super.key,
    required this.season,
    required this.level,
    required this.xp,
  });

  final SeasonModel season;
  final int level;
  final int xp;

  @override
  State<SeasonHeader> createState() => _SeasonHeaderState();
}

class _SeasonHeaderState extends State<SeasonHeader> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Countdown por minuto (exibição apenas — nada econômico aqui).
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _countdownLabel() {
    final Duration remaining = widget.season.endAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Encerrada';
    final int days = remaining.inDays;
    final int hours = remaining.inHours % 24;
    if (days > 0) return 'Termina em ${days}d ${hours}h';
    return 'Termina em ${remaining.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final int levelXp = widget.season.levelXp > 0 ? widget.season.levelXp : 1200;
    final int xpInLevel = widget.xp % levelXp;

    return NeonPanel(
      accent: AppColors.purple,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.schedule, color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 6),
              Text(
                _countdownLabel(),
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: AppColors.purple.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.purple),
                  ),
                ),
                child: Text(
                  '${widget.level}',
                  style: const TextStyle(
                    color: AppColors.purple,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'NÍVEL ${widget.level}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'XP $xpInLevel / $levelXp',
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: levelXp <= 0 ? 0 : (xpInLevel / levelXp).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            AppColors.textSecondary.withValues(alpha: 0.2),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
