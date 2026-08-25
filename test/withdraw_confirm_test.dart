import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/wallet/widgets/withdraw_confirm_sheet.dart';

Widget _wrap() => MaterialApp(
      home: Scaffold(body: Builder(builder: (BuildContext context) {
        return const SizedBox.shrink();
      })),
    );

Future<bool> _open(
  WidgetTester tester, {
  String destinationMasked = 'ow***@example.com',
}) {
  final BuildContext context = tester.element(find.byType(Scaffold));
  return WithdrawConfirmSheet.show(
    context,
    assetId: 'LTC',
    destinationMasked: destinationMasked,
    amountUnits: BigInt.from(58000000), // 58 coins
    feeUnits: BigInt.from(2000000), // 2 coins
    litoshiPerCoin: 100,
    displayRate: '1 COIN = 0,000001 LTC',
    receivedLitoshiValue: BigInt.from(5600), // 56 coins ⇒ 0,000056 LTC
  );
}

void main() {
  /// Superfície tipo telefone (a sheet é alta; o padrão 800×600 do teste
  /// cortaria os botões mesmo com scroll).
  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('sheet exibe resumo completo com e-mail MASCARADO',
      (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(_wrap());
    final Future<bool> result = _open(tester);
    await tester.pumpAndSettle();

    // Resumo completo.
    expect(find.byKey(const ValueKey<String>('confirm_title')), findsOneWidget);
    expect(find.text('Ativo'), findsOneWidget);
    expect(find.text('LTC'), findsOneWidget);
    expect(find.text('E-mail FaucetPay'), findsOneWidget);
    expect(find.text('ow***@example.com'), findsOneWidget);
    expect(find.text('58 COIN'), findsOneWidget);
    expect(find.text('2 COIN'), findsOneWidget);
    expect(find.text('1 COIN = 0,000001 LTC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('confirm_receive')),
      findsOneWidget,
    );
    expect(find.text('0,000056 LTC'), findsOneWidget);
    // Aviso de validação ≤5 min + cooldown.
    expect(find.textContaining('até 5 minutos'), findsOneWidget);
    expect(find.textContaining('24h'), findsOneWidget);
    // E-mail COMPLETO nunca aparece.
    expect(find.textContaining('owner@example.com'), findsNothing);

    // CONFIRMAR retorna true.
    await tester.tap(find.byKey(const ValueKey<String>('confirm_withdraw')));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('CANCELAR NÃO libera o intent (retorna false)',
      (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(_wrap());
    final Future<bool> result = _open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('cancel_withdraw')));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('botões CANCELAR e CONFIRMAR SAQUE estão presentes',
      (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(_wrap());
    final Future<bool> result = _open(tester, destinationMasked: 'jo***@mail.com');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('cancel_withdraw')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('confirm_withdraw')),
      findsOneWidget,
    );
    // Título + botão compartilham o texto.
    expect(find.text('CONFIRMAR SAQUE'), findsNWidgets(2));
    expect(find.text('CANCELAR'), findsOneWidget);

    // Fecha a sheet para não vazar timers no teste.
    await tester.tap(find.byKey(const ValueKey<String>('cancel_withdraw')));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
