import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sprites PRÓPRIOS da nave do jogador (docs 02: assets próprios do projeto
/// são permitidos; INIMIGOS permanecem desenhados em código).
///
/// Artes do dono em assets/nave/: idle.png (parada), esquerda.png (inclinada
/// à esquerda), direita.png (inclinada à direita) e capa.png (thumbnail do
/// card NOVA SWARM na aba JOGAR). Os PNGs possuem alpha próprio e SEM rastro
/// de motor ⇒ sprite puro (o flame/glow em código foi removido).
abstract final class PlayerShipSprites {
  static const String idle = 'assets/nave/idle.png';
  static const String left = 'assets/nave/esquerda.png';
  static const String right = 'assets/nave/direita.png';

  /// Capa do card NOVA SWARM no catálogo (aba JOGAR).
  static const String capa = 'assets/nave/capa.png';

  /// Todos os assets de nave (para precache em lote).
  static const List<String> all = <String>[idle, left, right, capa];

  /// Largura renderizada (dp) — proporção do PNG preservada.
  /// v3: DOBRO do tamanho anterior (56 → 112).
  static const double width = 112;

  /// Proporção real dos sprites (461×1024): altura = largura × [aspect].
  static const double aspect = 1024 / 461;

  /// Zona morta da velocidade horizontal (px/s): |v| abaixo disso = idle.
  static const double epsilon = 12;

  /// Histerese anti-flicker: permanência mínima em cada estado (s).
  static const double hysteresisSeconds = 0.12;
}

/// Estado de inclinação da nave — mapeia 1:1 para o asset correspondente.
enum ShipTilt { left, idle, right }

/// Asset correspondente a cada tilt.
extension ShipTiltAsset on ShipTilt {
  String get assetPath => switch (this) {
        ShipTilt.left => PlayerShipSprites.left,
        ShipTilt.idle => PlayerShipSprites.idle,
        ShipTilt.right => PlayerShipSprites.right,
      };
}

/// Tilt desejado a partir da velocidade horizontal (px/s):
/// v < −ε → left · v > ε → right · caso contrário → idle.
ShipTilt desiredShipTilt(double vx) {
  if (vx < -PlayerShipSprites.epsilon) return ShipTilt.left;
  if (vx > PlayerShipSprites.epsilon) return ShipTilt.right;
  return ShipTilt.idle;
}

/// Avança o tilt com HISTERESE (dwell mínimo de ~120ms por estado) para
/// evitar flicker entre sprites em movimentos oscilantes.
///
/// Retorna `(novo tilt, instante da última troca)` — função PURA (a troca só
/// ocorre se o estado desejado diferir do atual E o dwell mínimo expirar).
(ShipTilt, double) advanceShipTilt({
  required ShipTilt current,
  required double lastChangeAt,
  required double vx,
  required double elapsed,
}) {
  final ShipTilt desired = desiredShipTilt(vx);
  if (desired == current) return (current, lastChangeAt);
  if (elapsed - lastChangeAt < PlayerShipSprites.hysteresisSeconds) {
    return (current, lastChangeAt);
  }
  return (desired, elapsed);
}

/// Sprite do jogador renderizado via [Image.asset] (cache automático após
/// precache — ZERO alocação por frame) com as camadas de invulnerabilidade
/// (anel) e domo de escudo desenhadas POR CIMA do PNG.
///
/// Deve ser filho DIRETO da Stack do playfield (usa [Positioned]).
class PlayerShipSprite extends StatelessWidget {
  const PlayerShipSprite({
    super.key,
    required this.tilt,
    required this.x,
    required this.y,
    required this.blinkVisible,
    required this.showInvulnRing,
    required this.showShieldDome,
    required this.elapsed,
  });

  /// Tilt atual (seleciona idle/esquerda/direita).
  final ShipTilt tilt;

  /// Centro da nave no campo (px) — mesma âncora da hitbox.
  final double x;
  final double y;

  /// false durante a fase "apagada" do piscar de invulnerabilidade (8Hz).
  final bool blinkVisible;

  final bool showInvulnRing;
  final bool showShieldDome;
  final double elapsed;

  @override
  Widget build(BuildContext context) {
    final double w = PlayerShipSprites.width;
    final double h = w * PlayerShipSprites.aspect;
    // Escala relativa ao desenho antigo (52dp) — escudo/anel mantêm tamanho.
    final double k = w / 52;
    return Positioned(
      left: x - w / 2,
      top: y - h / 2,
      width: w,
      height: h,
      child: Stack(
        children: <Widget>[
          // Sprite puro (sem flame/glow em código — o PNG não tem rastro).
          Opacity(
            opacity: blinkVisible ? 1 : 0,
            child: Image.asset(
              tilt.assetPath,
              width: w,
              height: h,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true, // troca de tilt sem pop de carregamento
            ),
          ),
          // Invulnerabilidade (piscar α) e domo de escudo SOBRE o sprite.
          if (showInvulnRing || showShieldDome)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ShieldOverlayPainter(
                    showRing: showInvulnRing,
                    showDome: showShieldDome,
                    elapsed: elapsed,
                    scale: k,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Anel de invulnerabilidade + domo de escudo (mesmos visuais do desenho em
/// código anterior, escalados por [scale] e centralizados na caixa do sprite).
class _ShieldOverlayPainter extends CustomPainter {
  _ShieldOverlayPainter({
    required this.showRing,
    required this.showDome,
    required this.elapsed,
    required this.scale,
  });

  final bool showRing;
  final bool showDome;
  final double elapsed;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint();
    final Offset center = Offset(size.width / 2, size.height / 2);

    // Anel de escudo ciano durante invulnerabilidade.
    if (showRing) {
      p
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, 34 * scale, p);
    }

    // DOMO DE ESCUDO: azul translúcido pulsando levemente.
    if (showDome) {
      final double pulse =
          1 + 0.04 * math.sin(elapsed * 6 * math.pi);
      final Rect domeRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.545),
        width: 84 * scale * pulse,
        height: 76 * scale * pulse,
      );
      p
        ..color = const Color(0xFF2979FF).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;
      canvas.drawArc(domeRect, math.pi, math.pi, true, p);
      p
        ..color = const Color(0xFF7DD3FF).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawArc(domeRect, math.pi, math.pi, true, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ShieldOverlayPainter oldDelegate) =>
      oldDelegate.showRing != showRing ||
      oldDelegate.showDome != showDome ||
      oldDelegate.elapsed != elapsed;
}
