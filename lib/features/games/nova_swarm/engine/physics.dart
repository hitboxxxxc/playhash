import 'dart:math';
import 'dart:ui';

import 'entities.dart';
import 'game_state.dart';
import 'wave_spawner.dart';

/// Física/simulação PURA do NOVA SWARM (sem I/O, sem Flutter — testável).
///
/// Eventos emitidos por frame para a camada de apresentação (haptics etc.).
enum GameEvent { enemyKilled, eliteKilled, lifeLost, waveCleared }

/// Resultado de um passo: novo estado + eventos ocorridos.
class StepResult {
  const StepResult(this.state, this.events);

  final NovaSwarmState state;
  final List<GameEvent> events;
}

/// Constantes de sensação/ritmo (inspiração arcade original — nada copiado).
abstract final class NovaSwarmPhysics {
  /// Lerp do jogador por frame @60fps (0.22/frame conforme spec).
  static const double playerLerpPerFrame = 0.22;

  /// Velocidade do tiro do jogador (px/s).
  static const double bulletSpeed = 520;

  /// Cooldown de tiro (s) — SOMENTE enquanto tocando.
  static const double fireCooldown = 0.16;

  /// Duração do muzzle flash (s).
  static const double muzzleFlash = 0.06;

  /// Flash branco ao acertar inimigo (s).
  static const double hitFlash = 0.08;

  /// Invulnerabilidade pós-colisão (s).
  static const double invulnerability = 1.5;

  /// Sway senoidal da formação: amplitude (px) e frequência (Hz).
  static const double swayAmplitude = 18;
  static const double swayFrequency = 0.5;

  /// Descida lenta da formação (px/s).
  static const double formationDescent = 5;

  /// Fade de partícula (s) e velocidades radiais (px/s).
  static const double particleLife = 0.35;
  static const double particleSpeedMin = 60;
  static const double particleSpeedMax = 140;

  /// Duração do banner "WAVE N" (s) e do shake (s).
  static const double bannerDuration = 1.0;
  static const double shakeDuration = 0.12;

  /// Fator de lerp normalizado ao frame (independe de fps).
  static double frameLerp(double dt) =>
      1 - pow(1 - playerLerpPerFrame, dt * 60).toDouble();

  /// Colisão círculo-AABB.
  static bool circleAabb({
    required double cx,
    required double cy,
    required double radius,
    required Rect box,
  }) {
    final double nx = cx.clamp(box.left, box.right).toDouble();
    final double ny = cy.clamp(box.top, box.bottom).toDouble();
    final double dx = cx - nx;
    final double dy = cy - ny;
    return dx * dx + dy * dy <= radius * radius;
  }

  /// AABB de um inimigo (9×7 px × 3dp de pixel).
  static Rect enemyBox(Enemy e, {double pixel = 3}) => Rect.fromCenter(
        center: Offset(e.x, e.y),
        width: 9 * pixel,
        height: 7 * pixel,
      );
}

