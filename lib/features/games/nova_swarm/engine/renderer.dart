import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'entities.dart';
import 'game_state.dart';

extension _PaintReset on Paint {
  /// Restaura o estado base (Paint não possui reset() no Flutter).
  void resetP() {
    shader = null;
    maskFilter = null;
    style = PaintingStyle.fill;
    strokeWidth = 1;
    color = const Color(0xFF000005);
  }
}

/// Sprites 100% ORIGINAIS desenhados em código — pixel-art por matrizes const
/// (9×7, pixel = 3dp). NENHUM sprite/logo/arte de jogos existentes é usado.
abstract final class NovaSwarmSprites {
  /// DRONE — "caranguejo" assimétrico próprio (vermelho).
  static const List<String> drone = <String>[
    '..X...X..',
    '...X.X...',
    '..XXXXX..',
    '.XX.X.XX.',
    'XXXXXXXXX',
    'X.XXXXX.X',
    'X..X.X..X',
  ];

  /// WASP — losango com farpas (roxo).
  static const List<String> wasp = <String>[
    '....X....',
    '...X.X...',
    '..X.X.X..',
    '.X.XXX.X.',
    'X..XXX..X',
    '...XXX...',
    '..X.X.X..',
  ];

  /// ELITE — coroa angular (dourado).
  static const List<String> elite = <String>[
    'X...X...X',
    'XX..X..XX',
    'XXX.X.XXX',
    'XXXXXXXXX',
    '.XXXXXXX.',
    '.X.XXX.X.',
    'X.......X',
  ];

  /// Olhos (1px branco) por variante — [col,row].
  static const Map<EnemyVariant, List<(int, int)>> eyes =
      <EnemyVariant, List<(int, int)>>{
    EnemyVariant.drone: <(int, int)>[(2, 3), (6, 3)],
    EnemyVariant.wasp: <(int, int)>[(3, 3), (5, 3)],
    EnemyVariant.elite: <(int, int)>[(3, 4), (5, 4)],
  };

  static const Map<EnemyVariant, Color> colors = <EnemyVariant, Color>{
    EnemyVariant.drone: Color(0xFFFF5252),
    EnemyVariant.wasp: Color(0xFF7C4DFF),
    EnemyVariant.elite: Color(0xFFFFC400),
  };

  /// Rects pré-computados por variante (unidade = 1 pixel do sprite).
  static final Map<EnemyVariant, List<Rect>> rects = _buildRects();

  static Map<EnemyVariant, List<Rect>> _buildRects() {
    final Map<EnemyVariant, List<String>> matrices = <EnemyVariant, List<String>>{
      EnemyVariant.drone: drone,
      EnemyVariant.wasp: wasp,
      EnemyVariant.elite: elite,
    };
    return <EnemyVariant, List<Rect>>{
      for (final MapEntry<EnemyVariant, List<String>> e in matrices.entries)
        e.key: <Rect>[
          for (int row = 0; row < e.value.length; row++)
            for (int col = 0; col < e.value[row].length; col++)
              if (e.value[row][col] == 'X')
                Rect.fromLTWH(col.toDouble(), row.toDouble(), 1, 1),
        ],
    };
  }

  /// Path ORIGINAL da nave do jogador (largura 52dp): nariz pontudo,
  /// fuselagem alongada, asas enflechadas e duas aletas traseiras.
  static Path playerShip() => Path()
    ..moveTo(26, 0)
    ..lineTo(31, 12)
    ..lineTo(52, 34)
    ..lineTo(44, 38)
    ..lineTo(34, 32)
    ..lineTo(36, 44)
    ..lineTo(30, 40)
    ..lineTo(26, 42)
    ..lineTo(22, 40)
    ..lineTo(16, 44)
    ..lineTo(18, 32)
    ..lineTo(8, 38)
    ..lineTo(0, 34)
    ..lineTo(21, 12)
    ..close();
}

/// Pintor ÚNICO do jogo (um CustomPainter por frame, estado imutável).
class NovaSwarmPainter extends CustomPainter {
  NovaSwarmPainter({required this.state, required this.repaint})
      : super(repaint: repaint);

