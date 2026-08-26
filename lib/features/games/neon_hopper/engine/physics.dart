import 'dart:ui';

import 'entities.dart';
import 'level_data.dart';

/// NEON HOPPER — física e simulação (função PURA `stepHopper`, testável sem
/// UI/Firestore). Constantes conforme especificação do game:
/// gravidade 2200 px/s²; pulo 900; velocidade 320; coyote 0.10s; buffer
/// 0.12s; bounce de pisão 520; hitbox 80% do sprite.

// ---- Constantes de física (px lógicos, segundos) ---------------------------
const double kHopperGravity = 2200;
const double kHopperJumpVelocity = 900;
const double kHopperMoveSpeed = 320;
const double kHopperCoyoteTime = 0.10;
const double kHopperJumpBuffer = 0.12;
const double kHopperStompBounce = 520;
const double kHopperEnemySpeed = 60;

/// Tolerância do teste de pisão: base do jogador no frame ANTERIOR pode estar
/// até 8 px acima do topo atual do inimigo (evita falso negativo por tunneling).
const double kStompTolerancePx = 8;

/// Invulnerabilidade pós-dano (piscar) em segundos.
const double kInvulnerableSeconds = 1.5;

/// Config de gameplay lida do backend (EXIBIÇÃO; autoridade = servidor).
class HopperConfig {
  const HopperConfig({
    this.durationSeconds = 45,
    this.lives = 3,
    this.pointsPerStomp = 100,
    this.pointsPerCoin = 50,
    this.flagBonus = 500,
  });

  final int durationSeconds;
  final int lives;
  final int pointsPerStomp;
  final int pointsPerCoin;
  final int flagBonus;

  /// Score APRESENTADO na partida = breakdown aplicado. O score OFICIAL é
  /// recalculado pelo backend a partir do breakdown enviado (doc 05 §51).
  int presentationalScore(int stomps, int coins, bool flagReached) =>
      stomps * pointsPerStomp + coins * pointsPerCoin + (flagReached ? flagBonus : 0);
}

enum HopperPhase { playing, paused }

enum HopperEndReason { timeUp, dead, flag }

/// Eventos de um tick (haptics/áudio no widget; nada de UI aqui).
enum HopperEvent { stomp, coin, lifeLost, fell, flagReached, gameOver }

class StepResult {
  const StepResult(this.state, this.events);

  final NeonHopperState state;
  final List<HopperEvent> events;
}

/// Estado completo da partida (imutável — step devolve cópia).
class NeonHopperState {
  const NeonHopperState({
    required this.config,
    required this.solids,
    required this.player,
    required this.enemies,
    required this.coins,
    required this.elapsed,
    required this.lives,
    required this.stomps,
    required this.coinCount,
    required this.moveAxis,
    required this.jumpHeld,
    required this.jumpBufferTimer,
    required this.coyoteTimer,
    required this.jumpCut,
    required this.invulnUntil,
    required this.phase,
    this.endReason,
    this.cameraX = 0,
  });

  final HopperConfig config;
  final List<Rect> solids;
  final HopperPlayer player;
  final List<HopperEnemy> enemies;
  final List<HopperCoin> coins;
  final double elapsed;
  final int lives;
  final int stomps;
  final int coinCount;

  // Entrada corrente (escrita pelos widgets via copyWith).
  final double moveAxis; // -1..1
  final bool jumpHeld;
  final double jumpBufferTimer; // >0 ⇒ pulo solicitado recentemente
  final double coyoteTimer;
  final bool jumpCut; // soltar cedo ⇒ corta impulso pela metade

  final double invulnUntil; // elapsed até o qual está invulnerável

  final HopperPhase phase;
  final HopperEndReason? endReason;
  final double cameraX;

  bool get isInvulnerable => elapsed < invulnUntil;
  double get timeLeft =>
      (config.durationSeconds - elapsed).clamp(0, config.durationSeconds).toDouble();
  bool get flagReached => endReason == HopperEndReason.flag;

  /// Score APRESENTADO (breakdown aplicado; oficial = backend).
  int get score =>
      config.presentationalScore(stomps, coinCount, flagReached);

