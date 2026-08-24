import 'dart:math';
import 'dart:ui';

import '../../../../data/models/game_model.dart';
import 'entities.dart';
import 'wave_spawner.dart';

/// Fase da partida dentro da engine.
enum NovaSwarmPhase { playing, paused, finished }

/// Motivo do fim da partida.
enum NovaSwarmEndReason { timeUp, dead }

/// Config de gameplay derivada da config RECEBIDA do backend (nunca
/// inventada no cliente). Valores 0 caem em padrões seguros de exibição.
/// Campos v2 (mergulhos, tiros inimigos, power-ups) têm defaults = config
/// autoritativa do backend (seed v2) para docs legados.
class NovaSwarmConfig {
  const NovaSwarmConfig({
    required this.durationSeconds,
    required this.baseEnemies,
    required this.enemiesPerWaveStep,
    required this.enemyHp,
    required this.lives,
    required this.pointsPerKill,
    required this.pointsPerHit,
    required this.waveBonus,
    this.diverKillBonus = 50,
    this.coinBonus = 250,
    this.diveIntervalSeconds = 3.0,
    this.diveIntervalMinSeconds = 1.2,
    this.diveRampPerWave = 0.05,
    this.formationShotIntervalSeconds = 4.0,
    this.enemyBulletSpeed = 220,
    this.diverSpeed = 260,
    this.shieldChance = 0.08,
    this.doubleChance = 0.10,
    this.coinChance = 0.12,
    this.shieldSeconds = 6,
    this.doubleSeconds = 8,
  });

  factory NovaSwarmConfig.fromGame(GameModel game) {
    final GameConfig c = game.configuration;
    return NovaSwarmConfig(
      durationSeconds: c.durationSeconds > 0 ? c.durationSeconds : 60,
      baseEnemies: c.baseEnemies > 0 ? c.baseEnemies : 8,
      enemiesPerWaveStep: c.enemiesPerWaveStep > 0 ? c.enemiesPerWaveStep : 4,
      enemyHp: c.enemyHp > 0 ? c.enemyHp : 2,
      lives: c.lives > 0 ? c.lives : 3,
      pointsPerKill: c.pointsPerKill,
      pointsPerHit: c.pointsPerHit,
      waveBonus: c.waveBonus,
      diverKillBonus: c.diverKillBonus,
      coinBonus: c.coinBonus,
      diveIntervalSeconds:
          c.diveIntervalSeconds > 0 ? c.diveIntervalSeconds : 3.0,
      diveIntervalMinSeconds: c.diveIntervalMinSeconds > 0
          ? c.diveIntervalMinSeconds
          : 1.2,
      diveRampPerWave: c.diveRampPerWave,
      formationShotIntervalSeconds: c.formationShotIntervalSeconds > 0
          ? c.formationShotIntervalSeconds
          : 4.0,
      enemyBulletSpeed: c.enemyBulletSpeed > 0 ? c.enemyBulletSpeed : 220,
      diverSpeed: c.diverSpeed > 0 ? c.diverSpeed : 260,
      shieldChance: c.shieldChance,
      doubleChance: c.doubleChance,
      coinChance: c.coinChance,
      shieldSeconds: c.shieldSeconds > 0 ? c.shieldSeconds : 6,
      doubleSeconds: c.doubleSeconds > 0 ? c.doubleSeconds : 8,
    );
  }

  final int durationSeconds;
  final int baseEnemies;
  final int enemiesPerWaveStep;
  final int enemyHp;
  final int lives;
  final int pointsPerKill;
  final int pointsPerHit;
  final int waveBonus;

  // ---- v2 ------------------------------------------------------------------
  final int diverKillBonus; // +50 por abate de diver
  final int coinBonus; // +250 por moeda
  final double diveIntervalSeconds; // 3.0s base entre mergulhos
  final double diveIntervalMinSeconds; // piso 1.2s
  final double diveRampPerWave; // −0.05s por wave
  final double formationShotIntervalSeconds; // 4.0s (±2s rand no cliente)
  final double enemyBulletSpeed; // 220 px/s
  final double diverSpeed; // 260 px/s
  final double shieldChance; // 0.08
  final double doubleChance; // 0.10
  final double coinChance; // 0.12
  final double shieldSeconds; // 6s
  final double doubleSeconds; // 8s
}

