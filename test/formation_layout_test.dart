import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/engine/formation_controller.dart';

/// FORMAÇÃO CENTRADA/CONTIDA (v2): corrige o drift que levava a formação
/// para fora da tela. Invariante: minX ≥ 0 e maxX ≤ playW para qualquer
/// largura de dispositivo (320/360/411dp) e qualquer nº de colunas.
void main() {
  group('FormationController.swayAmplitudeFor — amplitude contida', () {
    test('largura folgada ⇒ amplitude = 24dp (máximo)', () {
      // 6 cols ⇒ formW = 5×44 + 27 = 247. Em 411dp: (411−247)/2 − 8 = 74 > 24.
      expect(
        FormationController.swayAmplitudeFor(fieldWidth: 411, cols: 6),
        24,
      );
    });

    test('largura justa ⇒ amplitude reduzida para caber com margem 8dp', () {
      // 320dp: (320−247)/2 − 8 = 28.5 → ainda acima do máximo 24.
      expect(
        FormationController.swayAmplitudeFor(fieldWidth: 320, cols: 6),
        24,
      );
      // Caso extremo: campo de 260dp ⇒ (260−247)/2 − 8 = −1.5 ⇒ clamp 0.
      expect(
        FormationController.swayAmplitudeFor(fieldWidth: 260, cols: 6),
        0,
      );
    });

    test('amplitude nunca negativa', () {
      expect(
        FormationController.swayAmplitudeFor(fieldWidth: 100, cols: 6),
        isNonNegative,
      );
    });
  });

  group('FormationGeometry — contida em 320/360/411dp', () {
    for (final double width in <double>[320, 360, 411]) {
      test('formação NUNCA sai da tela em ${width.round()}dp', () {
        for (int count = 8; count <= 44; count += 4) {
          final FormationGeometry geo = FormationController.compute(
            enemyCount: count,
            fieldSize: Size(width, 700),
          );
          expect(geo.isContained, isTrue,
              reason:
                  'count=$count width=$width: [$geo.minX .. $geo.maxX]');
        }
      });
    }

    test('centrada no centro-x do campo', () {
      final FormationGeometry geo = FormationController.compute(
        enemyCount: 8,
        fieldSize: const Size(360, 700),
      );
      expect((geo.minX + geo.maxX) / 2, closeTo(180, 1e-9));
    });

    test('topo = 8% da altura do campo', () {
      final FormationGeometry geo = FormationController.compute(
        enemyCount: 8,
        fieldSize: const Size(360, 800),
      );
      expect(geo.topY, closeTo(64, 1e-9));
      expect(FormationController.topFor(800), closeTo(64, 1e-9));
    });
  });

  group('slotPosition — sway senoidal + bob ±3dp', () {
    test('sway obedece sin(t × 0.6) × A', () {
      const double amplitude = 24;
      // t=0 ⇒ offset 0.
      expect(
        FormationController.swayOffset(t: 0, amplitude: amplitude),
        0,
      );
      // Pico positivo: sin(0.6t)=1 ⇒ t = π/(2×0.6).
      final double peakT = 3.141592653589793 / (2 * 0.6);
      expect(
        FormationController.swayOffset(t: peakT, amplitude: amplitude),
        closeTo(amplitude, 1e-9),
      );
    });

    test('bob limitado a ±3dp', () {
      for (double t = 0; t < 20; t += 0.05) {
        final double bob = FormationController.bobOffset(t);
        expect(bob.abs(), lessThanOrEqualTo(3.0000001));
      }
    });

    test('slots da última fileira centralizados', () {
      final FormationGeometry geo = FormationController.compute(
        enemyCount: 8,
        fieldSize: const Size(400, 800),
      );
      // Wave 1: 8 inimigos, 6 cols ⇒ rows=2; última fileira tem 2 inimigos
      // nos cols 0..1, centralizada ⇒ média dos x dos slots = centerX.
      final Offset a = geo.slotPosition(row: 1, col: 0, t: 0);
      final Offset b = geo.slotPosition(row: 1, col: 1, t: 0);
      expect((a.dx + b.dx) / 2, closeTo(200, 1e-9));
      // Fileira de cima: y = topo; fileira de baixo: +40.
      expect(a.dy, closeTo(geo.topY + 40, 1e-9));
      expect(
        geo.slotPosition(row: 0, col: 0, t: 0).dy,
        closeTo(geo.topY, 1e-9),
      );
    });
  });
}

