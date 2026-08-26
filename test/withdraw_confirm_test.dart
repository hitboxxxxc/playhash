import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/wallet/widgets/withdraw_confirm_sheet.dart';

Widget _wrap() => MaterialApp(
      home: Scaffold(body: Builder(builder: (BuildContext context) {
        return const SizedBox.shrink();
      })),
    );

/// Parâmetros fixos do sheet nos testes (espelham config/payouts v3):
/// mínimo 20 COIN · taxa 2 COIN · 1 COIN = 100 litoshi.
Future<bool> _open(
  WidgetTester tester, {
  required ValueNotifier<int> amountCoins,
  String destinationMasked = 'ow***@example.com',
}) {
  final BuildContext context = tester.element(find.byType(Scaffold));
  return WithdrawConfirmSheet.show(
    context,
    assetId: 'LTC',
    destinationMasked: destinationMasked,
    amountUnits: BigInt.from(20000000),
    feeUnits: BigInt.from(2000000), // 2 coins
    litoshiPerCoin: 100,
    displayRate: '1 COIN = 0,000001 LTC',
    minWithdrawUnits: BigInt.from(20000000), // 20 coins
    availableBalance: BigInt.from(100000000), // 100 coins
    amountCoins: amountCoins,
  );
}

void main() {
  /// Superfície tipo telefone (a sheet é alta; o padrão 800×600 do teste
  /// cortaria os botões mesmo com scroll).
  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('CONVERSÃO EM TEMPO REAL: 10 → 0,000008; 20 → 0,000018',
      (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(_wrap());
    final ValueNotifier<int> amountCoins = ValueNotifier<int>(10);
    final Future<bool> result = _open(tester, amountCoins: amountCoins);
    await tester.pumpAndSettle();

    // 10 coins − 2 de taxa = 8 × 100 litoshi = 0,000008 LTC.
    expect(
      find.byKey(const ValueKey<String>('confirm_receive')),
      findsOneWidget,
    );
    expect(find.text('0,000008 LTC'), findsOneWidget);
    expect(find.text('10 COIN'), findsOneWidget);

    // Digitar mais um dígito (notifier → 20) recalcula AO VIVO:
    // 20 − 2 = 18 × 100 = 1800 litoshi = 0,000018 LTC.
    amountCoins.value = 20;
    await tester.pumpAndSettle();
    expect(find.text('20 COIN'), findsOneWidget);
    expect(find.text('0,000018 LTC'), findsOneWidget);

    // CONFIRMAR habilitado com valor válido ⇒ retorna true.
    final Finder confirm =
        find.byKey(const ValueKey<String>('confirm_withdraw'));
    expect(tester.widget<OutlinedButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('valor ≤ taxa ⇒ "Você recebe 0" e CONFIRMAR DESABILITADO',
      (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(_wrap());
    final ValueNotifier<int> amountCoins = ValueNotifier<int>(2); // == taxa
    final Future<bool> result = _open(tester, amountCoins: amountCoins);
    await tester.pumpAndSettle();

    expect(find.text('0 LTC'), findsOneWidget);
    // Hint do mínimo visível.
    expect(find.byKey(const ValueKey<String>('confirm_min_hint')), findsOneWidget);
    // CONFIRMAR desabilitado (onPressed null).
    final Finder confirm =
        find.byKey(const ValueKey<String>('confirm_withdraw'));
    expect(tester.widget<OutlinedButton>(confirm).onPressed, isNull);

    // CANCELAR continua funcionando e NÃO libera o intent.
    await tester.tap(find.byKey(const ValueKey<String>('cancel_withdraw')));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('sheet exibe resumo completo com e-mail MASCARADO',
      (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(_wrap());
    final Future<bool> result =
        _open(tester, amountCoins: ValueNotifier<int>(58));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('confirm_title')), findsOneWidget);
    expect(find.text('Ativo'), findsOneWidget);
    expect(find.text('LTC'), findsOneWidget);
    expect(find.text('Destino (e-mail ou LTC)'), findsOneWidget);
    expect(find.text('ow***@example.com'), findsOneWidget);
    expect(find.text('Taxa'), findsOneWidget);
    expect(find.text('2 COIN'), findsOneWidget);
    expect(find.text('1 COIN = 0,000001 LTC'), findsOneWidget);
    // 58 − 2 = 56 × 100 = 5600 litoshi.
    expect(find.text('0,000056 LTC'), findsOneWidget);
    // Aviso 12.18: pagamento via FaucetPay + estorno — SEM cooldown.
    expect(find.byKey(const ValueKey<String>('confirm_notice')), findsOneWidget);
    expect(find.textContaining('FaucetPay'), findsWidgets);
    expect(find.textContaining('estornado'), findsOneWidget);
    expect(find.textContaining('24h'), findsNothing);
    expect(find.textContaining('intervalo'), findsNothing);
    // E-mail COMPLETO nunca aparece.
    expect(find.textContaining('owner@example.com'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('cancel_withdraw')));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
