import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'entities.dart';
import 'level_data.dart';
import 'physics.dart';

/// NEON HOPPER — renderizador 100% em código (CustomPaint único, 60fps):
/// parallax 2 camadas (starfield determinístico + colinas escuras), blocos
/// neon com topo ciano, sprites por matriz de pixel, moeda hexagonal
/// girando e bandeira-beacon pulsando.
class NeonHopperPainter extends CustomPainter {
  NeonHopperPainter({required this.state, required this.repaint});

  final NeonHopperState state;
  final Listenable repaint;

  // Viewport lógico do mundo visível (20 tiles de largura).
  static const double viewW = 640;
  static const double viewH = HopperLevel.worldHeight; // 448

  @override
  void paint(Canvas canvas, Size size) {
    // Escala: cabe o viewport inteiro na área disponível.
    final double scale = math.min(size.width / viewW, size.height / viewH);
    final double offX = (size.width - viewW * scale) / 2;
    final double offY = size.height - viewH * scale; // alinhado embaixo

    _paintSky(canvas, size);
    _paintParallax(canvas, size, scale, offX);

    canvas.save();
    canvas.translate(offX, offY);
    canvas.scale(scale);
    canvas.translate(-state.cameraX, 0);

    _paintTiles(canvas);
    _paintFlag(canvas);
    _paintCoins(canvas);
    _paintEnemies(canvas);
    _paintPlayer(canvas);

    canvas.restore();
  }

  // ---- Fundo ---------------------------------------------------------------

