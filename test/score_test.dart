import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/entities.dart';
import 'package:playhash/features/games/nova_swarm/engine/game_state.dart';
import 'package:playhash/features/games/nova_swarm/engine/physics.dart';

/// Score de EXIBIÇÃO (o oficial é o backend):
///   kills×pointsPerKill + hits×pointsPerHit + waves×waveBonus.
void main() {
  const NovaSwarmConfig config = NovaSwarmConfig(
    durationSeconds: 60,
    baseEnemies: 8,
    enemiesPerWaveStep: 4,
    enemyHp: 2,
    lives: 3,
    pointsPerKill: 150,
    pointsPerHit: 25,
    waveBonus: 500,
  );

  group('score math (config nova-swarm: 150/25/500)', () {
    test('kills × 150', () {
      // 3 kills = 450
      expect(3 * config.pointsPerKill, 450);
    });

    test('hits × 25', () {
      // 5 hits parciais = 125
      expect(5 * config.pointsPerHit, 125);
    });

    test('waves × 500', () {
      expect(2 * config.waveBonus, 1000);
    });

    test('composição: 10 kills + 12 hits + 3 waves', () {
      final int score = 10 * config.pointsPerKill +
          12 * config.pointsPerHit +
          3 * config.waveBonus;
      expect(score, 1500 + 300 + 1500);
      expect(score, 3300);
    });

    test('step acumula score ao matar inimigo de 1 hit restante', () {
      final NovaSwarmState state = NovaSwarmState(
        config: config,
        fieldSize: const Size(400, 800),
        playerX: 200,
        playerTargetX: 200,
        elapsed: 1,
        enemies: <Enemy>[
          const Enemy(
            x: 200,
            y: 300,
            variant: EnemyVariant.drone,
            hp: 1,
            row: 0,
            col: 0,
          ),
        ],
        bullets: <Bullet>[const Bullet(x: 200, y: 300)],
      );
      final StepResult result = step(state, 0.016);
      // kill (150) + waveBonus (500) — a onda limpa spawna a seguinte.
      expect(result.state.score,
          config.pointsPerKill + config.waveBonus);
      expect(result.state.kills, 1);
      expect(result.events, contains(GameEvent.enemyKilled));
      expect(result.events, contains(GameEvent.waveCleared));
    });

    test('step acumula pontos de hit parcial (HP 2 → 1)', () {
      final NovaSwarmState state = NovaSwarmState(
        config: config,
        fieldSize: const Size(400, 800),
        playerX: 200,
        playerTargetX: 200,
        elapsed: 1,
        enemies: <Enemy>[
          const Enemy(
            x: 200,
            y: 300,
            variant: EnemyVariant.drone,
            hp: 2,
            row: 0,
            col: 0,
          ),
        ],
        bullets: <Bullet>[const Bullet(x: 200, y: 300)],
      );
      final StepResult result = step(state, 0.016);
      expect(result.state.score, config.pointsPerHit);
      expect(result.state.hits, 1);
      expect(result.state.kills, 0);
      // Inimigo continua vivo com HP 1 e flash ativo.
      expect(result.state.enemies.single.hp, 1);
    });

    test('limpar a onda concede waveBonus e spawna a próxima', () {
      final List<Enemy> enemies = <Enemy>[
        const Enemy(
          x: 200,
          y: 300,
          variant: EnemyVariant.drone,
          hp: 1,
          row: 0,
          col: 0,
        ),
      ];
      final NovaSwarmState state = NovaSwarmState(
        config: config,
        fieldSize: const Size(400, 800),
        playerX: 200,
        playerTargetX: 200,
        elapsed: 1,
        enemies: enemies,
        bullets: <Bullet>[const Bullet(x: 200, y: 300)],
      );
      final StepResult result = step(state, 0.016);
      expect(result.state.score, config.pointsPerKill + config.waveBonus);
      expect(result.state.wave, 2);
      expect(result.state.enemies, isNotEmpty);
      expect(result.state.bannerText, 'WAVE 2');
      expect(result.events, contains(GameEvent.waveCleared));
    });
  });
}
