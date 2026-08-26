import 'dart:ui';

/// NEON HOPPER — entidades e sprites 100% em código (matrizes de pixel
/// próprias; NENHUM asset externo, NENHUM conteúdo de terceiros).
///
/// Jogador = robô pixel 12×12 (ciano); inimigo = "volt crab" 12×10 (magenta);
/// moeda = hexágono dourado girando (scale-x senoidal, desenhada no renderer).

/// Escala do pixel lógico para o mundo (12 px → 30 px de sprite).
const double kHopperPixelScale = 2.5;

/// Tamanho do sprite/hitbox base no mundo.
const double kPlayerSize = 30; // 12 × 2.5
const double kEnemyW = 30; // 12 × 2.5
const double kEnemyH = 25; // 10 × 2.5

/// Fator de hitbox (80% do sprite) — constante de física espelhada em physics.
const double kHitboxFactor = 0.8;

/// Paleta índice → cor (0 = transparente).
const List<Color?> kHopperPalette = <Color?>[
  null, // 0 transparente
  Color(0xFF00E5FF), // 1 ciano claro (corpo)
  Color(0xFF0088A8), // 2 ciano escuro (sombra)
  Color(0xFFFFFFFF), // 3 branco (olho/brilho)
  Color(0xFFFF2ED1), // 4 magenta (crab corpo)
  Color(0xFF9C1370), // 5 magenta escuro (crab sombra)
  Color(0xFF0A0A14), // 6 quase-preto (detalhe)
];

/// Robô 12×12 — frame PARADO (idle). Ciano com visor branco.
const List<List<int>> kRobotIdle = <List<int>>[
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 3, 3, 1, 1, 3, 3, 1, 1, 0],
  <int>[0, 1, 1, 3, 1, 1, 1, 1, 3, 1, 1, 0],
  <int>[0, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 0],
  <int>[0, 0, 1, 1, 2, 2, 2, 2, 1, 1, 0, 0],
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 0],
  <int>[0, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 0],
  <int>[0, 0, 1, 1, 2, 2, 2, 2, 1, 1, 0, 0],
  <int>[0, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 0],
];

/// Robô 12×12 — frame DE ANDAR A (perna esquerda avançada).
const List<List<int>> kRobotWalkA = <List<int>>[
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 3, 3, 1, 1, 3, 3, 1, 1, 0],
  <int>[0, 1, 1, 3, 1, 1, 1, 1, 3, 1, 1, 0],
  <int>[0, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 0],
  <int>[0, 0, 1, 1, 2, 2, 2, 2, 1, 1, 0, 0],
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 0],
  <int>[0, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 0],
  <int>[0, 1, 1, 1, 2, 2, 2, 2, 1, 1, 0, 0],
  <int>[2, 2, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0],
];

/// Robô 12×12 — frame DE ANDAR B (perna direita avançada).
const List<List<int>> kRobotWalkB = <List<int>>[
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 3, 3, 1, 1, 3, 3, 1, 1, 0],
  <int>[0, 1, 1, 3, 1, 1, 1, 1, 3, 1, 1, 0],
  <int>[0, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 0],
  <int>[0, 0, 1, 1, 2, 2, 2, 2, 1, 1, 0, 0],
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 0],
  <int>[0, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 0],
  <int>[0, 0, 1, 1, 2, 2, 2, 2, 1, 1, 1, 0],
  <int>[0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 2, 2],
];

/// Robô 12×12 — frame DE PULO (pernas recolhidas).
const List<List<int>> kRobotJump = <List<int>>[
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 1, 3, 3, 1, 1, 3, 3, 1, 1, 0],
  <int>[0, 1, 1, 3, 1, 1, 1, 1, 3, 1, 1, 0],
  <int>[0, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 0],
  <int>[0, 0, 1, 1, 2, 2, 2, 2, 1, 1, 0, 0],
  <int>[0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0],
  <int>[0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
  <int>[0, 1, 2, 1, 1, 1, 1, 1, 1, 2, 1, 0],
  <int>[0, 1, 2, 2, 1, 1, 1, 1, 2, 2, 1, 0],
  <int>[0, 0, 1, 2, 2, 2, 2, 2, 2, 1, 0, 0],
  <int>[0, 0, 0, 2, 2, 0, 0, 2, 2, 0, 0, 0],
];