/// Avança a simulação em [dt] segundos (clamp feito pelo chamador).
StepResult step(NovaSwarmState s, double dt, {Random? rng}) {
  if (s.phase != NovaSwarmPhase.playing || s.endReason != null) {
    return StepResult(s, const <GameEvent>[]);
  }
  final Random random = rng ?? Random();
  final List<GameEvent> events = <GameEvent>[];
  final double elapsed = s.elapsed + dt;
  final double timeLeft = max(0, s.timeLeft - dt);
  final Size field = s.fieldSize;

  // ---- Jogador: lerp ao alvo + bank ±10° --------------------------------
  final double lerp = NovaSwarmPhysics.frameLerp(dt);
  final double playerX =
      s.playerX + (s.playerTargetX - s.playerX) * lerp;
  final double velocity = (s.playerTargetX - s.playerX);
  final double bank = (velocity / 220.0).clamp(-1.0, 1.0) * (10 * pi / 180);

  // ---- Starfield ---------------------------------------------------------
  final List<Star> stars = <Star>[];
  for (final Star star in s.stars) {
    double y = star.y + star.speed * dt;
    double x = star.x;
    if (y > field.height) {
      y -= field.height;
      x = random.nextDouble() * field.width;
    }
    stars.add(star.withPosition(x, y));
  }

  // Estrela cadente rara (a cada 6–12s).
  ShootingStar? shootingStar = s.shootingStar;
  double nextShootingStarAt = s.nextShootingStarAt;
  if (shootingStar != null &&
      elapsed - shootingStar.bornAt > shootingStar.life) {
    shootingStar = null;
  }
  if (shootingStar == null && elapsed >= nextShootingStarAt) {
    final double sx = random.nextDouble() * field.width * 0.8;
    shootingStar = ShootingStar(
      x: sx,
      y: random.nextDouble() * field.height * 0.3,
      vx: 220 + random.nextDouble() * 160,
      vy: 130 + random.nextDouble() * 90,
      bornAt: elapsed,
    );
    nextShootingStarAt = elapsed + 6 + random.nextDouble() * 6;
  }
  if (shootingStar != null) {
    shootingStar = shootingStar.withPosition(
      shootingStar.x + shootingStar.vx * dt,
      shootingStar.y + shootingStar.vy * dt,
    );
  }

  // ---- Formação: sway senoidal + descida lenta ---------------------------
  final double sway =
      sin(2 * pi * NovaSwarmPhysics.swayFrequency * elapsed) *
          NovaSwarmPhysics.swayAmplitude;
  final double descent = NovaSwarmPhysics.formationDescent * dt;

  // ---- Tiros do jogador ---------------------------------------------------
  final List<Bullet> bullets = <Bullet>[];
  for (final Bullet b in s.bullets) {
    final double y = b.y - NovaSwarmPhysics.bulletSpeed * dt;
    if (y >= -20) bullets.add(b.withY(y));
  }
  double lastShotAt = s.lastShotAt;
  double muzzleUntil = s.muzzleUntil;
  final double playerY = s.playerY;
  if (s.shooting &&
      elapsed - lastShotAt >= NovaSwarmPhysics.fireCooldown &&
      s.enemies.isNotEmpty) {
    bullets.add(Bullet(x: playerX, y: playerY - 26));
    lastShotAt = elapsed;
    muzzleUntil = elapsed + NovaSwarmPhysics.muzzleFlash;
  }

  // ---- Colisões tiro × inimigo -------------------------------------------
  final NovaSwarmConfig cfg = s.config;
  final List<Enemy> enemies = <Enemy>[];
  List<Particle> particles = s.particles;
  List<Shockwave> shockwaves = s.shockwaves;
  int score = s.score;
  int kills = s.kills;
  int hits = s.hits;
  final List<Bullet> liveBullets = <Bullet>[];

  final Set<int> deadBullets = <int>{};
  final Map<int, int> damage = <int, int>{};
  for (int bi = 0; bi < bullets.length; bi++) {
    final Bullet b = bullets[bi];
    for (int ei = 0; ei < s.enemies.length; ei++) {
      if (deadBullets.contains(bi)) break;
      if (damage.containsKey(ei) && damage[ei]! >= 2) continue;
      final Enemy e = s.enemies[ei];
      if (NovaSwarmPhysics.circleAabb(
        cx: b.x,
        cy: b.y,
        radius: 8,
        box: NovaSwarmPhysics.enemyBox(e),
      )) {
        deadBullets.add(bi);
        damage[ei] = (damage[ei] ?? 0) + 1;
      }
    }
  }

  for (int bi = 0; bi < bullets.length; bi++) {
    if (!deadBullets.contains(bi)) liveBullets.add(bullets[bi]);
  }

  for (int ei = 0; ei < s.enemies.length; ei++) {
    final Enemy e = s.enemies[ei];
    final int dmg = damage[ei] ?? 0;
    if (dmg == 0) {
      enemies.add(e.withPosition(e.x + sway, e.y + descent));
      continue;
    }
    final int newHp = e.hp - dmg;
    if (newHp <= 0) {
      // Explosão: partículas (pool limitado) + anel de choque.
      kills += 1;
      score += cfg.pointsPerKill;
      events.add(e.variant == EnemyVariant.elite
          ? GameEvent.eliteKilled
          : GameEvent.enemyKilled);
      particles = _spawnParticles(particles, e.x, e.y, e.variant, elapsed, random);
      shockwaves = <Shockwave>[
        ...shockwaves,
        Shockwave(x: e.x, y: e.y, bornAt: elapsed),
      ];
    } else {
      hits += dmg;
      score += cfg.pointsPerHit * dmg;
      enemies.add(e.withHp(newHp, elapsed, flashDuration: NovaSwarmPhysics.hitFlash)
          .withPosition(e.x + sway, e.y + descent));
    }
  }

  // ---- Colisão jogador × inimigo -----------------------------------------
  int lives = s.lives;
  double invulnUntil = s.invulnUntil;
  double shakeUntil = s.shakeUntil;
  if (lives > 0 && elapsed >= invulnUntil) {
    final Rect playerBox = Rect.fromCenter(
      center: Offset(playerX, playerY),
      width: NovaSwarmState.playerWidth * 0.7,
      height: NovaSwarmState.playerWidth * 0.7,
    );
    for (int ei = 0; ei < enemies.length; ei++) {
      final Enemy e = enemies[ei];
      if (NovaSwarmPhysics.circleAabb(
        cx: playerX,
        cy: playerY,
        radius: s.playerHitboxRadius,
        box: NovaSwarmPhysics.enemyBox(e),
      ) ||
          NovaSwarmPhysics.circleAabb(
            cx: e.x,
            cy: e.y,
            radius: 10,
            box: playerBox,
          )) {
        lives -= 1;
        invulnUntil = elapsed + NovaSwarmPhysics.invulnerability;
        shakeUntil = elapsed + NovaSwarmPhysics.shakeDuration;
        events.add(GameEvent.lifeLost);
        particles = _spawnParticles(particles, e.x, e.y, e.variant, elapsed, random);
        shockwaves = <Shockwave>[
          ...shockwaves,
          Shockwave(x: e.x, y: e.y, bornAt: elapsed),
        ];
        enemies.removeAt(ei);
        break;
      }
    }
  }

  // ---- Partículas/anéis expirados ----------------------------------------
  particles = particles
      .where((Particle p) => elapsed - p.bornAt < p.life)
      .toList(growable: false);
  for (int i = 0; i < particles.length; i++) {
    final Particle p = particles[i];
    particles[i] = p.withPosition(p.x + p.vx * dt, p.y + p.vy * dt);
  }
  shockwaves = shockwaves
      .where((Shockwave w) => elapsed - w.bornAt < w.life)
      .toList(growable: false);

  // ---- Fim de onda / próxima onda ----------------------------------------
  int wave = s.wave;
  String bannerText = s.bannerText;
  double bannerUntil = s.bannerUntil;
  if (enemies.isEmpty && lives > 0) {
    score += cfg.waveBonus;
    wave += 1;
    events.add(GameEvent.waveCleared);
    bannerText = 'WAVE $wave';
    bannerUntil = elapsed + NovaSwarmPhysics.bannerDuration;
    enemies.addAll(
      WaveSpawner.spawnWave(
        wave: wave,
        baseEnemies: cfg.baseEnemies,
        enemiesPerWaveStep: cfg.enemiesPerWaveStep,
        enemyHp: cfg.enemyHp,
        fieldWidth: field.width,
      ),
    );
  }

  // ---- Fim de partida ------------------------------------------------------
  NovaSwarmEndReason? endReason = s.endReason;
  if (lives <= 0) {
    endReason = NovaSwarmEndReason.dead;
  } else if (timeLeft <= 0) {
    endReason = NovaSwarmEndReason.timeUp;
  }

  final NovaSwarmState next = s.copyWith(
    elapsed: elapsed,
    timeLeft: timeLeft,
    playerX: playerX,
    playerBank: bank,
    lastShotAt: lastShotAt,
    muzzleUntil: muzzleUntil,
    enemies: enemies,
    bullets: liveBullets,
    particles: particles,
    shockwaves: shockwaves,
    stars: stars,
    shootingStar: shootingStar,
    nextShootingStarAt: nextShootingStarAt,
    score: score,
    kills: kills,
    hits: hits,
    wave: wave,
    lives: lives,
    bannerText: bannerText,
    bannerUntil: bannerUntil,
    shakeUntil: shakeUntil,
    invulnUntil: invulnUntil,
    endReason: endReason,
  );
  return StepResult(next, events);
}

/// Pool limitado: no máximo 10 partículas por explosão (2–3px).
List<Particle> _spawnParticles(
  List<Particle> current,
  double x,
  double y,
  EnemyVariant variant,
  double now,
  Random rng,
) {
  final Color base = switch (variant) {
    EnemyVariant.drone => const Color(0xFFFF5252),
    EnemyVariant.wasp => const Color(0xFF7C4DFF),
    EnemyVariant.elite => const Color(0xFFFFC400),
  };
  final List<Particle> next = current.length > 40
      ? <Particle>[...current.sublist(current.length - 40)]
      : <Particle>[...current];
  for (int i = 0; i < 10; i++) {
    final double angle = rng.nextDouble() * 2 * pi;
    final double speed =
        NovaSwarmPhysics.particleSpeedMin +
            rng.nextDouble() *
                (NovaSwarmPhysics.particleSpeedMax -
                    NovaSwarmPhysics.particleSpeedMin);
    next.add(
      Particle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        bornAt: now,
        life: NovaSwarmPhysics.particleLife,
        color: base,
        size: 2 + rng.nextDouble(),
      ),
    );
  }
  return next;
}
