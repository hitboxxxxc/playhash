import 'dart:ui';

/// Entidades IMUTÁVEIS da engine NOVA SWARM. Um estado novo por frame —
/// nenhuma entidade é mutada in-place (facilita teste e evita bugs de
/// aliasing). Sprites são 100% código (ver [renderer.dart]).

/// Variantes de inimigo — pixel-art ORIGINAL definida por matrizes const.
enum EnemyVariant { drone, wasp, elite }

/// Inimigo da formação (posição = centro, em px lógicos do campo).
///
/// Um inimigo pode virar "diver" (mergulho programado): abandona o slot,
/// desce em trajetória senoidal até a região do jogador, atira 1 vez na
/// altura ~40% e, ao passar do fundo, retorna ao slot com fade de 0.5s.
class Enemy {
  const Enemy({
    required this.x,
    required this.y,
    required this.variant,
    required this.hp,
    required this.row,
    required this.col,
    this.hitFlashUntil = -1,
    this.isDiver = false,
    this.diveStartAt = -1,
    this.diveFromX = 0,
    this.diveFromY = 0,
    this.diveTargetX = 0,
    this.hasFired = false,
    this.returnStartedAt = -1,
  });

  final double x;
  final double y;
  final EnemyVariant variant;
  final int hp;
  final int row;
  final int col;

  /// Instante (tempo de jogo) até o qual o inimigo pisca branco (hit 1).
  final double hitFlashUntil;

  // ---- Estado de mergulho (v2) --------------------------------------------
  final bool isDiver;
  final double diveStartAt; // início do mergulho (tempo de jogo)
  final double diveFromX; // slot de origem (x)
  final double diveFromY; // slot de origem (y)
  final double diveTargetX; // x do jogador no momento do mergulho
  final bool hasFired; // já disparou a orbe na altura ~40%
  final double returnStartedAt; // início do retorno (-1 = não retornando)

  bool get isReturning => returnStartedAt >= 0;

  Enemy withPosition(double newX, double newY) => Enemy(
        x: newX,
        y: newY,
        variant: variant,
        hp: hp,
        row: row,
        col: col,
        hitFlashUntil: hitFlashUntil,
        isDiver: isDiver,
        diveStartAt: diveStartAt,
        diveFromX: diveFromX,
        diveFromY: diveFromY,
        diveTargetX: diveTargetX,
        hasFired: hasFired,
        returnStartedAt: returnStartedAt,
      );

  Enemy withHp(int newHp, double now, {required double flashDuration}) => Enemy(
        x: x,
        y: y,
        variant: variant,
        hp: newHp,
        row: row,
        col: col,
        hitFlashUntil: newHp < hp ? now + flashDuration : hitFlashUntil,
        isDiver: isDiver,
        diveStartAt: diveStartAt,
        diveFromX: diveFromX,
        diveFromY: diveFromY,
        diveTargetX: diveTargetX,
        hasFired: hasFired,
        returnStartedAt: returnStartedAt,
      );

  /// Converte o inimigo em diver (mantém todo o resto).
  Enemy startDive({
    required double now,
    required double fromX,
    required double fromY,
    required double targetX,
  }) =>
      Enemy(
        x: x,
        y: y,
        variant: variant,
        hp: hp,
        row: row,
        col: col,
        hitFlashUntil: hitFlashUntil,
        isDiver: true,
        diveStartAt: now,
        diveFromX: fromX,
        diveFromY: fromY,
        diveTargetX: targetX,
        hasFired: false,
        returnStartedAt: -1,
      );

  Enemy withDiveState({
    double? x,
    double? y,
    bool? hasFired,
    double? returnStartedAt,
  }) =>
      Enemy(
        x: x ?? this.x,
        y: y ?? this.y,
        variant: variant,
        hp: hp,
        row: row,
        col: col,
        hitFlashUntil: hitFlashUntil,
        isDiver: isDiver,
        diveStartAt: diveStartAt,
        diveFromX: diveFromX,
        diveFromY: diveFromY,
        diveTargetX: diveTargetX,
        hasFired: hasFired ?? this.hasFired,
        returnStartedAt: returnStartedAt ?? this.returnStartedAt,
      );

