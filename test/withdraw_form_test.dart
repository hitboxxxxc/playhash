import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/features/wallet/widgets/asset_selector.dart';
import 'package:playhash/features/wallet/widgets/withdraw_form.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

final WithdrawAssetInfo _ltc = WithdrawAssetInfo(
  id: 'LTC',
  network: 'FaucetPayEmail',
  minWithdrawUnits: BigInt.from(20000000), // 20 coins
  feeUnits: BigInt.from(2000000), // 2 coins
);

void main() {
  group('WithdrawForm (v3 — saque por e-mail FaucetPay)', () {
    testWidgets('exibe campo de e-mail, aviso fixo e linha de taxa/LTC',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(WithdrawForm(
        asset: _ltc,
        availableBalance: BigInt.from(100000000),
        onSubmit: (_, _) {},
      )));

      // Campo do e-mail FaucetPay presente.
      expect(find.text('E-mail da FaucetPay'), findsOneWidget);
      // AVISO FIXO sob o campo.
      expect(
        find.textContaining('não use endereço externo de carteira'),
        findsOneWidget,
      );
      // Card de taxa MINIMALISTA: SOMENTE a taxa da config.
      expect(find.byKey(const ValueKey<String>('fee_line')), findsOneWidget);
      expect(find.text('Taxa: 2 COIN'), findsOneWidget);
      // NADA de conversão/recebido no card (isso é só no sheet).
      expect(find.textContaining('Você recebe'), findsNothing);
      expect(find.textContaining('LTC'), findsNothing);
      // Rótulo "definidos pelo servidor".
      expect(find.textContaining('definidos pelo servidor'), findsOneWidget);
    });

    testWidgets('notifier amountCoins acompanha os dígitos digitados',
        (WidgetTester tester) async {
      final ValueNotifier<int> amountCoins = ValueNotifier<int>(0);
      await tester.pumpWidget(_wrap(WithdrawForm(
        asset: _ltc,
        availableBalance: BigInt.from(100000000),
        amountCoins: amountCoins,
        onSubmit: (_, _) {},
      )));

      await tester.enterText(find.byType(TextField).last, '10');
      await tester.pump();
      expect(amountCoins.value, 10);

      await tester.enterText(find.byType(TextField).last, '25,5');
      await tester.pump();
      expect(amountCoins.value, 25); // floor

      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump();
      expect(amountCoins.value, 0); // vazio = 0
    });

    testWidgets('e-mail inválido bloqueia o submit localmente',
        (WidgetTester tester) async {
      bool submitted = false;
      await tester.pumpWidget(_wrap(WithdrawForm(
        asset: _ltc,
        availableBalance: BigInt.from(100000000),
        onSubmit: (_, _) => submitted = true,
      )));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail da FaucetPay'),
        'e-mail-invalido',
      );
      await tester.enterText(find.byType(TextField).last, '20');
      await tester.tap(find.byKey(const ValueKey<String>('submit_withdraw')));
      await tester.pump();

      expect(submitted, isFalse);
      expect(find.text('E-mail inválido.'), findsOneWidget);
    });

    testWidgets('submit válido entrega valor + e-mail ao callback',
        (WidgetTester tester) async {
      BigInt? submittedAmount;
      String? submittedEmail;
      await tester.pumpWidget(_wrap(WithdrawForm(
        asset: _ltc,
        availableBalance: BigInt.from(100000000),
        onSubmit: (BigInt amount, String email) {
          submittedAmount = amount;
          submittedEmail = email;
        },
      )));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail da FaucetPay'),
        'owner@example.com',
      );
      await tester.enterText(find.byType(TextField).last, '58');
      await tester.tap(find.byKey(const ValueKey<String>('submit_withdraw')));
      await tester.pump();

      expect(submittedAmount, BigInt.from(58000000)); // 58 coins
      expect(submittedEmail, 'owner@example.com');
    });

    testWidgets('valor abaixo do mínimo é rejeitado', (WidgetTester tester) async {
      bool submitted = false;
      await tester.pumpWidget(_wrap(WithdrawForm(
        asset: _ltc,
        availableBalance: BigInt.from(100000000),
        onSubmit: (_, _) => submitted = true,
      )));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail da FaucetPay'),
        'owner@example.com',
      );
      await tester.enterText(find.byType(TextField).last, '10');
      await tester.tap(find.byKey(const ValueKey<String>('submit_withdraw')));
      await tester.pump();

      expect(submitted, isFalse);
      expect(find.textContaining('Abaixo do mínimo'), findsOneWidget);
    });
  });

  group('AssetSelector (v3 — LTC único habilitado)', () {
    testWidgets('BTC/DOGE/USDT desabilitados com selo EM BREVE; só LTC clica',
        (WidgetTester tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(AssetSelector(
        assets: const <WalletAssetChip>[
          WalletAssetChip(
              id: 'BTC', network: 'Bitcoin', symbol: 'B', enabled: false),
          WalletAssetChip(
              id: 'LTC', network: 'FaucetPayEmail', symbol: 'L', enabled: true),
          WalletAssetChip(
              id: 'DOGE', network: 'Dogecoin', symbol: 'D', enabled: false),
          WalletAssetChip(
              id: 'USDT', network: 'TRC20', symbol: 'T', enabled: false),
        ],
        selectedId: 'LTC',
        onSelected: (String id) => selected = id,
      )));

      expect(find.text('EM BREVE'), findsNWidgets(3));
      expect(find.byKey(const ValueKey<String>('soon_BTC')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('soon_DOGE')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('soon_USDT')), findsOneWidget);

      // Tocar num chip desabilitado NÃO seleciona.
      await tester.tap(find.text('BTC'));
      await tester.pump();
      expect(selected, isNull);

      // Tocar no LTC habilitado seleciona.
      await tester.tap(find.text('LTC'));
      await tester.pump();
      expect(selected, 'LTC');
    });

    testWidgets('chip habilitado selecionado não mostra EM BREVE e responde',
        (WidgetTester tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(AssetSelector(
        assets: const <WalletAssetChip>[
          WalletAssetChip(
              id: 'LTC', network: 'FaucetPayEmail', symbol: 'L', enabled: true),
        ],
        selectedId: 'LTC',
        onSelected: (String id) => selected = id,
      )));
      // Único chip habilitado/selecionado: sem selo "EM BREVE".
      expect(find.text('EM BREVE'), findsNothing);
      expect(find.text('FaucetPayEmail'), findsOneWidget);
      // Re-seleção segue emitindo callback.
      await tester.tap(find.text('LTC'));
      await tester.pump();
      expect(selected, 'LTC');
    });
  });
}
