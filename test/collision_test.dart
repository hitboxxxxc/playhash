import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/entities.dart';
import 'package:playhash/features/games/nova_swarm/engine/game_state.dart';
import 'package:playhash/features/games/nova_swarm/engine/physics.dart';

void main() {
  group('circleAabb — colisão círculo × AABB', () {
    final Rect box = Rect.fromLTWH(100, 100, 27, 21); // inimigo 9×7 × 3dp

    test('centro dentro ⇒ colide', () {
      expect(
        NovaSwarmPhysics.circleAabb(
          cx: 113,
          cy: 110,
          radius: 8,
          box: box,
        ),
        isTrue,
      );
    });

    test('borda encostando ⇒ colide', () {
      expect(
        NovaSwarmPhysics.circleAabb(
          cx: 100 - 8,
          cy: 110,
          radius: 8,
          box: box,
        ),
        isTrue,
      );
    });

    test('longe ⇒ não colide', () {
      expect(
        NovaSwarmPhysics.circleAabb(
          cx: 100 - 20,
          cy: 110,
          radius: 8,
          box: box,
        ),
        isFalse,
      );
    });

    test('diagonal fora do raio ⇒ não colide', () {
      expect(
        NovaSwarmPhysics.circleAabb(
          cx: 60,
          cy: 60,
          radius: 8,
          box: box,
        ),
        isFalse,
      );
    });
  });

  group('clamp/lerp do jogador', () {
    test('frameLerp normaliza 0.22/frame para o dt informado', () {
      // 1 frame @60fps ⇒ exatamente 0.22.
      expect(NovaSwarmPhysics.frameLerp(1 / 60), closeTo(0.22, 1e-9));
      // 2 frames ⇒ 1-(0.78)².
      expect(
        NovaSwarmPhysics.frameLerp(2 / 60),
        closeTo(1 - 0.78 * 0.78, 1e-9),
      );
    });

    test('step move o jogador em direção ao alvo (lerp 0.22)', () {
      final NovaSwarmState state = NovaSwarmState(
        config: const NovaSwarmConfig(
          durationSeconds: 60,
          baseEnemies: 8,
          enemiesPerWaveStep: 4,
          enemyHp: 2,
          lives: 3,
          pointsPerKill: 150,
          pointsPerHit: 25,
          waveBonus: 500,
        ),
        fieldSize: const Size(400, 800),
        playerX: 100,
        playerTargetX: 200,
        elapsed: 1,
      );
      final StepResult result = step(state, 1 / 60);
      expect(result.state.playerX, greaterThan(100));
      expect(result.state.playerX, lessThan(200));
      expect(
        result.state.playerX,
        closeTo(100 + 100 * 0.22, 0.5),
      );
    });

    test('colisão jogador × inimigo: perde vida + invulnerável + explode', () {
      final NovaSwarmState state = NovaSwarmState(
        config: const NovaSwarmConfig(
          durationSeconds: 60,
          baseEnemies: 8,
          enemiesPerWaveStep: 4,
          enemyHp: 2,
          lives: 3,
          pointsPerKill: 150,
          pointsPerHit: 25,
          waveBonus: 500,
        ),
        fieldSize: const Size(400, 800),
        playerX: 200,
        playerTargetX: 200,
        elapsed: 1,
        enemies: <Enemy>[
          // Inimigo descendo sobre o jogador (playerY = 800-96 = 704).
          const Enemy(
            x: 200,
            y: 704,
            variant: EnemyVariant.drone,
            hp: 2,
            row: 0,
            col: 0,
          ),
        ],
      );
      final StepResult result = step(state, 0.016);
      expect(result.state.lives, 2);
      expect(result.state.isInvulnerable, isTrue);
      expect(result.events, contains(GameEvent.lifeLost));
      // Inimigo explode (some) e partículas são geradas.
      expect(result.state.particles, isNotEmpty);
      // Com o campo vazio, a onda seguinte é imediatamente gerada.
      expect(result.state.enemies, isNotEmpty);
      expect(result.state.wave, 2);
    });

    test('invulnerabilidade evita perda de vida consecutiva', () {
      final NovaSwarmConfig config = const NovaSwarmConfig(
        durationSeconds: 60,
        baseEnemies: 8,
        enemiesPerWaveStep: 4,
        enemyHp: 2,
        lives: 3,
        pointsPerKill: 150,
        pointsPerHit: 25,
        waveBonus: 500,
      );
      NovaSwarmState state = NovaSwarmState(
        config: config,
        fieldSize: const Size(400, 800),
        playerX: 200,
        playerTargetX: 200,
        elapsed: 1,
        invulnUntil: 2,
        enemies: <Enemy>[
          const Enemy(
            x: 200,
            y: 704,
            variant: EnemyVariant.drone,
            hp: 2,
            row: 0,
            col: 0,
          ),
        ],
      );
      final StepResult result = step(state, 0.016);
      expect(result.state.lives, 3); // intocado
      state = result.state;
      // Após o fim da invulnerabilidade, colide de novo.
      final NovaSwarmState later = state.copyWith(
        elapsed: 3,
        invulnUntil: -1,
        enemies: <Enemy>[
          const Enemy(
            x: 200,
            y: 704,
            variant: EnemyVariant.drone,
            hp: 2,
            row: 0,
            col: 0,
          ),
        ],
      );
      final StepResult result2 = step(later, 0.016);
      expect(result2.state.lives, 2);
    });

    test('timer 0 encerra com vitória (timeUp); vidas 0 com derrota', () {
      final NovaSwarmConfig config = const NovaSwarmConfig(
        durationSeconds: 60,
        baseEnemies: 8,
        enemiesPerWaveStep: 4,
        enemyHp: 2,
        lives: 3,
        pointsPerKill: 150,
        pointsPerHit: 25,
        waveBonus: 500,
      );
      final StepResult timeUp = step(
        NovaSwarmState(
          config: config,
          fieldSize: const Size(400, 800),
          timeLeft: 0.01,
          elapsed: 59.99,
        ),
        0.02,
      );
      expect(timeUp.state.endReason, NovaSwarmEndReason.timeUp);

      final StepResult dead = step(
        NovaSwarmState(
          config: config,
          fieldSize: const Size(400, 800),
          playerX: 200,
          playerTargetX: 200,
          lives: 1,
          elapsed: 1,
          enemies: <Enemy>[
            const Enemy(
              x: 200,
              y: 704,
              variant: EnemyVariant.elite,
              hp: 2,
              row: 0,
              col: 0,
            ),
          ],
        ),
        0.016,
      );
      expect(dead.state.endReason, NovaSwarmEndReason.dead);
    });
  });
}
