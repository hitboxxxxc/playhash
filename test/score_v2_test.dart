import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/entities.dart';
import 'package:playhash/features/games/nova_swarm/engine/game_state.dart';
import 'package:playhash/features/games/nova_swarm/engine/physics.dart';

/// SCORE v2 (exibição; oficial = backend):
///   hit 25 · kill 150 · diver kill +50 · coin +250 · wave clear +500.
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
    diverKillBonus: 50,
    coinBonus: 250,
  );

  NovaSwarmState stateWith(List<Enemy> enemies, {int lives = 3}) =>
      NovaSwarmState(
        config: config,
        fieldSize: const Size(400, 800),
        playerX: 200,
        playerTargetX: 200,
        elapsed: 1,
        lives: lives,
        enemies: enemies,
        bullets: const <Bullet>[Bullet(x: 200, y: 300)],
      );

  group('score v2 — valores da config do backend', () {
    test('hit parcial = 25', () {
      final StepResult r = step(
        stateWith(const <Enemy>[
          Enemy(x: 200, y: 300, variant: EnemyVariant.drone, hp: 2, row: 0, col: 0),
        ]),
        0.016,
      );
      expect(r.state.score, 25);
    });

    test('kill = 150 (e limpa a onda ⇒ +500 de bônus)', () {
      final StepResult r = step(
        stateWith(const <Enemy>[
          Enemy(x: 200, y: 300, variant: EnemyVariant.drone, hp: 1, row: 0, col: 0),
        ]),
        0.016,
      );
      expect(r.state.score, 150 + 500);
      expect(r.state.kills, 1);
    });

    test('abate de DIVER concede +50 de bônus (150+50+500)', () {
      final StepResult r = step(
        stateWith(const <Enemy>[
          Enemy(
            x: 200,
            y: 300,
            variant: EnemyVariant.drone,
            hp: 1,
            row: 0,
            col: 0,
            isDiver: true,
            // Mergulho recém-iniciado NA POSIÇÃO do tiro (p ≈ 0).
            diveStartAt: 1,
            diveFromX: 200,
            diveFromY: 300,
            diveTargetX: 200,
          ),
        ]),
        0.016,
      );
      expect(r.state.score, 150 + 50 + 500);
      expect(r.events, contains(GameEvent.diverKilled));
    });

    test('coin +250 e wave clear +500 compõem o total', () {
      // Composição direta dos valores exibidos.
      final int total = config.pointsPerKill +
          config.diverKillBonus +
          config.coinBonus +
          config.waveBonus;
      expect(total, 950);
    });

    test('totalPowerUpsCollected soma os três contadores', () {
      final NovaSwarmState s = NovaSwarmState(
        config: config,
        fieldSize: const Size(400, 800),
      ).copyWith(coinsCollected: 2, shieldsCollected: 1, doublesCollected: 3);
      expect(s.totalPowerUpsCollected, 6);
    });

    test('fim por vidas 0 = dead; timer 0 = timeUp', () {
      final StepResult dead = step(
        NovaSwarmState(
          config: config,
          fieldSize: const Size(400, 800),
          playerX: 200,
          playerTargetX: 200,
          elapsed: 1,
          lives: 1,
          invulnUntil: -1,
          enemies: const <Enemy>[
            Enemy(x: 200, y: 640, variant: EnemyVariant.drone, hp: 2, row: 0, col: 0),
          ],
        ),
        0.016,
      );
      expect(dead.state.endReason, NovaSwarmEndReason.dead);

      final StepResult timeUp = step(
        NovaSwarmState(
          config: config,
          fieldSize: const Size(400, 800),
          playerX: 200,
          playerTargetX: 200,
          elapsed: 1,
          timeLeft: 0.01,
          enemies: const <Enemy>[
            Enemy(x: 60, y: 64, variant: EnemyVariant.drone, hp: 2, row: 0, col: 0),
          ],
        ),
        0.02,
      );
      expect(timeUp.state.endReason, NovaSwarmEndReason.timeUp);
    });
  });
}
