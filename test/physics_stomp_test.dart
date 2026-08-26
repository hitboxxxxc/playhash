import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/neon_hopper/engine/entities.dart';
import 'package:playhash/features/games/neon_hopper/engine/level_data.dart';
import 'package:playhash/features/games/neon_hopper/engine/physics.dart';

/// Testes unitários do engine NEON HOPPER: detecção de pisão (caindo/acima
/// vs lateral), fórmula de score, respawn/checkpoint e breakdown allowlist.
void main() {
  group('isStompHit — pisão vs toque lateral', () {
    test('pisão legítimo: caindo E base acima do topo do inimigo', () {
      expect(
        isStompHit(falling: true, previousPlayerBottom: 100, enemyTop: 110),
        isTrue,
      );
      // dentro da tolerância de 8 px
      expect(
        isStompHit(falling: true, previousPlayerBottom: 117, enemyTop: 110),
        isTrue,
      );
    });

    test('não é pisão: subindo (vy <= 0) ⇒ dano lateral', () {
      expect(
        isStompHit(falling: false, previousPlayerBottom: 100, enemyTop: 200),
        isFalse,
      );
    });

    test('não é pisão: base MUITO abaixo do topo do inimigo ⇒ lateral', () {
      expect(
        isStompHit(falling: true, previousPlayerBottom: 130, enemyTop: 110),
        isFalse,
      );
    });
  });

  group('stepHopper — stomp pontua e bounce', () {
    test('jogador caindo sobre inimigo mata + stomps+1 + bounce para cima', () {
      NeonHopperState s = createInitialHopperState();
      // Teleporta o jogador exatamente ACIMA do primeiro inimigo, caindo.
      final HopperEnemy e0 = s.enemies.first;
      s = s.copyWith(
        player: HopperPlayer(
          x: e0.x,
          y: e0.y - kPlayerSize - 4,
          vx: 0,
          vy: 300,
          onGround: false,
          facing: 1,
        ),
        invulnUntil: -1,
      );
      final StepResult r = stepHopper(s, 0.05);
      expect(r.state.stomps, 1);
      expect(r.events, contains(HopperEvent.stomp));
      expect(r.state.enemies.first.alive, isFalse);
      // bounce: subindo após o pisão
      expect(r.state.player.vy, lessThan(0));
    });

    test('toque LATERAL em inimigo tira vida (sem stomps)', () {
      NeonHopperState s = createInitialHopperState();
      final HopperEnemy e0 = s.enemies.first;
      // Jogador ao lado do inimigo, no chão, sem cair.
      s = s.copyWith(
        player: HopperPlayer(
          x: e0.x - kPlayerSize + 10, // overlap horizontal
          y: e0.y + kEnemyH - kPlayerSize, // alinhado verticalmente
          vx: 0,
          vy: 0,
          onGround: true,
          facing: 1,
        ),
        invulnUntil: -1,
      );
      final StepResult r = stepHopper(s, 0.02);
      expect(r.state.stomps, 0);
      expect(r.state.lives, s.lives - 1);
      expect(r.events, contains(HopperEvent.lifeLost));
    });

    test('invulnerabilidade pós-dano evita perda dupla no mesmo instante', () {
      NeonHopperState s = createInitialHopperState();
      final HopperEnemy e0 = s.enemies.first;
      s = s.copyWith(
        player: HopperPlayer(
          x: e0.x - kPlayerSize + 6,
          y: e0.y + kEnemyH - kPlayerSize,
          vx: 0,
          vy: 0,
          onGround: true,
          facing: 1,
        ),
        invulnUntil: 9999, // já invulnerável
      );
      final StepResult r = stepHopper(s, 0.02);
      expect(r.state.lives, s.lives); // intacta
    });
  });

  group('stepHopper — queda, respawn e fim de jogo', () {
    test('queda em fosso tira vida e respawna no CHECKPOINT da seção', () {
      NeonHopperState s = createInitialHopperState();
      // Sobre o fosso 1 (tiles 14–17 → x ~500), já abaixo do limiar de queda
      // (worldHeight + 40 = 488).
      s = s.copyWith(player: s.player.copyWith(x: 500, y: 500, vy: 400));
      final int livesBefore = s.lives;
      final StepResult r = stepHopper(s, 0.05);
      expect(r.state.lives, livesBefore - 1);
      // último checkpoint ≤ 500 é o início (16)
      expect(r.state.player.x, HopperLevel.checkpoints.first);
      expect(r.state.player.vy, 0);
    });

    test('vidas zeradas por queda encerra com gameOver', () {
      NeonHopperState s =
          createInitialHopperState(config: const HopperConfig(lives: 1));
      s = s.copyWith(player: s.player.copyWith(x: 500, y: 500, vy: 400));
      final StepResult r = stepHopper(s, 0.05);
      expect(r.state.endReason, HopperEndReason.dead);
      expect(r.events, contains(HopperEvent.gameOver));
    });

    test('timer zerando encerra com timeUp', () {
      NeonHopperState s = createInitialHopperState()
          .copyWith(elapsed: 44.98); // config default 45s
      final StepResult r = stepHopper(s, 0.05);
      expect(r.state.endReason, HopperEndReason.timeUp);
    });
  });

  group('score apresentado e breakdown', () {
    test('fórmula: stomps×100 + coins×50 + flag×500', () {
      const HopperConfig cfg = HopperConfig();
      expect(cfg.presentationalScore(10, 4, false), 1200);
      expect(cfg.presentationalScore(20, 10, true), 3000); // 2000+500+500
      expect(cfg.presentationalScore(0, 0, true), 500);
    });

    test('breakdown() tem EXATAMENTE as chaves da allowlist das rules', () {
      NeonHopperState s = createInitialHopperState()
          .copyWith(stomps: 3, coinCount: 7)
          .copyWith(endReason: HopperEndReason.flag);
      final Map<String, dynamic> bd = s.breakdown();
      expect(bd.keys.toSet(), <String>{'stomps', 'coins', 'flagReached'});
      expect(bd['stomps'], 3);
      expect(bd['coins'], 7);
      expect(bd['flagReached'], isTrue);
      // score apresentado = breakdown aplicado
      expect(s.score, 3 * 100 + 7 * 50 + 500);
    });

    test('moeda coletada incrementa coins e emite evento', () {
      NeonHopperState s = createInitialHopperState();
      final HopperCoin c0 = s.coins.first;
      s = s.copyWith(
        player: HopperPlayer(
          x: c0.x - kPlayerSize / 2,
          y: c0.y - kPlayerSize / 2,
          vx: 0,
          vy: 0,
          onGround: false,
          facing: 1,
        ),
      );
      final StepResult r = stepHopper(s, 0.02);
      expect(r.state.coinCount, 1);
      expect(r.events, contains(HopperEvent.coin));
      expect(r.state.coins.first.collected, isTrue);
    });
  });

  group('nível determinístico', () {
    test('96 tiles, 10 inimigos, 20 moedas, 4 fossos, bandeira no fim', () {
      expect(HopperLevel.tilesX, 96);
      expect(HopperLevel.enemySpawns.length, 10);
      expect(HopperLevel.coinPositions.length, 20);
      // fossos = segmentos de chão − 1
      expect(HopperLevel.groundSegments.length - 1, 4);
      expect(HopperLevel.flagX, greaterThan(90 * HopperLevel.tileSize));
      // dois checkpoints por seção (início de cada uma)
      expect(HopperLevel.checkpoints.length, HopperLevel.groundSegments.length);
    });
  });
}
