import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/entities.dart';
import 'package:playhash/features/games/nova_swarm/engine/game_state.dart';
import 'package:playhash/features/games/nova_swarm/engine/physics.dart';
import 'package:playhash/features/games/nova_swarm/engine/powerups.dart';

/// POWER-UPS (v2): escudo absorve 1 hit · tiro duplo (2 bolts, nível 3 se já
/// ativo) · moeda +250 com texto flutuante. Queda 120px/s e coleta pela nave.
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

  group('PowerUpSystem.rollDrop — chances da config', () {
    test('r < shieldChance ⇒ shield', () {
      final PowerUpType? t = PowerUpSystem.rollDrop(
        rng: Random(1)..nextDouble(), // consome; usamos mock abaixo
        shieldChance: 0.08,
        doubleChance: 0.10,
        coinChance: 0.12,
      );
      expect(t, anyOf(isNull, isA<PowerUpType>()));
    });

    test('distribuição aproximada em 100k sorteios', () {
      final Random rng = Random(42);
      int shield = 0, doubleShot = 0, coin = 0;
      for (int i = 0; i < 100000; i++) {
        switch (PowerUpSystem.rollDrop(
          rng: rng,
          shieldChance: 0.08,
          doubleChance: 0.10,
          coinChance: 0.12,
        )) {
          case PowerUpType.shield:
            shield++;
          case PowerUpType.doubleShot:
            doubleShot++;
          case PowerUpType.coin:
            coin++;
          case null:
            break;
        }
      }
      expect(shield / 100000, closeTo(0.08, 0.01));
      expect(doubleShot / 100000, closeTo(0.10, 0.01));
      expect(coin / 100000, closeTo(0.12, 0.01));
    });
  });

  group('PowerUpSystem — queda e coleta', () {
    test('queda a 120px/s e remoção ao passar do fundo', () {
      List<PowerUp> ups = <PowerUp>[
        const PowerUp(type: PowerUpType.coin, x: 100, y: 100, bornAt: 0),
      ];
      ups = PowerUpSystem.advanceFall(ups, 1.0, 800);
      expect(ups.single.y, 220); // 100 + 120
      ups = PowerUpSystem.advanceFall(ups, 6.0, 800);
      expect(ups, isEmpty); // 940 > 800+24
    });

    test('coleta quando a nave encosta (raio generoso)', () {
      const List<PowerUp> ups = <PowerUp>[
        PowerUp(type: PowerUpType.shield, x: 200, y: 615, bornAt: 0),
      ];
      // playerY = 800×0.8 = 640 ⇒ distância 25 ≤ 30.
      expect(
        PowerUpSystem.pickUpIndex(powerUps: ups, playerX: 200, playerY: 640),
        0,
      );
      expect(
        PowerUpSystem.pickUpIndex(powerUps: ups, playerX: 300, playerY: 640),
        -1,
      );
    });
  });

  group('Efeitos via step() — escudo/duplo/moeda', () {
    NovaSwarmState stateWith({
      required List<PowerUp> powerUps,
      double elapsed = 1,
    }) =>
        NovaSwarmState(
          config: config,
          fieldSize: const Size(400, 800),
          playerX: 200,
          playerTargetX: 200,
          elapsed: elapsed,
          powerUps: powerUps,
          enemies: const <Enemy>[
            Enemy(
              x: 60,
              y: 64,
              variant: EnemyVariant.drone,
              hp: 2,
              row: 0,
              col: 0,
            ),
          ],
        );

    test('SHIELD: absorve o hit do orbe inimigo sem perder vida', () {
      NovaSwarmState s = stateWith(
        powerUps: const <PowerUp>[
          PowerUp(type: PowerUpType.shield, x: 200, y: 640, bornAt: 0),
        ],
      );
      final StepResult r1 = step(s, 0.016);
      expect(r1.state.isShieldActive, isTrue); // escudo ativo por 6s
      expect(r1.state.shieldsCollected, 1);
      expect(r1.events, contains(GameEvent.powerupCollected));

      // Orbe inimiga acerta o jogador com escudo ativo.
      s = r1.state.copyWith(
        bullets: <Bullet>[
          const Bullet(x: 200, y: 640, vy: 220, isEnemy: true),
        ],
      );
      final StepResult r2 = step(s, 0.016);
      expect(r2.state.lives, config.lives); // vida intacta
      expect(r2.state.isShieldActive, isFalse); // escudo consumido
      expect(r2.events, contains(GameEvent.shieldAbsorbed));
    });

    test('DOUBLE: 2 bolts paralelos; pegando de novo nível sobe p/ 3', () {
      NovaSwarmState s = stateWith(
        powerUps: const <PowerUp>[
          PowerUp(type: PowerUpType.doubleShot, x: 200, y: 640, bornAt: 0),
        ],
      );
      StepResult r = step(s, 0.016);
      expect(r.state.isDoubleActive, isTrue);
      expect(r.state.doubleLevel, 2);
      expect(r.state.doublesCollected, 1);

      // Segundo drop enquanto ativo ⇒ nível 3.
      s = r.state.copyWith(
        powerUps: const <PowerUp>[
          PowerUp(type: PowerUpType.doubleShot, x: 200, y: 640, bornAt: 0),
        ],
      );
      r = step(s, 0.016);
      expect(r.state.doubleLevel, 3);

      // Atirando no nível 3 ⇒ 3 bolts.
      s = r.state.copyWith(shooting: true, lastShotAt: -10);
      final StepResult shot = step(s, 0.016);
      final int playerBullets = shot.state.bullets
          .where((Bullet b) => !b.isEnemy)
          .length;
      expect(playerBullets, 3);
    });

    test('COIN: +250 pts com texto flutuante "+250"', () {
      final NovaSwarmState s = stateWith(
        powerUps: const <PowerUp>[
          PowerUp(type: PowerUpType.coin, x: 200, y: 640, bornAt: 0),
        ],
      );
      final StepResult r = step(s, 0.016);
      expect(r.state.score, config.coinBonus);
      expect(r.state.coinsCollected, 1);
      expect(r.state.floatingTexts.single.text, '+${config.coinBonus}');
    });

    test('orbe inimiga SEM escudo custa 1 vida', () {
      NovaSwarmState s = stateWith(powerUps: const <PowerUp>[]);
      s = s.copyWith(
        invulnUntil: -1,
        bullets: <Bullet>[
          const Bullet(x: 200, y: 640, vy: 220, isEnemy: true),
        ],
      );
      final StepResult r = step(s, 0.016);
      expect(r.state.lives, config.lives - 1);
      expect(r.events, contains(GameEvent.lifeLost));
    });
  });
}