/// "Volt Crab" 12×10 — frame A (patas abertas). Magenta.
const List<List<int>> kCrabA = <List<int>>[
  <int>[0, 0, 0, 4, 4, 4, 4, 4, 4, 0, 0, 0],
  <int>[0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0],
  <int>[0, 4, 4, 3, 4, 4, 4, 4, 3, 4, 4, 0],
  <int>[4, 4, 4, 3, 4, 5, 5, 4, 3, 4, 4, 4],
  <int>[4, 4, 4, 4, 5, 5, 5, 5, 4, 4, 4, 4],
  <int>[0, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0],
  <int>[0, 5, 0, 4, 4, 4, 4, 4, 4, 0, 5, 0],
  <int>[5, 0, 0, 5, 0, 5, 5, 0, 5, 0, 0, 5],
  <int>[0, 5, 0, 5, 0, 5, 5, 0, 5, 0, 5, 0],
  <int>[0, 0, 5, 0, 5, 0, 0, 5, 0, 5, 0, 0],
];

/// "Volt Crab" 12×10 — frame B (patas fechadas).
const List<List<int>> kCrabB = <List<int>>[
  <int>[0, 0, 0, 4, 4, 4, 4, 4, 4, 0, 0, 0],
  <int>[0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0],
  <int>[0, 4, 4, 3, 4, 4, 4, 4, 3, 4, 4, 0],
  <int>[4, 4, 4, 3, 4, 5, 5, 4, 3, 4, 4, 4],
  <int>[4, 4, 4, 4, 5, 5, 5, 5, 4, 4, 4, 4],
  <int>[0, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0],
  <int>[0, 0, 5, 4, 4, 4, 4, 4, 4, 5, 0, 0],
  <int>[0, 5, 0, 5, 0, 5, 5, 0, 5, 0, 5, 0],
  <int>[5, 0, 5, 0, 5, 0, 0, 5, 0, 5, 0, 5],
  <int>[0, 5, 0, 0, 5, 0, 0, 5, 0, 0, 5, 0],
];

/// Estado do jogador (imutável por tick — copiado via copyWith no step).
class HopperPlayer {
  const HopperPlayer({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.onGround,
    required this.facing,
  });

  /// Posição do TOPO-ESQUERDA do sprite no mundo.
  final double x;
  final double y;
  final double vx;
  final double vy;
  final bool onGround;

  /// 1 = direita, -1 = esquerda (espelhamento do sprite).
  final int facing;

  Hitbox get hitbox => Hitbox(
        left: x + kPlayerSize * (1 - kHitboxFactor) / 2,
        top: y + kPlayerSize * (1 - kHitboxFactor) / 2,
        width: kPlayerSize * kHitboxFactor,
        height: kPlayerSize * kHitboxFactor,
      );

  HopperPlayer copyWith({
    double? x,
    double? y,
    double? vx,
    double? vy,
    bool? onGround,
    int? facing,
  }) =>
      HopperPlayer(
        x: x ?? this.x,
        y: y ?? this.y,
        vx: vx ?? this.vx,
        vy: vy ?? this.vy,
        onGround: onGround ?? this.onGround,
        facing: facing ?? this.facing,
      );
}

/// Inimigo patrulheiro (ida/volta entre minX e maxX).
class HopperEnemy {
  const HopperEnemy({
    required this.id,
    required this.x,
    required this.y,
    required this.minX,
    required this.maxX,
    required this.dir,
    required this.alive,
  });

  final int id;
  final double x; // topo-esquerda
  final double y;
  final double minX;
  final double maxX;
  final double dir; // 1 ou -1
  final bool alive;

  Hitbox get hitbox => Hitbox(
        left: x + kEnemyW * (1 - kHitboxFactor) / 2,
        top: y + kEnemyH * (1 - kHitboxFactor) / 2,
        width: kEnemyW * kHitboxFactor,
        height: kEnemyH * kHitboxFactor,
      );

  HopperEnemy copyWith({double? x, double? dir, bool? alive}) => HopperEnemy(
        id: id,
        x: x ?? this.x,
        y: y,
        minX: minX,
        maxX: maxX,
        dir: dir ?? this.dir,
        alive: alive ?? this.alive,
      );
}

/// Moeda coletável (hexágono dourado; animação no renderer).
class HopperCoin {
  const HopperCoin({required this.id, required this.x, required this.y, required this.collected});

  final int id;
  final double x; // centro
  final double y; // centro
  final bool collected;

  HopperCoin copyWith({bool? collected}) => HopperCoin(
        id: id,
        x: x,
        y: y,
        collected: collected ?? this.collected,
      );
}

/// AABB simples usado nas checagens puras de colisão/stomp (testável sem UI).
class Hitbox {
  const Hitbox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  bool overlaps(Hitbox o) =>
      left < o.right && right > o.left && top < o.bottom && bottom > o.top;
}
