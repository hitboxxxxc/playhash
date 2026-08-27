import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/core/navigation/loja_notifier.dart';
import 'package:playhash/core/widgets/pixel_shell.dart';
import 'package:playhash/features/store/pixel_loja_screen.dart';

void main() {
  Widget createTestableWidget({
    required ValueNotifier<int> indexNotifier,
  }) {
    return MaterialApp(
      home: PixelShell(
        balanceText: '1.000',
        indexNotifier: indexNotifier,
        pages: [
          const Center(child: Text('HOME_PAGE')),
          const Center(child: Text('SALA_PAGE')),
        ],
        menuItems: [],
      ),
    );
  }

  setUp(() {
    LojaNav.fecharLoja();
    LojaNav.goToTab.value = -1;
  });

  testWidgets('Deve abrir a loja quando LojaNav.open for true', (WidgetTester tester) async {
    final indexNotifier = ValueNotifier<int>(0);
    await tester.pumpWidget(createTestableWidget(indexNotifier: indexNotifier));

    expect(find.text('HOME_PAGE'), findsOneWidget);
    expect(find.byType(PixelLojaScreen), findsNothing);

    LojaNav.abrirLoja();
    await tester.pump();

    expect(find.byType(PixelLojaScreen), findsOneWidget);
  });

  testWidgets('Deve fechar a loja e voltar para a página anterior', (WidgetTester tester) async {
    final indexNotifier = ValueNotifier<int>(0);
    await tester.pumpWidget(createTestableWidget(indexNotifier: indexNotifier));

    LojaNav.abrirLoja();
    await tester.pump();
    expect(find.byType(PixelLojaScreen), findsOneWidget);

    LojaNav.fecharLoja();
    await tester.pump();

    expect(find.byType(PixelLojaScreen), findsNothing);
    expect(find.text('HOME_PAGE'), findsOneWidget);
  });

  testWidgets('irParaSala deve fechar a loja e mudar para a aba 1', (WidgetTester tester) async {
    final indexNotifier = ValueNotifier<int>(0);
    await tester.pumpWidget(createTestableWidget(indexNotifier: indexNotifier));

    LojaNav.abrirLoja();
    await tester.pump();

    LojaNav.irParaSala();
    await tester.pump(); // Notifica listeners e reconstrói

    expect(find.byType(PixelLojaScreen), findsNothing);
    expect(indexNotifier.value, 1);
    expect(find.text('SALA_PAGE'), findsOneWidget);
  });
}
