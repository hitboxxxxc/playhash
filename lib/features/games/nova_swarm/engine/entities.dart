import 'dart:ui';

/// Entidades IMUTÁVEIS da engine NOVA SWARM. Um estado novo por frame —
/// nenhuma entidade é mutada in-place (facilita teste e evita bugs de
/// aliasing). Sprites são 100% código (ver [renderer.dart]).

/// Variantes de inimigo — pixel-art ORIGINAL definida por matrizes const.
enum EnemyVariant { drone, wasp, elite }

/// Inimigo da formação (posição = centro, em px lógicos do campo).
class Enemy {
  const Enemy({
    required this.x,
    required this.y,
    required this.variant,
    required this.hp,
    required this.row,
    required this.col,
    this.hitFlashUntil = -1,
  });

  final double x;
  final double y;
  final EnemyVariant variant;
  final int hp;
  final int row;
  final int col;

  /// Instante (tempo de jogo) até o qual o inimigo pisca branco (hit 1).
  final double hitFlashUntil;

  Enemy withPosition(double newX, double newY) => Enemy(
        x: newX,
        y: newY,
        variant: variant,
        hp: hp,
        row: row,
        col: col,
        hitFlashUntil: hitFlashUntil,
      );

  Enemy withHp(int newHp, double now, {required double flashDuration}) => Enemy(
        x: x,
        y: y,
        variant: variant,
        hp: newHp,
        row: row,
        col: col,
        hitFlashUntil: newHp < hp ? now + flashDuration : hitFlashUntil,
      );
}

/// Tiro do jogador (sobe; sem tiros inimigos na v1 — dificuldade fácil).
class Bullet {
  const Bullet({required this.x, required this.y});

  final double x;
  final double y;

  Bullet withY(double newY) => Bullet(x: x, y: newY);
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

/// Anel de choque da explosão (raio → 26dp, alpha → 0).
class Shockwave {
  const Shockwave({
    required this.x,
    required this.y,
    required this.bornAt,
    this.life = 0.35,
  });

  final double x;
  final double y;
  final double bornAt;
  final double life;
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