/// Estado IMUTÁVEL por frame. Tempo interno = "tempo de jogo" (só avança
/// quando playing) — pausa não consome timer nem animações.
class NovaSwarmState {
  NovaSwarmState({
    this.phase = NovaSwarmPhase.playing,
    this.elapsed = 0,
    required this.config,
    required this.fieldSize,
    double? timeLeft,
    this.playerX = 0,
    this.playerTargetX = 0,
    this.playerBank = 0,
    this.invulnUntil = -1,
    this.shooting = false,
    this.lastShotAt = -10,
    this.muzzleUntil = -1,
    this.enemies = const <Enemy>[],
    this.bullets = const <Bullet>[],
    this.particles = const <Particle>[],
    this.shockwaves = const <Shockwave>[],
    this.stars = const <Star>[],
    this.shootingStar,
    this.nextShootingStarAt = 0,
    this.powerUps = const <PowerUp>[],
    this.floatingTexts = const <FloatingText>[],
    this.shieldUntil = -1,
    this.doubleUntil = -1,
    this.doubleLevel = 0,
    this.nextDiveAt = 2.5,
    this.nextFormationShotAt = 3.0,
    this.coinsCollected = 0,
    this.shieldsCollected = 0,
    this.doublesCollected = 0,
    this.score = 0,
    this.kills = 0,
    this.hits = 0,
    this.wave = 1,
    this.lives = 3,
    this.bannerText = '',
    this.bannerUntil = -1,
    this.shakeUntil = -1,
    this.endReason,
  }) : timeLeft = timeLeft ?? config.durationSeconds.toDouble();

  final NovaSwarmConfig config;
  final Size fieldSize;
  final NovaSwarmPhase phase;
  final double elapsed;

  /// Tempo restante (s). 0 ⇒ fim vitorioso.
  final double timeLeft;

  // Jogador
  final double playerX;
  final double playerTargetX;
  final double playerBank; // rad, ±10°
  final double invulnUntil; // 1.5s pós-colisão
  final bool shooting;
  final double lastShotAt;
  final double muzzleUntil;

  // Entidades
  final List<Enemy> enemies;
  final List<Bullet> bullets; // jogador (sobe) + orbes inimigas (descem)
  final List<Particle> particles;
  final List<Shockwave> shockwaves; // starbursts
  final List<Star> stars;
  final ShootingStar? shootingStar;
  final double nextShootingStarAt;

  // Power-ups (v2)
  final List<PowerUp> powerUps;
  final List<FloatingText> floatingTexts;
  final double shieldUntil; // escudo ativo até (absorve 1 hit)
  final double doubleUntil; // tiro duplo/nível 3 até
  final int doubleLevel; // 0 inativo · 2 = 2 bolts · 3 = 3 bolts
  final int coinsCollected;
  final int shieldsCollected;
  final int doublesCollected;

  // Schedulers (v2)
  final double nextDiveAt; // próximo mergulho programado
  final double nextFormationShotAt; // próximo tiro da formação

  // Placar
  final int score;
  final int kills;
  final int hits;
  final int wave;
  final int lives;

  // Efeitos
  final String bannerText;
  final double bannerUntil;
  final double shakeUntil;

  final NovaSwarmEndReason? endReason;

  /// Y fixo do jogador: centro-x na criação, 80% da altura do campo —
  /// sempre dentro da área visível (independe de insets do dispositivo).
  double get playerY => fieldSize.height * 0.8;

  /// Largura do sprite do jogador (dp).
  static const double playerWidth = 52;

  /// Hitbox do jogador = 70% do sprite (tolerância generosa).
  double get playerHitboxRadius => playerWidth * 0.35;

  bool get isInvulnerable => elapsed < invulnUntil;

  bool get isShieldActive => elapsed < shieldUntil;

  bool get isDoubleActive => elapsed < doubleUntil && doubleLevel > 0;

  bool get isBannerActive => elapsed < bannerUntil;

  bool get isShaking => elapsed < shakeUntil;

  /// Score de EXIBIÇÃO (o oficial é o backend).
  int get displayScore => score;

  /// Total de power-ups coletados (painel final).
  int get totalPowerUpsCollected =>
      coinsCollected + shieldsCollected + doublesCollected;