  void _paintSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF04040C),
    );
  }

  /// Starfield DETERMINÍSTICO (hash senoidal — sem Random) + colinas escuras
  /// com fator de parallax 0.3.
  void _paintParallax(Canvas canvas, Size size, double scale, double offX) {
    final Paint star = Paint()..color = AppColors.cyan.withValues(alpha: 0.5);
    for (int i = 0; i < 60; i++) {
      final double sx = _hash(i * 2.13) * HopperLevel.worldWidth;
      final double sy = _hash(i * 7.77) * 300;
      final double px =
          ((sx - state.cameraX * 0.3) % (viewW + 40)) * scale + offX - 20 * scale;
      if (px < 0 || px > size.width) continue;
      final double py = sy * scale;
      canvas.drawCircle(Offset(px, py), (i.isEven ? 1.4 : 0.9) * scale, star);
    }

    // Colinas escuras (duas camadas de arcos).
    final Paint hills = Paint()
      ..color = const Color(0xFF0B0B22)
      ..style = PaintingStyle.fill;
    final Path path = Path();
    path.moveTo(0, size.height);
    for (int i = 0; i <= 12; i++) {
      final double wx = i * 320.0;
      final double sx =
          ((wx - state.cameraX * 0.3) % (viewW + 320)) * scale + offX - 160 * scale;
      path.lineTo(sx, size.height - (90 + _hash(i * 3.3) * 70) * scale);
      path.quadraticBezierTo(
        sx + 160 * scale,
        size.height - (150 + _hash(i * 5.1) * 80) * scale,
        sx + 320 * scale,
        size.height - (90 + _hash((i + 1) * 3.3) * 70) * scale,
      );
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, hills);
  }

  static double _hash(double n) {
    final double v = math.sin(n * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  // ---- Mundo -----------------------------------------------------------------

  void _paintTiles(Canvas canvas) {
    final Paint body = Paint()..color = const Color(0xFF101032);
    final Paint top = Paint()..color = AppColors.cyan.withValues(alpha: 0.9);
    final Paint edge = Paint()
      ..color = AppColors.purple.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final Rect r in state.solids) {
      canvas.drawRect(r, body);
      // Topo ciano só na face superior exposta.
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 4), top);
      canvas.drawRect(r, edge);
    }
  }

  void _paintFlag(Canvas canvas) {
    final double x = HopperLevel.flagX;
    final double baseY = HopperLevel.flagBaseY;
    final double h = HopperLevel.flagPoleHeight;

    canvas.drawRect(
      Rect.fromLTWH(x, baseY - h, 4, h),
      Paint()..color = AppColors.textSecondary,
    );
    // Beacon pulsando no topo do mastro.
    final double pulse =
        6 + 3 * math.sin(state.elapsed * math.pi * 2); // ~1 Hz
    canvas.drawCircle(
      Offset(x + 2, baseY - h),
      pulse,
      Paint()..color = AppColors.gold.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      Offset(x + 2, baseY - h),
      pulse + 5,
      Paint()..color = AppColors.gold.withValues(alpha: 0.25),
    );
  }

  void _paintCoins(Canvas canvas) {
    for (final HopperCoin c in state.coins) {
      if (c.collected) continue;
      // Giro: escala X senoidal (hexágono "girando").
      final double sx = math.sin(state.elapsed * 5 + c.id * 0.9).abs() * 0.8 + 0.2;
      final Path hex = Path();
      for (int i = 0; i < 6; i++) {
        final double a = math.pi / 3 * i;
        final double dx = math.cos(a) * 10 * sx;
        final double dy = math.sin(a) * 10;
        i == 0
            ? hex.moveTo(c.x + dx, c.y + dy)
            : hex.lineTo(c.x + dx, c.y + dy);
      }
      hex.close();
      canvas.drawPath(hex, Paint()..color = AppColors.gold);
      canvas.drawPath(
        hex,
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _paintEnemies(Canvas canvas) {
    for (final HopperEnemy e in state.enemies) {
      if (!e.alive) continue;
      final List<List<int>> frame =
          (state.elapsed * 6).floor().isEven ? kCrabA : kCrabB;
      _drawMatrix(canvas, frame, e.x, e.y, flip: false);
    }
  }

  void _paintPlayer(Canvas canvas) {
    // Invulnerável: pisca (visível em frames alternados).
    if (state.isInvulnerable && (state.elapsed * 8).floor().isEven) return;

    final HopperPlayer p = state.player;
    List<List<int>> frame;
    if (!p.onGround) {
      frame = kRobotJump;
    } else if (p.vx.abs() > 10) {
      frame = (state.elapsed * 8).floor().isEven ? kRobotWalkA : kRobotWalkB;
    } else {
      frame = kRobotIdle;
    }
    _drawMatrix(canvas, frame, p.x, p.y, flip: p.facing < 0);
  }

  /// Desenha uma matriz de pixel (índices em [kHopperPalette]) com espelho
  /// opcional (facing esquerda).
  void _drawMatrix(
    Canvas canvas,
    List<List<int>> matrix,
    double x,
    double y, {
    required bool flip,
  }) {
    final double s = kHopperPixelScale;
    for (int row = 0; row < matrix.length; row++) {
      final List<int> line = matrix[row];
      for (int col = 0; col < line.length; col++) {
        final int idx = line[col];
        if (idx == 0) continue;
        final Color? color = kHopperPalette[idx];
        if (color == null) continue;
        final double cx = (flip ? (line.length - 1 - col) : col).toDouble();
        canvas.drawRect(
          Rect.fromLTWH(x + cx * s, y + row * s, s, s),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant NeonHopperPainter oldDelegate) => true;
}

/// Thumbnail do catálogo: mini cena desenhada em código (robô + plataforma +
/// bandeira) — identidade própria NEON HOPPER, zero assets.
class NeonHopperThumbPainter extends CustomPainter {
  const NeonHopperThumbPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF04040C),
    );
    // Starfield fixo.
    final Paint star = Paint()..color = AppColors.cyan.withValues(alpha: 0.6);
    for (int i = 0; i < 24; i++) {
      final double sx = NeonHopperPainter._hash(i * 2.7) * size.width;
      final double sy = NeonHopperPainter._hash(i * 9.1) * size.height * 0.7;
      canvas.drawCircle(Offset(sx, sy), 1.2, star);
    }

    final double u = size.shortestSide / 24; // unidade pixel da mini cena

    // Plataforma neon.
    final Rect plat = Rect.fromLTWH(size.width * 0.08, size.height * 0.72,
        size.width * 0.84, u * 1.6);
    canvas.drawRect(plat, Paint()..color = const Color(0xFF101032));
    canvas.drawRect(
      Rect.fromLTWH(plat.left, plat.top, plat.width, u * 0.5),
      Paint()..color = AppColors.cyan,
    );

    // Bandeira à direita.
    final double fx = size.width * 0.82;
    canvas.drawRect(
      Rect.fromLTWH(fx, plat.top - u * 7, u * 0.5, u * 7),
      Paint()..color = AppColors.textSecondary,
    );
    canvas.drawCircle(
      Offset(fx + u * 0.25, plat.top - u * 7),
      u * 0.9,
      Paint()..color = AppColors.gold,
    );

    // Robô (mini matriz 6×6 simplificada do sprite 12×12).
    const List<List<int>> mini = <List<int>>[
      <int>[0, 1, 1, 1, 1, 0],
      <int>[0, 1, 3, 1, 3, 0],
      <int>[0, 0, 1, 1, 1, 0],
      <int>[0, 1, 1, 1, 1, 0],
      <int>[0, 1, 0, 0, 1, 0],
      <int>[0, 1, 0, 0, 1, 0],
    ];
    final double bx = size.width * 0.18;
    final double by = plat.top - u * 6;
    for (int r = 0; r < mini.length; r++) {
      for (int c = 0; c < mini[r].length; c++) {
        final int idx = mini[r][c];
        if (idx == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(bx + c * u, by + r * u, u, u),
          Paint()..color = kHopperPalette[idx]!,
        );
      }
    }

    // Moedas flutuando.
    final Paint coin = Paint()..color = AppColors.gold;
    canvas.drawCircle(Offset(size.width * 0.48, size.height * 0.42), u * 0.9, coin);
    canvas.drawCircle(Offset(size.width * 0.62, size.height * 0.30), u * 0.9, coin);
  }

  @override
  bool shouldRepaint(covariant NeonHopperThumbPainter oldDelegate) => false;
}