  /// Encerra o ciclo de mergulho: volta ao formato de formação no slot.
  Enemy endDive({required double x, required double y}) => Enemy(
        x: x,
        y: y,
        variant: variant,
        hp: hp,
        row: row,
        col: col,
        hitFlashUntil: hitFlashUntil,
      );
}

/// Tiro. Do jogador (sobe, ciano) ou da FORMAÇÃO/DIVER (desce, orbe laranja).
/// Construtor compatível com v1: `Bullet(x:, y:)` = tiro do jogador.
class Bullet {
  const Bullet({
    required this.x,
    required this.y,
    this.vy = -520,
    this.isEnemy = false,
  });

  final double x;
  final double y;

  /// Velocidade vertical (px/s). Jogador: negativa (sobe); inimigo: positiva.
  final double vy;

  /// true = orbe inimiga (esfera laranja 6dp com glow).
  final bool isEnemy;

  Bullet withY(double newY) => Bullet(x: x, y: newY, vy: vy, isEnemy: isEnemy);

  Bullet withPosition(double newX, double newY) =>
      Bullet(x: newX, y: newY, vy: vy, isEnemy: isEnemy);
}

/// Partícula de explosão (pool limitado; fade 350ms).
class Particle {
  const Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.bornAt,
    required this.life,
    required this.color,
    required this.size,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double bornAt;
  final double life;
  final Color color;
  final double size;

  Particle withPosition(double newX, double newY) => Particle(
        x: newX,
        y: newY,
        vx: vx,
        vy: vy,
        bornAt: bornAt,
        life: life,
        color: color,
        size: size,
      );
}

/// Explosão STARBURST (v2): estrela de 5–6 pontas + anel, cor por variante.
class Shockwave {
  const Shockwave({
    required this.x,
    required this.y,
    required this.bornAt,
    this.life = 0.35,
    this.color = const Color(0xFF7DF3FF),
    this.starPoints = 6,
  });

  final double x;
  final double y;
  final double bornAt;
  final double life;
  final Color color;

  /// Nº de pontas da estrela (5 ou 6, alternado por explosão).
  final int starPoints;
}

/// Power-up que cai (120px/s) e é apanhado pela nave. Desenho 100% código:
/// SHIELD = domo azul · DOUBLE = par de bolts · COIN = moeda hex própria.
enum PowerUpType { shield, doubleShot, coin }

class PowerUp {
  const PowerUp({
    required this.type,
    required this.x,
    required this.y,
    required this.bornAt,
  });

  final PowerUpType type;
  final double x;
  final double y;

  /// Nascimento (tempo de jogo) — usado para o pulso/rotação do ícone.
  final double bornAt;

  PowerUp withPosition(double newX, double newY) =>
      PowerUp(type: type, x: newX, y: newY, bornAt: bornAt);
}

/// Texto flutuante ("+250" da moeda): sobe 30px/s com fade de ~0.9s.
class FloatingText {
  const FloatingText({
    required this.text,
    required this.x,
    required this.y,
    required this.bornAt,
    this.life = 0.9,
    this.color = const Color(0xFFFFC400),
  });

  final String text;
  final double x;
  final double y;
  final double bornAt;
  final double life;
  final Color color;

  FloatingText withPosition(double newX, double newY) => FloatingText(
        text: text,
        x: newX,
        y: newY,
        bornAt: bornAt,
        life: life,
        color: color,
      );
}

/// Estrela do starfield (3 camadas parallax + twinkle senoidal).
class Star {
  const Star({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.baseAlpha,
    required this.phase,
    required this.twinkleFreq,
    required this.color,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final double baseAlpha;
  final double phase;
  final double twinkleFreq;
  final Color color;

  Star withPosition(double newX, double newY) => Star(
        x: newX,
        y: newY,
        size: size,
        speed: speed,
        baseAlpha: baseAlpha,
        phase: phase,
        twinkleFreq: twinkleFreq,
        color: color,
      );
}

/// Estrela cadente rara (a cada 6–12s).
class ShootingStar {
  const ShootingStar({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.bornAt,
    this.life = 0.9,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double bornAt;
  final double life;

  ShootingStar withPosition(double newX, double newY) => ShootingStar(
        x: newX,
        y: newY,
        vx: vx,
        vy: vy,
        bornAt: bornAt,
        life: life,
      );
}
