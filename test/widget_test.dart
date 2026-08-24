import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/main.dart';

/// Smoke test: o app deve subir sem crashar e o AuthGate deve renderizar
/// um estado válido (splash enquanto inicializa OU tela de erro com retry,
/// quando não há configuração Firebase no ambiente de teste).
void main() {
  testWidgets('app sobe e AuthGate renderiza estado válido',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PlayHashApp()),
    );

    // Permite que o bootstrap assíncrono (Firebase.initializeApp) conclua
    // no mundo real antes de avaliar a UI.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);

    final bool errorShown =
        find.text('TENTAR NOVAMENTE').evaluate().isNotEmpty;
    final bool splashShown =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;

    // Sem google-services.json no ambiente de teste o esperado é o erro
    // amigável com retry; em outros ambientes, o splash pode persistir.
    expect(errorShown || splashShown, isTrue);
  });
}
