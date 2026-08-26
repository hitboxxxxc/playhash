import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/neon_hopper/widgets/joystick_widget.dart';
import 'package:playhash/features/games/neon_hopper/widgets/jump_button.dart';

/// Testes de widget dos CONTROLES NEON HOPPER: joystick emite direção
/// contínua (-1..1) e botão PULO dispara press/release.
void main() {
  group('JoystickWidget', () {
    testWidgets('arrastar para a direita emite eixo positivo', (WidgetTester tester) async {
      double? axis;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 170,
              child: JoystickWidget(onAxis: (double a) => axis = a),
            ),
          ),
        ),
      );

      final Offset center = tester.getCenter(find.byType(JoystickWidget));
      final TestGesture gesture = await tester.startGesture(center);
      await tester.pump();
      expect(axis, 0.0); // toque sem arrastar = parado

      // Arrasta +48 px ⇒ eixo 1.0.
      await gesture.moveBy(const Offset(48, 0));
      await tester.pump();
      expect(axis, closeTo(1.0, 0.001));

      // Volta ao centro ⇒ eixo 0.
      await gesture.moveBy(const Offset(-48, 0));
      await tester.pump();
      expect(axis, closeTo(0.0, 0.001));

      // Arrasta para a esquerda ⇒ eixo -1.
      await gesture.moveBy(const Offset(-48, 0));
      await tester.pump();
      expect(axis, closeTo(-1.0, 0.001));

      await gesture.up();
      await tester.pump();
      expect(axis, 0.0); // soltar zera o eixo
    });

    testWidgets('soltar o dedo zera o eixo mesmo longe da base',
        (WidgetTester tester) async {
      double? axis;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 170,
              child: JoystickWidget(onAxis: (double a) => axis = a),
            ),
          ),
        ),
      );
      final Offset center = tester.getCenter(find.byType(JoystickWidget));
      final TestGesture gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(axis, greaterThan(0));

      // Cancelamento (ex.: sistema rouba o gesto) também zera.
      await gesture.cancel();
      await tester.pump();
      expect(axis, 0.0);
    });
  });

  group('JumpButton', () {
    testWidgets('pressionar dispara onPress; soltar dispara onRelease',
        (WidgetTester tester) async {
      int presses = 0;
      int releases = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 128,
                height: 132,
                child: JumpButton(
                  onPress: () => presses++,
                  onRelease: () => releases++,
                ),
              ),
            ),
          ),
        ),
      );

      expect(presses, 0);
      expect(releases, 0);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(JumpButton)),
        pointer: 7,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(presses, 1);
      expect(releases, 0);

      await gesture.up();
      await tester.pump();
      expect(presses, 1);
      expect(releases, 1);
    });

    testWidgets('segundo dedo no botão não duplica o disparo',
        (WidgetTester tester) async {
      int presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 128,
                height: 132,
                child: JumpButton(
                  onPress: () => presses++,
                  onRelease: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final Offset c = tester.getCenter(find.byType(JumpButton));
      final TestGesture g1 = await tester.startGesture(c, pointer: 1);
      await tester.pump();
      final TestGesture g2 = await tester.startGesture(c, pointer: 2);
      await tester.pump();
      expect(presses, 1); // só o primeiro pointerId comanda

      await g1.up();
      await g2.up();
      await tester.pump();
      expect(presses, 1);
    });
  });
}
