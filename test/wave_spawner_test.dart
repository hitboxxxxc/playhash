import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/entities.dart';
import 'package:playhash/features/games/nova_swarm/engine/wave_spawner.dart';

void main() {
  group('WaveSpawner — contagem de inimigos (8/12/16…)', () {
    test('wave 1 = 8; wave n = 8 + (n-1)×4', () {
      expect(
        WaveSpawner.enemyCountForWave(
          1,
          baseEnemies: 8,
          enemiesPerWaveStep: 4,
        ),
        8,
      );
      expect(
        WaveSpawner.enemyCountForWave(
          2,
          baseEnemies: 8,
          enemiesPerWaveStep: 4,
        ),
        12,
      );
      expect(
        WaveSpawner.enemyCountForWave(
          3,
          baseEnemies: 8,
          enemiesPerWaveStep: 4,
        ),
        16,
      );
      expect(
        WaveSpawner.enemyCountForWave(
          10,
          baseEnemies: 8,
          enemiesPerWaveStep: 4,
        ),
        44,
      );
    });

    test('spawnWave gera exatamente a contagem esperada', () {
      for (int wave = 1; wave <= 5; wave++) {
        final List<Enemy> enemies = WaveSpawner.spawnWave(
          wave: wave,
          baseEnemies: 8,
          enemiesPerWaveStep: 4,
          enemyHp: 2,
          fieldWidth: 400,
        );
        expect(
          enemies.length,
          WaveSpawner.enemyCountForWave(
            wave,
            baseEnemies: 8,
            enemiesPerWaveStep: 4,
          ),
        );
      }
    });

    test('grade centralizada no topo com cols = min(6, count)', () {
      final List<Enemy> enemies = WaveSpawner.spawnWave(
        wave: 1,
        baseEnemies: 8,
        enemiesPerWaveStep: 4,
        enemyHp: 2,
        fieldWidth: 400,
      );
      expect(WaveSpawner.columnsForCount(8), 6);
      expect(WaveSpawner.columnsForCount(4), 4);
      // Centralizada: min x + max x ≈ largura do campo.
      final double minX = enemies
          .map((Enemy e) => e.x)
          .reduce((double a, double b) => a < b ? a : b);
      final double maxX = enemies
          .map((Enemy e) => e.x)
          .reduce((double a, double b) => a > b ? a : b);
      expect((minX + maxX) / 2, closeTo(200, 0.01));
      // Topo: primeira linha na altura da formação.
      final double minY = enemies
          .map((Enemy e) => e.y)
          .reduce((double a, double b) => a < b ? a : b);
      expect(minY, WaveSpawner.formationTop);
    });

    test('todos os inimigos nascem com HP da config', () {
      final List<Enemy> enemies = WaveSpawner.spawnWave(
        wave: 2,
        baseEnemies: 8,
        enemiesPerWaveStep: 4,
        enemyHp: 2,
        fieldWidth: 400,
      );
      for (final Enemy e in enemies) {
        expect(e.hp, 2);
        expect(e.variant, isA<EnemyVariant>());
      }
    });

    test('determinístico por wave (mesma seed ⇒ mesma formação)', () {
      final List<Enemy> a = WaveSpawner.spawnWave(
        wave: 3,
        baseEnemies: 8,
        enemiesPerWaveStep: 4,
        enemyHp: 2,
        fieldWidth: 400,
      );
      final List<Enemy> b = WaveSpawner.spawnWave(
        wave: 3,
        baseEnemies: 8,
        enemiesPerWaveStep: 4,
        enemyHp: 2,
        fieldWidth: 400,
      );
      for (int i = 0; i < a.length; i++) {
        expect(a[i].variant, b[i].variant);
        expect(a[i].x, b[i].x);
        expect(a[i].y, b[i].y);
      }
    });
  });
}