  /// Breakdown EXATO enviado ao backend no finishSession (allowlist das rules:
  /// {stomps:int, coins:int, flagReached:bool} — NADA mais).
  Map<String, dynamic> breakdown() => <String, dynamic>{
        'stomps': stomps,
        'coins': coinCount,
        'flagReached': flagReached,
      };

  NeonHopperState copyWith({
    HopperPlayer? player,
    List<HopperEnemy>? enemies,
    List<HopperCoin>? coins,
    double? elapsed,
    int? lives,
    int? stomps,
    int? coinCount,
    double? moveAxis,
    bool? jumpHeld,
    double? jumpBufferTimer,
    double? coyoteTimer,
    bool? jumpCut,
    double? invulnUntil,
    HopperPhase? phase,
    HopperEndReason? endReason,
    double? cameraX,
  }) =>
      NeonHopperState(
        config: config,
        solids: solids,
        player: player ?? this.player,
        enemies: enemies ?? this.enemies,
        coins: coins ?? this.coins,
        elapsed: elapsed ?? this.elapsed,
        lives: lives ?? this.lives,
        stomps: stomps ?? this.stomps,
        coinCount: coinCount ?? this.coinCount,
        moveAxis: moveAxis ?? this.moveAxis,
        jumpHeld: jumpHeld ?? this.jumpHeld,
        jumpBufferTimer: jumpBufferTimer ?? this.jumpBufferTimer,
        coyoteTimer: coyoteTimer ?? this.coyoteTimer,
        jumpCut: jumpCut ?? this.jumpCut,
        invulnUntil: invulnUntil ?? this.invulnUntil,
        phase: phase ?? this.phase,
        endReason: endReason ?? this.endReason,
        cameraX: cameraX ?? this.cameraX,
      );
}

/// Estado inicial determinístico a partir da config do backend.
NeonHopperState createInitialHopperState({
  HopperConfig config = const HopperConfig(),
}) {
  return NeonHopperState(
    config: config,
    solids: HopperLevel.buildSolids(),
    player: const HopperPlayer(
      x: HopperLevel.spawnX,
      y: HopperLevel.spawnY,
      vx: 0,
      vy: 0,
      onGround: false,
      facing: 1,
    ),
    enemies: _initialEnemies(),
    coins: <HopperCoin>[
      for (int i = 0; i < HopperLevel.coinPositions.length; i++)
        HopperCoin(
          id: i,
          x: HopperLevel.coinPositions[i].$1,
          y: HopperLevel.coinPositions[i].$2,
          collected: false,
        ),
    ],
    elapsed: 0,
    lives: config.lives,
    stomps: 0,
    coinCount: 0,
    moveAxis: 0,
    jumpHeld: false,
    jumpBufferTimer: 0,
    coyoteTimer: 0,
    jumpCut: false,
    invulnUntil: -1,
    phase: HopperPhase.playing,
  );
}

// ---------------------------------------------------------------------------
// Checagens PURAS de stomp/dano (espelho exato do usado no step)
// ---------------------------------------------------------------------------

/// Pisão legítimo: jogador CAINDO e base dele estava ACIMA do topo do
/// inimigo no frame anterior (com tolerância). Toque lateral/inferior ⇒ dano.
bool isStompHit({
  required bool falling,
  required double previousPlayerBottom,
  required double enemyTop,
  double tolerance = kStompTolerancePx,
}) =>
    falling && previousPlayerBottom <= enemyTop + tolerance;

bool aabbOverlap(Hitbox a, Hitbox b) => a.overlaps(b);

// ---------------------------------------------------------------------------
// Step
// ---------------------------------------------------------------------------