  NovaSwarmState copyWith({
    NovaSwarmPhase? phase,
    double? elapsed,
    double? timeLeft,
    double? playerX,
    double? playerTargetX,
    double? playerBank,
    double? invulnUntil,
    bool? shooting,
    double? lastShotAt,
    double? muzzleUntil,
    List<Enemy>? enemies,
    List<Bullet>? bullets,
    List<Particle>? particles,
    List<Shockwave>? shockwaves,
    List<Star>? stars,
    Object? shootingStar = _sentinel,
    double? nextShootingStarAt,
    List<PowerUp>? powerUps,
    List<FloatingText>? floatingTexts,
    double? shieldUntil,
    double? doubleUntil,
    int? doubleLevel,
    double? nextDiveAt,
    double? nextFormationShotAt,
    int? coinsCollected,
    int? shieldsCollected,
    int? doublesCollected,
    int? score,
    int? kills,
    int? hits,
    int? wave,
    int? lives,
    String? bannerText,
    double? bannerUntil,
    double? shakeUntil,
    Object? endReason = _sentinel,
  }) =>
      NovaSwarmState(
        config: config,
        fieldSize: fieldSize,
        phase: phase ?? this.phase,
        elapsed: elapsed ?? this.elapsed,
        timeLeft: timeLeft ?? this.timeLeft,
        playerX: playerX ?? this.playerX,
        playerTargetX: playerTargetX ?? this.playerTargetX,
        playerBank: playerBank ?? this.playerBank,
        invulnUntil: invulnUntil ?? this.invulnUntil,
        shooting: shooting ?? this.shooting,
        lastShotAt: lastShotAt ?? this.lastShotAt,
        muzzleUntil: muzzleUntil ?? this.muzzleUntil,
        enemies: enemies ?? this.enemies,
        bullets: bullets ?? this.bullets,
        particles: particles ?? this.particles,
        shockwaves: shockwaves ?? this.shockwaves,
        stars: stars ?? this.stars,
        shootingStar: shootingStar == _sentinel
            ? this.shootingStar
            : shootingStar as ShootingStar?,
        nextShootingStarAt: nextShootingStarAt ?? this.nextShootingStarAt,
        powerUps: powerUps ?? this.powerUps,
        floatingTexts: floatingTexts ?? this.floatingTexts,
        shieldUntil: shieldUntil ?? this.shieldUntil,
        doubleUntil: doubleUntil ?? this.doubleUntil,
        doubleLevel: doubleLevel ?? this.doubleLevel,
        nextDiveAt: nextDiveAt ?? this.nextDiveAt,
        nextFormationShotAt: nextFormationShotAt ?? this.nextFormationShotAt,
        coinsCollected: coinsCollected ?? this.coinsCollected,
        shieldsCollected: shieldsCollected ?? this.shieldsCollected,
        doublesCollected: doublesCollected ?? this.doublesCollected,
        score: score ?? this.score,
        kills: kills ?? this.kills,
        hits: hits ?? this.hits,
        wave: wave ?? this.wave,
        lives: lives ?? this.lives,
        bannerText: bannerText ?? this.bannerText,
        bannerUntil: bannerUntil ?? this.bannerUntil,
        shakeUntil: shakeUntil ?? this.shakeUntil,
        endReason:
            endReason == _sentinel ? this.endReason : endReason as NovaSwarmEndReason?,
      );

  static const Object _sentinel = Object();
}

/// Starfield inicial: 3 camadas parallax (longe 70, meio 32, perto 12).
NovaSwarmState createInitialState({
  required NovaSwarmConfig config,
  required Size fieldSize,
  int seed = 42,
}) {
  final Random rng = Random(seed);
  final List<Star> stars = <Star>[];

  void addLayer({
    required int count,
    required double minSize,
    required double maxSize,
    required double alpha,
    required double speed,
    required Color color,
  }) {
    for (int i = 0; i < count; i++) {
      stars.add(
        Star(
          x: rng.nextDouble() * fieldSize.width,
          y: rng.nextDouble() * fieldSize.height,
          size: minSize + rng.nextDouble() * (maxSize - minSize),
          speed: speed,
          baseAlpha: alpha,
          phase: rng.nextDouble() * pi * 2,
          twinkleFreq: 1.5 + rng.nextDouble() * 3,
          color: color,
        ),
      );
    }
  }

  addLayer(
    count: 70,
    minSize: 1,
    maxSize: 1,
    alpha: 0.45,
    speed: 12,
    color: const Color(0xFFFFFFFF),
  );
  addLayer(
    count: 32,
    minSize: 1.5,
    maxSize: 2,
    alpha: 0.7,
    speed: 28,
    color: const Color(0xFFFFFFFF),
  );
  addLayer(
    count: 12,
    minSize: 2,
    maxSize: 3,
    alpha: 0.9,
    speed: 55,
    color: const Color(0xFF7DF3FF),
  );

  return NovaSwarmState(
    config: config,
    fieldSize: fieldSize,
    playerX: fieldSize.width / 2,
    playerTargetX: fieldSize.width / 2,
    stars: stars,
    enemies: WaveSpawner.spawnWave(
      wave: 1,
      baseEnemies: config.baseEnemies,
      enemiesPerWaveStep: config.enemiesPerWaveStep,
      enemyHp: config.enemyHp,
      fieldWidth: fieldSize.width,
      topY: fieldSize.height * 0.08,
    ),
    bannerText: 'WAVE 1',
    bannerUntil: 1.0,
    nextShootingStarAt: 6 + rng.nextDouble() * 6,
    nextDiveAt: 2.5,
    nextFormationShotAt: 3.0,
  );
}
