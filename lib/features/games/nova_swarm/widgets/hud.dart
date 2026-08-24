import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/chamfered_border.dart';
import '../engine/renderer.dart';

/// HUD do topo: SCORE (esq., ciano) · TIMER (centro, dourado; <10s vermelho
/// com pulso) · vidas (3 mini-naves) + WAVE n (roxo). Sobre faixa translúcida
/// chanfrada. Textos escaláveis + feedback não só por cor.
class NovaSwarmHud extends StatelessWidget {
  const NovaSwarmHud({
    super.key,
    required this.score,
    required this.timeLeft,
    required this.lives,
    required this.maxLives,
    required this.wave,
    this.shieldRemaining = 0,
    this.doubleRemaining = 0,
    this.doubleLevel = 0,
    this.onPause,
  });

  final int score;
  final int timeLeft;
  final int lives;
  final int maxLives;
  final int wave;

  /// Fração restante dos power-ups ativos (0 = inativo) — anel de tempo.
  final double shieldRemaining;
  final double doubleRemaining;
  final int doubleLevel; // 2 = bolts duplos · 3 = triplos

  final VoidCallback? onPause;

  @override
  Widget build(BuildContext context) {
    final bool urgent = timeLeft < 10;
    // Pulso do timer (<10s): escala oscila 0.92–1.0 a ~11Hz.
    final double pulse = urgent
        ? 0.92 + 0.08 * math.sin(DateTime.now().microsecondsSinceEpoch / 90000 * math.pi)
        : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: const Color(0xFF0B0E1A).withValues(alpha: 0.7),
          shape: ChamferedBorder(
            cut: 10,
            side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.25)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          // IMPORTANTE: as Columns usam MainAxisSize.min — sem isso cada uma
          // expande para a ALTURA TOTAL disponível (constraints frouxas do
          // Align sob StackFit.expand) e o HUD vira um painel INVISÍVEL de
          // tela inteira que rouba TODOS os toques do playfield.
          child: Row(
            children: <Widget>[
              // SCORE
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'SCORE',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$score',
                      style: const TextStyle(
                        fontSize: 18,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.cyan,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              // TIMER
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'TEMPO',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Transform.scale(
                    scale: pulse,
                    child: Text(
                      '$timeLeft',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: urgent ? AppColors.error : AppColors.gold,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  if (urgent)
                    const Icon(Icons.priority_high, size: 12, color: AppColors.error)
                  else
                    const SizedBox(height: 12),
                ],
              ),
              // VIDAS + WAVE
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int i = 0; i < maxLives; i++)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Opacity(
                              opacity: i < lives ? 1.0 : 0.25,
                              child: _MiniShip(active: i < lives),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'WAVE $wave',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.purple,
                      ),
                    ),
                    // Ícones de power-ups ativos com anel de tempo restante.
                    if (shieldRemaining > 0 || doubleRemaining > 0) ...<Widget>[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (shieldRemaining > 0)
                            _PowerUpRing(
                              fraction: shieldRemaining,
                              color: const Color(0xFF2979FF),
                              icon: Icons.shield_outlined,
                            ),
                          if (shieldRemaining > 0 && doubleRemaining > 0)
                            const SizedBox(width: 4),
                          if (doubleRemaining > 0)
                            _PowerUpRing(
                              fraction: doubleRemaining,
                              color: AppColors.gold,
                              icon: Icons.bolt_rounded,
                              label: doubleLevel >= 3 ? '×3' : null,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // PAUSE (>=48dp de área de toque)
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  onPressed: onPause,
                  icon: const Icon(Icons.pause_rounded, size: 22),
                  color: AppColors.textSecondary,
                  tooltip: 'Pausar',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícone de vida: mini nave desenhada em código (mesmo path do jogo).
class _MiniShip extends StatelessWidget {
  const _MiniShip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(14, 12),
        painter: _MiniShipPainter(active: active),
      );
}

class _MiniShipPainter extends CustomPainter {
  _MiniShipPainter({required this.active});

  final bool active;

  final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 52, size.height / 44);
    _p.color = active ? AppColors.cyan : AppColors.textSecondary;
    canvas.drawPath(NovaSwarmSprites.playerShip(), _p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniShipPainter oldDelegate) =>
      oldDelegate.active != active;
}

/// Ícone pequeno de power-up ativo com anel de tempo restante (arco 360°).
class _PowerUpRing extends StatelessWidget {
  const _PowerUpRing({
    required this.fraction,
    required this.color,
    required this.icon,
    this.label,
  });

  final double fraction; // 0..1 tempo restante
  final Color color;
  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(
          painter: _PowerUpRingPainter(
            fraction: fraction.clamp(0.0, 1.0),
            color: color,
            label: label,
          ),
          child: Icon(icon, size: 10, color: color),
        ),
      );
}

class _PowerUpRingPainter extends CustomPainter {
  _PowerUpRingPainter({
    required this.fraction,
    required this.color,
    required this.label,
  });

  final double fraction;
  final Color color;
  final String? label;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    // Trilha.
    p.color = color.withValues(alpha: 0.2);
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width / 2 - 1, p);
    // Arco de tempo restante (começa no topo, sentido horário).
    p.color = color;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2 - 1,
      ),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      p,
    );
    if (label != null) {
      final TextPainter tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        )
        ..layout();
      tp.paint(
        canvas,
        Offset(size.width - tp.width - 1, size.height / 2 - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PowerUpRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.label != label;
}
