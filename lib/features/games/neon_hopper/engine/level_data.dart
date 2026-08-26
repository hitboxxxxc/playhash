import 'dart:ui';

/// NEON HOPPER — dados de nível DETERMINÍSTICOS (zero aleatoriedade).
///
/// Mundo em pixels lógicos: tile = 32 px; 96 tiles de largura (3072 px);
/// altura do mundo = 14 tiles (448 px). Chão no topo da linha y=12 (y=384).
///
/// Estrutura: 5 seções de chão separadas por 4 fossos; plataformas em duas
/// alturas; 10 inimigos patrulhando (ida/volta); 20 moedas em arcos sobre os
/// fossos + plataformas; bandeira-beacon no tile final. Checkpoints = início
/// de cada seção (respawn ao cair em fosso).
class HopperLevel {
  const HopperLevel._();

  static const double tileSize = 32;
  static const int tilesX = 96;
  static const int tilesY = 14;
  static const double worldWidth = tilesX * tileSize; // 3072
  static const double worldHeight = tilesY * tileSize; // 448
  static const double groundTopY = 12 * tileSize; // 384

  /// Seções de chão [tileInicial..tileFinal] (inclusivos) — 4 fossos entre elas.
  static const List<(int, int)> groundSegments = <(int, int)>[
    (0, 13),
    (18, 33),
    (38, 55),
    (60, 77),
    (82, 95),
  ];

  /// Plataformas sólidas em DUAS alturas: (tileX, tileY, larguraEmTiles).
  /// Topo da plataforma em tileY*32; bloco com 16 px de espessura.
  static const List<(int, int, int)> platforms = <(int, int, int)>[
    // seção 1
    (6, 9, 3),
    // seção 2
    (20, 9, 3),
    (25, 6, 3),
    // seção 3
    (40, 9, 3),
    (45, 6, 3),
    (50, 9, 3),
    // seção 4
    (62, 9, 3),
    (67, 6, 3),
    (72, 9, 3),
    // seção 5
    (84, 9, 3),
    (89, 6, 3),
  ];

  /// Inimigos "volt crab": (spawnX, patrolMinX, patrolMaxX) em px.
  /// Todos no chão (y resolvido pela física); velocidade única (60 px/s).
  static const List<(double, double, double)> enemySpawns = <(double, double, double)>[
    // seção 1 (1)
    (200, 96, 420),
    // seção 2 (2)
    (640, 600, 900),
    (1000, 940, 1050),
    // seção 3 (3)
    (1280, 1230, 1500),
    (1600, 1540, 1740),
    (1450, 1250, 1720),
    // seção 4 (2)
    (1980, 1930, 2200),
    (2330, 2260, 2440),
    // seção 5 (2)
    (2680, 2640, 2850),
    (2930, 2880, 3010),
  ];

  /// Moedas (20): arcos sobre os 4 fossos (16) + plataformas (4).
  static const List<(double, double)> coinPositions = <(double, double)>[
    // arco fosso 1 (tiles 14–17 → x 448..576)
    (464, 320), (496, 296), (528, 280), (560, 296),
    // arco fosso 2 (tiles 34–37 → x 1088..1216)
    (1104, 320), (1136, 296), (1168, 280), (1200, 296),
    // arco fosso 3 (tiles 56–59 → x 1792..1920)
    (1808, 320), (1840, 296), (1872, 280), (1904, 296),
    // arco fosso 4 (tiles 78–81 → x 2496..2624)
    (2512, 320), (2544, 296), (2576, 280), (2608, 296),
    // plataformas altas (tile y=6 → topo 192)
    (816, 152), (1456, 152), (2160, 152), (2864, 152),
  ];

  /// Checkpoints = início de cada seção (x do respawn). O ativo é o último
  /// checkpoint ≤ player.x no momento da queda.
  static const List<double> checkpoints = <double>[16, 576, 1216, 1920, 2624];

  /// Bandeira-beacon: base no chão do tile 94.
  static const double flagX = 94 * tileSize; // 3008
  static const double flagBaseY = groundTopY;
  static const double flagPoleHeight = 112;

  /// Spawn inicial do jogador (centro-x no tile 1, sobre o chão).
  static const double spawnX = 48;
  static const double spawnY = groundTopY - 30;

  /// Retângulos SÓLIDOS do nível (chão + plataformas) para colisão AABB.
  static List<Rect> buildSolids() {
    final List<Rect> solids = <Rect>[];
    for (final (int a, int b) in groundSegments) {
      solids.add(
        Rect.fromLTWH(a * tileSize, groundTopY, (b - a + 1) * tileSize, worldHeight - groundTopY),
      );
    }
    for (final (int x, int y, int w) in platforms) {
      solids.add(Rect.fromLTWH(x * tileSize, y * tileSize, w * tileSize, 16));
    }
    return solids;
  }

  /// Último checkpoint ≤ [x] (fallback: primeiro).
  static double checkpointFor(double x) {
    double best = checkpoints.first;
    for (final double cx in checkpoints) {
      if (cx <= x) best = cx;
    }
    return best;
  }
}
