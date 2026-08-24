import 'dart:math';

import '../engine/entities.dart';

/// Spawner de ondas — funções PURAS (testável sem Flutter).
///
/// Wave 1 = baseEnemies (8); wave n = base + (n-1)×step (8, 12, 16, …).
/// Formação: grade centralizada no topo; cols = min(6, count).
abstract final class WaveSpawner {
  /// Espaçamento horizontal entre colunas (px lógicos).
  static const double colSpacing = 44;

  /// Espaçamento vertical entre linhas (px lógicos).
  static const double rowSpacing = 40;

  /// Altura inicial da formação (px lógicos a partir do topo do campo).
  static const double formationTop = 90;

  static int enemyCountForWave(
    int wave, {
    required int baseEnemies,
    required int enemiesPerWaveStep,
  }) =>
      baseEnemies + (wave - 1) * enemiesPerWaveStep;

  static int columnsForCount(int count) => min(6, count);

  /// Gera a formação da [wave]. Determinística por wave (Random semeado),
  /// com ELITE na primeira fileira (a partir da wave 2) e WASP nas fileiras
  /// do meio — DRONE preenche o resto.
  static List<Enemy> spawnWave({
    required int wave,
    required int baseEnemies,
    required int enemiesPerWaveStep,
    required int enemyHp,
    required double fieldWidth,
  }) {
    final int count = enemyCountForWave(
      wave,
      baseEnemies: baseEnemies,
      enemiesPerWaveStep: enemiesPerWaveStep,
    );
    final int cols = columnsForCount(count);
    final int rows = (count / cols).ceil();
    final double gridWidth = (cols - 1) * colSpacing;
    final double startX = (fieldWidth - gridWidth) / 2;

    final Random rng = Random(wave * 7919);
    final List<Enemy> enemies = <Enemy>[];
    for (int i = 0; i < count; i++) {
      final int row = i ~/ cols;
      final int col = i % cols;
      final int colsInRow = (row == rows - 1) ? count - (rows - 1) * cols : cols;
      // Última fileira (possivelmente parcial) também centralizada.
      final double rowStartX =
          (fieldWidth - (colsInRow - 1) * colSpacing) / 2;
      enemies.add(
        Enemy(
          x: rowStartX + col * colSpacing,
          y: formationTop + row * rowSpacing,
          variant: _variantFor(row: row, col: col, rows: rows, rng: rng, wave: wave),
          hp: enemyHp,
          row: row,
          col: col,
        ),
      );
    }
    // startX usado apenas para documentar centralização da grade cheia.
    assert(startX >= 0 || fieldWidth < gridWidth);
    return enemies;
  }

  static EnemyVariant _variantFor({
    required int row,
    required int col,
    required int rows,
    required Random rng,
    required int wave,
  }) {
    if (row == 0 && wave >= 2 && col % 3 == 1) return EnemyVariant.elite;
    if (row == (rows - 1) ~/ 2 && rng.nextBool()) return EnemyVariant.wasp;
    return EnemyVariant.drone;
  }
}
