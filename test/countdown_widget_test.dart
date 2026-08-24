import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/games/nova_swarm/widgets/countdown_overlay.dart';

/// COUNTDOWN 3→2→1→GO! (v2): 700ms por passo (~2.8s total), pop de escala +
/// fade, onFinished disparado ao terminar.
void main() {
  testWidgets('countdown completa em ~2.8s e dispara onFinished',
      (WidgetTester tester) async {
    bool finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CountdownOverlay(onFinished: () => finished = true),
        ),
      ),
    );

    // Antes do fim: ainda não chamou.
    expect(finished, isFalse);

    // Avança o tempo total (4 × 700ms).
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('onFinished NÃO dispara antes de ~2.8s',
      (WidgetTester tester) async {
    bool finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CountdownOverlay(onFinished: () => finished = true),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1400)); // só "2"
    expect(finished, isFalse);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('renderiza CustomPaint dos dígitos pixel durante os passos',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CountdownOverlay(onFinished: () {}),
        ),
      ),
    );
    // Frame inicial ("3") tem o painter de matriz pixel.
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