  final NovaSwarmState state;
  final Listenable repaint;

  static const Color _bg = Color(0xFF000005);
  static const Color _shipTop = Color(0xFF00E5FF);
  static const Color _shipBottom = Color(0xFF0077AA);
  static const Color _shipOutline = Color(0xFF7DF3FF);
  static const Color _flameA = Color(0xFFFFC400);
  static const Color _flameB = Color(0xFFFF5252);

  final Paint _paint = Paint();
  final TextPainter _textPainter = TextPainter(textDirection: TextDirection.ltr);
  Size _lastSize = Size.zero;
  ui.Gradient? _nebulaA;
  ui.Gradient? _nebulaB;
  Path? _shipPath;

  @override
  void paint(Canvas canvas, Size size) {
    final NovaSwarmState s = state;
    _paint
      ..resetP()
      ..color = _bg
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, _paint);

    canvas.save();
    if (s.isShaking) {
      final double t = (math.Random().nextDouble() * 2 - 1) * 2;
      canvas.translate(t, t * 0.6);
    }

    _paintNebulas(canvas, size);
    _paintStars(canvas, s);
    _paintShootingStar(canvas, s);
    _paintBullets(canvas, s);
    _paintEnemies(canvas, s);
    _paintPlayer(canvas, s);
    _paintParticles(canvas, s);
    _paintShockwaves(canvas, s);
    _paintBanner(canvas, s, size);

