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
  final List<Bullet> bullets;
  final List<Particle> particles;
  final List<Shockwave> shockwaves;
  final List<Star> stars;
  final ShootingStar? shootingStar;
  final double nextShootingStarAt;

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

  /// Y fixo do jogador (px lógicos a partir do topo).
  double get playerY => fieldSize.height - 96;

  /// Largura do sprite do jogador (dp).
  static const double playerWidth = 52;

  /// Hitbox do jogador = 70% do sprite (tolerância generosa).
  double get playerHitboxRadius => playerWidth * 0.35;

  bool get isInvulnerable => elapsed < invulnUntil;

  bool get isBannerActive => elapsed < bannerUntil;

  bool get isShaking => elapsed < shakeUntil;

  /// Score de EXIBIÇÃO (o oficial é o backend): kills×kill + hits×hit + waves×bônus.
  int get displayScore => score;

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
    ),
    bannerText: 'WAVE 1',
    bannerUntil: 1.0,
    nextShootingStarAt: 6 + rng.nextDouble() * 6,
  );
}