StepResult stepHopper(NeonHopperState s, double dt) {
  if (s.phase != HopperPhase.playing || s.endReason != null) {
    return StepResult(s, const <HopperEvent>[]);
  }
  final List<HopperEvent> events = <HopperEvent>[];
  final double prevBottom = s.player.hitbox.bottom;

  // ---- Timer ---------------------------------------------------------------
  final double elapsed = s.elapsed + dt;
  if (elapsed >= s.config.durationSeconds) {
    return StepResult(
      s.copyWith(
        elapsed: s.config.durationSeconds.toDouble(),
        endReason: HopperEndReason.timeUp,
      ),
      events,
    );
  }

  // ---- Timers de entrada ---------------------------------------------------
  double jumpBuffer = (s.jumpBufferTimer - dt).clamp(0.0, kHopperJumpBuffer);
  double coyote = (s.coyoteTimer - dt).clamp(0.0, kHopperCoyoteTime);

  // ---- Movimento horizontal ------------------------------------------------
  final double vx = s.moveAxis * kHopperMoveSpeed;
  final int facing =
      s.moveAxis.abs() > 0.05 ? (s.moveAxis > 0 ? 1 : -1) : s.player.facing;

  // ---- Pulo (buffer + coyote) ----------------------------------------------
  double vy = s.player.vy + kHopperGravity * dt;
  bool onGround = s.player.onGround;
  bool jumpCut = s.jumpCut;
  if (jumpBuffer > 0 && (onGround || coyote > 0)) {
    vy = -kHopperJumpVelocity;
    onGround = false;
    coyote = 0;
    jumpBuffer = 0;
    jumpCut = false;
  }
  // Pulo variável: soltar cedo corta a subida pela metade (uma única vez).
  if (jumpCut && vy < 0) {
    vy *= 0.5;
    jumpCut = false;
  }

  // ---- Integração com colisão (eixo X depois Y) ----------------------------
  double nx = s.player.x + vx * dt;
  nx = nx.clamp(0.0, HopperLevel.worldWidth - kPlayerSize);
  Rect box = Rect.fromLTWH(nx, s.player.y, kPlayerSize, kPlayerSize);
  for (final Rect r in s.solids) {
    if (box.overlaps(r)) {
      if (vx > 0) {
        nx = r.left - kPlayerSize;
      } else if (vx < 0) {
        nx = r.right;
      }
      box = Rect.fromLTWH(nx, s.player.y, kPlayerSize, kPlayerSize);
    }
  }

  double ny = s.player.y + vy * dt;
  onGround = false;
  box = Rect.fromLTWH(nx, ny, kPlayerSize, kPlayerSize);
  for (final Rect r in s.solids) {
    if (box.overlaps(r)) {
      if (vy > 0) {
        ny = r.top - kPlayerSize;
        vy = 0;
        onGround = true;
      } else if (vy < 0) {
        ny = r.bottom;
        vy = 0;
      }
      box = Rect.fromLTWH(nx, ny, kPlayerSize, kPlayerSize);
    }
  }
  // Coyote: acabou de sair do chão sem pular.
  if (onGround) {
    coyote = kHopperCoyoteTime;
  }

  HopperPlayer player = s.player.copyWith(
    x: nx,
    y: ny,
    vx: vx,
    vy: vy,
    onGround: onGround,
    facing: facing,
  );

  int lives = s.lives;
  int stomps = s.stomps;
  int coinCount = s.coinCount;
  double invulnUntil = s.invulnUntil;
  List<HopperEnemy> enemies = s.enemies;
  List<HopperCoin> coins = s.coins;
  HopperEndReason? endReason;

  // ---- Inimigos: patrulha + stomp/dano -------------------------------------
  final Hitbox pHb = player.hitbox;
  bool enemyChanged = false;
  final List<HopperEnemy> nextEnemies = <HopperEnemy>[];
  for (final HopperEnemy e in enemies) {
    if (!e.alive) {
      nextEnemies.add(e);
      continue;
    }
    enemyChanged = true;
    double x = e.x + e.dir * kHopperEnemySpeed * dt;
    double dir = e.dir;
    if (x <= e.minX) {
      x = e.minX;
      dir = 1;
    } else if (x >= e.maxX) {
      x = e.maxX;
      dir = -1;
    }
    nextEnemies.add(e.copyWith(x: x, dir: dir));
  }
  enemies = enemyChanged ? nextEnemies : enemies;

  for (int i = 0; i < enemies.length; i++) {
    final HopperEnemy e = enemies[i];
    if (!e.alive) continue;
    final Hitbox eHb = e.hitbox;
    if (!pHb.overlaps(eHb)) continue;

    if (isStompHit(
      falling: player.vy > 0,
      previousPlayerBottom: prevBottom,
      enemyTop: eHb.top,
    )) {
      // PISÃO: inimigo explode + bounce + stomps+1.
      enemies = <HopperEnemy>[
        for (int j = 0; j < enemies.length; j++)
          j == i ? enemies[j].copyWith(alive: false) : enemies[j],
      ];
      stomps += 1;
      player = player.copyWith(vy: -kHopperStompBounce, onGround: false);
      events.add(HopperEvent.stomp);
    } else {
      // Toque lateral/inferior: dano (respeitando invulnerabilidade).
      if (!s.isInvulnerable && elapsed >= invulnUntil) {
        lives -= 1;
        invulnUntil = elapsed + kInvulnerableSeconds;
        events.add(HopperEvent.lifeLost);
        if (lives <= 0) {
          endReason = HopperEndReason.dead;
          events.add(HopperEvent.gameOver);
        } else {
          // Repulsão para fora do inimigo.
          final double push = player.hitbox.left + player.hitbox.width / 2 <
                  eHb.left + eHb.width / 2
              ? -1.0
              : 1.0;
          player = player.copyWith(vy: -420);
          player = _nudge(player, push * 26);
        }
      }
    }
    if (endReason != null) break;
  }

  // ---- Moedas ---------------------------------------------------------------
  if (endReason == null) {
    final Hitbox hb = player.hitbox;
    for (int i = 0; i < coins.length; i++) {
      final HopperCoin c = coins[i];
      if (c.collected) continue;
      final bool hit = (hb.left - c.x).abs() < 20 && (hb.top + kPlayerSize / 2 - c.y).abs() < 24;
      if (hit) {
        coins = <HopperCoin>[
          for (int j = 0; j < coins.length; j++)
            j == i ? coins[j].copyWith(collected: true) : coins[j],
        ];
        coinCount += 1;
        events.add(HopperEvent.coin);
      }
    }
  }

  // ---- Queda em fosso → respawn no checkpoint -------------------------------
  if (endReason == null && player.y > HopperLevel.worldHeight + 40) {
    lives -= 1;
    events.add(HopperEvent.fell);
    if (lives <= 0) {
      endReason = HopperEndReason.dead;
      events.add(HopperEvent.gameOver);
    } else {
      final double cx = HopperLevel.checkpointFor(player.x);
      player = HopperPlayer(
        x: cx,
        y: HopperLevel.spawnY,
        vx: 0,
        vy: 0,
        onGround: false,
        facing: 1,
      );
      invulnUntil = elapsed + kInvulnerableSeconds;
    }
  }

  // ---- Bandeira-beacon -------------------------------------------------------
  if (endReason == null &&
      player.x + kPlayerSize >= HopperLevel.flagX - 8 &&
      player.x <= HopperLevel.flagX + 24) {
    endReason = HopperEndReason.flag;
    events.add(HopperEvent.flagReached);
  }

  // ---- Câmera ----------------------------------------------------------------
  final double camRaw = player.x + kPlayerSize / 2 - 320; // viewport 640 lógico
  final double cameraX = camRaw.clamp(0.0, HopperLevel.worldWidth - 640);

  return StepResult(
    s.copyWith(
      player: player,
      enemies: enemies,
      coins: coins,
      elapsed: elapsed,
      lives: lives,
      stomps: stomps,
      coinCount: coinCount,
      jumpBufferTimer: jumpBuffer,
      coyoteTimer: coyote,
      jumpCut: jumpCut,
      invulnUntil: invulnUntil,
      endReason: endReason,
      cameraX: cameraX,
    ),
    events,
  );
}

/// Inimigos iniciais determinísticos (patrulha ida/volta).
List<HopperEnemy> _initialEnemies() => <HopperEnemy>[
      for (int i = 0; i < HopperLevel.enemySpawns.length; i++)
        HopperEnemy(
          id: i,
          x: HopperLevel.enemySpawns[i].$1,
          y: HopperLevel.groundTopY - kEnemyH,
          minX: HopperLevel.enemySpawns[i].$2,
          maxX: HopperLevel.enemySpawns[i].$3,
          dir: i.isEven ? 1 : -1,
          alive: true,
        ),
    ];

/// Empurrão horizontal pós-dano com resolução simples de parede.
HopperPlayer _nudge(HopperPlayer p, double dx) {
  final double x = (p.x + dx).clamp(0.0, HopperLevel.worldWidth - kPlayerSize);
  return p.copyWith(x: x);
}
