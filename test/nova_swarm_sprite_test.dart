import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/game_state.dart';
import 'package:playhash/features/games/nova_swarm/engine/physics.dart';
import 'package:playhash/features/games/nova_swarm/engine/player_sprite.dart';

NovaSwarmConfig _config() => const NovaSwarmConfig(
      durationSeconds: 60,
      baseEnemies: 8,
      enemiesPerWaveStep: 4,
      enemyHp: 2,
      lives: 3,
      pointsPerKill: 150,
      pointsPerHit: 25,
      waveBonus: 500,
    );

void main() {
  group('advanceShipTilt — histerese do tilt', () {
    test('sequência de velocidades → left/idle/right', () {
      const double never = -1e9;
      // v forte à esquerda em t=0: idle → left.
      var (ShipTilt tilt, double at) = advanceShipTilt(
        current: ShipTilt.idle,
        lastChangeAt: never,
        vx: -300,
        elapsed: 0,
      );
      expect(tilt, ShipTilt.left);
      expect(at, 0);

      // 50ms depois inverte para a direita: dwell < 120ms ⇒ PERMANECE left.
      (tilt, at) = advanceShipTilt(
        current: tilt,
        lastChangeAt: at,
        vx: 400,
        elapsed: 0.05,
      );
      expect(tilt, ShipTilt.left);
      expect(at, 0);

      // 130ms depois: histerese expirada ⇒ troca para right.
      (tilt, at) = advanceShipTilt(
        current: tilt,
        lastChangeAt: at,
        vx: 400,
        elapsed: 0.13,
      );
      expect(tilt, ShipTilt.right);
      expect(at, 0.13);

      // Soltar (v≈0) antes do dwell: permanece right.
      (tilt, at) = advanceShipTilt(
        current: tilt,
        lastChangeAt: at,
        vx: 0,
        elapsed: 0.20,
      );
      expect(tilt, ShipTilt.right);

      // Dwell cumprido ⇒ volta para idle.
      (tilt, at) = advanceShipTilt(
        current: tilt,
        lastChangeAt: at,
        vx: 0,
        elapsed: 0.30,
      );
      expect(tilt, ShipTilt.idle);
      expect(at, 0.30);
    });

    test('zona morta (|v| < ε) mantém idle', () {
      expect(desiredShipTilt(0), ShipTilt.idle);
      expect(desiredShipTilt(PlayerShipSprites.epsilon - 1), ShipTilt.idle);
      expect(desiredShipTilt(-PlayerShipSprites.epsilon + 1), ShipTilt.idle);
    });

    test('mesmo estado desejado não altera o instante da última troca', () {
      var (ShipTilt tilt, double at) = advanceShipTilt(
        current: ShipTilt.left,
        lastChangeAt: 5,
        vx: -100,
        elapsed: 9,
      );
      expect(tilt, ShipTilt.left);
      expect(at, 5);
    });
  });

  group('step() integra o tilt ao estado', () {
    test('alvo distante à esquerda ⇒ tilt left durante o movimento', () {
      NovaSwarmState s = createInitialState(
        config: _config(),
        fieldSize: const Size(400, 800),
      );
      // v3 (nave 2×): o alvo chega ao clamp mais cedo — verificar MID-MOTION.
      s = s.copyWith(playerTargetX: 60);
      for (int i = 0; i < 5; i++) {
        s = step(s, 1 / 60).state;
      }
      expect(s.tilt, ShipTilt.left);
    });

    test('alvo distante à direita ⇒ tilt right durante o movimento', () {
      NovaSwarmState s = createInitialState(
        config: _config(),
        fieldSize: const Size(400, 800),
      );
      s = s.copyWith(playerTargetX: 340);
      for (int i = 0; i < 5; i++) {
        s = step(s, 1 / 60).state;
      }
      expect(s.tilt, ShipTilt.right);
    });

    test('oscilação rápida de alvo NÃO provoca flicker (≤ ~8 trocas/s)',
        () {
      NovaSwarmState s = createInitialState(
        config: _config(),
        fieldSize: const Size(400, 800),
      );
      int changes = 0;
      for (int i = 0; i < 120; i++) {
        // Alvo alterna a cada frame (60Hz) entre extremos.
        s = s.copyWith(playerTargetX: i.isEven ? 10 : 390);
        final ShipTilt before = s.tilt;
        s = step(s, 1 / 60).state;
        if (s.tilt != before) changes++;
      }
      // Histerese de 120ms ⇒ no máximo ~1 troca a cada 7–8 frames.
      expect(changes, lessThanOrEqualTo(120 * (1 / 60) / 0.12 + 1));
    });

    test('nave parada retorna a idle', () {
      NovaSwarmState s = createInitialState(
        config: _config(),
        fieldSize: const Size(400, 800),
      );
      s = s.copyWith(playerTargetX: 340);
      for (int i = 0; i < 5; i++) {
        s = step(s, 1 / 60).state;
      }
      expect(s.tilt, ShipTilt.right);
      // Alvo alcançado ⇒ velocidade ≈ 0 ⇒ idle após a histerese.
      for (int i = 0; i < 45; i++) {
        s = step(s, 1 / 60).state;
      }
      expect(s.tilt, ShipTilt.idle);
    });
  });

  group('v3 — nave 2× e hitbox 70%', () {
    test('sprite renderizado com o DOBRO da largura anterior', () {
      // Anterior: 56dp ⇒ agora 112dp.
      expect(PlayerShipSprites.width, 112);
    });

    test('hitbox do jogador = 70% do novo tamanho', () {
      final NovaSwarmState s = createInitialState(
        config: _config(),
        fieldSize: const Size(400, 800),
      );
      expect(NovaSwarmState.playerWidth, 104); // 2 × 52 antigo
      expect(s.playerHitboxRadius, closeTo(NovaSwarmState.playerWidth * 0.35, 1e-9));
    });

    test('movimento livre em Y: nave converge (lerp) para o alvo Y', () {
      NovaSwarmState s = createInitialState(
        config: _config(),
        fieldSize: const Size(400, 800),
      );
      expect(s.playerY, closeTo(640, 0.5)); // posição clássica 80%
      // Alvo ACIMA (topo, abaixo do HUD) — antes impossível ("túnel").
      s = s.copyWith(playerTargetY: 150);
      for (int i = 0; i < 40; i++) {
        s = step(s, 1 / 60).state;
      }
      expect(s.playerY, closeTo(150, 2.0));
      // Alvo ABAIXO (perto da base) — clamp respeitado.
      s = s.copyWith(playerTargetY: 790);
      for (int i = 0; i < 60; i++) {
        s = step(s, 1 / 60).state;
      }
      // maxY = 800 − 52 − 26 = 722.
      expect(s.playerY, lessThanOrEqualTo(722.5));
      expect(s.playerY, greaterThan(700));
    });
  });

  group('mapa de assets', () {
    test('cada tilt mapeia para o PNG correto', () {
      expect(ShipTilt.idle.assetPath, 'assets/nave/idle.png');
      expect(ShipTilt.left.assetPath, 'assets/nave/esquerda.png');
      expect(ShipTilt.right.assetPath, 'assets/nave/direita.png');
      expect(PlayerShipSprites.capa, 'assets/nave/capa.png');
      expect(PlayerShipSprites.all, hasLength(4));
    });

    testWidgets('PlayerShipSprite renderiza o asset do tilt atual',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            color: Colors.black,
            child: Stack(
              children: <Widget>[
                PlayerShipSprite(
                  tilt: ShipTilt.left,
                  x: 100,
                  y: 200,
                  blinkVisible: true,
                  showInvulnRing: false,
                  showShieldDome: false,
                  elapsed: 0,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final Image image =
          tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName,
          'assets/nave/esquerda.png');
    });
  });
}