    canvas.restore();
  }

  void _paintNebulas(Canvas canvas, Size size) {
    if (_lastSize != size || _nebulaA == null) {
      _lastSize = size;
      final double r = size.shortestSide * 0.4;
      _nebulaA = ui.Gradient.radial(
        Offset(size.width * 0.25, size.height * 0.3),
        r,
        <Color>[const Color(0xFF7C4DFF).withValues(alpha: 0.07), const Color(0xFF7C4DFF).withValues(alpha: 0)],
      );
      _nebulaB = ui.Gradient.radial(
        Offset(size.width * 0.78, size.height * 0.55),
        r,
        <Color>[const Color(0xFF00E5FF).withValues(alpha: 0.05), const Color(0xFF00E5FF).withValues(alpha: 0)],
      );
    }
    // Deriva lenta 4px/s (posição ancorada no tempo de jogo).
    final double drift = state.elapsed * 4;
    _paint
      ..resetP()
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(drift % 40 - 20, 0);
    _paint.shader = _nebulaA;
    canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.3), size.shortestSide * 0.4, _paint);
    _paint.shader = _nebulaB;
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.55), size.shortestSide * 0.4, _paint);
    canvas.restore();
    _paint.shader = null;
  }

  void _paintStars(Canvas canvas, NovaSwarmState s) {
    for (final Star star in s.stars) {
      final double twinkle = 0.75 + 0.25 * math.sin(s.elapsed * star.twinkleFreq * 2 * math.pi + star.phase);
      _paint
        ..resetP()
        ..color = star.color.withValues(alpha: (star.baseAlpha * twinkle).clamp(0.0, 1.0));
      canvas.drawRect(
        Rect.fromLTWH(star.x, star.y, star.size, star.size),
        _paint,
      );
    }
  }

  void _paintShootingStar(Canvas canvas, NovaSwarmState s) {
    final ShootingStar? ss = s.shootingStar;
    if (ss == null) return;
    final double fade = 1 - ((s.elapsed - ss.bornAt) / ss.life).clamp(0.0, 1.0);
    _paint
      ..resetP()
      ..color = const Color(0xFF7DF3FF).withValues(alpha: 0.7 * fade)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(ss.x, ss.y),
      Offset(ss.x - ss.vx * 0.12, ss.y - ss.vy * 0.12),
      _paint,
    );
  }

  void _paintBullets(Canvas canvas, NovaSwarmState s) {
    for (final Bullet b in s.bullets) {
      // Trilha com alpha decrescente.
      _paint
        ..resetP()
        ..color = const Color(0xFF7DF3FF).withValues(alpha: 0.25);
      canvas.drawRect(Rect.fromLTWH(b.x - 1.5, b.y + 10, 3, 12), _paint);
      // Cápsula 3×12dp com glow.
      _paint
        ..color = const Color(0xFF7DF3FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(b.x - 1.5, b.y - 6, 3, 12), const Radius.circular(2)),
        _paint,
      );
      _paint.maskFilter = null;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(b.x - 1.5, b.y - 6, 3, 12), const Radius.circular(2)),
        _paint,
      );
    }
    // Muzzle flash 60ms.
    if (s.elapsed < s.muzzleUntil) {
      _paint
        ..resetP()
        ..color = const Color(0xFFFFC400).withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(s.playerX, s.playerY - 28), 5, _paint);
      _paint.maskFilter = null;
    }
  }

  void _paintEnemies(Canvas canvas, NovaSwarmState s) {
    const double pixel = 3;
    for (final Enemy e in s.enemies) {
      final bool flash = s.elapsed < e.hitFlashUntil;
      final Color base = NovaSwarmSprites.colors[e.variant]!;
      _paint
        ..resetP()
        ..style = PaintingStyle.fill
        ..color = flash ? const Color(0xFFFFFFFF) : base;
      canvas.save();
      canvas.translate(e.x - 9 * pixel / 2, e.y - 7 * pixel / 2);
      canvas.scale(pixel);
      for (final Rect r in NovaSwarmSprites.rects[e.variant]!) {
        // Hit 1 sem flash: trinca — remove 2 px do centro.
        if (!flash && e.hp < s.config.enemyHp && _isCrack(r)) continue;
        canvas.drawRect(r, _paint);
      }
      // Olhos 1px branco.
      _paint.color = const Color(0xFFFFFFFF);
      for (final (int, int) eye in NovaSwarmSprites.eyes[e.variant]!) {
        canvas.drawRect(Rect.fromLTWH(eye.$1.toDouble(), eye.$2.toDouble(), 1, 1), _paint);
      }
      canvas.restore();
    }
  }

  /// Pixels centrais removidos na "trinca" do primeiro hit.
  static bool _isCrack(Rect r) =>
      (r.left == 4 && (r.top == 3 || r.top == 4));

  void _paintPlayer(Canvas canvas, NovaSwarmState s) {
    if (s.endReason == NovaSwarmEndReason.dead) return;
    final bool blink = s.isInvulnerable &&
        ((s.elapsed * 8).floor() % 2 == 0); // pisca 8Hz

    canvas.save();
    canvas.translate(s.playerX, s.playerY);
    canvas.rotate(s.playerBank);

    // Flame do motor: triângulo animado 8–16dp a 12Hz.
    final double flameH =
        12 + 4 * math.sin(s.elapsed * 12 * 2 * math.pi);
    final Path flame = Path()
      ..moveTo(20, 42)
      ..lineTo(26, 42 + flameH)
      ..lineTo(32, 42)
      ..close();
    _paint
      ..resetP()
      ..shader = ui.Gradient.linear(
        Offset(26, 42),
        Offset(26, 42 + flameH),
        <Color>[_flameA.withValues(alpha: 0.85), _flameB.withValues(alpha: 0.85)],
      );
    canvas.drawPath(flame, _paint);
    _paint.shader = null;

    // Corpo: gradiente vertical + contorno com glow.
    final Path ship = _shipPath ??= NovaSwarmSprites.playerShip();
    _paint
      ..resetP()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, 44),
        <Color>[_shipTop, _shipBottom],
      )
      ..color = _shipTop;
    if (!blink) {
      canvas.drawPath(ship, _paint);
      _paint
        ..shader = null
        ..color = _shipOutline.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(ship, _paint);
      _paint.maskFilter = null;
      canvas.drawPath(ship, _paint);

      // Cockpit: elipse branca α.9 4dp.
      _paint
        ..resetP()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9);
      canvas.drawOval(Rect.fromCenter(center: const Offset(26, 14), width: 4, height: 7), _paint);
    }

    // Anel de escudo ciano durante invulnerabilidade.
    if (s.isInvulnerable) {
      _paint
        ..resetP()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(26, 22), 34, _paint);
    }
    canvas.restore();
  }

  void _paintParticles(Canvas canvas, NovaSwarmState s) {
    for (final Particle p in s.particles) {
      final double fade = 1 - ((s.elapsed - p.bornAt) / p.life).clamp(0.0, 1.0);
      _paint
        ..resetP()
        ..color = p.color.withValues(alpha: fade);
      canvas.drawRect(Rect.fromLTWH(p.x, p.y, p.size, p.size), _paint);
    }
  }

  void _paintShockwaves(Canvas canvas, NovaSwarmState s) {
    for (final Shockwave w in s.shockwaves) {
      final double t = ((s.elapsed - w.bornAt) / w.life).clamp(0.0, 1.0);
      _paint
        ..resetP()
        ..color = const Color(0xFF7DF3FF).withValues(alpha: (1 - t) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset(w.x, w.y), 4 + t * 26, _paint);
    }
  }

  void _paintBanner(Canvas canvas, NovaSwarmState s, Size size) {
    if (!s.isBannerActive || s.bannerText.isEmpty) return;
    final double fade = (s.bannerUntil - s.elapsed).clamp(0.0, 1.0);
    _textPainter
      ..text = TextSpan(
        text: s.bannerText,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 6,
          color: const Color(0xFF7C4DFF).withValues(alpha: 0.35 + 0.65 * fade),
        ),
      )
      ..layout();
    _textPainter.paint(
      canvas,
      Offset(
        size.width / 2 - _textPainter.width / 2,
        size.height * 0.32,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant NovaSwarmPainter oldDelegate) => true;
}

