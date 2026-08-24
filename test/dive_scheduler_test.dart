import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/dive_controller.dart';

/// SCHEDULER DE MERGULHOS (v2): intervalo com rampa por wave até o mínimo,
/// trajetória senoidal de 2.2s, tiro único na altura ~40%, retorno 0.5s.
void main() {
  group('DiveController.intervalForWave — rampa por wave', () {
    test('wave 1 = intervalo base (3.0s)', () {
      expect(
        DiveController.intervalForWave(
          wave: 1,
          baseSeconds: 3.0,
          minSeconds: 1.2,
          rampPerWave: 0.05,
        ),
        3.0,
      );
    });

    test('rampa reduz 0.05s por wave', () {
      expect(
        DiveController.intervalForWave(
          wave: 10,
          baseSeconds: 3.0,
          minSeconds: 1.2,
          rampPerWave: 0.05,
        ),
        closeTo(3.0 - 0.05 * 9, 1e-9),
      );
    });

    test('piso mínimo de 1.2s nunca é ultrapassado', () {
      // Wave 100 ⇒ sem piso seria negativo; com piso = 1.2.
      expect(
        DiveController.intervalForWave(
          wave: 100,
          baseSeconds: 3.0,
          minSeconds: 1.2,
          rampPerWave: 0.05,
        ),
        1.2,
      );
    });
  });

  group('DiveController — trajetória da descida', () {
    test('progress mapeia diveStartAt → [0..1] em 2.2s', () {
      expect(
        DiveController.progress(elapsed: 5.0, diveStartAt: 5.0),
        0,
      );
      expect(
        DiveController.progress(elapsed: 6.1, diveStartAt: 5.0),
        closeTo(0.5, 1e-9),
      );
      expect(
        DiveController.progress(elapsed: 8.0, diveStartAt: 5.0),
        1,
      );
      expect(
        DiveController.progress(elapsed: 99, diveStartAt: 5.0),
        1,
      );
    });

    test('descida começa no slot e termina além do fundo do campo', () {
      final Offset start = DiveController.descentPosition(
        p: 0,
        fromX: 180,
        fromY: 64,
        targetX: 200,
        fieldHeight: 800,
      );
      expect(start.dy, 64);
      final Offset end = DiveController.descentPosition(
        p: 1,
        fromX: 180,
        fromY: 64,
        targetX: 200,
        fieldHeight: 800,
      );
      expect(end.dy, greaterThan(800)); // passou do fundo
    });

    test('costura senoidal: x desvia do caminho reto no meio', () {
      final Offset mid = DiveController.descentPosition(
        p: 0.25,
        fromX: 180,
        fromY: 64,
        targetX: 200,
        fieldHeight: 800,
      );
      // Reto em p=0.25 daria 185; seno(π/2)=1 adiciona +36 ⇒ ~221.
      expect(mid.dx, closeTo(185 + DiveController.weaveAmplitude, 1e-6));
    });
  });

  group('DiveController — tiro na altura ~40% e retorno', () {
    test('crossedFireHeight detecta a travessia de 40% do campo', () {
      const double fieldH = 800;
      const double fireY = fieldH * 0.4; // 320
      expect(
        DiveController.crossedFireHeight(
          previousY: fireY - 1,
          currentY: fireY + 1,
          fieldHeight: fieldH,
        ),
        isTrue,
      );
      expect(
        DiveController.crossedFireHeight(
          previousY: fireY + 5,
          currentY: fireY + 10,
          fieldHeight: fieldH,
        ),
        isFalse,
      );
    });

    test('retorno progride em 0.5s e alpha acompanha', () {
      expect(
        DiveController.returnProgress(elapsed: 10.0, returnStartedAt: 10.0),
        0,
      );
      expect(
        DiveController.returnProgress(elapsed: 10.25, returnStartedAt: 10.0),
        closeTo(0.5, 1e-9),
      );
      expect(
        DiveController.returnProgress(elapsed: 11.0, returnStartedAt: 10.0),
        1,
      );
      expect(DiveController.returnAlpha(0), 0);
      expect(DiveController.returnAlpha(1), 1);
    });
  });

  group('DiveController.pickDiverCandidate — 1 diver por vez', () {
    test('escolhe apenas entre não-divers', () {
      final Random rng = Random(7);
      final List<bool> diving = <bool>[false, true, false, false];
      for (int i = 0; i < 50; i++) {
        final int idx = DiveController.pickDiverCandidate(diving, rng);
        expect(idx, isIn(<int>[0, 2, 3]));
      }
    });

    test('sem candidatos ⇒ −1', () {
      final int idx = DiveController.pickDiverCandidate(
        <bool>[true, true],
        Random(1),
      );
      expect(idx, -1);
    });
  });
}
