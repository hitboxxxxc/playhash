import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neon_icons.dart';
import '../../../data/repositories/mining_repository.dart';

/// Contagem regressiva "Próximo bloco em mm:ss" da MINERAÇÃO.
///
/// DISPLAY APENAS: o instante do próximo bloco vem SEMPRE do backend
/// (`blocks/current.nextBlockAt`, alinhado ao múltiplo de 5 minutos do
/// relógio do SERVIDOR gravado no último bloco finalizado). Sem schedule
/// oficial => traços ("--:--") — nunca um horário inventado localmente.
class NextBlockCountdown extends StatefulWidget {
  const NextBlockCountdown({super.key, this.block});

  final BlockSnapshot? block;

  @override
  State<NextBlockCountdown> createState() => _NextBlockCountdownState();
}

class _NextBlockCountdownState extends State<NextBlockCountdown> {
  Timer? _ticker;
  DateTime? _nextBlockAt;

  @override
  void initState() {
    super.initState();
    _syncSchedule();
  }

  @override
  void didUpdateWidget(NextBlockCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSchedule();
  }

  /// Intervalo NOMINAL de exibição (5 min). Usado APENAS para projetar o
  /// próximo múltiplo quando a âncora do servidor já passou (runner ainda
  /// não gravou o bloco novo) — a AUTORIDADE continua sendo o backend.
  static const Duration _displayInterval = Duration(minutes: 5);

  /// Próximo instante efetivo a exibir: a âncora do servidor; se já passou,
  /// o próximo múltiplo do intervalo APÓS a âncora (nunca "00:00" preso).
  DateTime? get _effectiveNext {
    final DateTime? anchor = _nextBlockAt;
    if (anchor == null) return null;
    final DateTime now = DateTime.now();
    if (anchor.isAfter(now)) return anchor;
    final int lateMinutes = now.difference(anchor).inMinutes;
    final int steps = (lateMinutes ~/ _displayInterval.inMinutes) + 1;
    return anchor.add(_displayInterval * steps);
  }

  void _syncSchedule() {
    final DateTime? next = widget.block?.nextBlockAt;
    if (next == _nextBlockAt) return;
    _ticker?.cancel();
    _ticker = null;
    _nextBlockAt = next;
    if (next != null) {
      // Tick visual apenas; a AUTORIDADE do horário é 100% do backend.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _label {
    final DateTime? next = _effectiveNext;
    if (next == null) return '--:--';
    Duration remaining = next.difference(DateTime.now());
    if (remaining.isNegative) remaining = Duration.zero;
    final int minutes = remaining.inMinutes;
    final int seconds = remaining.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSchedule = _effectiveNext != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SvgPicture.string(
          NeonIcons.clock,
          width: 16,
          colorFilter: ColorFilter.mode(
            hasSchedule ? AppColors.purple : AppColors.textSecondary,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: 'Próximo bloco em',
          value: _label,
          child: Text(
            'Próximo bloco em $_label',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: hasSchedule ? AppColors.gold : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
