import 'dart:math';
import 'dart:ui';

import 'dive_controller.dart';
import 'entities.dart';
import 'formation_controller.dart';
import 'game_state.dart';
import 'powerups.dart';
import 'wave_spawner.dart';

/// Física/simulação PURA do NOVA SWARM (sem I/O, sem Flutter — testável).
///
/// Eventos emitidos por frame para a camada de apresentação (haptics etc.).
enum GameEvent {
  enemyKilled,
  eliteKilled,
  diverKilled,
  lifeLost,
  waveCleared,
  shieldAbsorbed,
  powerupCollected,
}

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

  /// Descida lenta da formação — REMOVIDA na v2: a formação fica contida no
  /// topo (8% da altura) com sway limitado; sem descida não há drift.
  @Deprecated('v2: formação contida no topo; mantido só para referência')
  static const double formationDescent = 0;

  /// Fade de partícula (s) e velocidades radiais (px/s).
  static const double particleLife = 0.35;
  static const double particleSpeedMin = 60;
  static const double particleSpeedMax = 140;

  /// Duração do banner "WAVE N" (s) e do shake (s).
  static const double bannerDuration = 1.0;
  static const double shakeDuration = 0.12;

  /// Margem interna de clamp do jogador nas bordas (dp) — mesma usada pelo
  /// input (ver [NovaSwarmInputController]).
  static const double playerMargin = 26;

  /// Pool máximo de partículas simultâneas (performance 60fps).
  static const int maxParticles = 80;

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
  final NovaSwarmConfig cfg = s.config;

  // ---- Jogador: lerp ao alvo + clamp nas bordas + bank ±10° -------------
  final double lerp = NovaSwarmPhysics.frameLerp(dt);
  final double half = NovaSwarmState.playerWidth / 2;
  final double minX = half + NovaSwarmPhysics.playerMargin;
  final double maxX = field.width - half - NovaSwarmPhysics.playerMargin;
  final double playerX =
      (s.playerX + (s.playerTargetX - s.playerX) * lerp)
          .clamp(minX, maxX < minX ? field.width / 2 : maxX)
          .toDouble();
  final double velocity = (s.playerTargetX - s.playerX);
  final double bank = (velocity / 220.0).clamp(-1.0, 1.0) * (10 * pi / 180);
  final double playerY = s.playerY;

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

  // ---- Formação CONTIDA (v2): sway limitado + bob; SEM descida -----------
  final int waveEnemyCount = WaveSpawner.enemyCountForWave(
    s.wave,
    baseEnemies: cfg.baseEnemies,
    enemiesPerWaveStep: cfg.enemiesPerWaveStep,
  );
  final FormationGeometry geo = FormationController.compute(
    enemyCount: waveEnemyCount,
    fieldSize: field,
  );

  // ---- Tiros do jogador (com DOUBLE v2: 2 ou 3 bolts paralelos) ----------
  final List<Bullet> bullets = <Bullet>[];
  for (final Bullet b in s.bullets) {
    final double y = b.y + b.vy * dt;
    if (y >= -20 && y <= field.height + 20) bullets.add(b.withY(y));
  }
  double lastShotAt = s.lastShotAt;
  double muzzleUntil = s.muzzleUntil;
  if (s.shooting &&
      elapsed - lastShotAt >= NovaSwarmPhysics.fireCooldown &&
      s.enemies.isNotEmpty) {
    if (s.isDoubleActive && s.doubleLevel >= 3) {
      bullets.add(Bullet(x: playerX - 10, y: playerY - 26));
      bullets.add(Bullet(x: playerX, y: playerY - 30));
      bullets.add(Bullet(x: playerX + 10, y: playerY - 26));
    } else if (s.isDoubleActive) {
      bullets.add(Bullet(x: playerX - 8, y: playerY - 26));
      bullets.add(Bullet(x: playerX + 8, y: playerY - 26));
    } else {
      bullets.add(Bullet(x: playerX, y: playerY - 26));
    }
    lastShotAt = elapsed;
    muzzleUntil = elapsed + NovaSwarmPhysics.muzzleFlash;
  }

  // ---- Mergulhos programados (v2) ----------------------------------------
  double nextDiveAt = s.nextDiveAt;
  final bool anyDiving = s.enemies.any((Enemy e) => e.isDiver);
  if (elapsed >= nextDiveAt && !anyDiving && s.enemies.length > 1) {
    final List<bool> candidates = <bool>[
      for (final Enemy e in s.enemies) e.isDiver,
    ];
    final int idx = DiveController.pickDiverCandidate(candidates, random);
    if (idx >= 0) {
      final Enemy picked = s.enemies[idx];
      // Origem do mergulho = posição ATUAL do inimigo na formação.
      s.enemies[idx] = picked.startDive(
        now: elapsed,
        fromX: picked.x,
        fromY: picked.y,
        targetX: playerX,
      );
    }
    nextDiveAt = elapsed +
        DiveController.intervalForWave(
          wave: s.wave,
          baseSeconds: cfg.diveIntervalSeconds,
          minSeconds: cfg.diveIntervalMinSeconds,
          rampPerWave: cfg.diveRampPerWave,
        );
  }

  // ---- Tiros da formação (v2): intervalo ±2s aleatório --------------------
  double nextFormationShotAt = s.nextFormationShotAt;
  if (elapsed >= nextFormationShotAt) {
    final List<int> shooters = <int>[
      for (int i = 0; i < s.enemies.length; i++)
        if (!s.enemies[i].isDiver) i,
    ];
    if (shooters.isNotEmpty) {
      final Enemy shooter = s.enemies[shooters[random.nextInt(shooters.length)]];
      bullets.add(Bullet(
        x: shooter.x,
        y: shooter.y + 14,
        vy: cfg.enemyBulletSpeed,
        isEnemy: true,
      ));
    }
    nextFormationShotAt =
        elapsed + cfg.formationShotIntervalSeconds + (random.nextDouble() * 4 - 2);
  }

  // ---- Atualiza posição dos inimigos (formação + divers) ------------------
  // DELTA-SWAY (v2): a formação inteira se move pelo DELTA do offset senoidal
  // entre frames — soma telescópica exata (sway(t) − sway(t0)), ZERO drift
  // acumulado; amplitude contida ⇒ nunca sai da tela. Sem descida.
  final double dSway =
      FormationController.swayOffset(t: elapsed, amplitude: geo.amplitude) -
          FormationController.swayOffset(t: s.elapsed, amplitude: geo.amplitude);
  final double dBob = FormationController.bobOffset(elapsed) -
      FormationController.bobOffset(s.elapsed);
  final List<Enemy> enemies = <Enemy>[];
  for (final Enemy e in s.enemies) {
    if (!e.isDiver) {
      enemies.add(e.withPosition(e.x + dSway, e.y + dBob));
      continue;
    }
    // Diver em RETORNO ao slot (fade 0.5s).
    if (e.isReturning) {
      final double rp =
          DiveController.returnProgress(elapsed: elapsed, returnStartedAt: e.returnStartedAt);
      final Offset slot = geo.slotPosition(row: e.row, col: e.col, t: elapsed);
      if (rp >= 1) {
        enemies.add(e.endDive(x: slot.dx, y: slot.dy));
      } else {
        final double x = e.x + (slot.dx - e.x) * rp;
        final double y = field.height + 40 + (slot.dy - field.height - 40) * rp;
        enemies.add(e.withDiveState(x: x, y: y));
      }
      continue;
    }
    // Diver em DESCIDA senoidal.
    final double p = DiveController.progress(elapsed: elapsed, diveStartAt: e.diveStartAt);
    final Offset pos = DiveController.descentPosition(
      p: p,
      fromX: e.diveFromX,
      fromY: e.diveFromY,
      targetX: e.diveTargetX,
      fieldHeight: field.height,
    );
    bool hasFired = e.hasFired;
    if (!hasFired &&
        DiveController.crossedFireHeight(
          previousY: e.y,
          currentY: pos.dy,
          fieldHeight: field.height,
        ) &&
        random.nextDouble() < DiveController.fireChance) {
      hasFired = true;
      bullets.add(Bullet(
        x: pos.dx,
        y: pos.dy + 14,
        vy: cfg.enemyBulletSpeed,
        isEnemy: true,
      ));
    }
    if (p >= 1) {
      // Passou do fundo ⇒ inicia retorno ao slot (fade 0.5s).
      enemies.add(e.withDiveState(
        x: pos.dx,
        y: pos.dy,
        hasFired: hasFired,
        returnStartedAt: elapsed,
      ));
    } else {
      enemies.add(e.withDiveState(x: pos.dx, y: pos.dy, hasFired: hasFired));
    }
  }

  // ---- Colisões tiro × inimigo -------------------------------------------
  final List<Particle> particles = List<Particle>.of(s.particles);
  final List<Shockwave> shockwaves = List<Shockwave>.of(s.shockwaves);
  int score = s.score;
  int kills = s.kills;
  int hits = s.hits;
  final List<Bullet> liveBullets = <Bullet>[];

  final Set<int> deadBullets = <int>{};
  final Map<int, int> damage = <int, int>{};
  for (int bi = 0; bi < bullets.length; bi++) {
    final Bullet b = bullets[bi];
    if (b.isEnemy) continue;
    for (int ei = 0; ei < enemies.length; ei++) {
      if (deadBullets.contains(bi)) break;
      if (damage.containsKey(ei) && damage[ei]! >= 2) continue;
      final Enemy e = enemies[ei];
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

  final List<PowerUp> powerUps = List<PowerUp>.of(s.powerUps);
  for (int ei = enemies.length - 1; ei >= 0; ei--) {
    final Enemy e = enemies[ei];
    final int dmg = damage[ei] ?? 0;
    if (dmg == 0) continue;
    final int newHp = e.hp - dmg;
    if (newHp <= 0) {
      kills += 1;
      score += cfg.pointsPerKill + (e.isDiver ? cfg.diverKillBonus : 0);
      events.add(e.isDiver
          ? GameEvent.diverKilled
          : (e.variant == EnemyVariant.elite
              ? GameEvent.eliteKilled
              : GameEvent.enemyKilled));
      _spawnParticles(particles, e.x, e.y, e.variant, elapsed, random);
      shockwaves.add(_starburst(e, elapsed));
      // Drop de power-up (chances da config do backend).
      final PowerUpType? drop = PowerUpSystem.rollDrop(
        rng: random,
        shieldChance: cfg.shieldChance,
        doubleChance: cfg.doubleChance,
        coinChance: cfg.coinChance,
      );
      if (drop != null) {
        powerUps.add(PowerUp(type: drop, x: e.x, y: e.y, bornAt: elapsed));
      }
      enemies.removeAt(ei);
    } else {
      hits += dmg;
      score += cfg.pointsPerHit * dmg;
      enemies[ei] = e.withHp(newHp, elapsed,
          flashDuration: NovaSwarmPhysics.hitFlash);
    }
  }

  // ---- DANO NO JOGADOR (v2): orbes inimigas + toque em inimigo/diver ------
  int lives = s.lives;
  double invulnUntil = s.invulnUntil;
  double shakeUntil = s.shakeUntil;
  double shieldUntil = s.shieldUntil;

  /// Aplica dano: escudo consome ANTES da vida.
  void damagePlayer() {
    if (elapsed < shieldUntil) {
      // Escudo absorve o hit (consome o domo inteiro).
      shieldUntil = -1;
      invulnUntil = elapsed + NovaSwarmPhysics.invulnerability;
      events.add(GameEvent.shieldAbsorbed);
      return;
    }
    lives -= 1;
    invulnUntil = elapsed + NovaSwarmPhysics.invulnerability;
    shakeUntil = elapsed + NovaSwarmPhysics.shakeDuration;
    events.add(GameEvent.lifeLost);
  }

  // Orbes inimigas × jogador.
  for (int bi = liveBullets.length - 1; bi >= 0; bi--) {
    final Bullet b = liveBullets[bi];
    if (!b.isEnemy || lives <= 0 || elapsed < invulnUntil) continue;
    final Rect playerBox = Rect.fromCenter(
      center: Offset(playerX, playerY),
      width: NovaSwarmState.playerWidth * 0.7,
      height: NovaSwarmState.playerWidth * 0.7,
    );
    if (NovaSwarmPhysics.circleAabb(
      cx: b.x,
      cy: b.y,
      radius: 5,
      box: playerBox,
    )) {
      liveBullets.removeAt(bi);
      damagePlayer();
    }
  }

  // Corpo do inimigo (formação ou diver) × jogador.
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
        damagePlayer();
        _spawnParticles(particles, e.x, e.y, e.variant, elapsed, random);
        shockwaves.add(_starburst(e, elapsed));
        enemies.removeAt(ei);
        break;
      }
    }
  }

  // ---- Power-ups: queda + coleta (v2) --------------------------------------
  final List<FloatingText> floatingTexts = List<FloatingText>.of(s.floatingTexts);
  int coinsCollected = s.coinsCollected;
  int shieldsCollected = s.shieldsCollected;
  int doublesCollected = s.doublesCollected;
  int doubleLevel = s.doubleLevel;
  double doubleUntil = s.doubleUntil;

  final List<PowerUp> falling =
      PowerUpSystem.advanceFall(powerUps, dt, field.height);
  powerUps.clear();
  powerUps.addAll(falling);

  final int pickupIdx = PowerUpSystem.pickUpIndex(
    powerUps: powerUps,
    playerX: playerX,
    playerY: playerY,
  );
  if (pickupIdx >= 0) {
    final PowerUp pu = powerUps.removeAt(pickupIdx);
    events.add(GameEvent.powerupCollected);
    switch (pu.type) {
      case PowerUpType.shield:
        shieldsCollected += 1;
        shieldUntil = elapsed + cfg.shieldSeconds;
        break;
      case PowerUpType.doubleShot:
        doublesCollected += 1;
        // Já ativo ⇒ nível sobe para 3; senão nível 2 (2 bolts).
        doubleLevel = s.isDoubleActive ? 3 : 2;
        doubleUntil = elapsed + cfg.doubleSeconds;
        break;
      case PowerUpType.coin:
        coinsCollected += 1;
        score += cfg.coinBonus;
        floatingTexts.add(FloatingText(
          text: '+${cfg.coinBonus}',
          x: pu.x,
          y: pu.y,
          bornAt: elapsed,
        ));
        break;
    }
  }

  // Textos flutuantes expirados + subida suave.
  for (int i = floatingTexts.length - 1; i >= 0; i--) {
    final FloatingText ft = floatingTexts[i];
    if (elapsed - ft.bornAt > ft.life) {
      floatingTexts.removeAt(i);
    } else {
      floatingTexts[i] = ft.withPosition(ft.x, ft.y - 30 * dt);
    }
  }

  // ---- Partículas/anéis expirados (pool limitado) --------------------------
  particles.removeWhere((Particle p) => elapsed - p.bornAt >= p.life);
  while (particles.length > NovaSwarmPhysics.maxParticles) {
    particles.removeAt(0);
  }
  for (int i = 0; i < particles.length; i++) {
    final Particle p = particles[i];
    particles[i] = p.withPosition(p.x + p.vx * dt, p.y + p.vy * dt);
  }
  shockwaves.removeWhere((Shockwave w) => elapsed - w.bornAt >= w.life);

  // ---- Fim de onda / próxima onda -----------------------------------------
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
        topY: FormationController.topFor(field.height),
        // Spawn na MESMA referência absoluta do delta-sway (sem salto).
        offsetX: FormationController.swayOffset(
          t: elapsed,
          amplitude: geo.amplitude,
        ),
        offsetY: FormationController.bobOffset(elapsed),
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
    powerUps: powerUps,
    floatingTexts: floatingTexts,
    shieldUntil: shieldUntil,
    doubleUntil: doubleUntil,
    doubleLevel: doubleLevel,
    nextDiveAt: nextDiveAt,
    nextFormationShotAt: nextFormationShotAt,
    coinsCollected: coinsCollected,
    shieldsCollected: shieldsCollected,
    doublesCollected: doublesCollected,
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

/// Starburst: estrela de 5–6 pontas alternadas + cor por variante.
Shockwave _starburst(Enemy e, double now) {
  final Color color = switch (e.variant) {
    EnemyVariant.drone => const Color(0xFFFF5252),
    EnemyVariant.wasp => const Color(0xFF7C4DFF),
    EnemyVariant.elite => const Color(0xFFFFC400),
  };
  return Shockwave(
    x: e.x,
    y: e.y,
    bornAt: now,
    color: color,
    starPoints: e.row.isEven ? 6 : 5,
  );
}

/// Pool limitado: no máximo 10 partículas por explosão (2–3px).
void _spawnParticles(
  List<Particle> particles,
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
  for (int i = 0; i < 10; i++) {
    final double angle = rng.nextDouble() * 2 * pi;
    final double speed =
        NovaSwarmPhysics.particleSpeedMin +
            rng.nextDouble() *
                (NovaSwarmPhysics.particleSpeedMax -
                    NovaSwarmPhysics.particleSpeedMin);
    particles.add(
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
}