/// Mini-cena estática do card do catálogo: fundo estrelado + nave ciano.
/// 100% código, sem assets.
class NovaSwarmThumbPainter extends CustomPainter {
  NovaSwarmThumbPainter();

  static const List<Offset> _stars = <Offset>[
    Offset(0.1, 0.15), Offset(0.3, 0.08), Offset(0.55, 0.2), Offset(0.8, 0.1),
    Offset(0.15, 0.45), Offset(0.45, 0.38), Offset(0.7, 0.5), Offset(0.9, 0.32),
    Offset(0.25, 0.7), Offset(0.6, 0.75), Offset(0.85, 0.65), Offset(0.05, 0.85),
    Offset(0.4, 0.9), Offset(0.75, 0.88),
  ];

  final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    _p
      ..resetP()
      ..color = const Color(0xFF000005);
    canvas.drawRect(Offset.zero & size, _p);

    for (int i = 0; i < _stars.length; i++) {
      final Offset s = _stars[i];
      _p.color = const Color(0xFFFFFFFF).withValues(alpha: 0.25 + (i % 4) * 0.15);
      canvas.drawRect(
        Rect.fromLTWH(s.dx * size.width, s.dy * size.height, 1.5, 1.5),
        _p,
      );
    }

    // Nebulosa discreta.
    _p.shader = ui.Gradient.radial(
      Offset(size.width * 0.7, size.height * 0.35),
      size.shortestSide * 0.5,
      <Color>[const Color(0xFF7C4DFF).withValues(alpha: 0.10), const Color(0xFF7C4DFF).withValues(alpha: 0)],
    );
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.35), size.shortestSide * 0.5, _p);
    _p.shader = null;

    // Nave ciano centralizada (path original compartilhado).
    final double scale = size.width / 80;
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.62);
    canvas.scale(scale, scale);
    canvas.translate(-26, -22);
    final Path ship = NovaSwarmSprites.playerShip();
    _p.shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(0, 44),
      <Color>[const Color(0xFF00E5FF), const Color(0xFF0077AA)],
    );
    canvas.drawPath(ship, _p);
    _p
      ..shader = null
      ..color = const Color(0xFF7DF3FF).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / scale;
    canvas.drawPath(ship, _p);
    _p
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9);
    canvas.drawOval(Rect.fromCenter(center: const Offset(26, 14), width: 4, height: 7), _p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant NovaSwarmThumbPainter oldDelegate) => false;
}
