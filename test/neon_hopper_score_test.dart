import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/neon_hopper/engine/physics.dart';

/// Testes do payload de score NEON HOPPER: o breakdown enviado ao backend
/// tem EXATAMENTE as chaves da allowlist das security rules e o score
/// apresentado é a fórmula aplicada (o OFICIAL é recalculado no servidor).
void main() {
  group('breakdown — allowlist das rules', () {
    test('chaves exatas {stomps, coins, flagReached} e tipos corretos', () {
      final NeonHopperState s = createInitialHopperState(
        config: const HopperConfig(),
      ).copyWith(stomps: 12, coinCount: 6);
      final Map<String, dynamic> bd =
          s.copyWith(endReason: HopperEndReason.flag).breakdown();

      expect(bd.keys.length, 3);
      expect(bd.containsKey('stomps'), isTrue);
      expect(bd.containsKey('coins'), isTrue);
      expect(bd.containsKey('flagReached'), isTrue);
      expect(bd['stomps'], isA<int>());
      expect(bd['coins'], isA<int>());
      expect(bd['flagReached'], isA<bool>());
    });

    test('valores zerados em partida sem progresso', () {
      final Map<String, dynamic> bd = createInitialHopperState().breakdown();
      expect(bd['stomps'], 0);
      expect(bd['coins'], 0);
      expect(bd['flagReached'], isFalse);
    });
  });

  group('score apresentado = fórmula do game (espelho do backend)', () {
    test('stomps×100 + coins×50; bandeira soma 500', () {
      const HopperConfig cfg = HopperConfig();
      NeonHopperState s = createInitialHopperState(config: cfg)
          .copyWith(stomps: 5, coinCount: 2);
      expect(s.score, 5 * 100 + 2 * 50);

      s = s.copyWith(endReason: HopperEndReason.flag);
      expect(s.score, 5 * 100 + 2 * 50 + 500);
    });

    test('config lida do backend muda a fórmula APRESENTADA', () {
      const HopperConfig custom = HopperConfig(
        pointsPerStomp: 200,
        pointsPerCoin: 10,
        flagBonus: 1000,
      );
      final NeonHopperState s = createInitialHopperState(config: custom)
          .copyWith(stomps: 1, coinCount: 3)
          .copyWith(endReason: HopperEndReason.timeUp);
      expect(s.score, 1 * 200 + 3 * 10); // sem bandeira
    });

    test('timeUp/dead NÃO somam bônus de bandeira', () {
      for (final HopperEndReason reason in <HopperEndReason>[
        HopperEndReason.timeUp,
        HopperEndReason.dead,
      ]) {
        final NeonHopperState s = createInitialHopperState()
            .copyWith(stomps: 1, coinCount: 0)
            .copyWith(endReason: reason);
        expect(s.flagReached, isFalse);
        expect(s.score, 100);
      }
    });
  });
}
