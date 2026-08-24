import 'dart:math';

import 'entities.dart';

/// POWER-UPS (v2) — funções PURAS de sorteio, queda e coleta.
///
/// - Caem a 120px/s e são apanhados pela nave (raio de coleta generoso).
/// - SHIELD: domo azul translúcido absorve 1 hit (ou expira em 6s).
/// - DOUBLE: 2 bolts paralelos por 8s; pegando de novo com o ativo ativo,
///   o nível sobe para 3 (3 bolts).
/// - COIN: +250 pts com texto flutuante "+250".
abstract final class PowerUpSystem {
  /// Velocidade de queda (px/s).
  static const double fallSpeed = 120;

  /// Raio de coleta pela nave (dp) — hitbox generosa.
  static const double pickupRadius = 30;

  /// Sorteia o tipo dropado num abate a partir das chances da config
  /// (ordem: shield → double → coin). Retorna null na maioria dos abates.
  static PowerUpType? rollDrop({
    required Random rng,
    required double shieldChance,
    required double doubleChance,
    required double coinChance,
  }) {
    final double r = rng.nextDouble();
    double acc = shieldChance;
    if (r < acc) return PowerUpType.shield;
    acc += doubleChance;
    if (r < acc) return PowerUpType.doubleShot;
    acc += coinChance;
    if (r < acc) return PowerUpType.coin;
    return null;
  }

  /// Avança a queda do power-up; remove ao passar do fundo.
  static List<PowerUp> advanceFall(List<PowerUp> current, double dt, double fieldHeight) {
    final List<PowerUp> next = <PowerUp>[];
    for (final PowerUp p in current) {
      final double y = p.y + fallSpeed * dt;
      if (y <= fieldHeight + 24) next.add(p.withPosition(p.x, y));
    }
    return next;
  }

  /// Índice do power-up coletado pela nave (−1 = nenhum). Pega o mais próximo.
  static int pickUpIndex({
    required List<PowerUp> powerUps,
    required double playerX,
    required double playerY,
  }) {
    for (int i = 0; i < powerUps.length; i++) {
      final PowerUp p = powerUps[i];
      final double dx = p.x - playerX;
      final double dy = p.y - playerY;
      if (dx * dx + dy * dy <= pickupRadius * pickupRadius) return i;
    }
    return -1;
  }
}
